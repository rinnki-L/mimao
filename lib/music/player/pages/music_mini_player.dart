// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 模块页底部的迷你播放条（M4-P）。
///
/// 队列为空时由 [MusicPlayerUiImpl.buildMiniPlayer] 返回 null，本组件只在
/// 有当前曲目时被挂载。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/player_store.dart';

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({super.key, required this.player});

  final MusicPlayerStore player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Observer(
      builder: (context) {
        final song = player.currentSong;
        if (song == null) return const SizedBox.shrink();
        return Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => MusicPlayerPage(player: player),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: <Widget>[
                  _MiniCover(url: song.coverUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _displayTitle(song.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          song.artistText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (player.isResolving)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      tooltip: player.snapshot.playing ? '暂停' : '播放',
                      icon: Icon(
                        player.snapshot.playing
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      onPressed: player.toggle,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.music_note,
      color: Theme.of(context).colorScheme.primary,
    );
    if (url.isEmpty) {
      return SizedBox(width: 40, height: 40, child: Center(child: fallback));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            SizedBox(width: 40, height: 40, child: Center(child: fallback)),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(
                width: 40,
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
      ),
    );
  }
}

/// wire 的 SongName 可能带 `<em>` 高亮标签（复杂搜索命中高亮），展示层剥掉。
String _displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');
