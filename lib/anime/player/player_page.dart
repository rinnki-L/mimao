// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart（同 lib/main.dart 说明）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/anime/player/player_controller.dart';

/// 最小播放页：视频区 + 进度条 + 传输控制 + 剧集列表。
///
/// 刻意不做弹幕/手势/画中画（留给后续里程碑）。[video] 是视频输出槽：
/// 演示入口传 media_kit 的 `Video`，单测可传占位 widget——页面本身不依赖解码。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.controller,
    this.video,
    this.title = '播放器',
    this.autoStart = true,
  });

  final PlayerController controller;
  final Widget? video;
  final String title;
  final bool autoStart;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  /// 拖动中的本地值：避免每次 onChanged 都打后端 seek。
  double? _dragMillis;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.controller.start());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final controller = widget.controller;
    return Column(
      children: [
        Expanded(child: _buildVideoArea(context, controller)),
        _buildProgressBar(context, controller),
        _buildControls(context, controller),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '剧集 ${controller.index + 1}/${controller.episodeCount}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        SizedBox(height: 64, child: _buildEpisodeList(controller)),
      ],
    );
  }

  Widget _buildVideoArea(BuildContext context, PlayerController controller) {
    final error = controller.errorMessage;
    final textTheme = Theme.of(context).textTheme;
    final Widget center;
    if (error != null && controller.status == PlayerStatus.error) {
      center = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              '播放失败',
              style: textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('player-retry'),
              onPressed: () => unawaited(controller.start()),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    } else if (controller.isLoading) {
      center = const CircularProgressIndicator();
    } else {
      center =
          widget.video ??
          const Icon(Icons.movie_outlined, color: Colors.white38, size: 72);
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: center),
          if (controller.buffering && controller.status != PlayerStatus.error)
            const Positioned(
              top: 16,
              right: 16,
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, PlayerController controller) {
    final totalMillis = controller.duration.inMilliseconds;
    final maxMillis = totalMillis > 0 ? totalMillis.toDouble() : 1.0;
    final positionMillis = _dragMillis ?? controller.position.inMilliseconds;
    final value = positionMillis.toDouble().clamp(0.0, maxMillis);
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Text(
            _formatDuration(Duration(milliseconds: positionMillis.round())),
            style: labelStyle,
          ),
          Expanded(
            child: Slider(
              key: const Key('player-slider'),
              value: value,
              max: maxMillis,
              onChanged: totalMillis > 0
                  ? (next) => setState(() => _dragMillis = next)
                  : null,
              onChangeEnd: totalMillis > 0
                  ? (next) {
                      setState(() => _dragMillis = null);
                      unawaited(
                        controller.seek(Duration(milliseconds: next.round())),
                      );
                    }
                  : null,
            ),
          ),
          Text(_formatDuration(controller.duration), style: labelStyle),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, PlayerController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('player-prev'),
            tooltip: '上一集',
            onPressed: controller.hasPrevious
                ? () => unawaited(controller.loadEpisode(controller.index - 1))
                : null,
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            key: const Key('player-play-pause'),
            tooltip: controller.isPlaying ? '暂停' : '播放',
            onPressed: () => unawaited(controller.togglePlay()),
            icon: Icon(
              controller.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 36,
            ),
          ),
          IconButton(
            key: const Key('player-next'),
            tooltip: '下一集',
            onPressed: controller.hasNext
                ? () => unawaited(controller.loadEpisode(controller.index + 1))
                : null,
            icon: const Icon(Icons.skip_next),
          ),
          PopupMenuButton<double>(
            key: const Key('player-speed'),
            tooltip: '倍速',
            initialValue: controller.speed,
            onSelected: (speed) => unawaited(controller.setSpeed(speed)),
            itemBuilder: (context) => <PopupMenuEntry<double>>[
              for (final speed in PlayerController.speedPresets)
                PopupMenuItem<double>(
                  value: speed,
                  child: Text('${_speedLabel(speed)}x'),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${_speedLabel(controller.speed)}x'),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                controller.currentEpisode.title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeList(PlayerController controller) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: controller.episodeCount,
      separatorBuilder: (context, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final episode = controller.episodes[index];
        return ChoiceChip(
          key: Key('episode-$index'),
          label: Text(
            episode.title.isEmpty ? '第 ${episode.number} 话' : episode.title,
          ),
          selected: index == controller.index,
          onSelected: (_) => unawaited(controller.loadEpisode(index)),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String _speedLabel(double speed) {
  final text = speed.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
