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
import 'package:mimao/music/player/pages/music_mode_card.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/pages/music_queue_sheet.dart';
import 'package:mimao/music/player/pages/music_wavy_progress.dart';
import 'package:mimao/music/player/player_store.dart';

/// 迷你条按钮统一 36×36：三个按钮总宽固定 108，便于在卡片中精确居中。
const ButtonStyle _miniIconButtonStyle = ButtonStyle(
  padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
  minimumSize: WidgetStatePropertyAll<Size>(Size(36, 36)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

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
        // 在 Observer 的 builder 里读取：Builder 子树的读取不在追踪范围内。
        final playMode = player.playMode;
        // 圆角悬浮卡（r14 + 细描边），不再通栏贴底——MD3 的浮动播放条形态。
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
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
                        // 左：封面 + 歌名/歌手。与右侧 Expanded 均分空白，
                        // 中间固定宽度的按钮组因此落在卡片水平中心。
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              _MiniCover(url: song.coverUrl),
                              const SizedBox(width: 8),
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
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 中：上一首 / 播放暂停 / 下一首。
                        SizedBox(
                          width: 108,
                          height: 40,
                          child: player.isResolving
                              ? const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    IconButton(
                                      key: const Key('mini-previous'),
                                      tooltip: '上一首',
                                      iconSize: 20,
                                      style: _miniIconButtonStyle,
                                      icon: const Icon(Icons.skip_previous),
                                      onPressed: player.previous,
                                    ),
                                    IconButton.filled(
                                      key: const Key('mini-play-pause'),
                                      tooltip: player.snapshot.playing
                                          ? '暂停'
                                          : '播放',
                                      iconSize: 22,
                                      style: _miniIconButtonStyle,
                                      icon: Icon(
                                        player.snapshot.playing
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      onPressed: player.toggle,
                                    ),
                                    IconButton(
                                      key: const Key('mini-next'),
                                      tooltip: '下一首',
                                      iconSize: 20,
                                      style: _miniIconButtonStyle,
                                      icon: const Icon(Icons.skip_next),
                                      onPressed: player.next,
                                    ),
                                  ],
                                ),
                        ),
                        // 右：播放模式（上方弹小卡片）+ 歌曲列表（右侧抽屉）。
                        // 两个独立按钮仍在同一个固定宽度的 Expanded 里，
                        // 不参与中段 108 的居中计算。
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Builder(
                                  builder: (buttonContext) => IconButton(
                                    key: const Key('mini-play-mode'),
                                    tooltip: '播放模式',
                                    iconSize: 22,
                                    style: _miniIconButtonStyle,
                                    icon: Icon(playModeIcon(playMode)),
                                    onPressed: () async {
                                      // 以按钮顶部中点作为卡片锚点，卡片在
                                      // 按钮上方弹出（Overlay 不惧迷你条裁剪）。
                                      final box =
                                          buttonContext.findRenderObject()
                                              as RenderBox?;
                                      final anchor = box == null
                                          ? Offset.zero
                                          : box.localToGlobal(
                                              Offset(box.size.width / 2, 0),
                                            );
                                      final mode = await showPlayModeCard(
                                        context,
                                        anchor,
                                        playMode,
                                      );
                                      if (mode != null) {
                                        player.setPlayMode(mode);
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  key: const Key('mini-queue'),
                                  tooltip: '播放列表',
                                  iconSize: 22,
                                  style: _miniIconButtonStyle,
                                  icon: const Icon(Icons.queue_music),
                                  onPressed: () =>
                                      showMusicQueueSheet(context, player),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 卡片底部波浪进度：只画不管手势，IgnorePointer 让整卡点击
                    // 仍进播放页；progress 由 MobX 快照实时驱动。
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        key: const Key('mini-wavy-progress'),
                        // strokeWidth 7 + 上下各 3.5 振幅 ≈ 14；留 16 避免裁切。
                        height: 16,
                        child: MiniWavyProgress(
                          height: 16,
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
