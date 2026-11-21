// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 播放页（M4-P，最小可用）：封面/歌名/歌手/进度条/播放暂停/上一首下一首/
/// 错误态与重试；队列放进底部抽屉（不单独开页）。
///
/// L4 起为 StatefulWidget：持有「当前曲目高潮区间」的页面级状态（不用
/// store 的 @observable，避免 build_runner）；`loadClimax` 为空或 hash
/// 非 32 位时不取，失败静默、无数据不显示。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/player/player_store.dart';

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key, required this.player, this.loadClimax});

  final MusicPlayerStore player;

  /// 歌曲高潮区间加载缝（集成者传 `discovery.songClimax`）；null 时整段隐藏。
  final Future<List<MusicSongClimaxSegment>> Function(String hash)? loadClimax;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  /// 已发起过高潮加载的歌曲 key（每首歌只取一次；失败也不重试）。
  String? _climaxSongKey;

  /// 当前歌曲的高潮区间；null = 加载中/无数据/失败（统一不显示 chip）。
  List<MusicSongClimaxSegment>? _climaxSegments;

  MusicPlayerStore get player => widget.player;

  /// Observer builder 内检测换歌并按需发起高潮加载。
  ///
  /// 为什么在 build 里收口副作用：换歌信号来自 store 的 observable（本页
  /// 不新增 @observable），Observer 每次重建时按歌曲 key 比对一次是最小
  /// 接线；同步部分只改普通字段，结果回来才 setState。
  void _ensureClimax(MusicSong song) {
    final key = song.id.isNotEmpty ? song.id : song.hash;
    if (_climaxSongKey == key) return;
    _climaxSongKey = key;
    _climaxSegments = null; // 换歌丢弃旧结果
    unawaited(_loadClimax(key, song.hash));
  }

  Future<void> _loadClimax(String requestKey, String hash) async {
    final load = widget.loadClimax;
    // 高潮端点只认 32 位 hash（song_climax.rs valid_hash 的长度约束）。
    if (load == null || hash.length != 32) return;
    try {
      final segments = await load(hash);
      // 慢请求期间换歌：按发起时的歌曲 key 比对，不一致就丢弃旧结果。
      if (!mounted || _climaxSongKey != requestKey) return;
      setState(() => _climaxSegments = segments);
    } on Object {
      // 失败静默：保持隐藏，不影响播放。
    }
  }

  /// 「高潮 mm:ss–mm:ss」chip 列表（点击 seek 到高潮起点）；无数据显示空。
  List<Widget> _climaxChips() {
    final segments = _climaxSegments;
    if (segments == null) return const <Widget>[];
    final chips = <Widget>[];
    for (final segment in segments) {
      final startMs = segment.startMs;
      final endMs = segment.endMs;
      if (startMs == null || endMs == null || endMs < startMs) continue;
      chips.add(
        ActionChip(
          tooltip: '跳到高潮',
          label: Text(
            '高潮 ${_formatDuration(Duration(milliseconds: startMs))}'
            '–${_formatDuration(Duration(milliseconds: endMs))}',
          ),
          onPressed: () => player.seekTo(Duration(milliseconds: startMs)),
        ),
      );
    }
    if (chips.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: chips,
      ),
    ];
  }

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
          _ensureClimax(song);
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
                ..._climaxChips(),
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
