// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic/anime 入口同款说明。
/// 音乐模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （docs/architecture.md §4.3）。
///
/// **契约提交（M4 三线并行的前置）**：本类只声明三个切片的可选缝，
/// 全部默认 null 且 null 时对应功能隐藏，因此既有测试
/// `MusicModule(api: _FakeApi())` 继续可编译可跑：
/// - 播放（P）：[playbackApi] + [engineFactory] + [progressSink] → [playerUiFactory]
///   懒构造出 [MusicPlayerUi]；
/// - 登录（L）：[account] 透传给设置分组，并在进入模块时驱动全屏登录闸门
///   （匿名每次进入都弹、可跳过）；
/// - 收藏历史（C）：[collect] / [history] / [searchHistory] + [libraryBuilder]。
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/music/api/everyday_style_recommend.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/music_browse_apis.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_account_center_page.dart';
import 'package:mimao/music/pages/music_album_detail_page.dart';
import 'package:mimao/music/pages/music_artist_detail_page.dart';
import 'package:mimao/music/pages/music_discovery_page.dart';
import 'package:mimao/music/pages/music_login_gate.dart';
import 'package:mimao/music/pages/music_module_page.dart';
import 'package:mimao/music/pages/music_module_settings.dart';
import 'package:mimao/music/pages/music_playlist_detail_page.dart';
import 'package:mimao/music/pages/music_playlist_list_page.dart';
import 'package:mimao/music/pages/music_rank_page.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_progress.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 音乐模块入口。
class MusicModule implements AppModule {
  MusicModule({
    required MusicApi api,
    MusicStore? store,
    this.playbackApi,
    this.engineFactory,
    this.progressSink,
    this.playerUiFactory,
    this.account,
    this.collect,
    this.history,
    this.searchHistory,
    this.libraryBuilder,
    this.browse,
    this.settings,
    this.authEpoch,
  }) : _api = api,
       store = store ?? MusicStore(api);

  final MusicApi _api;

  /// 模块生命周期内唯一的 store（在搜索/我的/设置各 tab 间切换时，
  /// 搜索结果等状态保持）。
  final MusicStore store;

  // ── M4-P 播放 ──
  final MusicPlaybackApi? playbackApi;
  final MusicPlaybackEngine Function()? engineFactory;
  final ProgressSink? progressSink;
  final MusicPlayerUiFactory? playerUiFactory;

  // ── M4-L 登录 ──
  final MusicAccountApi? account;

  // ── M4-C 收藏历史 ──
  final MusicCollectApi? collect;
  final MusicHistoryApi? history;
  final MusicSearchHistoryApi? searchHistory;
  final MusicLibraryBuilder? libraryBuilder;

  /// 扩容端点能力包（发现/榜单/专辑/歌手/歌单/用户/账号/歌词…）。
  /// null 时模块退回旧搜索主页，不显示新入口。
  final MusicBrowseApis? browse;

  /// 本地设置（听歌上报开关）；null 时设置页不显示开关。播放器侧的同一份
  /// 实例由 registry 注入（见 app_registry 的 createMusicPlayerUi 闭包）。
  final MusicSettings? settings;

  /// 登录态变化信号；页面监听后自动重拉账号数据。null 时不监听（旧行为）。
  final ValueListenable<int>? authEpoch;

  /// 播放 UI 懒构造：P 线产品路径才注入 [playerUiFactory]；测试/未接线时
  /// 保持 null，绝不触碰 media_kit。
  MusicPlayerUi? _playerUi;
  bool _playerUiResolved = false;

  MusicPlayerUi? get _resolvePlayerUi {
    if (_playerUiResolved) return _playerUi;
    _playerUiResolved = true;
    final factory = playerUiFactory;
    final playback = playbackApi;
    final engines = engineFactory;
    if (factory != null && playback != null && engines != null) {
      _playerUi = factory(playback, engines, progressSink);
    }
    return _playerUi;
  }

  @override
  MediaType get type => MediaType.music;

  @override
  String get label => '音乐';

  @override
  IconData get icon => MediaType.music.icon;

  @override
  Widget buildHome(BuildContext context) {
    final player = _resolvePlayerUi;
    final collect = this.collect;
    final history = this.history;
    final builder = libraryBuilder;
    final browseApis = browse;
    final libraryTab =
        (builder != null &&
            player != null &&
            collect != null &&
            history != null)
        ? builder(context, player, collect, history)
        : null;

    // 发现页（搜索扩展 + 推荐）：只有搜索扩展/发现/播放三者都就绪才替换
    // 旧搜索首 tab；否则保持既有搜索主页，不影响未接线环境。
    final searchExt = browseApis?.searchExt;
    final discovery = browseApis?.discovery;
    final discoveryTab =
        (player != null && searchExt != null && discovery != null)
        ? MusicDiscoveryPage(
            searchExt: searchExt,
            discovery: discovery,
            store: store,
            player: player,
            collect: collect,
            searchHistory: searchHistory,
            authEpoch: authEpoch,
            onOpenRank: browseApis?.rank == null
                ? null
                : () => _openRank(context),
          )
        : null;

    // 「我的」页顶部的歌单入口；缺任何一项就隐藏，避免死链。
    final canOpenPlaylists =
        player != null &&
        browseApis?.userLibrary != null &&
        browseApis?.playlistRead != null;

    final userProfile = browseApis?.userProfile;
    final userLibrary = browseApis?.userLibrary;
    final accountTab =
        (player != null && userProfile != null && userLibrary != null)
        ? MusicAccountCenterPage(
            profile: userProfile,
            library: userLibrary,
            player: player,
            authEpoch: authEpoch,
            onOpenAlbum: browseApis?.album == null
                ? null
                : (id) => _openAlbum(context, id),
            onOpenPlaylist: browseApis?.playlistRead == null
                ? null
                : (playlist) => _openUserPlaylist(context, playlist),
            // 音乐偏好页的官方标签候选：首载空 tagIds 即完整标签目录；
            // discovery 未接线时传 null，候选区静默隐藏。
            loadPreferenceTagGroups: discovery == null
                ? null
                : () async => (await discovery.everydayStyleRecommend(
                    const EverydayStyleRecommendQuery(),
                  )).groups,
          )
        : null;

    final home = MusicModulePage(
      store: store,
      embedded: true,
      playerUi: player,
      collect: collect,
      searchHistory: searchHistory,
      libraryTab: libraryTab,
      accountTab: accountTab,
      browseTab: discoveryTab,
      onOpenPlaylists: canOpenPlaylists ? () => _openPlaylists(context) : null,
      // 各入口的设置放进各入口：账号/设备设置作为最右侧「设置」tab。
      settingsTab: buildSettings(context),
    );
    // 未登录时每次进入都全屏弹扫码（可跳过）；account 未接线时直接返回主页，
    // 不套闸门层（既有测试断言 buildHome 返回 MusicModulePage 的锚点不变）。
    final loginAccount = account;
    if (loginAccount == null) return home;
    return MusicLoginGate(
      api: _api,
      account: loginAccount,
      // L5：登录扩展门面齐备时全屏登录页带「使用其他方式登录」。
      auth: browseApis?.auth,
      verify: browseApis?.verify,
      searchExt: browseApis?.searchExt,
      child: home,
    );
  }

  void _openAlbum(BuildContext context, int albumId) {
    final api = browse?.album;
    final player = _resolvePlayerUi;
    if (api == null || player == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/album'),
        builder: (_) => MusicAlbumDetailPage(
          album: api,
          albumId: albumId,
          player: player,
          playbackExt: browse?.playbackExt,
          onOpenArtist: browse?.artist == null
              ? null
              : (id) => _openArtist(context, id),
        ),
      ),
    );
  }

  void _openArtist(BuildContext context, int artistId) {
    final api = browse?.artist;
    final player = _resolvePlayerUi;
    if (api == null || player == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/artist'),
        builder: (_) => MusicArtistDetailPage(
          artist: api,
          artistId: artistId,
          player: player,
          playbackExt: browse?.playbackExt,
          onOpenAlbum: browse?.album == null
              ? null
              : (id) => _openAlbum(context, id),
        ),
      ),
    );
  }

  void _openUserPlaylist(BuildContext context, MusicUserPlaylist playlist) {
    final read = browse?.playlistRead;
    final player = _resolvePlayerUi;
    if (read == null || player == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/playlist'),
        builder: (_) => MusicPlaylistDetailPage(
          read: read,
          player: player,
          globalId: playlist.globalId,
          cloudListId: playlist.cloudListId,
          title: playlist.title,
          coverUrl: playlist.coverUrl,
          write: browse?.playlistWrite,
          // 账号中心「我的歌单」行直接进详情：同样透传可编辑事实，否则
          // 只有列表页入口能写、这里会静默变成只读。
          editable: playlist.editable == true,
          // 写端点需要的版本/归属/简介事实从列表条目透传；missing 时页面
          // 自己隐藏写入口（不臆造版本号）。
          revision: playlist.revision,
          sortIndex: playlist.sortIndex,
          kind: MusicPlaylistKind.fromWire(playlist.kindCode),
          description: playlist.descriptionPresent
              ? playlist.description
              : null,
          tags: playlist.tagsPresent ? playlist.tags : null,
          searchSongs: _searchSongs,
        ),
      ),
    );
  }

  void _openPlaylists(BuildContext context) {
    final library = browse?.userLibrary;
    final read = browse?.playlistRead;
    final player = _resolvePlayerUi;
    if (library == null || read == null || player == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/playlists'),
        builder: (_) => MusicPlaylistListPage(
          library: library,
          read: read,
          player: player,
          write: browse?.playlistWrite,
          searchSongs: _searchSongs,
        ),
      ),
    );
  }

  /// 添加歌曲页的搜索缝：把 [MusicApi.searchSongs] 的命名参数形态适配成
  /// `MusicSongSearch` 的位置参数 + 可选分页（页面不依赖 MusicApi）。
  Future<MusicPage<MusicSong>> _searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) => _api.searchSongs(keyword: keyword, page: page, pageSize: pageSize);

  void _openRank(BuildContext context) {
    final api = browse?.rank;
    final player = _resolvePlayerUi;
    if (api == null || player == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/rank'),
        builder: (_) => MusicRankPage(api: api, player: player),
      ),
    );
  }

  @override
  Widget buildSettings(BuildContext context) {
    return MusicModuleSettings(
      api: _api,
      account: account,
      // L5：扩展入口都按「注入才显示」处理，缺一项不出现死链。
      auth: browse?.auth,
      verify: browse?.verify,
      searchExt: browse?.searchExt,
      settings: settings,
    );
  }
}
