/// 音乐 API 门面——UI/Store 依赖的唯一数据入口（对齐 anime/comic 的
/// data source 缝：页面不认识 dio/KugouClient，换实现不改 UI）。
///
/// 生产实现 [KugouMusicApi] = 设备身份引导（ensureDevice）+ 各端点函数的组合；
/// 测试提供 fake 实现即可跑通页面/MobX 流程。
library;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:mimao/music/api/album_api.dart';
import 'package:mimao/music/api/artist_api.dart';
import 'package:mimao/music/api/auth_login_api.dart';
import 'package:mimao/music/api/discovery_api.dart';
import 'package:mimao/music/api/effects_api.dart';
import 'package:mimao/music/api/listen_report_api.dart';
import 'package:mimao/music/api/lyric_api.dart';
import 'package:mimao/music/api/music_browse_apis.dart';
import 'package:mimao/music/api/music_identity_api.dart';
import 'package:mimao/music/music_auth_events.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/api/rank_api.dart';
import 'package:mimao/music/api/register_dev.dart';
// 别名导入：本类的实例方法 searchSongs 会遮蔽同名顶层端点函数。
import 'package:mimao/music/api/search.dart' as search;
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/api/user_profile_api.dart';
import 'package:mimao/music/api/verify_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';

abstract interface class MusicApi {
  /// 搜索单曲（1 起始页码；pageSize 1..100）。
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page,
    int pageSize,
  });

  /// 确保设备身份可用：首次生成匿名身份（guid/mid）并注册真 dfid，
  /// 每一步都落盘。网络失败按 [KugouApiException] 抛出，下次调用重试。
  Future<KugouIdentity> ensureDevice();

  /// 只读当前身份（不生成/不注册/不联网）；未引导过返回 null。
  /// 设置页展示用。
  Future<KugouIdentity?> currentIdentity();
}

/// 生产实现：把 [KugouClient]、[KugouIdentityStore] 与各端点函数装配起来。
///
/// 身份仓库走工厂**惰性解析**——app_registry 装配音乐模块时不碰
/// path_provider（CI/测试无插件环境也能完成注册），首次调用 API 才解析。
class KugouMusicApi implements MusicApi, MusicIdentityApi, MusicAuthEvents {
  KugouMusicApi({
    required this.client,
    required Future<KugouIdentityStore> Function() identityStoreFactory,
    RegisterDeviceFn? register,
  }) : _identityStoreFactory = identityStoreFactory,
       _register = register ?? registerDevice;

  final KugouClient client;

  /// 登录/登出信号：`saveIdentity` 是账号态唯一写入口（扫码线与登录组共用），
  /// 账号态或 userId 变化时递增，页面监听后自动重拉账号数据。
  final ValueNotifier<int> _authEpoch = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get authEpoch => _authEpoch;

  /// 端点组共享会话：与 [ensureDevice] / [_loadIdentity] / [_saveIdentity]
  /// 共用同一份身份缓存（登录后下一搜自动带 token）。
  late final MusicSession session = MusicSession(
    client: client,
    ensureDevice: ensureDevice,
    loadIdentity: _loadIdentity,
    saveIdentity: _saveIdentity,
  );

  // ── 扩容端点组（惰性；首次访问才构造，不联网/不碰插件）──
  late final MusicSearchExtApi searchExt = KugouSearchExtApi(session);
  late final MusicDiscoveryApi discovery = KugouDiscoveryApi(session);
  late final MusicRankApi rank = KugouRankApi(session);
  late final MusicAlbumApi album = KugouAlbumApi(session);
  late final MusicArtistApi artist = KugouArtistApi(session);
  late final MusicEffectsApi effects = KugouEffectsApi(session);
  late final MusicPlaylistReadApi playlistRead = KugouPlaylistReadApi(session);
  late final MusicPlaylistWriteApi playlistWrite = KugouPlaylistWriteApi(
    session,
  );
  late final MusicUserProfileApi userProfile = KugouUserProfileApi(session);
  late final MusicUserLibraryApi userLibrary = KugouUserLibraryApi(session);
  late final MusicAuthApi auth = KugouAuthApi(session);
  late final MusicVerifyApi verify = KugouVerifyApi(session);
  late final MusicLyricApi lyric = KugouLyricApi(session);
  late final MusicPlaybackExtApi playbackExt = KugouPlaybackExtApi(session);
  late final MusicListenReportApi listenReport = KugouListenReportApi(session);

  /// 传给 `MusicModule`/UI 的能力包。
  MusicBrowseApis get browseApis => MusicBrowseApis(
    searchExt: searchExt,
    discovery: discovery,
    rank: rank,
    album: album,
    artist: artist,
    effects: effects,
    playlistRead: playlistRead,
    playlistWrite: playlistWrite,
    userProfile: userProfile,
    userLibrary: userLibrary,
    auth: auth,
    verify: verify,
    lyric: lyric,
    playbackExt: playbackExt,
    listenReport: listenReport,
  );
  final Future<KugouIdentityStore> Function() _identityStoreFactory;

  /// 可注入的注册函数（测试替换，避免真网络）。
  final RegisterDeviceFn _register;

  KugouIdentityStore? _identityStore;

  Future<KugouIdentityStore> _store() async =>
      _identityStore ??= await _identityStoreFactory();

  KugouIdentity? _identity;

  /// 已缓存则直接用；否则读盘；都没有给全空身份（guid 空 = 未引导）。
  Future<KugouIdentity> _loadIdentity() async {
    final cached = _identity;
    if (cached != null) return cached;
    final identity =
        await (await _store()).load() ?? const KugouIdentity.empty();
    _identity = identity;
    return identity;
  }

  Future<void> _saveIdentity(KugouIdentity identity) async {
    final previous = _identity;
    _identity = identity;
    await (await _store()).save(identity);
    final hadAccount = previous?.hasAccount ?? false;
    final hasAccount = identity.hasAccount;
    // 只在账号态真正变化（登录/登出/换号）时通知：设备引导的匿名写入、
    // 同账号刷新 token 都不触发页面重拉。
    if (hadAccount != hasAccount ||
        (hasAccount && previous?.userId != identity.userId)) {
      _authEpoch.value += 1;
    }
  }

  @override
  Future<KugouIdentity> ensureDevice() async {
    var identity = await _loadIdentity();
    if (identity.guid.isEmpty || identity.mid.isEmpty) {
      identity = KugouIdentity.anonymous();
      await _saveIdentity(identity);
    }
    if (identity.needsDeviceRegistration) {
      final registered = await _register(client, identity);
      identity = identity.withDfid(registered.dfid);
      await _saveIdentity(identity);
    }
    return identity;
  }

  @override
  Future<KugouIdentity?> currentIdentity() => _loadIdentity().then(
    (identity) => identity.guid.isEmpty ? null : identity,
  );

  /// [MusicIdentityApi]：登录/登出后的统一写入口——复用同一份缓存与写盘
  /// 逻辑，绝不另起一份状态（否则登录后搜索仍会拿旧 token）。
  @override
  Future<void> saveIdentity(KugouIdentity identity) => _saveIdentity(identity);

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    final identity = await ensureDevice();
    final query = search.SearchSongsQuery(
      keyword: keyword,
      page: page,
      pageSize: pageSize,
    );
    return search.searchSongs(client, identity, query);
  }
}
