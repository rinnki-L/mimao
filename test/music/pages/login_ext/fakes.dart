// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它测试同款说明。
/// 登录扩展测试替身：纯内存、不联网、无真实计时器。
///
/// fake 按调用次序消费响应队列；队列取空后轮询类返回 waiting（默认态），
/// 一次性类抛 StateError（配置遗漏要显式失败）。
library;

import 'package:mimao/music/api/auth_login_api.dart';
import 'package:mimao/music/api/captcha_sent.dart';
import 'package:mimao/music/api/get_verify_info.dart';
import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/login_cellphone.dart';
import 'package:mimao/music/api/login_device_kick.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/search.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/search_lyric.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/api/sidedt.dart';
import 'package:mimao/music/api/verify_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/models/auth_models.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:mimao/music/models/verify_models.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/player/play_mode.dart';

/// 1×1 PNG 的 base64（二维码图片渲染用，不读真实文件）。
const String kPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// 认证失败（匿名/未登录）的统一入口——kind 对齐 KugouApiException 词表。
KugouApiException authenticationError() =>
    const KugouApiException('authentication', '请先登录');

// ── 模型工厂 ──────────────────────────────────────────────────────────────

MusicLoginAuthorization authorizedLogin({int userId = 42}) =>
    MusicLoginAuthorization(
      userId: userId,
      token: 'token-value',
      refreshCredential: null,
      expiresAtSeconds: null,
      nickname: '小明',
      avatarUrl: '',
    );

MusicCellphoneLoginResult cellphoneAuthorized({int userId = 42}) =>
    MusicCellphoneLoginResult.authorized(authorizedLogin(userId: userId));

const List<MusicLoginCandidate> cellphoneCandidates = <MusicLoginCandidate>[
  MusicLoginCandidate(
    userId: 1001,
    nickname: '账号一',
    avatarUrl: '',
    username: 'user_one',
    appId: null,
  ),
  MusicLoginCandidate(
    userId: 1002,
    nickname: '账号二',
    avatarUrl: '',
    username: 'user_two',
    appId: 5,
  ),
];

MusicQqQrSession fakeQqSession() => MusicQqQrSession(
  xloginUrl: 'https://xui.ptlogin2.qq.com/cgi-bin/xlogin',
  ptLoginSig: 'pt-login-sig',
  qrsig: 'qrsig-value',
  cookie: 'pt_login_sig=pt-login-sig; qrsig=qrsig-value',
  ptqrtoken: 123456,
  openloginData: 'openlogin-data',
  imageDataUrl: 'data:image/png;base64,$kPngBase64',
);

MusicWxSession fakeWxSession() => MusicWxSession(
  key: 'wx-key',
  imageDataUrl: 'data:image/jpeg;base64,$kPngBase64',
);

MusicLoginDevice fakeDevice({
  required String id,
  required bool current,
  String model = '设备',
  String platform = 'Android',
  String location = '广东深圳',
  int? activeAtSeconds = 1760000000,
  int? appId = 100,
  int? clientVersion = 11440,
}) => MusicLoginDevice(
  id: id,
  transportFingerprint: 'mt-fingerprint',
  model: model,
  platform: platform,
  location: location,
  loginType: 0,
  activeAtSeconds: activeAtSeconds,
  newAtSeconds: null,
  appId: appId,
  clientVersion: clientVersion,
  current: current,
);

MusicVerificationConfiguration fakeVerifyConfig({
  String provider = 'sms',
  String vendor = 'TX',
  String displayMessage = '请输入短信验证码完成验证',
  int verificationType = 32,
  List<int> availableTypes = const <int>[23, 32],
}) => MusicVerificationConfiguration(
  provider: provider,
  vendor: vendor,
  appId: 'tx-appid',
  displayMessage: displayMessage,
  verificationType: verificationType,
  availableTypes: availableTypes,
  businessId: null,
  sessionId: null,
  partnerStatus: const <String, int>{},
  protocolFlag: null,
);

// ── API 替身 ──────────────────────────────────────────────────────────────

/// 登录组替身：记录查询参数，结果按调用次序消费。
class FakeAuthApi implements MusicAuthApi {
  // 手机号验证码登录。
  final List<MusicCellphoneQuery> cellphoneQueries = <MusicCellphoneQuery>[];
  Object? cellphoneError;
  final List<MusicCellphoneLoginResult> cellphoneResults =
      <MusicCellphoneLoginResult>[];

  // QQ 扫码。
  int qqCreateCalls = 0;
  MusicQqQrSession? qqSession;
  Object? qqCreateError;
  final List<MusicQqQrCheckResult> qqCheckStates = <MusicQqQrCheckResult>[];
  Object? qqCheckError;
  int qqCheckCalls = 0;
  final List<MusicProviderAuthorization> qqLogins =
      <MusicProviderAuthorization>[];
  int qqLoginCalls = 0;
  Object? qqLoginError;

  // 微信扫码 + openplat 两步登录。
  int wxCreateCalls = 0;
  MusicWxSession? wxSession;
  Object? wxCreateError;
  final List<MusicWxCheckResult> wxCheckStates = <MusicWxCheckResult>[];
  Object? wxCheckError;
  int wxCheckCalls = 0;
  final List<MusicOpenplatQuery> openplatQueries = <MusicOpenplatQuery>[];
  int openplatCalls = 0;

  /// authorize/finish 的结果队列（MusicProviderAuthorization /
  /// MusicLoginAuthorization）；取空抛 StateError。
  final List<Object> openplatResults = <Object>[];
  Object? openplatError;

  // 登录设备。
  int deviceCalls = 0;
  List<MusicLoginDevice> devices = const <MusicLoginDevice>[];
  Object? deviceError;
  final List<MusicDeviceKickQuery> kickQueries = <MusicDeviceKickQuery>[];
  int kickCalls = 0;
  Object? kickError;

  @override
  Future<MusicCellphoneLoginResult> loginCellphone(
    MusicCellphoneQuery query,
  ) async {
    cellphoneQueries.add(query);
    final Object? error = cellphoneError;
    if (error != null) throw error;
    if (cellphoneResults.isEmpty) {
      throw StateError('FakeAuthApi: 未配置 cellphoneResults');
    }
    return cellphoneResults.removeAt(0);
  }

  @override
  Future<MusicQqQrSession> loginQqQrCreate() async {
    qqCreateCalls++;
    final Object? error = qqCreateError;
    if (error != null) throw error;
    final MusicQqQrSession? session = qqSession;
    if (session == null) throw StateError('FakeAuthApi: 未配置 qqSession');
    return session;
  }

  @override
  Future<MusicQqQrCheckResult> loginQqQrCheck(
    MusicQqQrSession qrSession,
  ) async {
    qqCheckCalls++;
    final Object? error = qqCheckError;
    if (error != null) throw error;
    // 状态按次序消费；取空回 waiting（未授权前的常态）。
    if (qqCheckStates.isEmpty) {
      return const MusicQqQrCheckResult(
        state: MusicQqQrCheckResult.stateWaiting,
      );
    }
    return qqCheckStates.removeAt(0);
  }

  @override
  Future<MusicLoginAuthorization> loginQq(
    MusicProviderAuthorization authorization,
  ) async {
    qqLoginCalls++;
    qqLogins.add(authorization);
    final Object? error = qqLoginError;
    if (error != null) throw error;
    return authorizedLogin();
  }

  @override
  Future<Object> loginOpenplat(MusicOpenplatQuery query) async {
    openplatCalls++;
    openplatQueries.add(query);
    final Object? error = openplatError;
    if (error != null) throw error;
    if (openplatResults.isEmpty) {
      throw StateError('FakeAuthApi: 未配置 openplatResults');
    }
    return openplatResults.removeAt(0);
  }

  @override
  Future<MusicWxSession> loginWxCreate() async {
    wxCreateCalls++;
    final Object? error = wxCreateError;
    if (error != null) throw error;
    final MusicWxSession? session = wxSession;
    if (session == null) throw StateError('FakeAuthApi: 未配置 wxSession');
    return session;
  }

  @override
  Future<MusicWxCheckResult> loginWxCheck(String key) async {
    wxCheckCalls++;
    final Object? error = wxCheckError;
    if (error != null) throw error;
    if (wxCheckStates.isEmpty) {
      return const MusicWxCheckResult(
        state: MusicWxCheckResult.stateWaiting,
        code: null,
      );
    }
    return wxCheckStates.removeAt(0);
  }

  @override
  Future<List<MusicLoginDevice>> loginDevice() async {
    deviceCalls++;
    final Object? error = deviceError;
    if (error != null) throw error;
    return devices;
  }

  @override
  Future<MusicDeviceKickResult> loginDeviceKick(
    MusicDeviceKickQuery query,
  ) async {
    kickCalls++;
    kickQueries.add(query);
    final Object? error = kickError;
    if (error != null) throw error;
    return const MusicDeviceKickResult(removed: true);
  }

  @override
  Future<MusicLoginAuthorization> login(MusicLoginQuery query) =>
      throw UnimplementedError();

  @override
  Future<MusicAccountSession> loginToken() => throw UnimplementedError();
}

/// 验证组替身：发码 / 挑战配置。
class FakeVerifyApi implements MusicVerifyApi {
  final List<MusicCaptchaSentQuery> captchaQueries = <MusicCaptchaSentQuery>[];
  int captchaCalls = 0;
  Object? captchaError;

  final List<MusicVerifyInfoQuery> verifyInfoQueries = <MusicVerifyInfoQuery>[];
  int verifyInfoCalls = 0;
  MusicVerificationConfiguration? verifyInfo;
  Object? verifyInfoError;

  @override
  Future<bool> captchaSent(MusicCaptchaSentQuery query) async {
    captchaCalls++;
    captchaQueries.add(query);
    final Object? error = captchaError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<MusicVerificationConfiguration> getVerifyInfo(
    MusicVerifyInfoQuery query,
  ) async {
    verifyInfoCalls++;
    verifyInfoQueries.add(query);
    final Object? error = verifyInfoError;
    if (error != null) throw error;
    final MusicVerificationConfiguration? config = verifyInfo;
    if (config == null) throw StateError('FakeVerifyApi: 未配置 verifyInfo');
    return config;
  }
}

/// 搜索扩展替身：只实现 sideDt（本片用到的唯一方法）。
class FakeSearchExtApi implements MusicSearchExtApi {
  final List<MusicSideDtQuery> sideDtQueries = <MusicSideDtQuery>[];
  int sideDtCalls = 0;
  Object? sideDtError;
  bool acknowledged = true;

  @override
  Future<MusicSideDtAcknowledgement> sideDt(MusicSideDtQuery query) async {
    sideDtCalls++;
    sideDtQueries.add(query);
    final Object? error = sideDtError;
    if (error != null) throw error;
    return MusicSideDtAcknowledgement(acknowledged: acknowledged);
  }

  @override
  Future<MusicPage<MusicAlbumSummary>> searchAlbums(SearchSongsQuery query) =>
      throw UnimplementedError();

  @override
  Future<MusicPage<MusicArtistSummary>> searchArtists(SearchSongsQuery query) =>
      throw UnimplementedError();

  @override
  Future<MusicPage<MusicPlaylistSummary>> searchPlaylists(
    SearchSongsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<MusicPage<MusicLyricHit>> searchLyrics(SearchSongsQuery query) =>
      throw UnimplementedError();

  @override
  Future<MusicSearchDefault> searchDefault() => throw UnimplementedError();

  @override
  Future<List<MusicHotSearchGroup>> searchHot() => throw UnimplementedError();

  @override
  Future<MusicSearchSuggestions> searchSuggest(MusicSearchSuggestQuery query) =>
      throw UnimplementedError();

  @override
  Future<List<MusicLyricCandidate>> searchLyric(MusicSearchLyricQuery query) =>
      throw UnimplementedError();
}

/// 本地设置替身（听歌上报开关 + 歌词开关/模式 + 播放模式）。
class FakeMusicSettings implements MusicSettings {
  FakeMusicSettings({
    bool initial = true,
    bool lyricEnabled = true,
    LyricMode lyricMode = LyricMode.original,
    PlayMode playMode = PlayMode.listLoop,
  }) : _enabled = initial,
       _lyricEnabled = lyricEnabled,
       _lyricMode = lyricMode,
       _playMode = playMode;

  bool _enabled;
  bool _lyricEnabled;
  LyricMode _lyricMode;
  PlayMode _playMode;
  bool loaded = false;
  int ensureLoadedCalls = 0;
  final List<bool> savedValues = <bool>[];
  final List<bool> savedLyricValues = <bool>[];
  final List<LyricMode> savedLyricModes = <LyricMode>[];
  final List<PlayMode> savedPlayModes = <PlayMode>[];
  Object? saveError;

  @override
  bool get listenReportEnabled => _enabled;

  @override
  bool get lyricEnabled => _lyricEnabled;

  @override
  LyricMode get lyricMode => _lyricMode;

  @override
  PlayMode get playMode => _playMode;

  @override
  Future<void> ensureLoaded() async {
    ensureLoadedCalls++;
    loaded = true;
  }

  @override
  Future<void> setListenReportEnabled(bool value) async {
    final Object? error = saveError;
    if (error != null) throw error;
    savedValues.add(value);
    _enabled = value;
  }

  @override
  Future<void> setLyricEnabled(bool value) async {
    final Object? error = saveError;
    if (error != null) throw error;
    savedLyricValues.add(value);
    _lyricEnabled = value;
  }

  @override
  Future<void> setLyricMode(LyricMode mode) async {
    final Object? error = saveError;
    if (error != null) throw error;
    savedLyricModes.add(mode);
    _lyricMode = mode;
  }

  @override
  Future<void> setPlayMode(PlayMode mode) async {
    final Object? error = saveError;
    if (error != null) throw error;
    savedPlayModes.add(mode);
    _playMode = mode;
  }
}

/// MusicApi 替身（设置页/闸门的必填依赖）。
class FakeMusicApi implements MusicApi {
  FakeMusicApi(this.identity);

  final KugouIdentity? identity;

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async => const MusicPage<MusicSong>(items: <MusicSong>[]);

  @override
  Future<KugouIdentity> ensureDevice() async =>
      identity ?? KugouIdentity.anonymous();

  @override
  Future<KugouIdentity?> currentIdentity() async => identity;
}

/// 账号门面替身（闸门扫码线 / 设置页扫码对话框用）。
class FakeAccountApi implements MusicAccountApi {
  FakeAccountApi({
    this.imageDataUrl = 'data:image/png;base64,$kPngBase64',
    this.states = const <QrLoginState>[QrLoginState.waiting],
  });

  final String imageDataUrl;
  List<QrLoginState> states;
  int polls = 0;

  @override
  Future<QrLoginSession> startQrLogin() async =>
      QrLoginSession(key: 'KEY', imageDataUrl: imageDataUrl);

  @override
  Future<QrLoginStatus> pollQrLogin(String key) async {
    final index = polls++;
    final state = index < states.length ? states[index] : states.last;
    return QrLoginStatus(
      state: state,
      authorization: state == QrLoginState.authorized
          ? const QrAuthorization(
              userId: 42,
              token: 'token-value',
              nickname: '小明',
              avatarUrl: '',
            )
          : null,
    );
  }

  @override
  Future<KugouIdentity> loginWith(QrAuthorization authorization) async =>
      KugouIdentity.anonymous()
          .withDfid('dfid1234567890')
          .withAccount(
            userId: authorization.userId,
            token: authorization.token,
            nickname: authorization.nickname,
            avatarUrl: authorization.avatarUrl,
          );

  @override
  Future<KugouIdentity> logout() async =>
      KugouIdentity.anonymous().withDfid('dfid1234567890');
}
