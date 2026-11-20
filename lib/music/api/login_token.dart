/// token 续期登录端点——EchoMusicNext `crates/echo-api/src/module/login_token.rs`
/// 的逐函数翻译。
///
/// 要求完整账号 + 设备身份（guid/mac/deviceName）；`p3/t1/t2` 用上游固定
/// LITEKEY/LITEIV 等常量做 AES-256 加密（照抄）；`pk` 参数在本端点转小写
/// （与 login.rs 的大写不同）。error_code=20017 → authentication。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// p3 的 key/iv（login_token.rs `LITEKEY/LITEIV`）。
const String kLiteKey = 'c24f74ca2820225badc01946dba4fdf7';
const String kLiteIv = 'adc01946dba4fdf7';

/// t1/t2 的 key/iv（login_token.rs `LITET1*/LITET2*`；login_protocol.rs
/// `proofs` 内联同值）。
const String kLiteT1Key = '5e4ef500e9597fe004bd09a46d8add98';
const String kLiteT1Iv = '04bd09a46d8add98';
const String kLiteT2Key = 'fd14b35e3f81af3817a20ae7adae7020';
const String kLiteT2Iv = '17a20ae7adae7020';

/// t3 固定协议证明常量（不是账号续期字段 t1）。
const String kugouTokenProofT3 = 'MCwwLDAsMCwwLDAsMCwwLDA=';

/// /v5/login_by_token（网关 + x-router=login.user.kugou.com；TLS 网关）。
///
/// `timestampMs`/`seed` 仅供测试注入。
Future<MusicAccountSession> fetchLoginToken(
  MusicSession session, {
  int? timestampMs,
  String? seed,
}) async {
  final identity = await session.ensureDevice();
  if (identity.userId == 0 ||
      identity.token.isEmpty ||
      identity.guid.isEmpty ||
      identity.mac.isEmpty ||
      identity.deviceName.isEmpty) {
    throw const KugouApiException('input', '刷新登录需要完整账号与设备身份');
  }
  final time = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final envelope = kugouLoginParameterEnvelope(
    <String, Object?>{},
    time,
    seed: seed,
  );
  final p3 = kugouAes256Hex(
    utf8.encode(
      _sortedJson(<String, Object?>{
        'clienttime': time ~/ 1000,
        'token': identity.token,
      }),
    ),
    utf8.encode(kLiteKey),
    utf8.encode(kLiteIv),
  );
  final t1 = kugouAes256Hex(
    utf8.encode('${identity.t1}|$time'),
    utf8.encode(kLiteT1Key),
    utf8.encode(kLiteT1Iv),
  );
  final t2 = kugouAes256Hex(
    utf8.encode(
      '${identity.guid}'
      '|0f607264fc6318a92b9e13c65db7cd3c'
      '|${identity.mac}'
      '|${identity.deviceName}'
      '|$time',
    ),
    utf8.encode(kLiteT2Key),
    utf8.encode(kLiteT2Iv),
  );
  // serde_json BTreeMap 键序。
  final body = <String, Object?>{
    'clienttime_ms': time,
    'dev': identity.deviceName,
    'dfid': identity.dfid,
    'p3': p3,
    'params': envelope.params,
    'pk': envelope.portrait.toLowerCase(),
    'plat': 1,
    't1': t1,
    't2': t2,
    't3': kugouTokenProofT3,
    'userid': identity.userId,
  };
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v5/login_by_token',
      router: 'login.user.kugou.com',
      method: 'POST',
      body: encodeJsonBody(body),
    ),
  );
  return _convert(response.bytes, envelope.seed, identity.userId);
}

/// wire 解析（login_token.rs execute + convert；两处判定一致，这里单次解码）。
MusicAccountSession _convert(Uint8List bytes, String seed, int expectedUserId) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.errorCode == 20017) {
    throw const KugouApiException(
      'authentication',
      '账号认证无效，请重新登录',
      code: 20017,
    );
  }
  if (envelope.status != 1 || envelope.errorCode != 0) {
    throw KugouApiException('business', '请求失败', code: envelope.errorCode);
  }
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '登录响应 data 不是 object');
  }
  // WireAccount：userid/t1/secu_params 必填（无 serde default），缺失 → decode。
  final userId = authRequiredScalarU64(data, 'userid');
  final t1 = authRequiredScalarText(data, 't1');
  final expires = authOptionalU64(data['t_expire_time']);
  final nickname = wireText(data['nickname']);
  final avatarUrl = wireText(data['pic']);
  final secuParams = authRequiredScalarText(data, 'secu_params');
  // 解密凭证也按 request::decode 语义先判过期再取 token 字段。
  final secret = authDecodeProviderJson(
    kugouDecryptCredentials(secuParams, seed),
  );
  final secretMap = wireMap(secret);
  if (secretMap == null) {
    throw const KugouApiException('decode', '登录凭证不是 object');
  }
  final token = authRequiredScalarText(secretMap, 'token');
  if (userId == 0 ||
      userId != expectedUserId ||
      t1.isEmpty ||
      secuParams.isEmpty ||
      token.isEmpty) {
    throw const KugouApiException('authentication', '服务未返回有效登录凭证');
  }
  return MusicAccountSession(
    userId: userId,
    token: token,
    refreshCredential: t1,
    expiresAtSeconds: expires,
    nickname: nickname,
    avatarUrl: avatarUrl,
  );
}

/// 稳定键序 JSON（登录端点的加密明文与 serde_json BTreeMap 输出一致）。
String _sortedJson(Map<String, Object?> value) {
  final keys = value.keys.toList()..sort();
  return jsonEncode(<String, Object?>{for (final key in keys) key: value[key]});
}
