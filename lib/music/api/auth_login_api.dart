/// 登录端点组门面——EchoMusicNext `module/login*.rs` 十一个端点的组接口
/// （docs/music-api-expansion.md §4：`MusicAuthApi` + `KugouAuthApi`）。
///
/// 端点协议在各自文件（login/login_cellphone/login_token/login_qq/
/// login_openplat/login_qq_qr_*/login_wx_*/login_device*）；本文件只负责
/// 组装与「登录成功后把账号并回身份」（唯一写入口 `session.saveIdentity`，
/// 与搜索/播放共用同一份缓存，登录后下一次请求自动带上新 token/userid）。
///
/// 二维码（login_qr）与既有账号门面不在此列：那是既有扫码线，另行维护。
library;

import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/login_cellphone.dart';
import 'package:mimao/music/api/login_device.dart';
import 'package:mimao/music/api/login_device_kick.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/login_qq.dart';
import 'package:mimao/music/api/login_qq_qr_check.dart';
import 'package:mimao/music/api/login_qq_qr_create.dart';
import 'package:mimao/music/api/login_token.dart';
import 'package:mimao/music/api/login_wx_check.dart';
import 'package:mimao/music/api/login_wx_create.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/auth_models.dart';

/// 登录组接口（页面/Store 只依赖这里，不认识 dio/信封细节）。
abstract interface class MusicAuthApi {
  /// 密码登录（login.rs）。成功后账号并回本地身份。
  Future<MusicLoginAuthorization> login(MusicLoginQuery query);

  /// 手机验证码登录（login_cellphone.rs）。34175 时返回候选列表，
  /// 调方选定后带 [MusicCellphoneQuery.userId] 重试。
  Future<MusicCellphoneLoginResult> loginCellphone(MusicCellphoneQuery query);

  /// token 续期登录（login_token.rs）。要求完整账号与设备身份。
  Future<MusicAccountSession> loginToken();

  /// QQ 开放平台登录（login_qq.rs；partner=1）。成功后账号并回本地身份。
  Future<MusicLoginAuthorization> loginQq(
    MusicProviderAuthorization authorization,
  );

  /// 微信开放平台登录（login_openplat.rs）：
  /// - [MusicOpenplatQuery.authorize] → [MusicProviderAuthorization]（换凭证，
  ///   不写身份）；
  /// - [MusicOpenplatQuery.finish] → [MusicLoginAuthorization]（并回身份）。
  Future<Object> loginOpenplat(MusicOpenplatQuery query);

  /// QQ 扫码创建（login_qq_qr_create.rs；纯 provider 请求）。
  Future<MusicQqQrSession> loginQqQrCreate();

  /// QQ 扫码轮询（login_qq_qr_check.rs）。provider_authorized 时带凭证。
  Future<MusicQqQrCheckResult> loginQqQrCheck(MusicQqQrSession qrSession);

  /// 微信扫码创建（login_wx_create.rs；纯 provider 请求）。
  Future<MusicWxSession> loginWxCreate();

  /// 微信扫码轮询（login_wx_check.rs）。provider_code 时带授权码。
  Future<MusicWxCheckResult> loginWxCheck(String key);

  /// 登录设备列表（login_device.rs；要求账号）。
  Future<List<MusicLoginDevice>> loginDevice();

  /// 踢出其它登录设备（login_device_kick.rs；要求账号）。
  Future<MusicDeviceKickResult> loginDeviceKick(MusicDeviceKickQuery query);
}

/// 生产实现：端点函数（协议）+ 会话（传输与身份读写）。
class KugouAuthApi implements MusicAuthApi {
  KugouAuthApi(this.session);

  final MusicSession session;

  @override
  Future<MusicLoginAuthorization> login(MusicLoginQuery query) async {
    final authorization = await fetchLogin(session, query);
    await _mergeAccount(
      userId: authorization.userId,
      token: authorization.token,
      t1: authorization.refreshCredential,
      nickname: authorization.nickname,
      avatarUrl: authorization.avatarUrl,
    );
    return authorization;
  }

  @override
  Future<MusicCellphoneLoginResult> loginCellphone(
    MusicCellphoneQuery query,
  ) async {
    final result = await fetchLoginCellphone(session, query);
    final authorization = result.authorization;
    if (authorization != null) {
      await _mergeAccount(
        userId: authorization.userId,
        token: authorization.token,
        t1: authorization.refreshCredential,
        nickname: authorization.nickname,
        avatarUrl: authorization.avatarUrl,
      );
    }
    return result;
  }

  @override
  Future<MusicAccountSession> loginToken() async {
    final accountSession = await fetchLoginToken(session);
    await _mergeAccount(
      userId: accountSession.userId,
      token: accountSession.token,
      t1: accountSession.refreshCredential,
      nickname: accountSession.nickname,
      avatarUrl: accountSession.avatarUrl,
    );
    return accountSession;
  }

  @override
  Future<MusicLoginAuthorization> loginQq(
    MusicProviderAuthorization authorization,
  ) async {
    final login = await fetchLoginQq(session, authorization);
    await _mergeAccount(
      userId: login.userId,
      token: login.token,
      t1: login.refreshCredential,
      nickname: login.nickname,
      avatarUrl: login.avatarUrl,
    );
    return login;
  }

  @override
  Future<Object> loginOpenplat(MusicOpenplatQuery query) async {
    final result = await fetchLoginOpenplat(session, query);
    if (result is MusicLoginAuthorization) {
      await _mergeAccount(
        userId: result.userId,
        token: result.token,
        t1: result.refreshCredential,
        nickname: result.nickname,
        avatarUrl: result.avatarUrl,
      );
    }
    return result;
  }

  @override
  Future<MusicQqQrSession> loginQqQrCreate() => fetchLoginQqQrCreate(session);

  @override
  Future<MusicQqQrCheckResult> loginQqQrCheck(MusicQqQrSession qrSession) =>
      fetchLoginQqQrCheck(session, qrSession);

  @override
  Future<MusicWxSession> loginWxCreate() => fetchLoginWxCreate(session);

  @override
  Future<MusicWxCheckResult> loginWxCheck(String key) =>
      fetchLoginWxCheck(session, key);

  @override
  Future<List<MusicLoginDevice>> loginDevice() => fetchLoginDevice(session);

  @override
  Future<MusicDeviceKickResult> loginDeviceKick(MusicDeviceKickQuery query) =>
      fetchLoginDeviceKick(session, query);

  /// 登录成功后的唯一身份写入口：剥旧账号 → 并新账号 → 落盘。
  Future<void> _mergeAccount({
    required int userId,
    required String token,
    required String? t1,
    required String nickname,
    required String avatarUrl,
  }) async {
    final identity = await session.ensureDevice();
    await session.saveIdentity(
      identity.withAccount(
        userId: userId,
        token: token,
        t1: t1 ?? '',
        nickname: nickname,
        avatarUrl: avatarUrl,
      ),
    );
  }
}
