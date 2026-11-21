// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 模块页底部的迷你播放条（M4-P）。
///
/// 队列为空时由 [MusicPlayerUiImpl.buildMiniPlayer] 返回 null，本组件只在
/// 有当前曲目时被挂载。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/pages/music_wavy_progress.dart';
import 'package:mimao/music/player/player_store.dart';

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({
    super.key,
    required this.player,
    this.loadClimax,
    this.loadLyric,
    this.playbackExt,
  });

  final MusicPlayerStore player;

  /// 透传给播放页的高潮加载缝；null 时播放页不显示高潮 chip。
  final Future<List<MusicSongClimaxSegment>> Function(String hash)? loadClimax;

  /// 透传给播放页的歌词加载缝；null 时播放页右侧显示「暂无歌词」。
  final LoadLyric? loadLyric;

  /// 透传给播放页的歌曲资料入口；null 时播放页不显示资料按钮。
  final MusicPlaybackExtApi? playbackExt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Observer(
      builder: (context) {
        final song = player.currentSong;
        if (song == null) return const SizedBox.shrink();
        // 圆角悬浮卡（r14 + 细描边），不再通栏贴底——MD3 的浮动播放条形态。
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: MimaoShapes.md,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: 'music/player'),
                  builder: (context) => MusicPlayerPage(
                    player: player,
                    loadClimax: loadClimax,
                    loadLyric: loadLyric,
                    playbackExt: playbackExt,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
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
                          IconButton.filled(
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
                    // 卡片底部波浪进度：只画不管手势，IgnorePointer 让整卡点击
                    // 仍进播放页；progress 由 MobX 快照实时驱动。
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        key: const Key('mini-wavy-progress'),
                        height: 10,
                        child: MiniWavyProgress(
                          progress: player.snapshot.duration.inMilliseconds <= 0
                              ? 0
                              : (player.snapshot.position.inMilliseconds /
                                        player.snapshot.duration.inMilliseconds)
                                    .clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                  ],
                ),
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
      borderRadius: MimaoShapes.sm,
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
