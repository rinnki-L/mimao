// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart（同 lib/main.dart 说明）。
// ════════════════════════════════════════════════════════════════════════
// B 线手动验收入口（不属于产品导航；不改 lib/main.dart / app_registry）。
//
//   flutter run -d windows -t lib/anime/player/player_demo.dart
//
// 进度写入已收敛：本 demo 不再自建 JSON store，而是经
// AnimeHistoryProgressRecorder → AnimeHistoryService.saveProgress，
// 与收藏/历史共用同一条权威写入口（docs/anime-dual-ledger.md §5）。
//
// 验收清单：
//   □ 第 1 话（公开 m3u8）能起播，画面出现
//   □ 拖动进度条能跳转（松手后生效）
//   □ 点第 2 话（m3u8）/第 3 话（直链 MP4）切集正常
//   □ 暂停 → 继续、倍速菜单（0.5x–3x）生效
//   □ 暂停/切集后，统一书架出现一条"硬编码视频源验证"，进度文案与位置一致
//   □ 切集再暂停 → 同一条投影更新，不出现第二条；退出重进仍只有一条
//   □ 错误态：把任一 URL 改坏后重进，出现"播放失败 + 重试"
//
// 无真机/模拟器时可只跑单测并把播放三项标"待验"（本机当前即此状态）。
// ════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mimao/anime/anime_db.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/media_kit_playback_engine.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/anime/player/player_page.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

/// 硬编码验证源：两路 HLS + 一路直链，刚好覆盖"m3u8 与直链"和"切集"。
const List<Episode> demoEpisodes = <Episode>[
  Episode(
    number: 1,
    title: '第 1 话 · HLS',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  Episode(
    number: 2,
    title: '第 2 话 · HLS',
    url:
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
        'img_bipbop_adv_example_fmp4/master.m3u8',
  ),
  Episode(
    number: 3,
    title: '第 3 话 · 直链',
    url: 'https://media.w3.org/2010/05/sintel/trailer.mp4',
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AppDb 的生命周期与进程一致：demo 全程只有一个实例，LibraryRepository、
  // AnimeHistoryService、Recorder 都持有它，退出由 OS 统一回收；不在此处 close，
  // 以免关库早于 PlayerController.dispose 触发的最后一笔异步落盘。
  final AppDb db = AppDb();
  final library = LibraryRepository(db);

  // AnimeDb 是收敛后的唯一权威库，由本 demo 显式持有并在退出时释放。
  final AnimeDb animeDb = AnimeDb();
  final history = AnimeHistoryService(animeDb, library);
  final recorder = AnimeHistoryProgressRecorder(
    history: history,
    entryId: 'anime:demo:hardcoded',
    sourceName: '演示源（硬编码）',
    title: '硬编码视频源验证',
  );

  runApp(_PlayerDemoApp(recorder: recorder, onClose: animeDb.close));
}

class _PlayerDemoApp extends StatefulWidget {
  const _PlayerDemoApp({required this.recorder, required this.onClose});

  final ProgressRecorder recorder;

  /// 释放权威库（AnimeDb）的回调，由 demo 退出时调用。
  final Future<void> Function() onClose;

  @override
  State<_PlayerDemoApp> createState() => _PlayerDemoAppState();
}

class _PlayerDemoAppState extends State<_PlayerDemoApp> {
  late final MediaKitPlaybackEngine _engine;
  late final PlayerController _controller;
  late final VideoController _videoController;

  @override
  void initState() {
    super.initState();
    _engine = MediaKitPlaybackEngine();
    _controller = PlayerController(
      engine: _engine,
      episodes: demoEpisodes,
      progressRecorder: widget.recorder,
    );
    _videoController = VideoController(_engine.player);
  }

  @override
  void dispose() {
    _controller.dispose();
    // dispose 内部的最后一笔进度落盘是 unawaited 的：让过一个事件循环再关库，
    // 避免写操作落到已关闭的 executor 上（写失败已被 controller 吞进 error 态）。
    unawaited(() async {
      await Future<void>.delayed(Duration.zero);
      await widget.onClose();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'mimao · 播放器内核验收',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6750A4)),
      home: PlayerPage(
        controller: _controller,
        video: Video(controller: _videoController),
        title: '播放器内核验收（硬编码源）',
      ),
    );
  }
}
