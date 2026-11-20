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
/// - 登录（L）：[account] 透传给设置分组；
/// - 收藏历史（C）：[collect] / [history] / [searchHistory] + [libraryBuilder]。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_module_page.dart';
import 'package:mimao/music/pages/music_module_settings.dart';
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
    final libraryTab =
        (builder != null &&
            player != null &&
            collect != null &&
            history != null)
        ? builder(context, player, collect, history)
        : null;
    return MusicModulePage(
      store: store,
      embedded: true,
      playerUi: player,
      collect: collect,
      searchHistory: searchHistory,
      libraryTab: libraryTab,
      // 各入口的设置放进各入口：账号/设备设置作为最右侧「设置」tab。
      settingsTab: buildSettings(context),
    );
  }

  @override
  Widget buildSettings(BuildContext context) {
    return MusicModuleSettings(api: _api, account: account);
  }
}
