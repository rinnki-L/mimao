/// 账号登录门面（L 线实现）。
///
/// 二维码流程（EchoMusicNext `module/login_qr_key.rs` / `login_qr_check.rs`）：
/// 取码 → 轮询 → 授权成功把 userid/token 并入本地身份。
/// 扫码不返回 `t1`，因此不做 token 自动续期；过期只能重新扫码。
library;

import 'package:mimao/music/api/login_qr.dart' as login_qr;
import 'package:mimao/music/api/music_identity_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
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

/// 生产实现：端点（[login_qr]）负责协议，身份读写走 [MusicIdentityApi]。
///
/// 与 `KugouMusicApi` 共享同一份身份缓存/仓库——登录成功后下一次搜索自动
/// 带上 token/userid（`KugouClient` 的默认参数注入）。
class KugouAccountApi implements MusicAccountApi {
  KugouAccountApi({required this.client, required this.identityApi});

  final KugouClient client;
  final MusicIdentityApi identityApi;

  @override
  Future<QrLoginSession> startQrLogin() async {
    // 先保证 mid/dfid 就绪；端点在内部再剥账号字段（扫码必须匿名）。
    final identity = await identityApi.ensureDevice();
    return login_qr.startQrLogin(client, identity);
  }

  @override
  Future<QrLoginStatus> pollQrLogin(String key) async {
    final identity = await identityApi.ensureDevice();
    return login_qr.pollQrLogin(client, identity, key);
  }

  @override
  Future<KugouIdentity> loginWith(QrAuthorization authorization) async {
    if (authorization.userId == 0 || authorization.token.isEmpty) {
      throw const KugouApiException('input', '登录凭证无效');
    }
    final current =
        await identityApi.currentIdentity() ??
        (throw const KugouApiException('input', '设备身份未引导'));
    final identity = current.withAccount(
      userId: authorization.userId,
      token: authorization.token,
      nickname: authorization.nickname,
      avatarUrl: authorization.avatarUrl,
    );
    await identityApi.saveIdentity(identity);
    return identity;
  }

  @override
  Future<KugouIdentity> logout() async {
    final current =
        await identityApi.currentIdentity() ??
        (throw const KugouApiException('input', '设备身份未引导'));
    // 已匿名时幂等返回（不重复写盘）。
    if (!current.hasAccount) return current;
    final anonymous = current.withoutAccount();
    await identityApi.saveIdentity(anonymous);
    return anonymous;
  }
}
