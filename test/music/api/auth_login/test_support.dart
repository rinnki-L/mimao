/// 登录端点组测试共享件：假 `MusicSession` + 全字段身份 + 凭证信封加密 +
/// 带响应头的 provider 请求桩（不联网）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

/// 全字段设备身份（login/proofs 要求 guid/mac/deviceName 完整）。
KugouIdentity fixtureIdentity({
  int userId = 0,
  String token = '',
  String t1 = '',
}) => KugouIdentity(
  userId: userId,
  token: token,
  t1: t1,
  mid: 'fixture-mid',
  dfid: 'fixture-dfid',
  uuid: '-',
  guid: 'fixture-guid',
  mac: 'fixture-mac',
  deviceName: 'fixture-device',
  renderFingerprint: '123',
);

/// 假会话：身份固定注入；[saved] 记录所有 saveIdentity 写回。
MusicSession fakeSession(
  KugouClient client,
  KugouIdentity identity, {
  List<KugouIdentity>? saved,
}) => MusicSession(
  client: client,
  ensureDevice: () async => identity,
  loadIdentity: () async => identity,
  saveIdentity: (value) async {
    saved?.add(value);
  },
);

/// 测试用固定 seed 与毫秒时间戳。
const String testSeed = '0123456789abcdef';
const int testTimestampMs = 1735660800123;

/// 用 seed 加密一段明文（与 kugouDecryptCredentials 互逆）。
String encryptForSeed(String plain, String seed) {
  final keyMaterial = utf8.encode(md5.convert(utf8.encode(seed)).toString());
  return kugouAes256Hex(
    utf8.encode(plain),
    keyMaterial,
    keyMaterial.sublist(16),
  );
}

/// 加密凭证 JSON（login 信封的 secu_params 内容）。
String encryptedCredentials(
  Map<String, Object?> credentials, {
  String seed = testSeed,
}) => encryptForSeed(jsonEncode(credentials), seed);

/// {status, error_code, data} 信封。
String envelopeJson({
  Object? status = 1,
  Object? errorCode = 0,
  Object? data,
}) => jsonEncode(<String, Object?>{
  'status': status,
  'error_code': errorCode,
  if (data != null) 'data': data,
});

/// 「未提供」哨兵：区分显式 null 与缺省（wire 的字段存在性有语义）。
const Object unset = Object();

/// 登录信封的 `data`（login.rs/cellphone/qq/openplat 共用的 WireAccount 形状）。
Map<String, Object?> accountWireData({
  String seed = testSeed,
  Map<String, Object?> credentials = const <String, Object?>{'token': 'TK-1'},
  Object? userId = 42,
  Object? nickname = '昵称',
  Object? pic = 'http://pic/1',
  Object? t1,
  Object? tExpire,
  Object? secuParams = unset,
  Object? token,
}) => <String, Object?>{
  'userid': userId,
  'nickname': nickname,
  'pic': pic,
  if (t1 != null) 't1': t1,
  if (tExpire != null) 't_expire_time': tExpire,
  'secu_params': identical(secuParams, unset)
      ? encryptedCredentials(credentials, seed: seed)
      : secuParams,
  if (token != null) 'token': token,
};

/// provider 请求桩：按序出队响应（状态码/字节/响应头），并快照每次请求。
class ProviderStubAdapter implements HttpClientAdapter {
  final List<_StubResponse> _responses = <_StubResponse>[];
  final List<CapturedRequest> requests = <CapturedRequest>[];

  /// 清空已配置响应（请求快照保留）。
  void clear() => _responses.clear();

  void enqueue(int statusCode, Object body, [Map<String, String>? headers]) {
    enqueueValues(statusCode, body, <String, List<String>>{
      if (headers != null)
        for (final entry in headers.entries) entry.key: <String>[entry.value],
    });
  }

  void enqueueBytes(
    int statusCode,
    List<int> bytes, [
    Map<String, String>? headers,
  ]) {
    enqueueValues(statusCode, bytes, <String, List<String>>{
      if (headers != null)
        for (final entry in headers.entries) entry.key: <String>[entry.value],
    });
  }

  /// 配置**多值响应头**（多条 Set-Cookie 等；键大小写由测试控制）。
  void enqueueValues(
    int statusCode,
    Object body,
    Map<String, List<String>> headers,
  ) {
    final Uint8List bytes;
    if (body is Uint8List) {
      bytes = body;
    } else if (body is List<int>) {
      bytes = Uint8List.fromList(body);
    } else {
      bytes = Uint8List.fromList(utf8.encode(body is String ? body : '$body'));
    }
    _responses.add(_StubResponse(statusCode, bytes, headers));
  }

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
    if (_responses.isEmpty) {
      throw StateError('第 ${requests.length} 个请求未配置响应');
    }
    final response = _responses.removeAt(0);
    return ResponseBody.fromBytes(
      response.bytes,
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StubResponse {
  const _StubResponse(this.statusCode, this.bytes, this.headers);

  final int statusCode;
  final Uint8List bytes;
  final Map<String, List<String>> headers;
}

/// 响应头快捷构造（capture_adapter 的 jsonBytes 只配字节）。
Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));
