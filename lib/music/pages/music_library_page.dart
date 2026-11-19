// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 音乐「我的」页：收藏 / 历史两段（C 线）。
///
/// 页面只依赖 [MusicCollectService] / [MusicHistoryService]（需要列表方法）；
/// 续播只经 [MusicLibraryPlayHandler]（集成方接到 `playerUi.playSong`），
/// 本文件不 import 播放线（P）的任何实现——与 P 线保持编译隔离。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/collect_service.dart';
import 'package:mimao/music/history_service.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_library_store.dart';
import 'package:mimao/music/music_projection.dart';

/// 历史条目点击的续播入口（集成方接线到 `playerStore.playSong`）。
typedef MusicLibraryPlayHandler =
    void Function(MusicSong song, Duration startAt);

/// 「我的」页。`onPlaySong` 为空时，点击只提示「播放功能未接线」。
class MusicLibraryPage extends StatefulWidget {
  const MusicLibraryPage({
    super.key,
    required this.collect,
    required this.history,
    this.onPlaySong,
  });

  final MusicCollectService collect;
  final MusicHistoryService history;
  final MusicLibraryPlayHandler? onPlaySong;

  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  late final MusicLibraryStore _store = MusicLibraryStore(
    widget.collect,
    widget.history,
  );

  @override
  void initState() {
    super.initState();
    // 收藏/历史在搜索页也能被改动（收藏按钮、播放进度），服务写完会通知刷新。
    widget.collect.addListener(_onLibraryChanged);
    widget.history.addListener(_onLibraryChanged);
    _store.refresh();
  }

  @override
  void dispose() {
    widget.collect.removeListener(_onLibraryChanged);
    widget.history.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    _store.refresh();
  }

  void _play(MusicSong song, Duration startAt) {
    // 播完的歌历史位置≈总时长，直接续播会立刻结束；这种起点从 0 重播。
    final total = song.durationMs ?? 0;
    final at = (total > 0 && startAt.inMilliseconds >= total - 2000)
        ? Duration.zero
        : startAt;
    // 打开点校正：以内部权威值刷新投影（失败不影响播放）。
    widget.history.open(song).catchError((Object _) {});
    final handler = widget.onPlaySong;
    if (handler != null) {
      handler(song, at);
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('播放功能未接线')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Observer(
                  builder: (_) => SegmentedButton<int>(
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(
                        value: 0,
                        icon: Icon(Icons.favorite_outline),
                        label: Text('收藏'),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: Icon(Icons.history),
                        label: Text('历史'),
                      ),
                    ],
                    selected: <int>{_store.libraryTab},
                    onSelectionChanged: (selection) =>
                        _store.selectTab(selection.first),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
                onPressed: _store.refresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: Observer(
            builder: (_) {
              if (_store.isLoading && _store.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              final error = _store.error;
              if (error != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(error),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _store.refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              return _store.libraryTab == 0
                  ? _buildCollected()
                  : _buildHistory();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollected() {
    final items = _store.collected;
    if (items.isEmpty) {
      return const _EmptyHint(text: '还没有收藏的歌曲');
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final song = item.song;
        return ListTile(
          key: ValueKey<String>('library-collect-${item.ref.id}'),
          leading: _CoverThumb(url: item.coverUrl),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.artistText.isEmpty ? '已收藏' : item.artistText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.play_circle_outline),
          onTap: song == null ? null : () => _play(song, Duration.zero),
        );
      },
    );
  }

  Widget _buildHistory() {
    final items = _store.history;
    if (items.isEmpty) {
      return const _EmptyHint(text: '还没有播放记录');
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final song = item.song;
        final progress = musicProgressText(
          positionMs: item.position.inMilliseconds,
          durationMs: item.duration.inMilliseconds,
        );
        final artist = song.artistText;
        return ListTile(
          key: ValueKey<String>('library-history-${song.id}'),
          leading: _CoverThumb(
            url: song.coverUrl.isEmpty ? null : song.coverUrl,
          ),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            artist.isEmpty ? progress : '$artist · $progress',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.play_circle_outline),
          onTap: () => _play(song, item.position),
        );
      },
    );
  }
}

/// 封面缩略图；无 URL/加载失败/离线测试时回退到音符占位。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.music_note, color: theme.colorScheme.primary),
    );
    final coverUrl = url;
    if (coverUrl == null || coverUrl.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        coverUrl,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
