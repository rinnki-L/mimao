// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 播放 UI 的契约实现（`player_ui_impl.dart`）——入口/页面只认
/// `player_ui.dart` 的接口，本文件把 store 包成 [MusicPlayerUi]。
///
/// 工厂 [createMusicPlayerUi] 由 `app_registry.dart` 的 M4-P 缝注入；
/// 引擎仍是惰性求值：这里只传工厂函数，不构造引擎。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/listen_report_api.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/player/pages/music_mini_player.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_progress.dart';
import 'package:mimao/music/player/player_store.dart';
import 'package:mimao/music/player/player_ui.dart';

class MusicPlayerUiImpl implements MusicPlayerUi {
  MusicPlayerUiImpl(this.store, {this.loadClimax});

  final MusicPlayerStore store;

  /// 歌曲高潮加载缝；非空时播放页（含迷你条入口）显示高潮 chip。
  final Future<List<MusicSongClimaxSegment>> Function(String hash)? loadClimax;

  @override
  Widget? buildMiniPlayer(BuildContext context) {
    // 队列为空/未配置播放 → null（调用方不渲染）。队列变化由调用方的
    // `Observer` 驱动重建（模块页已按此接线）。
    if (!store.canPlay || store.queue.isEmpty) return null;
    return MusicMiniPlayer(player: store, loadClimax: loadClimax);
  }

  @override
  Widget buildPlayerPage(BuildContext context) =>
      MusicPlayerPage(player: store, loadClimax: loadClimax);

  @override
  Future<void> playSong(MusicSong song, {Duration startAt = Duration.zero}) =>
      store.playSong(song, startAt: startAt);

  @override
  void dispose() => store.dispose();
}

/// registry 注入用工厂（位置参数与 `MusicPlayerUiFactory` typedef 一致；
/// 新增可选命名参数不影响 typedef 赋值，集成者用闭包适配时按需传入）。
MusicPlayerUi createMusicPlayerUi(
  MusicPlaybackApi playbackApi,
  MusicPlaybackEngine Function() engineFactory,
  ProgressSink? progressSink, {
  MusicListenReportApi? listenReport,
  MusicSettings? settings,
  Future<List<MusicSongClimaxSegment>> Function(String hash)? loadClimax,
}) => MusicPlayerUiImpl(
  MusicPlayerStore(
    playbackApi: playbackApi,
    engineFactory: engineFactory,
    progressSink: progressSink,
    listenReport: listenReport,
    settings: settings,
  ),
  loadClimax: loadClimax,
);
