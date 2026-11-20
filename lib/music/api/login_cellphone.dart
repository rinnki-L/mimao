/// 手机验证码登录端点——EchoMusicNext `crates/echo-api/src/module/login_cellphone.rs`
/// 的逐函数翻译。
///
/// 走 `loginserviceretry.kugou.com`（origin LoginRetry）+ 重试型 UA；请求身份
/// 匿名化；t1/t2 由 `kugouLoginProofs`（login_protocol.rs `proofs`）生成；
/// error_code=34175 表示该手机号下有多个账号，返回候选列表而非授权。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// 手机号校验（login_cellphone.rs `valid_mobile`：11 位、1 开头、全数字）。
bool kugouIsValidMobile(String mobile) {
  if (utf8.encode(mobile).length != 11) return false;
  if (!mobile.startsWith('1')) return false;
  return RegExp(r'^[0-9]+$').hasMatch(mobile);
}

/// 登录输入（login_cellphone.rs `Query`；[userId] 为可选的指定账号）。
class MusicCellphoneQuery {
  const MusicCellphoneQuery({
    required this.mobile,
    required this.code,
    this.userId,
  });

  final String mobile;
  final String code;
  final int? userId;

  void validate() {
    if (!kugouIsValidMobile(mobile) ||
        code.trim().isEmpty ||
        utf8.encode(code).length > 32 ||
        userId == 0) {
      throw const KugouApiException('input', '请输入手机号码和验证码');
    }
  }
}

/// /v7/login_by_verifycode（origin LoginRetry；无 x-router）。
///
/// `timestampMs`/`seed` 仅供测试注入。
Future<MusicCellphoneLoginResult> fetchLoginCellphone(
  MusicSession session,
  MusicCellphoneQuery query, {
  int? timestampMs,
  String? seed,
}) async {
  query.validate();
  final identity = await session.ensureDevice();
  final anonymous = identity.withoutAccount();
  final time = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final envelope = kugouLoginParameterEnvelope(
    <String, Object?>{'mobile': query.mobile, 'code': query.code},
    time,
    seed: seed,
  );
  final (t1, t2) = kugouLoginProofs(anonymous, time);
  // serde_json BTreeMap 键序；mobile 按 Rust 字节切片语义掩码（前2*****后1）。
  final body = <String, Object?>{
    'clienttime_ms': time,
    'dev': anonymous.deviceName,
    'dfid': anonymous.dfid,
    'gitversion': '5f0b7c4',
    'key': kugouCloudListKeyedTime(time),
    'mobile':
        '${query.mobile.substring(0, 2)}*****${query.mobile.substring(10)}',
    'params': envelope.params,
    'pk': envelope.portrait,
    'plat': 1,
    'support_multi': 1,
    't1': t1,
    't2': t2,
    if (query.userId != null) 'userid': query.userId,
  };
  final response = await session.client.sendEndpoint(
    anonymous,
    KugouEndpoint(
      origin: KugouOrigin.loginRetry,
      path: '/v7/login_by_verifycode',
      method: 'POST',
      body: encodeJsonBody(body),
      headers: const <(String, String)>[
        ('support-calm', '1'),
        ('User-Agent', 'Android16-1070-11440-130-0-LOGIN-wifi'),
      ],
    ),
  );
  return _convert(response.bytes, envelope.seed);
}

/// wire 解析（login_cellphone.rs `convert`）。
MusicCellphoneLoginResult _convert(Uint8List bytes, String seed) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.errorCode == 34175) {
    final data = wireMap(envelope.data);
    if (data == null) {
      throw const KugouApiException('decode', '候选账号响应 data 不是 object');
    }
    final rows = wireList(data['info_list'], 'info_list');
    final candidates = <MusicLoginCandidate>[];
    for (final row in rows) {
      final map = wireMap(row);
      if (map == null) {
        throw const KugouApiException('decode', '候选账号行不是 object');
      }
      final userId = authRequiredScalarU64(map, 'userid');
      final nickname = wireText(map['nickname']);
      final username = authScalarText(map, 'username');
      // 展示名：nickname → username → userid 文本（上游同款回退）。
      final name = nickname.isNotEmpty
          ? nickname
          : username.isNotEmpty
          ? username
          : '$userId';
      candidates.add(
        MusicLoginCandidate(
          userId: userId,
          nickname: name,
          avatarUrl: wireText(map['pic']),
          username: username,
          appId: authOptionalU64(map['appid']),
        ),
      );
    }
    return MusicCellphoneLoginResult.selectAccount(candidates);
  }
  ensureBusinessSuccess(
    envelope.status,
    envelope.errorCode,
    context: '手机验证码登录',
  );
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '登录响应 data 不是 object');
  }
  return MusicCellphoneLoginResult.authorized(
    loginAuthorizationFromData(data, seed, allowPlaintextToken: true),
  );
}
