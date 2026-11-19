/// 扫码登录端点——EchoMusicNext `crates/echo-api/src/module/login_qr_key.rs`
/// 与 `login_qr_check.rs` 的逐函数翻译（docs/architecture.md §4.3）。
///
/// 两端点都走 [KugouOrigin.qrLogin]（login-user.kugou.com + **web 签名**），
/// 且请求身份必须先匿名化：扫码本身不需要账号态，带上旧 token 反而会污染
/// 服务端会话（上游 `execute` 里的 `anonymous` 同款处理）。
///
/// 上游只返回 `userid + token`，不含 `t1`——因此本模块不做 token 自动续期，
/// 过期只能重新扫码。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// `/v2/qrcode`（login_qr_key.rs）：取二维码会话 key 与服务端成品 PNG。
Future<QrLoginSession> startQrLogin(
  KugouClient client,
  KugouIdentity deviceIdentity,
) async {
  final anonymous = deviceIdentity.withoutAccount();
  final response = await client.sendEndpoint(
    anonymous,
    const KugouEndpoint(
      origin: KugouOrigin.qrLogin,
      path: '/v2/qrcode',
      method: 'GET',
      params: <String, String>{
        'appid': '1001',
        'type': '1',
        'plat': '4',
        // 末尾的 `&` 是上游原样常量（h5 页面自己再拼参数）。
        'qrcode_txt':
            'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=3116&',
        'srcappid': '2919',
      },
    ),
  );
  return _convertSession(response.bytes);
}

/// `/v2/get_userinfo_qrcode`（login_qr_check.rs）：轮询扫码/授权状态。
Future<QrLoginStatus> pollQrLogin(
  KugouClient client,
  KugouIdentity deviceIdentity,
  String key,
) async {
  if (key.trim().isEmpty || key.length > 4096) {
    throw const KugouApiException('input', '二维码会话无效');
  }
  final anonymous = deviceIdentity.withoutAccount();
  final response = await client.sendEndpoint(
    anonymous,
    KugouEndpoint(
      origin: KugouOrigin.qrLogin,
      path: '/v2/get_userinfo_qrcode',
      method: 'GET',
      params: <String, String>{
        'appid': '3116',
        'srcappid': '2919',
        'plat': '4',
        'qrcode': key,
        // 空串也照发（上游同款；dev 只是埋点字段）。
        'dev': anonymous.deviceName,
      },
    ),
  );
  return _convertStatus(response.bytes);
}

/// wire 解析（login_qr_key.rs `convert`）。
///
/// `scalar` 宽容面：字符串原样、数字转字符串；缺失/null/bool/复合类型都是
/// decode 失败。空串是合法值，是否接受由上层产品策略决定。
QrLoginSession _convertSession(Uint8List bytes) {
  final data = decodeBusinessEnvelope(bytes, context: '二维码').data;
  final map = wireMap(data);
  if (map == null) {
    throw const KugouApiException('decode', '二维码响应 data 不是 object');
  }
  final key = _scalarText(map, 'qrcode');
  final image = _scalarText(map, 'qrcode_img');
  return QrLoginSession(key: key, imageDataUrl: image);
}

/// wire 解析（login_qr_check.rs `convert` 的状态映射）。
QrLoginStatus _convertStatus(Uint8List bytes) {
  final data = decodeBusinessEnvelope(bytes, context: '二维码状态').data;
  final map = wireMap(data);
  if (map == null) {
    throw const KugouApiException('decode', '二维码状态响应 data 不是 object');
  }
  final status = requiredScalarInt(map['status'], 'status');
  switch (status) {
    case 0:
      return const QrLoginStatus(state: QrLoginState.expired);
    case 1:
      return const QrLoginStatus(state: QrLoginState.waiting);
    case 2:
      return const QrLoginStatus(state: QrLoginState.scanned);
    case 4:
      // 上游先解 WireAuthorization（userid/token 必填标量）再判 0/空。
      // 「缺字段」按产品口径收口为 authentication（服务未给凭证），类型错
      // 仍是 decode——两者都不能当成登录成功。
      final userId = _credentialInt(map, 'userid');
      final token = _credentialText(map, 'token');
      if (userId == 0 || token.isEmpty) {
        throw const KugouApiException('authentication', '服务未返回有效登录凭证');
      }
      return QrLoginStatus(
        state: QrLoginState.authorized,
        authorization: QrAuthorization(
          userId: userId,
          token: token,
          // nickname/pic 是展示字段：text 语义，缺省/类型错都退化为空串。
          nickname: wireText(map['nickname']),
          avatarUrl: wireText(map['pic']),
        ),
      );
    default:
      throw KugouApiException(
        'business',
        '二维码状态异常（status=$status）',
        code: status,
      );
  }
}

/// 严格 scalar 文本：字段缺失或非 String/Number 一律 decode。
String _scalarText(Map<String, Object?> map, String field) {
  final value = map[field];
  final text = optionalText(value);
  if (!map.containsKey(field) || text == null) {
    throw KugouApiException('decode', '响应字段 $field 缺失或不是标量');
  }
  return text;
}

/// 凭证数字：缺失/null → 0（交给上层判「无凭证」）；类型错 → decode。
int _credentialInt(Map<String, Object?> map, String field) {
  if (!map.containsKey(field) || map[field] == null) return 0;
  final parsed = optionalInt(map[field]);
  if (parsed == null) {
    throw KugouApiException('decode', '响应字段 $field 不是标量数字');
  }
  return parsed;
}

/// 凭证文本：缺失/null → ''（交给上层判「无凭证」）；类型错 → decode。
String _credentialText(Map<String, Object?> map, String field) {
  if (!map.containsKey(field) || map[field] == null) return '';
  final text = optionalText(map[field]);
  if (text == null) {
    throw KugouApiException('decode', '响应字段 $field 不是标量');
  }
  return text;
}
