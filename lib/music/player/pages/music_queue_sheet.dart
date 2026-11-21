// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 「播放队列」右侧抽屉（迷你播放条与播放页共用）。
///
/// 只承载队列：点任意一行切到该曲并关闭抽屉。模式选择已拆到独立的
/// 模式小卡片（music_mode_card.dart），这里不再出现模式控件。
///
/// 用 [showGeneralDialog] 自行滑入，而不是 `Drawer`/`endDrawer`：迷你条同时
/// 寄宿在模块页与播放页两个 Scaffold 上，Overlay 路由不依赖宿主 Scaffold，
/// 更稳。动画固定 250ms（有限），测试里 `pumpAndSettle` 可收敛。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/player/player_store.dart';

/// 从屏幕右侧滑出播放队列抽屉。
Future<void> showMusicQueueSheet(
  BuildContext context,
  MusicPlayerStore player,
) {
  // 宽屏封顶 360，窄屏最多占 86%，给左侧留出遮罩以便点击关闭。
  final drawerWidth = math.min(360.0, MediaQuery.sizeOf(context).width * 0.86);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭播放队列',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final theme = Theme.of(dialogContext);
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          key: const Key('music-queue-drawer'),
          color: theme.colorScheme.surface,
          elevation: 8,
          child: SizedBox(
            width: drawerWidth,
            height: double.infinity,
            child: SafeArea(
              // 抽屉贴右边，右侧安全区由内部 padding 处理即可。
              left: false,
              child: Observer(
                builder: (context) {
                  final queue = player.queue;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '播放队列',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: queue.isEmpty
                            ? const Center(child: Text('播放队列为空'))
                            : ListView.builder(
                                key: const Key('music-queue-list'),
                                padding: const EdgeInsets.only(bottom: 8),
                                itemCount: queue.length,
                                itemBuilder: (context, index) {
                                  final song = queue[index];
                                  final current = index == player.index;
                                  return _QueueTile(
                                    song: song,
                                    current: current,
                                    onTap: () {
                                      player.playAt(index);
                                      Navigator.of(dialogContext).pop();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.song,
    required this.current,
    required this.onTap,
  });

  final MusicSong song;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: current,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: _QueueCover(url: song.coverUrl),
      // 当前曲用 trailing 的喇叭图标提示（selected 高亮仍保留）。
      trailing: current
          ? Icon(Icons.volume_up, color: theme.colorScheme.primary)
          : null,
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
      onTap: onTap,
    );
  }
}

/// 队列行 40×40 封面缩略图，与迷你条 `_MiniCover` 同款圆角与兜底口径：
/// 空 URL 直接给图标；有 URL 走网络图，加载中给进度占位、失败给图标。
class _QueueCover extends StatelessWidget {
  const _QueueCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = Icon(Icons.music_note, color: colorScheme.primary);
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
