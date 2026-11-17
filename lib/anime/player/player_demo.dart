// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart（同 lib/main.dart 说明）。
// ════════════════════════════════════════════════════════════════════════
// B 线手动验收入口（不属于产品导航；不改 lib/main.dart / app_registry）。
//
//   flutter run -d windows -t lib/anime/player/player_demo.dart
//
// 验收清单：
//   □ 第 1 话（公开 m3u8）能起播，画面出现
//   □ 拖动进度条能跳转（松手后生效）
//   □ 点第 2 话（m3u8）/第 3 话（直链 MP4）切集正常
//   □ 暂停 → 继续、倍速菜单（0.5x–3x）生效
//   □ 暂停/切集后，core 投影里出现 progressText（时间线可见）
//   □ 错误态：把任一 URL 改坏后重进，出现"播放失败 + 重试"
//
// 无真机/模拟器时可只跑单测并把播放三项标"待验"（本机当前即此状态）。
// ════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/media_kit_playback_engine.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/anime/player/player_page.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:path_provider/path_provider.dart';

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

  final AppDb db = AppDb();
  final library = LibraryRepository(db);
  final supportDir = await getApplicationSupportDirectory();
  final recorder = LibraryProgressRecorder(
    library: library,
    store: JsonFileAnimeProgressStore(
      File('${supportDir.path}${Platform.pathSeparator}anime_progress.json'),
    ),
    entryId: 'anime:demo:hardcoded',
    sourceName: '演示源（硬编码）',
    title: '硬编码视频源验证',
  );

  runApp(_PlayerDemoApp(recorder: recorder));
}

class _PlayerDemoApp extends StatefulWidget {
  const _PlayerDemoApp({required this.recorder});

  final ProgressRecorder recorder;

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
