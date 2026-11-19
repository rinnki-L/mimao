/// 播放授权端点——EchoMusicNext `crates/echo-api/src/module/user_verify.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 匿名身份即可调用；返回的授权串交给 [songAuthorize] 换歌曲级授权。
/// 授权串只用于本次播放链路，不落盘、不进日志。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// 播放授权（user_verify.rs `UserAuthorization`）。
class UserAuthorization {
  const UserAuthorization({required this.valid, required this.authorization});

  /// 上游 `valid` 标志（`valid == 1`）；只作诊断，不是播放的额外门禁。
  final bool valid;

  /// 播放授权串（`data.auth`）。
  final String authorization;
}

/// 上游注释：登录态失败时 `data.auth` 是一段字符串而不是授权对象，
/// 该组合固定以 35005 上报（不是通用业务错）。
const int kugouErrorCodeUserVerifyLoginRequired = 35005;

/// GET /v1/user_verify（网关 + x-router=trackercdngz.kugou.com）。
Future<UserAuthorization> userVerify(
  KugouClient client,
  KugouIdentity identity,
) async {
  final response = await client.sendEndpoint(
    identity,
    const KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/user_verify',
      router: 'trackercdngz.kugou.com',
      method: 'GET',
      params: <String, String>{'module_id': '51'},
    ),
  );
  return _convertUserAuthorization(response.bytes);
}

/// wire 解析（user_verify.rs `convert`）。
UserAuthorization _convertUserAuthorization(Uint8List bytes) {
  final envelope = decodeEnvelope(bytes);
  // 先判登录态失败：上游在通用 success() 之前单列这一分支。
  if (envelope.status == 0 &&
      envelope.errorCode == kugouErrorCodeUserVerifyLoginRequired) {
    throw KugouApiException(
      'authentication',
      '播放授权无效',
      code: envelope.errorCode,
    );
  }
  if (envelope.status != 1 || envelope.errorCode != 0) {
    throw KugouApiException('business', '获取歌曲播放授权失败', code: envelope.errorCode);
  }
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '播放授权响应 data 不是 object');
  }
  // 上游：成功响应必须带非空字符串 auth；`valid` 只上报，不做额外准入。
  final authValue = data['auth'];
  if (authValue is! String || authValue.trim().isEmpty) {
    throw const KugouApiException('authentication', '播放授权无效');
  }
  return UserAuthorization(
    valid: optionalInt(data['valid']) == 1,
    authorization: authValue,
  );
}
