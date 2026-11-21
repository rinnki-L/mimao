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
                    // 卡片底部波浪进度：外层兜底点击仍进播放页，条自身是可
                    // seek 的手势区（子级 recognizer 赢竞技场，不会触发整卡
                    // onTap）；progress 由 MobX 快照实时驱动。
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _MiniSeekBar(
                        player: player,
                        progress: player.snapshot.duration.inMilliseconds <= 0
                            ? 0
                            : (player.snapshot.position.inMilliseconds /
                                      player.snapshot.duration.inMilliseconds)
                                  .clamp(0.0, 1.0),
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

/// 迷你条底部的可交互 seek 条。
///
/// 外层整卡 [InkWell] 负责进播放页，本组件作为它的子级注册自己的拖拽/
/// 点按 recognizer：命中在条上时手势竞技场由子级先赢，整卡 onTap 不会触发。
/// 命中区比视觉条高（视觉 16，命中 28），方便手指点按。
///
/// seek 时机：拖动/按住过程中只在本地暂存 fraction 做即时预览，点按抬起或
/// 拖动结束时才调用一次 [MusicPlayerStore.seekTo]——seekTo 会顺带写一次
/// 播放进度（DB），每帧都调会造成写放大。
class _MiniSeekBar extends StatefulWidget {
  const _MiniSeekBar({required this.player, required this.progress});

  final MusicPlayerStore player;

  /// 当前播放进度（0..1），来自外层的 MobX 快照。
  final double progress;

  @override
  State<_MiniSeekBar> createState() => _MiniSeekBarState();
}

class _MiniSeekBarState extends State<_MiniSeekBar> {
  /// 按住/拖动中的即时预览值；null 表示跟随 [MusicMiniPlayer] 的播放进度。
  double? _preview;

  /// 命中区高度：视觉条仍 16，上下各留 6 给手指。
  static const double _hitHeight = 28;

  /// 视觉条高度（strokeWidth 7 + 上下各 3.5 振幅 ≈ 14，留 16 避免裁切）。
  static const double _visualHeight = 16;

  double get _shown => _preview ?? widget.progress;

  double _fractionAt(double localDx, double width) =>
      width <= 0 ? 0 : (localDx / width).clamp(0.0, 1.0);

  void _previewAt(double localDx, double width) {
    setState(() => _preview = _fractionAt(localDx, width));
  }

  /// 提交一次 seek：duration 未知时只清预览、不发 seek。
  ///
  /// 预览值保留到 seekTo 完成，避免「松手 → 进度闪回旧值 → 快照更新」的回跳。
  void _commit() {
    final fraction = _preview;
    if (fraction == null) return;
    final durationMs = widget.player.snapshot.duration.inMilliseconds;
    if (durationMs <= 0) {
      setState(() => _preview = null);
      return;
    }
    widget.player
        .seekTo(Duration(milliseconds: (fraction * durationMs).round()))
        .whenComplete(() {
          if (!mounted || _preview != fraction) return;
          setState(() => _preview = null);
        });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 所有回调都非空：duration 未知时仍要占住手势竞技场，否则事件会
        // 冒泡到整卡 InkWell 直接进播放页。
        return GestureDetector(
          key: const Key('mini-wavy-progress'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _previewAt(details.localPosition.dx, width),
          onTapUp: (details) {
            _previewAt(details.localPosition.dx, width);
            _commit();
          },
          onHorizontalDragStart: (details) =>
              _previewAt(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) =>
              _previewAt(details.localPosition.dx, width),
          onHorizontalDragEnd: (details) => _commit(),
          child: SizedBox(
            height: _hitHeight,
            child: Center(
              child: SizedBox(
                height: _visualHeight,
                width: double.infinity,
                child: MiniWavyProgress(
                  height: _visualHeight,
                  progress: _shown,
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
