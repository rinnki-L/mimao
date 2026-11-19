/// 账号登录门面（L 线实现）。
///
/// 二维码流程（EchoMusicNext `module/login_qr_key.rs` / `login_qr_check.rs`）：
/// 取码 → 轮询 → 授权成功把 userid/token 并入本地身份。
/// 扫码不返回 `t1`，因此不做 token 自动续期；过期只能重新扫码。
library;

import 'package:mimao/music/client/kugou_identity.dart';

/// 二维码会话状态（上游 `data.status` 0/1/2/4 的模型化）。
enum QrLoginState { waiting, scanned, authorized, expired }

/// 取码结果：key 用于轮询，imageDataUrl 是服务端直接给的 PNG data URL。
class QrLoginSession {
  const QrLoginSession({required this.key, required this.imageDataUrl});

  final String key;
  final String imageDataUrl;
}

/// 授权成功时返回的账号凭证。
class QrAuthorization {
  const QrAuthorization({
    required this.userId,
    required this.token,
    this.nickname = '',
    this.avatarUrl = '',
  });

  final int userId;
  final String token;
  final String nickname;
  final String avatarUrl;
}

/// 一次轮询的结果；仅 [QrLoginState.authorized] 时携带 [authorization]。
class QrLoginStatus {
  const QrLoginStatus({required this.state, this.authorization});

  final QrLoginState state;
  final QrAuthorization? authorization;
}

abstract interface class MusicAccountApi {
  /// 取新二维码（匿名身份请求）。
  Future<QrLoginSession> startQrLogin();

  /// 轮询；调用方负责节奏（控制器每 2 秒）。
  Future<QrLoginStatus> pollQrLogin(String key);

  /// 把授权并入本地身份并落盘，返回新身份。
  Future<KugouIdentity> loginWith(QrAuthorization authorization);

  /// 清除账号字段、保留设备身份；返回匿名身份。
  Future<KugouIdentity> logout();
}
