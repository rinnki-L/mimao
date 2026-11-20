/// 开放平台（微信）登录端点 + `util/login_protocol.rs` / `util/login_config.rs` /
/// `util/provider.rs` 的组内共享翻译。
///
/// - `openplat`（login_protocol.rs）：QQ(type=1)/微信(type=36) 共用的
///   /v6/login_by_openplat 请求装配；请求身份必须匿名化；
/// - `kugouProviderRequest`（provider.rs）：第三方 HTTP 与酷狗签名/账号注入
///   完全隔离——https + 主机白名单 + 无端口/用户信息校验，2xx/3xx 之外
///   一律 http 失败，重定向由端点层显式处理；
/// - 微信 Authorize 分支（login_openplat.rs `Query::Authorize`）直接 POST
///   api.weixin.qq.com 的 oauth access_token 接口换 openid/access_token。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/login_token.dart'
    show kLiteT1Iv, kLiteT1Key, kLiteT2Iv, kLiteT2Key;
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/auth_models.dart';

/// 固定 lite 应用标识（login_config.rs；随包发布的 provider 凭证，非用户
/// token，也不是安全边界）。
const String kWxLiteAppId = 'wx72b795aca60ad321';
const String kWxLiteSecret = '33e486041e5e25729a4e3d2da7502f9a';
const String kQqLiteAppId = '101706348';

/// provider 移动端 UA（provider.rs `QQ_USER_AGENT`）。
const String kQqUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// provider 主机白名单（provider.rs provider_request 的 match 块，逐值对齐）。
const Set<String> _kProviderHosts = <String>{
  'openmobile.qq.com',
  'xui.ptlogin2.qq.com',
  'api.weixin.qq.com',
  'open.weixin.qq.com',
  'long.open.weixin.qq.com',
  'ssl.ptlogin2.qq.com',
  'ptlogin2.qq.com',
  'ui.ptlogin2.qq.com',
  'graph.qq.com',
  'connect.qq.com',
};

/// provider HTTP（provider.rs `provider_request`）：URL 校验 → 裸传输
/// （无酷狗身份/签名注入）→ 2xx/3xx 之外按 http 失败。重定向不跟随
/// （客户端 Policy::none 同语义），由端点层读响应头显式续链。
Future<KugouHttpResponse> kugouProviderRequest(
  KugouClient client, {
  required String method,
  required String url,
  Map<String, String> params = const <String, String>{},
  Map<String, String> headers = const <String, String>{},
}) async {
  final parsed = Uri.tryParse(url);
  if (parsed == null ||
      parsed.scheme != 'https' ||
      !_kProviderHosts.contains(parsed.host) ||
      parsed.port != 443 ||
      parsed.userInfo.isNotEmpty) {
    throw const KugouApiException('input', '登录服务地址无效');
  }
  final response = await client.sendRaw(
    url: url,
    method: method,
    params: params,
    headers: headers,
    allowNon2xx: true,
  );
  if (response.statusCode < 200 || response.statusCode >= 400) {
    throw const KugouApiException('http', '登录服务暂时不可用');
  }
  return response;
}

/// 登录设备证明 t1/t2（login_protocol.rs `proofs`；与账号续期字段 t1 无关）。
(String, String) kugouLoginProofs(KugouIdentity identity, int time) {
  if (identity.guid.isEmpty ||
      identity.mac.isEmpty ||
      identity.deviceName.isEmpty) {
    throw const KugouApiException('input', '登录设备上下文不完整');
  }
  return (
    kugouAes256Hex(
      utf8.encode('|$time'),
      utf8.encode(kLiteT1Key),
      utf8.encode(kLiteT1Iv),
    ),
    kugouAes256Hex(
      utf8.encode(
        '${identity.guid}'
        '|0f607264fc6318a92b9e13c65db7cd3c'
        '|${identity.mac}'
        '|${identity.deviceName}'
        '|$time',
      ),
      utf8.encode(kLiteT2Key),
      utf8.encode(kLiteT2Iv),
    ),
  );
}

/// openplat 登录请求（login_protocol.rs `openplat`）：返回原始响应字节与
/// 本次请求的解密 seed。OAuth 换取与该请求分离，SSA 重试不复用一次性 code。
Future<(Uint8List, String)> openplatLoginBytes(
  KugouClient client,
  KugouIdentity identity,
  int partner,
  MusicProviderAuthorization authorization, {
  int? timestampMs,
  String? seed,
}) async {
  if (authorization.openid.isEmpty ||
      authorization.accessToken.isEmpty ||
      utf8.encode(authorization.openid).length > 4096 ||
      utf8.encode(authorization.accessToken).length > 16384) {
    throw const KugouApiException('input', '第三方登录凭证无效');
  }
  final device = identity.withoutAccount();
  final time = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final envelope = kugouLoginParameterEnvelope(
    <String, Object?>{'access_token': authorization.accessToken},
    time,
    seed: seed,
  );
  final (t1, t2) = kugouLoginProofs(device, time);
  // serde_json BTreeMap 键序（third_appid 恒在 t3 之后）。
  final body = <String, Object?>{
    'clienttime_ms': time,
    'dev': device.deviceName,
    'force_login': 1,
    'openid': authorization.openid,
    'params': envelope.params,
    'partnerid': partner,
    'pk': envelope.portrait,
    't1': t1,
    't2': t2,
    't3': 'MCwwLDAsMCwwLDAsMCwwLDA=',
    if (partner == 1) 'third_appid': kQqLiteAppId,
  };
  final response = await client.sendEndpoint(
    device,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v6/login_by_openplat',
      router: 'login.user.kugou.com',
      method: 'POST',
      body: encodeJsonBody(body),
    ),
  );
  return (response.bytes, envelope.seed);
}

/// openplat 端点输入（login_openplat.rs `Query` 的 Authorize/Finish 两分支）。
class MusicOpenplatQuery {
  /// 微信授权码换取 openid/access_token（stage=authorize）。
  const MusicOpenplatQuery.authorize(this.code) : authorization = null;

  /// 用第三方凭证直接登录（stage=finish，partner=36）。
  const MusicOpenplatQuery.finish(this.authorization) : code = null;

  final String? code;
  final MusicProviderAuthorization? authorization;
}

/// login_openplat.rs `execute`：Authorize 换凭证（返回
/// [MusicProviderAuthorization]），Finish 走 openplat 登录（返回
/// [MusicLoginAuthorization]）。
Future<Object> fetchLoginOpenplat(
  MusicSession session,
  MusicOpenplatQuery query, {
  int? timestampMs,
  String? seed,
}) async {
  final code = query.code;
  if (code != null) {
    if (code.isEmpty || utf8.encode(code).length > 4096) {
      throw const KugouApiException('input', '微信授权码无效');
    }
    final response = await kugouProviderRequest(
      session.client,
      method: 'POST',
      url: 'https://api.weixin.qq.com/sns/oauth2/access_token',
      params: <String, String>{
        'secret': kWxLiteSecret,
        'appid': kWxLiteAppId,
        'code': code,
        'grant_type': 'authorization_code',
      },
    );
    return _convertOauth(response.bytes);
  }
  final authorization = query.authorization;
  if (authorization == null) {
    throw const KugouApiException('input', '第三方登录凭证无效');
  }
  final identity = await session.ensureDevice();
  final (bytes, seedValue) = await openplatLoginBytes(
    session.client,
    identity,
    36,
    authorization,
    timestampMs: timestampMs,
    seed: seed,
  );
  return openplatAuthorization(bytes, seedValue);
}

/// OAuth 应答解析（login_openplat.rs `convert_oauth`）。
MusicProviderAuthorization _convertOauth(Uint8List bytes) {
  final decoded = authDecodeProviderJson(bytes);
  final map = wireMap(decoded);
  if (map == null) {
    throw const KugouApiException('decode', '微信授权响应不是 object');
  }
  // optional i64：errcode 存在且非 0 → provider 失效。
  final errcode = authOptionalI64(map['errcode']);
  if (errcode != null && errcode != 0) {
    throw const KugouApiException('provider', '微信授权已失效，请重新扫码');
  }
  final openid = optionalText(map['openid']);
  final accessToken = optionalText(map['access_token']);
  if (openid == null || accessToken == null) {
    throw const KugouApiException('decode', '微信授权响应缺少凭证字段');
  }
  if (openid.isEmpty || accessToken.isEmpty) {
    throw const KugouApiException('authentication', '服务未返回有效登录凭证');
  }
  return MusicProviderAuthorization(openid: openid, accessToken: accessToken);
}

/// openplat 应答解析（login_qq.rs / login_openplat.rs `convert`：密文凭证
/// 必须能解密——空 secu_params 直接 decode，无明文兜底）。
Future<MusicLoginAuthorization> openplatAuthorization(
  Uint8List bytes,
  String seed,
) async {
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 || envelope.errorCode != 0) {
    throw KugouApiException('business', '请求失败', code: envelope.errorCode);
  }
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '登录响应 data 不是 object');
  }
  return loginAuthorizationFromData(data, seed, allowPlaintextToken: false);
}
