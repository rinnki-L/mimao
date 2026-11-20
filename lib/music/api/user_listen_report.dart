/// 听歌上报端点——EchoMusicNext `crates/echo-api/src/module/user_listen_report.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// CSCC 私有协议（`http://d.kugou.com`，全部走 [KugouClient.sendRaw] 裸传输，
/// 无网关默认参数/签名/dfid/mid 头注入）：
///
/// 1. `/v3/qrydid` POST 机器画像换 `deviceid`（无 KG-Rec/UA 头）；
/// 2. `/v2/gen` GET RSA 画像换 AES 加密会话（KG-Rec:1 + CsccGen UA）；
/// 3. `/v2/post` POST 双层 zlib + AES-256 事件（KG-Rec:1 + CsccPost UA）。
///
/// 会话缓存（`MusicListenReportSessionCache`）是实例私有的内存表：按身份派生
/// key、1800 秒过期、最多 256 条（超限淘汰最早过期）、并发初始化经内部
/// 互斥合并、上报失败即清缓存——对应上游 `client.listen_sessions` 的
/// tokio::Mutex 语义。绝不做全局单例。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_listen_report_models.dart';
import 'package:pointycastle/export.dart';

/// CSCC 上报协议 APPKEY（user_listen_report.rs `APPKEY`）。
const String kugouListenReportAppKey = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';

/// /v2/gen 的固定 UA（request_cscc：CsccGen）。
const String kugouListenReportGenUserAgent =
    'Android9-1070-10597-18-0-CsccGen-wifi';

/// /v2/post 的固定 UA（request_cscc：CsccPost）。
const String kugouListenReportPostUserAgent =
    'Android9-1070-10597-18-0-CsccPost-wifi';

/// 会话有效期（user_listen_report.rs：`Duration::from_secs(1800)`）。
const Duration kugouListenReportSessionLifetime = Duration(seconds: 1800);

/// 会话缓存上限（user_listen_report.rs：`sessions.len() >= 256`）。
const int kugouListenReportMaxSessions = 256;

/// 时钟缝——上游 `request::unix_seconds/unix_milliseconds` 的注入点。
/// 每个使用点独立取值（与上游逐处调用对齐）；测试注入固定时刻。
typedef MusicListenReportClock = DateTime Function();

/// 听歌上报的 CSCC 会话缓存（实例私有内存表；Rust `listen_sessions` 同语义）。
///
/// [guarded] 把握手/上报整体串行化（上游 tokio::Mutex）：并发调用排队，
/// 初始化天然合并——后进者直接命中先完成的缓存。
class MusicListenReportSessionCache {
  final Map<String, MusicListenReportSession> _sessions =
      <String, MusicListenReportSession>{};
  Future<void> _guard = Future<void>.value();

  /// 串行执行 [action]；失败不污染后续排队（链上吞掉上一轮错误）。
  Future<T> guarded<T>(Future<T> Function() action) {
    final result = _guard.then((_) => action());
    _guard = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// 清理过期会话（Rust `sessions.retain(|_, s| s.expires > now)`）。
  void purgeExpired(DateTime now) {
    _sessions.removeWhere((_, value) => !value.expiresAt.isAfter(now));
  }

  /// 读取（命中返回，未命中 null）。
  MusicListenReportSession? get(String key) => _sessions[key];

  /// 写入；容量达到 [kugouListenReportMaxSessions] 时淘汰最早过期的条目
  /// （Rust `min_by_key(|(_, s)| s.expires)`）。
  void put(String key, MusicListenReportSession value) {
    if (_sessions.length >= kugouListenReportMaxSessions) {
      String? oldestKey;
      for (final entry in _sessions.entries) {
        final current = _sessions[oldestKey];
        if (current == null ||
            entry.value.expiresAt.isBefore(current.expiresAt)) {
          oldestKey = entry.key;
        }
      }
      if (oldestKey != null) {
        _sessions.remove(oldestKey);
      }
    }
    _sessions[key] = value;
  }

  /// 失败后清除该身份的缓存（Rust `sessions.remove(&key)`）。
  void remove(String key) {
    _sessions.remove(key);
  }
}

/// 会话缓存 key（Rust `execute` 的 `key`）：
/// `md5(json([uuid, mid, userid, token, device_name]))`——serde_json 元组
/// 序列化成 JSON 数组，字段序/转义逐字对齐（serde_json 默认不转义非 ASCII，
/// 与 Dart jsonEncode 一致）。
String listenReportSessionKey(KugouIdentity identity, String uuid) => _md5Text(
  jsonEncode(<Object?>[
    uuid,
    identity.mid,
    identity.userId,
    identity.token,
    identity.deviceName,
  ]),
);

/// /v2/gen 的 RSA 画像明文（Rust `session`：
/// `"{uuid}\t{seed}\t{毫秒}\t{deviceid}"`）——独立成函数便于对拍。
String listenReportPortraitText({
  required String uuid,
  required String seed,
  required int milliseconds,
  required String deviceId,
}) => '$uuid\t$seed\t$milliseconds\t$deviceId';

/// 身份的 CSCC uuid 归一化（Rust `execute` 开头）：`uuid` 为 '-'/空时回退
/// `guid`，再去掉全部连字符（宿主持久化带分隔符的 GUID；CSCC 只用裸 32 位）。
String normalizeListenReportUuid(KugouIdentity identity) {
  final raw = identity.uuid == '-' || identity.uuid.isEmpty
      ? identity.guid
      : identity.uuid;
  return raw.replaceAll('-', '');
}

/// 听歌上报（user_listen_report.rs `execute`）。
///
/// 入口先 [MusicSession.ensureDevice] 取身份；随后在 [cache] 的互斥里完成
/// input 校验 → （必要时）CSCC 握手 → 事件加密上报；上报失败（传输/business/
/// decode）即清除该身份的会话缓存。`clock`/`random` 是测试注入缝。
Future<MusicListenReportAcceptance> fetchListenReport(
  MusicSession session,
  MusicListenReportQuery query, {
  MusicListenReportSessionCache? cache,
  MusicListenReportClock? clock,
  Random? random,
}) async {
  final identity = await session.ensureDevice();
  final effectiveCache = cache ?? MusicListenReportSessionCache();
  return effectiveCache.guarded(() async {
    final uuid = normalizeListenReportUuid(identity);
    final uuidBytes = utf8.encode(uuid);
    // 身份/事件完整性（Rust execute 的第一段 input 校验）。
    if (identity.userId == 0 ||
        identity.token.isEmpty ||
        uuidBytes.length != 32 ||
        !uuidBytes.every(_isAsciiAlphanumeric) ||
        identity.mid.isEmpty ||
        query.mixsongid <= 0 ||
        (query.event == MusicListenReportEvent.end &&
            query.durationMs == null)) {
      throw const KugouApiException('input', '听歌上报身份或事件不完整');
    }
    // 设备资料有效性（Rust execute 的第二段 input 校验；128 按字符数）。
    if (identity.deviceName.isEmpty ||
        identity.deviceName.runes.length > 128 ||
        _hasControlOrAmpersand(identity.deviceName) ||
        _hasControlOrAmpersand(identity.mid)) {
      throw const KugouApiException('input', '听歌上报设备资料无效');
    }
    final key = listenReportSessionKey(identity, uuid);
    final now = _dateTime(clock);
    effectiveCache.purgeExpired(now);
    var current = effectiveCache.get(key);
    if (current == null) {
      current = await establishListenReportSession(
        session,
        identity: identity,
        uuid: uuid,
        clock: clock,
        random: random,
      );
      effectiveCache.put(key, current);
    }
    final active = current;
    final plain = buildListenReportEvent(
      identity: identity,
      uuid: uuid,
      query: query,
      clock: clock,
      random: random ?? Random.secure(),
    );
    // 事件密钥：md5(uuid + clienttime + seed + serverstr) 的 32 个 ASCII 字节；
    // iv 取 uuid 前 16 个 ASCII 字节（Rust execute 的 cipher_key/iv）。
    final cipherKey = utf8.encode(
      _md5Text('$uuid${active.clienttime}${active.seed}${active.serverstr}'),
    );
    final packed = _zlibCompress(plain);
    final encrypted = _aesCbcPkcs7(
      packed,
      cipherKey,
      uuidBytes.sublist(0, 16),
      encrypt: true,
    );
    // 签名参数（BTreeMap 字典序拼接 key+value，再接 APPKEY 与密文字节）。
    final seconds = _unixSeconds(clock);
    final joined =
        '_t${seconds}appid3116cookie${active.cookie}length${plain.length}';
    final sign = _md5Bytes(<int>[
      ...utf8.encode('$joined$kugouListenReportAppKey'),
      ...encrypted,
    ]);
    try {
      final response = await session.client.sendRaw(
        url: 'http://d.kugou.com/v2/post',
        method: 'POST',
        params: <String, String>{
          '_t': '$seconds',
          'appid': '3116',
          'cookie': active.cookie,
          'length': '${plain.length}',
          'sign': sign,
        },
        body: encrypted,
        headers: const <String, String>{
          'KG-Rec': '1',
          'User-Agent': kugouListenReportPostUserAgent,
          'Content-Type': 'application/octet-stream',
        },
      );
      return convertListenReportAcceptance(response.bytes);
    } on Object {
      // 任何失败（传输/business/decode）都丢弃该身份的会话（上游同语义）。
      effectiveCache.remove(key);
      rethrow;
    }
  });
}

/// CSCC 两步握手（user_listen_report.rs `session`）。
///
/// 返回的会话 `expiresAt = 当前时刻 + 1800 秒`；seed 是本端随机 16 字节 hex。
Future<MusicListenReportSession> establishListenReportSession(
  MusicSession session, {
  required KugouIdentity identity,
  required String uuid,
  MusicListenReportClock? clock,
  Random? random,
}) async {
  final client = session.client;
  final uuidBytes = utf8.encode(uuid);

  // 第一步 /v3/qrydid：机器画像换 deviceid。字段序按 Rust struct
  // （machine/mid/uuid/wh）；此路径无 KG-Rec/UA 头（request_cscc 分支）。
  final deviceBody = utf8.encode(
    jsonEncode(<String, Object?>{
      'machine': identity.deviceName,
      'mid': identity.mid,
      'uuid': uuid,
      'wh': const <int>[1920, 1080],
    }),
  );
  final deviceSeconds = _unixSeconds(clock);
  final deviceSign = _md5Bytes(<int>[
    ...utf8.encode('_t${deviceSeconds}appidand02pbKC7zn{4U*ydo2M1Rir'),
    ...deviceBody,
  ]);
  final device = _csccEnvelope(
    (await client.sendRaw(
      url: 'http://d.kugou.com/v3/qrydid',
      method: 'POST',
      params: <String, String>{
        '_t': '$deviceSeconds',
        'appid': 'and02',
        'sign': deviceSign,
      },
      body: deviceBody,
      headers: const <String, String>{
        'Content-Type': 'application/octet-stream',
      },
    )).bytes,
  ).data;
  final deviceId = _requiredDeviceId(device);

  // 第二步 /v2/gen：RSA PKCS#1 画像换 AES 加密会话（KG-Rec:1 + CsccGen UA）。
  final seed = _randomHex(random ?? Random.secure());
  final portrait = kugouLitePkcs1Base64(
    utf8.encode(
      listenReportPortraitText(
        uuid: uuid,
        seed: seed,
        milliseconds: _unixMilliseconds(clock),
        deviceId: deviceId,
      ),
    ),
    random: random,
  );
  final genSeconds = _unixSeconds(clock);
  final genSign = _md5Text(
    '_t${genSeconds}appid3116s$portrait$kugouListenReportAppKey',
  );
  final encoded = _csccEnvelope(
    (await client.sendRaw(
      url: 'http://d.kugou.com/v2/gen',
      method: 'GET',
      params: <String, String>{
        '_t': '$genSeconds',
        'appid': '3116',
        's': portrait,
        'sign': genSign,
      },
      headers: const <String, String>{
        'KG-Rec': '1',
        'User-Agent': kugouListenReportGenUserAgent,
      },
    )).bytes,
  ).data;
  // data 是 base64 密文：AES-256-CBC/PKCS7，key=seed 的 32 个 ASCII 字节、
  // iv=uuid 前 16 个 ASCII 字节（Rust `session` 的解密段）。
  final encrypted = _base64Decode(_scalarString(encoded, 'data'));
  final plain = _aesCbcPkcs7(
    encrypted,
    utf8.encode(seed),
    uuidBytes.sublist(0, 16),
    encrypt: false,
  );
  final data = _decodeJsonRoot(Uint8List.fromList(plain));
  final cookie = _requiredScalarString(data, 'cookie');
  final clienttime = _requiredScalarUnsigned(data, 'clienttime');
  final serverstr = _requiredScalarString(data, 'serverstr');
  if (cookie.isEmpty || serverstr.isEmpty) {
    throw const KugouApiException('decode', '上报会话数据不完整');
  }
  return MusicListenReportSession(
    cookie: cookie,
    clienttime: clienttime,
    serverstr: serverstr,
    seed: seed,
    expiresAt: _dateTime(clock).add(kugouListenReportSessionLifetime),
  );
}

/// 事件明文装配（user_listen_report.rs `event_body`）：
/// `[header 文本字节 + zlib(fields 字节)]`。
///
/// header 第二行的 `length` 是 fields 的 **UTF-8 字节长度**（Rust `len()`），
/// 不含 header 本身；ss3 = md5(16 随机字节 hex)；时间取值顺序与上游一致
/// （毫秒 → 随机 → 秒）。
Uint8List buildListenReportEvent({
  required KugouIdentity identity,
  required String uuid,
  required MusicListenReportQuery query,
  required MusicListenReportClock? clock,
  required Random random,
}) {
  final song = query.mixsongid;
  final fields = StringBuffer();
  switch (query.event) {
    case MusicListenReportEvent.start:
      fields.write(
        'type_id=20431&action=play&fo3=3878,4320,4326,5747,5749,7229,7289,7863'
        '&spt=0&sty=手动&mixsongid=$song&source=46&ivar1=1&fo=/专辑播放页',
      );
      break;
    case MusicListenReportEvent.end:
      final state = query.completed ? '完整播放' : '中断播放';
      fields.write(
        'type_id=4&action=play&fo3=3878,4320,4326,5747,5749,7229,7289,7863'
        '&duration=${query.durationMs ?? 0}&svar3=0&svar2=0'
        '&fo=我的音乐/主态/自建歌单/RU&sty=手动&state=$state&mixsongid=$song'
        '&source=46&ivar3=0&type=1&fs=1.0&ivar1=1',
      );
      break;
  }
  final milliseconds = _unixMilliseconds(clock);
  fields.write(
    '&mid=${identity.mid}&uuid=$uuid&ss1=1&ss2=1&sys=9'
    '&mod=${identity.deviceName}&channelid=18&ip=0.0.0.0&net=1&ver=10597'
    '&gitversion=7aa8a76&time=$milliseconds&userid=${identity.userId}'
    '&ss3=${_md5Text(_randomHex(random))}',
  );
  final fieldsBytes = utf8.encode(fields.toString());
  final seconds = _unixSeconds(clock);
  final header =
      '4\t1\t$uuid\t0\t3116\t10597\t18\t9\t${identity.deviceName}'
      '\t$uuid\t${identity.mid}\t0\t$kugouHeaderZeroBlock\r\n'
      '${fieldsBytes.length}\t10048\t0\t$seconds\t1\t${identity.userId}\t0\t0\r\n';
  return (BytesBuilder()
        ..add(utf8.encode(header))
        ..add(_zlibCompress(fieldsBytes)))
      .toBytes();
}

/// 上报响应转换（user_listen_report.rs `convert`）：信封通过即受理。
MusicListenReportAcceptance convertListenReportAcceptance(Uint8List bytes) {
  _csccEnvelope(bytes);
  return const MusicListenReportAcceptance(accepted: true);
}

/// header 里的固定 36 个 '0'（Rust 格式串逐字对拍）。
const String kugouHeaderZeroBlock = '000000000000000000000000000000000000';

bool _isAsciiAlphanumeric(int byte) =>
    (byte >= 0x30 && byte <= 0x39) ||
    (byte >= 0x41 && byte <= 0x5A) ||
    (byte >= 0x61 && byte <= 0x7A);

/// 控制字符（Rust `char::is_control`：U+0000–001F 与 U+007F–009F）或 '&'。
bool _hasControlOrAmpersand(String value) {
  for (final code in value.runes) {
    if (code == 0x26 || code <= 0x1F || (code >= 0x7F && code <= 0x9F)) {
      return true;
    }
  }
  return false;
}

String _md5Text(String value) => md5.convert(utf8.encode(value)).toString();

String _md5Bytes(List<int> value) => md5.convert(value).toString();

/// 16 随机字节的 hex（Rust `random_hex`：32 个小写 hex 字符）。
String _randomHex(Random random) => List<int>.generate(
  16,
  (_) => random.nextInt(256),
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

DateTime _dateTime(MusicListenReportClock? clock) => (clock ?? DateTime.now)();

int _unixSeconds(MusicListenReportClock? clock) =>
    _dateTime(clock).millisecondsSinceEpoch ~/ 1000;

int _unixMilliseconds(MusicListenReportClock? clock) =>
    _dateTime(clock).millisecondsSinceEpoch;

/// zlib 压缩（Rust `pack`：flate2 `Compression::default()` 即 level 6，
/// 与 Dart [ZLibEncoder] 默认级别一致；两实现的字节流不必逐位相同，
/// 协议只要求是合法 zlib 流）。
Uint8List _zlibCompress(List<int> bytes) {
  try {
    return Uint8List.fromList(ZLibEncoder().convert(bytes));
  } on Object {
    throw const KugouApiException('encoding', '上报事件压缩失败');
  }
}

/// AES-256-CBC + PKCS7（本组内实现；key 必须 32 字节、iv 16 字节）。
/// 加密失败 → encoding（Rust `encrypt_padded_mut` 路径）；解密失败 → decode。
Uint8List _aesCbcPkcs7(
  List<int> input,
  List<int> key,
  List<int> iv, {
  required bool encrypt,
}) {
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    encrypt,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      ParametersWithIV<KeyParameter>(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      ),
      null,
    ),
  );
  try {
    return cipher.process(Uint8List.fromList(input));
  } on Object {
    throw KugouApiException(
      encrypt ? 'encoding' : 'decode',
      encrypt ? '上报事件加密失败' : '上报会话解密失败',
    );
  }
}

Uint8List _base64Decode(String text) {
  try {
    return base64Decode(text);
  } on Object {
    throw const KugouApiException('decode', '上报会话密文不是合法 base64');
  }
}

/// request::decode 的统一前置：登录过期映射（error_code=20018 或
/// `msg` 含「登录已过期」）+ JSON object 必需。
Map<String, Object?> _decodeJsonRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  final message = root['msg'];
  final expiredMessage = message is String && message.contains('登录已过期');
  final code = _optionalSigned(root['error_code']);
  if (expiredMessage || code == kugouErrorCodeAuthenticationExpired) {
    throw KugouApiException('authentication', '登录已过期，请重新登录酷狗账号', code: code);
  }
  return root;
}

/// CSCC 信封（user_listen_report.rs `envelope`/`Wire`）：三个错误字段全部
/// optional（缺省/null/不可解析 → null，不拒绝整包）；`status==0` 或任一
/// 非 0 错误码 → business（error_code 优先于 errcode）。
class _CsccEnvelope {
  const _CsccEnvelope(this.status, this.errcode, this.errorCode, this.data);

  final int? status;
  final int? errcode;
  final int? errorCode;
  final Object? data;
}

_CsccEnvelope _csccEnvelopeOf(Uint8List bytes) {
  final root = _decodeJsonRoot(bytes);
  return _CsccEnvelope(
    _optionalU32(root['status']),
    _optionalSigned(root['errcode']),
    _optionalSigned(root['error_code']),
    root['data'],
  );
}

_CsccEnvelope _csccEnvelope(Uint8List bytes) {
  final envelope = _csccEnvelopeOf(bytes);
  final code = envelope.errorCode != null && envelope.errorCode != 0
      ? envelope.errorCode
      : (envelope.errcode != null && envelope.errcode != 0
            ? envelope.errcode
            : null);
  if (envelope.status == 0 || code != null) {
    throw KugouApiException('business', '音乐服务拒绝了上报', code: code);
  }
  return envelope;
}

/// deviceid 抽取（Rust `Device`）：data 必须 object、`deviceid` 必填标量
/// 文本、非空，否则 decode。
String _requiredDeviceId(Object? data) {
  final map = wireMap(data);
  if (map == null) {
    throw const KugouApiException('decode', '设备注册响应 data 不是 object');
  }
  if (!map.containsKey('deviceid')) {
    throw const KugouApiException('decode', '设备注册响应缺少 deviceid');
  }
  final id = _scalarString(map['deviceid'], 'deviceid');
  if (id.isEmpty) {
    throw const KugouApiException('decode', '设备注册响应 deviceid 为空');
  }
  return id;
}

/// 标量文本（response.rs `from_value::<String>`）：字符串原样、数字转文本，
/// bool/null/复合类型 → decode。
String _scalarString(Object? value, String field) {
  if (value is String) return value;
  if (value is num) return '$value';
  throw KugouApiException('decode', '响应字段 $field 不是标量文本');
}

String _requiredScalarString(Map<String, Object?> map, String field) {
  if (!map.containsKey(field)) {
    throw KugouApiException('decode', '响应字段 $field 缺失');
  }
  return _scalarString(map[field], field);
}

/// 必填无符号标量（response.rs `scalar`：数字/数字字符串精确解析），失败 → decode。
int _requiredScalarUnsigned(Map<String, Object?> map, String field) {
  if (!map.containsKey(field)) {
    throw KugouApiException('decode', '响应字段 $field 缺失');
  }
  final parsed = _exactUnsigned(map[field]);
  if (parsed == null) {
    throw KugouApiException('decode', '响应字段 $field 不是标量数字');
  }
  return parsed;
}

/// response.rs `unsigned`/`exact_unsigned`：int 直取；double 须为精确非负整数；
/// 字符串先按 u64 解析、再按十进制/指数记号解析（trim 后）。
int? _exactUnsigned(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is num) {
    return _exactDouble(value.toDouble());
  }
  if (value is String) {
    final text = value.trim();
    final direct = int.tryParse(text);
    if (direct != null) return direct >= 0 ? direct : null;
    return _exactDouble(double.tryParse(text));
  }
  return null;
}

int? _exactDouble(double? value) {
  if (value == null ||
      value.isNegative ||
      !value.isFinite ||
      value != value.truncateToDouble()) {
    return null;
  }
  return value.toInt();
}

/// response.rs `signed`（负数也精确解析；不可解析 → null）。
int? _optionalSigned(Object? value) {
  if (value is int) return value;
  if (value is num) {
    final double d = value.toDouble();
    if (!d.isFinite || d != d.truncateToDouble()) return null;
    return d.toInt();
  }
  if (value is String) {
    final direct = int.tryParse(value.trim());
    if (direct != null) return direct;
    final relaxed = double.tryParse(value.trim());
    if (relaxed == null || !relaxed.isFinite) return null;
    if (relaxed != relaxed.truncateToDouble()) return null;
    return relaxed.toInt();
  }
  return null;
}

/// response.rs `optional` + u32（`Wire.status`）：缺省/null/不可解析/越界
/// → null，不拒绝整包。
int? _optionalU32(Object? value) {
  final parsed = _exactUnsigned(value);
  if (parsed == null || parsed > 0xFFFFFFFF) return null;
  return parsed;
}
