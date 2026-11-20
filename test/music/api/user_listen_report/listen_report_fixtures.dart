/// 听歌上报测试夹具：固定时钟/身份/周期随机源、AES 原语、握手响应构造。
///
/// 全部离线：CaptureAdapter 供响应、点城堡原语在测试侧复算密文。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:pointycastle/export.dart';

import '../capture_adapter.dart';

/// 固定时刻：unix 秒 1700000012 / 毫秒 1700000012345。
DateTime listenReportClock() =>
    DateTime.fromMillisecondsSinceEpoch(1700000012345, isUtc: true);

const int listenReportSeconds = 1700000012;
const int listenReportMilliseconds = 1700000012345;

/// 带账号身份（uuid='-' → CSCC 回退 guid 去连字符）。
KugouIdentity listenReportIdentity() => const KugouIdentity(
  userId: 42,
  token: 'fixture-token',
  t1: '',
  mid: '1234567890',
  dfid: 'fixture-dfid',
  uuid: '-',
  guid: '00112233-4455-6677-8899-aabbccddeeff',
  mac: '02:00:00:00:00:00',
  deviceName: 'EchoMusicNext',
  renderFingerprint: '',
);

/// CSCC 用的 32 位 uuid（guid 去连字符）。
const String listenReportUuid = '00112233445566778899aabbccddeeff';

/// 握手响应里的 deviceid。
const String fixtureDeviceId = 'fixture-device-id';

/// 会话明文三件套（/v2/gen 解密后的 SessionData）。
const String fixtureCookie = 'private-session';
const int fixtureClienttime = 123;
const String fixtureServerstr = 'server-key';

/// 会话明文 JSON（字段序按 Rust struct：cookie/clienttime/serverstr）。
const String fixtureSessionJson =
    '{"cookie":"private-session","clienttime":123,"serverstr":"server-key"}';

/// 16 字节确定性熵：seed/ss3 的随机源共用一个周期序列。
final List<int> listenReportEntropy = List<int>.generate(
  16,
  (index) => (index * 7 + 3) % 256,
);

/// 熵的 hex（Rust `random_hex` 输出；seed 与 ss3 的输入相同）。
String get listenReportEntropyHex => listenReportEntropy
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// 周期序列随机源：每个 nextInt 依序取值、循环往复（确定性断言用）。
class SequenceRandom implements Random {
  SequenceRandom(this.values) : _index = 0;

  final List<int> values;
  int _index;

  @override
  int nextInt(int max) => values[_index++ % values.length] % max;

  @override
  bool nextBool() => values[_index++ % values.length].isOdd;

  @override
  double nextDouble() => values[_index++ % values.length] / 256.0;
}

/// 假 MusicSession：ensureDevice 直接给 [identity]，不联网。
MusicSession fakeListenReportSession(
  KugouIdentity identity,
  KugouClient client,
) => MusicSession(
  client: client,
  ensureDevice: () async => identity,
  loadIdentity: () async => identity,
  saveIdentity: (_) async {},
);

/// /v3/qrydid 成功响应。
Uint8List qrydidOkResponse() => jsonBytes(
  '{"status":1,"errcode":0,"data":{"deviceid":"$fixtureDeviceId"}}',
);

/// /v2/gen 成功响应：data 为用 [seed]/[uuid] 派生密钥加密的会话明文。
Uint8List genOkResponse(String seed, String uuid) => jsonBytes(
  '{"status":1,"errcode":0,"data":"${base64Encode(aesCbcPkcs7Encrypt(utf8.encode(fixtureSessionJson), aesKey(seed), aesIv(uuid)))}"}',
);

/// /v2/post 成功响应。
Uint8List postOkResponse() => jsonBytes('{"status":1,"errcode":0}');

/// AES-256 密钥（seed 的 32 个 ASCII 字节）。
Uint8List aesKey(String seed) => Uint8List.fromList(utf8.encode(seed));

/// AES-256 iv（uuid 前 16 个 ASCII 字节）。
Uint8List aesIv(String uuid) =>
    Uint8List.fromList(utf8.encode(uuid).sublist(0, 16));

/// AES-256-CBC + PKCS7 加密（与生产实现独立互证）。
Uint8List aesCbcPkcs7Encrypt(List<int> plain, List<int> key, List<int> iv) =>
    _aesCbcPkcs7(plain, key, iv, true);

/// AES-256-CBC + PKCS7 解密。
Uint8List aesCbcPkcs7Decrypt(
  List<int> encrypted,
  List<int> key,
  List<int> iv,
) => _aesCbcPkcs7(encrypted, key, iv, false);

Uint8List _aesCbcPkcs7(
  List<int> input,
  List<int> key,
  List<int> iv,
  bool encrypt,
) {
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
  return cipher.process(Uint8List.fromList(input));
}

/// 带账号身份的局部副本（只改给定字段）。
KugouIdentity copyIdentity(
  KugouIdentity base, {
  int? userId,
  String? token,
  String? mid,
  String? uuid,
  String? guid,
  String? deviceName,
}) => KugouIdentity(
  userId: userId ?? base.userId,
  token: token ?? base.token,
  t1: base.t1,
  mid: mid ?? base.mid,
  dfid: base.dfid,
  uuid: uuid ?? base.uuid,
  guid: guid ?? base.guid,
  mac: base.mac,
  deviceName: deviceName ?? base.deviceName,
  renderFingerprint: base.renderFingerprint,
);

/// 组装标准三步响应（qrydid/gen/post 各一；先清空既有响应列表）。
void installHappyPath(
  CaptureAdapter adapter,
  String seed,
  String uuid, {
  Uint8List? post,
}) {
  adapter
    ..bytes = post ?? postOkResponse()
    ..responses.clear()
    ..responses.addAll(<Uint8List>[
      qrydidOkResponse(),
      genOkResponse(seed, uuid),
      post ?? postOkResponse(),
    ]);
}

/// CSCC 三个端点的完整 URL（dio RequestOptions.path 保留完整地址）。
const String qrydidUrl = 'http://d.kugou.com/v3/qrydid';
const String genUrl = 'http://d.kugou.com/v2/gen';
const String postUrl = 'http://d.kugou.com/v2/post';

/// 按路径供响应的捕获适配器：缓存复用/失败重握手会让「请求序号 → 响应」
/// 错位，这里按完整 URL 匹配；请求快照与 CaptureAdapter 同构。
class ListenReportAdapter implements HttpClientAdapter {
  final List<CapturedRequest> requests = <CapturedRequest>[];
  final Map<String, Uint8List> responsesByPath = <String, Uint8List>{};

  /// 未配置路径的兜底响应（默认上报成功）。
  Uint8List fallback = postOkResponse();

  void on(String url, Uint8List bytes) => responsesByPath[url] = bytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      CapturedRequest(
        method: options.method,
        path: options.path,
        queryParameters: Map<String, Object?>.from(options.queryParameters),
        headers: Map<String, Object?>.from(options.headers),
        data: options.data,
      ),
    );
    final body = responsesByPath[options.path] ?? fallback;
    return ResponseBody.fromBytes(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

/// 组装按路径的标准三步响应。
void installPathHappyPath(ListenReportAdapter adapter, {Uint8List? post}) {
  adapter
    ..fallback = post ?? postOkResponse()
    ..on(qrydidUrl, qrydidOkResponse())
    ..on(genUrl, genOkResponse(listenReportEntropyHex, listenReportUuid))
    ..on(postUrl, post ?? postOkResponse());
}
