// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 播放页（M4-P，最小可用）：封面/歌名/歌手/进度条/播放暂停/上一首下一首/
/// 错误态与重试；队列放进底部抽屉（不单独开页）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/player/player_store.dart';

class MusicPlayerPage extends StatelessWidget {
  const MusicPlayerPage({super.key, required this.player});

  final MusicPlayerStore player;

  void _openQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Observer(
          builder: (context) {
            if (player.queue.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('播放队列为空'),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: player.queue.length,
              itemBuilder: (context, index) {
                final song = player.queue[index];
                final current = index == player.index;
                return ListTile(
                  selected: current,
                  leading: Icon(
                    current ? Icons.volume_up : Icons.music_note,
                    color: current
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    _displayTitle(song.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artistText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    player.playAt(index);
                    Navigator.of(sheetContext).pop();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: <Widget>[
          IconButton(
            tooltip: '播放队列',
            icon: const Icon(Icons.queue_music),
            onPressed: () => _openQueue(context),
          ),
        ],
      ),
      body: Observer(
        builder: (context) {
          final song = player.currentSong;
          if (song == null) {
            return const Center(child: Text('暂无播放曲目'));
          }
          final snapshot = player.snapshot;
          final failure = player.error;
          final durationMs = snapshot.duration.inMilliseconds;
          final positionMs = durationMs <= 0
              ? 0
              : snapshot.position.inMilliseconds.clamp(0, durationMs);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                _Cover(url: song.coverUrl),
                const SizedBox(height: 20),
                Text(
                  _displayTitle(song.title),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  song.artistText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (failure != null) ...<Widget>[
                  Text(
                    failure,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: player.retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
                const SizedBox(height: 8),
                Slider(
                  value: positionMs.toDouble(),
                  max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                  onChanged: durationMs <= 0 ? null : (value) {},
                  onChangeEnd: durationMs <= 0
                      ? null
                      : (value) => player.seekTo(
                          Duration(milliseconds: value.round()),
                        ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(_formatDuration(snapshot.position)),
                    Text(_formatDuration(snapshot.duration)),
                  ],
                ),
                const SizedBox(height: 8),
                if (player.isResolving)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton.filledTonal(
                        tooltip: '上一首',
                        iconSize: 32,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: player.previous,
                      ),
                      const SizedBox(width: 16),
                      IconButton.filled(
                        tooltip: snapshot.playing ? '暂停' : '播放',
                        iconSize: 40,
                        icon: Icon(
                          snapshot.playing ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: player.toggle,
                      ),
                      const SizedBox(width: 16),
                      IconButton.filledTonal(
                        tooltip: '下一首',
                        iconSize: 32,
                        icon: const Icon(Icons.skip_next),
                        onPressed: player.next,
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 240,
      height: 240,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.xl,
      ),
      child: Icon(Icons.music_note, size: 96, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    // widget 测试无网络：errorBuilder/loadingBuilder 缺一个都会抛异常。
    return ClipRRect(
      borderRadius: MimaoShapes.xl,
      child: Image.network(
        url,
        width: 240,
        height: 240,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(
                width: 240,
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

/// 展示层剥掉复杂搜索的 `<em>` 高亮标签。
String _displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds <= 0) return '0:00';
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
