// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 PlayerPage / player_demo.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/media_kit_playback_engine.dart';
import 'package:mimao/anime/player/playback_engine.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/anime/player/player_page.dart';

/// 番剧播放器页——只负责把 B 线内核接到一个完整生命周期里。
///
/// [engineFactory] 可注入：widget 测试传 FakePlaybackEngine 工厂即可完全离线，
/// 不会初始化 media_kit；生产路径由 app_registry 注入 [MediaKitPlaybackEngine]。
/// 本页不实现自动续播/手势/弹幕，PlayerController 的加载/错误/重试/切集/倍速原样保留。
class AnimePlayerPage extends StatefulWidget {
  const AnimePlayerPage({
    super.key,
    required this.title,
    required this.episodes,
    required this.initialIndex,
    required this.recorder,
    required this.engineFactory,
  });

  final String title;
  final List<Episode> episodes;
  final int initialIndex;
  final ProgressRecorder recorder;
  final PlaybackEngine Function() engineFactory;

  @override
  State<AnimePlayerPage> createState() => _AnimePlayerPageState();
}

class _AnimePlayerPageState extends State<AnimePlayerPage> {
  late final PlaybackEngine _engine;
  late final PlayerController _controller;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    _engine = widget.engineFactory();
    _controller = PlayerController(
      engine: _engine,
      episodes: widget.episodes,
      initialIndex: widget.initialIndex,
      progressRecorder: widget.recorder,
    );
    if (_engine is MediaKitPlaybackEngine) {
      _videoController = VideoController(_engine.player);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;
    return PlayerPage(
      controller: _controller,
      video: videoController == null
          ? null
          : Video(controller: videoController),
      title: widget.title,
    );
  }

  @override
  void dispose() {
    // PlayerController 负责释放 engine；VideoController 随 Video.dispose 释放。
    _controller.dispose();
    super.dispose();
  }
}
