/// 登录端点组的结果模型——EchoMusicNext `crates/echo-api/src/domain.rs` 的
/// `LoginAuthorization` / `AccountSession` / `LoginDevice` 与
/// `module/login_cellphone.rs` / `login_qq_qr_create.rs` / `login_wx_create.rs` /
/// `login_wx_check.rs` / `login_device_kick.rs` 各自 wire DTO 的模型化。
///
/// 凭证字段（token/t1/openid/access_token）只在内存里流转，不序列化落盘
/// ——身份落盘统一走 `KugouIdentity.withAccount` + `session.saveIdentity`。
library;

/// 密码/手机号/第三方登录成功后的授权（domain.rs `LoginAuthorization`）。
///
/// 初始登录可能不带续期凭证/过期时间；缺省保持 null，不臆造值。
class MusicLoginAuthorization {
  const MusicLoginAuthorization({
    required this.userId,
    required this.token,
    required this.refreshCredential,
    required this.expiresAtSeconds,
    required this.nickname,
    required this.avatarUrl,
  });

  final int userId;
  final String token;

  /// 续期凭证 t1；服务未给或为空串时为 null。
  final String? refreshCredential;

  /// 过期秒级时间戳；缺省或 <=0 时为 null。
  final int? expiresAtSeconds;

  final String nickname;
  final String avatarUrl;
}

/// token 续期登录的完整会话（domain.rs `AccountSession`）：
/// 与 [MusicLoginAuthorization] 的差别是续期凭证必填（协议本身校验非空）。
class MusicAccountSession {
  const MusicAccountSession({
    required this.userId,
    required this.token,
    required this.refreshCredential,
    required this.expiresAtSeconds,
    required this.nickname,
    required this.avatarUrl,
  });

  final int userId;
  final String token;
  final String refreshCredential;
  final int? expiresAtSeconds;
  final String nickname;
  final String avatarUrl;
}

/// 手机验证码登录撞上 34175（多账号）时的候选账号
/// （login_cellphone.rs `WireCandidate` → 上游 JSON 输出字段）。
class MusicLoginCandidate {
  const MusicLoginCandidate({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.username,
    required this.appId,
  });

  final int userId;

  /// 展示名：nickname 非空用之，否则 username，否则 userid 文本。
  final String nickname;
  final String avatarUrl;
  final String username;

  /// wire `appid`；缺省/类型错为 null（optional）。
  final int? appId;
}

/// 手机验证码登录结果（login_cellphone.rs `convert` 的两个出口）：
/// 授权成功（[authorization] 非空）或要求选择账号（[selectAccount]）。
class MusicCellphoneLoginResult {
  const MusicCellphoneLoginResult.authorized(this.authorization)
    : selectAccount = false,
      candidates = const <MusicLoginCandidate>[];

  const MusicCellphoneLoginResult.selectAccount(this.candidates)
    : selectAccount = true,
      authorization = null;

  /// true 表示服务要求先选账号（error_code=34175），此时 [candidates] 有值。
  final bool selectAccount;
  final MusicLoginAuthorization? authorization;
  final List<MusicLoginCandidate> candidates;
}

/// 第三方开放平台凭证（util/login_protocol.rs `Authorization`）——
/// openid/access_token 只在内存中传递，不进 QML/日志。
class MusicProviderAuthorization {
  const MusicProviderAuthorization({
    required this.openid,
    required this.accessToken,
  });

  final String openid;
  final String accessToken;
}

/// QQ 扫码创建结果（login_qq_qr_create.rs `Session` + `image_data_url`）。
///
/// [cookie]/[ptLoginSig]/[qrsig] 是会话材料，轮询时原样回传。
class MusicQqQrSession {
  const MusicQqQrSession({
    required this.xloginUrl,
    required this.ptLoginSig,
    required this.qrsig,
    required this.cookie,
    required this.ptqrtoken,
    required this.openloginData,
    required this.imageDataUrl,
  });

  /// 授权跳板页 URL（后续轮询的 Referer）。
  final String xloginUrl;
  final String ptLoginSig;
  final String qrsig;
  final String cookie;

  /// hash33(qrsig)，轮询参数 `ptqrtoken`。
  final int ptqrtoken;

  /// xlogin URL 的 query 原样文本（轮询参数 `pt_openlogin_data`）。
  final String openloginData;
  final String imageDataUrl;
}

/// QQ 扫码轮询结果（login_qq_qr_check.rs `convert` 状态字符串）。
class MusicQqQrCheckResult {
  const MusicQqQrCheckResult({required this.state, this.authorization});

  static const String stateWaiting = 'waiting';
  static const String stateExpired = 'expired';
  static const String stateScanned = 'scanned';
  static const String stateProviderAuthorized = 'provider_authorized';

  /// [stateProviderAuthorized] 时携带 [authorization]。
  final String state;
  final MusicProviderAuthorization? authorization;
}

/// 微信扫码创建结果（login_wx_create.rs `Session`）。
class MusicWxSession {
  const MusicWxSession({required this.key, required this.imageDataUrl});

  final String key;
  final String imageDataUrl;
}

/// 微信扫码轮询结果（login_wx_check.rs `Status` 状态字符串）。
class MusicWxCheckResult {
  const MusicWxCheckResult({required this.state, required this.code});

  static const String stateWaiting = 'waiting';
  static const String stateScanned = 'scanned';
  static const String stateExpired = 'expired';
  static const String stateProviderCode = 'provider_code';

  /// [stateProviderCode] 时携带授权码，其余为 null。
  final String state;
  final String? code;
}

/// 登录设备列表行（domain.rs `LoginDevice`）。
class MusicLoginDevice {
  const MusicLoginDevice({
    required this.id,
    required this.transportFingerprint,
    required this.model,
    required this.platform,
    required this.location,
    required this.loginType,
    required this.activeAtSeconds,
    required this.newAtSeconds,
    required this.appId,
    required this.clientVersion,
    required this.current,
  });

  /// 设备 mid，也是踢出目标 id。
  final String id;

  /// 目标设备指纹（dev_logout 的 transport_fingerprint），仅供协议使用。
  final String transportFingerprint;
  final String model;
  final String platform;
  final String location;

  /// wire `login_type`；本地刷新会话上报 -1，未知码保留。
  final int? loginType;
  final int? activeAtSeconds;
  final int? newAtSeconds;
  final int? appId;
  final int? clientVersion;
  final bool current;
}

/// 踢出设备的应答（login_device_kick.rs `Acknowledgement`）。
class MusicDeviceKickResult {
  const MusicDeviceKickResult({required this.removed});

  final bool removed;
}
