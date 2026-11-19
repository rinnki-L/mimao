// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 播放 UI 契约（P 线实现，页面/入口消费）。
///
/// 为什么把「UI」也做成接口：模块页与入口需要 mini player 和播放页，但
/// **不能 import `player/` 的实现**（否则 P 线文件不存在时 C/L 线编译不过）。
/// 实现类住 `player/`，与 `pages/` 之间只认本接口。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_progress.dart';

/// 入口/registry 注入的构造器：P 线实现 `MusicPlayerUi` 后由这里装配。
typedef MusicPlayerUiFactory =
    MusicPlayerUi Function(
      MusicPlaybackApi playbackApi,
      MusicPlaybackEngine Function() engineFactory,
      ProgressSink? progressSink,
    );

/// 「我的」页构造器（C 线提供）：需要能触发播放（续播带起始位置）。
typedef MusicLibraryBuilder =
    Widget Function(
      BuildContext context,
      MusicPlayerUi playerUi,
      MusicCollectApi collect,
      MusicHistoryApi history,
    );

abstract interface class MusicPlayerUi {
  /// 底部迷你播放条；队列为空/未配置播放时返回 null（不渲染）。
  Widget? buildMiniPlayer(BuildContext context);

  /// 完整播放页（从 mini player 或列表点开）。
  Widget buildPlayerPage(BuildContext context);

  /// 播放一首歌；`startAt` 供历史续播。失败由实现方内部呈现（页面/提示），
  /// 不要向调用方抛未捕获异常。
  Future<void> playSong(MusicSong song, {Duration startAt = Duration.zero});

  /// 释放 engine/订阅；模块销毁时调用。
  void dispose();
}
