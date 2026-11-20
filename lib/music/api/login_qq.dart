/// QQ 开放平台登录端点——EchoMusicNext `crates/echo-api/src/module/login_qq.rs`
/// 的逐函数翻译。
///
/// 请求装配完全复用 [openplatLoginBytes]（util/login_protocol.rs `openplat`，
/// partner=1 时 body 附带 `third_appid`）；响应凭证**必须**是密文（无明文
/// token 兜底），解密失败/空凭证一律 decode/authentication。
library;

import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/auth_models.dart';

/// /v6/login_by_openplat（partner=1；网关 + x-router=login.user.kugou.com）。
///
/// `timestampMs`/`seed` 仅供测试注入。
Future<MusicLoginAuthorization> fetchLoginQq(
  MusicSession session,
  MusicProviderAuthorization authorization, {
  int? timestampMs,
  String? seed,
}) async {
  final identity = await session.ensureDevice();
  final (bytes, responseSeed) = await openplatLoginBytes(
    session.client,
    identity,
    1,
    authorization,
    timestampMs: timestampMs,
    seed: seed,
  );
  return openplatAuthorization(bytes, responseSeed);
}
