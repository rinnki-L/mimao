/// 酷狗设备/账号身份快照与本地持久化。
///
/// Rust 侧是 caller-owned 的 `Identity`（request.rs）；Dart 侧由
/// [KugouIdentityStore] 以一个 JSON 文件持有（anime 规则仓库同款「文件即真相」
/// 模式，不用 drift——它是一个整体快照，不是可查询的表）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'kugou_error.dart';

/// 账号/设备身份快照（request.rs `Identity`）。
class KugouIdentity {
  const KugouIdentity({
    required this.userId,
    required this.token,
    required this.t1,
    required this.mid,
    required this.dfid,
    required this.uuid,
    required this.guid,
    required this.mac,
    required this.deviceName,
    required this.renderFingerprint,
    this.nickname = '',
    this.avatarUrl = '',
  });

  /// 新匿名设备：guid=UUID v4，mid=calculateMid(guid)，dfid='-'（由
  /// register_dev 升级为真 dfid），uuid/mac 沿上游常量。
  factory KugouIdentity.anonymous({Random? random}) {
    final guid = kugouNewGuid(random: random);
    return KugouIdentity(
      userId: 0,
      token: '',
      t1: '',
      mid: kugouCalculateMid(guid),
      dfid: '-',
      uuid: '-',
      guid: guid,
      mac: '02:00:00:00:00:00',
      deviceName: '',
      renderFingerprint: '',
    );
  }

  /// 全空身份——「还没有任何身份」的内存表示（store 未引导过）。
  const KugouIdentity.empty()
    : userId = 0,
      token = '',
      t1 = '',
      mid = '',
      dfid = '',
      uuid = '',
      guid = '',
      mac = '',
      deviceName = '',
      renderFingerprint = '',
      nickname = '',
      avatarUrl = '';

  final int userId;
  final String token;
  final String t1;
  final String mid;
  final String dfid;
  final String uuid;
  final String guid;
  final String mac;
  final String deviceName;
  final String renderFingerprint;

  /// 账号展示名（扫码授权返回；旧身份文件缺键时为空串）。
  final String nickname;

  /// 账号头像 URL（扫码授权返回；可能为空）。
  final String avatarUrl;

  bool get hasAccount => userId != 0 && token.isNotEmpty;

  /// 设置页账号标题：有昵称用昵称，否则用「用户 id」。
  String get accountLabel => nickname.isEmpty ? '用户 $userId' : nickname;

  /// 设备上下文是否满足网关校验（request.rs send_endpoint 开头的断言，
  /// 含「userid=0 时不许残留 t1」）。
  bool get isUsable =>
      mid.isNotEmpty &&
      dfid.isNotEmpty &&
      (userId == 0) == token.isEmpty &&
      !(userId == 0 && t1.isNotEmpty);

  /// 未注册过真 dfid（'-' 是上游约定的占位值）。
  bool get needsDeviceRegistration => dfid.isEmpty || dfid == '-';

  KugouIdentity withDfid(String newDfid) => KugouIdentity(
    userId: userId,
    token: token,
    t1: t1,
    mid: mid,
    dfid: newDfid,
    uuid: uuid,
    guid: guid,
    mac: mac,
    deviceName: deviceName,
    renderFingerprint: renderFingerprint,
    nickname: nickname,
    avatarUrl: avatarUrl,
  );

  /// 只改账号字段（扫码授权成功后合并）；设备字段原样保留。
  KugouIdentity withAccount({
    required int userId,
    required String token,
    String t1 = '',
    String nickname = '',
    String avatarUrl = '',
  }) => KugouIdentity(
    userId: userId,
    token: token,
    t1: t1,
    mid: mid,
    dfid: dfid,
    uuid: uuid,
    guid: guid,
    mac: mac,
    deviceName: deviceName,
    renderFingerprint: renderFingerprint,
    nickname: nickname,
    avatarUrl: avatarUrl,
  );

  /// 剥掉账号信息（register_dev 必须匿名注册——上游 request_wire 语义；
  /// 扫码登录也要求匿名身份请求）。
  KugouIdentity withoutAccount() => KugouIdentity(
    userId: 0,
    token: '',
    t1: '',
    mid: mid,
    dfid: dfid,
    uuid: uuid,
    guid: guid,
    mac: mac,
    deviceName: deviceName,
    renderFingerprint: renderFingerprint,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'token': token,
    't1': t1,
    'mid': mid,
    'dfid': dfid,
    'uuid': uuid,
    'guid': guid,
    'mac': mac,
    'deviceName': deviceName,
    'renderFingerprint': renderFingerprint,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
  };

  factory KugouIdentity.fromJson(Map<String, Object?> json) {
    int intOf(Object? value) =>
        value is int ? value : int.tryParse('$value') ?? 0;
    String textOf(Object? value) => value == null ? '' : '$value';
    return KugouIdentity(
      userId: intOf(json['userId']),
      token: textOf(json['token']),
      t1: textOf(json['t1']),
      mid: textOf(json['mid']),
      dfid: textOf(json['dfid']),
      uuid: textOf(json['uuid']),
      guid: textOf(json['guid']),
      mac: textOf(json['mac']),
      deviceName: textOf(json['deviceName']),
      renderFingerprint: textOf(json['renderFingerprint']),
      // 旧身份文件没有这两个键——缺省空串，保持可读。
      nickname: textOf(json['nickname']),
      avatarUrl: textOf(json['avatarUrl']),
    );
  }
}

/// UUID v4（Node 版 getGuid 同构：8-4-4-4-12，版本位 4、变体位 8/9/a/b）。
String kugouNewGuid({Random? random}) {
  final r = random ?? Random.secure();
  String hex(int count) =>
      List.generate(count, (_) => r.nextInt(16).toRadixString(16)).join();
  final variant = <String>['8', '9', 'a', 'b'][r.nextInt(4)];
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(4)}${hex(4)}${hex(4)}';
}

/// calculateMid（Node util.js）：MD5 hex 视为 16 进制大整数，输出十进制串。
String kugouCalculateMid(String input) {
  final digest = md5.convert(utf8.encode(input)).toString();
  return BigInt.parse(digest, radix: 16).toString();
}

/// 身份文件仓库：`<directory>/music_identity.json`。
class KugouIdentityStore {
  KugouIdentityStore(this.directory);

  /// 默认位置：`<应用支持目录>/music_device/`。
  static Future<KugouIdentityStore> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return KugouIdentityStore(
      Directory('${support.path}${Platform.pathSeparator}music_device'),
    );
  }

  final Directory directory;

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}music_identity.json');

  /// 读身份；文件不存在或损坏都返回 null（下次 ensureDevice 重新引导）。
  /// 损坏不抛——身份是可再生资源，抛错反而挡住整个模块初始化。
  Future<KugouIdentity?> load() async {
    try {
      if (!await _file.exists()) return null;
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map) return null;
      return KugouIdentity.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }

  Future<void> save(KugouIdentity identity) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await _file.writeAsString(
      '${encoder.convert(identity.toJson())}\n',
      flush: true,
    );
  }

  /// 删除身份文件（登出/重置设备用；后续切片消费）。
  Future<bool> delete() async {
    if (!await _file.exists()) return false;
    await _file.delete();
    return true;
  }
}

/// 身份不可用的统一入口错误——页面能按 kind 显示引导文案。
KugouApiException identityNotUsableError(KugouIdentity identity) {
  return KugouApiException(
    'input',
    '账号或设备上下文不完整（mid=${identity.mid.isEmpty ? '缺' : '有'}'
        '/dfid=${identity.dfid.isEmpty ? '缺' : identity.dfid}'
        '/账号=${identity.hasAccount ? '有' : '无'}）',
  );
}
