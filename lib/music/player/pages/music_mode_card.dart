// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 播放模式小卡片：从模式按钮上方弹出，只列「另外两种」模式。
///
/// 中文名与图标集中定义在本文件（[playModeLabel] / [playModeIcon]），迷你
/// 播放条的当前模式按钮与卡片选项都从这里取，避免文案漂移。
///
/// 用 [showGeneralDialog] 挂在根 Overlay 上，而不是在迷你条内部用 Stack
/// 溢出——迷你条外层 Material 是 `clipBehavior: antiAlias`，越界的小卡片会
/// 被裁掉。Overlay 不受宿主裁剪，且动画有限，测试里 `pumpAndSettle` 可收敛。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/player/play_mode.dart';

/// 模式中文名（按钮 tooltip / 卡片选项共用）。
String playModeLabel(PlayMode mode) {
  switch (mode) {
    case PlayMode.shuffle:
      return '随机';
    case PlayMode.repeatOne:
      return '单曲循环';
    case PlayMode.listLoop:
      return '列表循环';
  }
}

/// 模式图标（按钮当前态与卡片选项共用）。
IconData playModeIcon(PlayMode mode) {
  switch (mode) {
    case PlayMode.shuffle:
      return Icons.shuffle;
    case PlayMode.repeatOne:
      return Icons.repeat_one;
    case PlayMode.listLoop:
      return Icons.repeat;
  }
}

/// 卡片宽度与单行高度（配合 [options] 数量即可预算卡片高度，用于定位）。
const double _cardWidth = 160;
const double _rowHeight = 48;
const double _cardPadding = 8;

/// 在 [anchor]（模式按钮的顶部中点，全局坐标）上方弹出模式选择小卡片。
///
/// 只渲染 [PlayMode.values] 中不等于 [current] 的模式；点选返回该模式，
/// 点遮罩或返回键返回 null。上方空间不足（如播放页 AppBar）时落到按钮
/// 下方，避免卡片跑出屏幕。
Future<PlayMode?> showPlayModeCard(
  BuildContext context,
  Offset anchor,
  PlayMode current,
) {
  final options = PlayMode.values
      .where((mode) => mode != current)
      .toList(growable: false);
  final cardHeight = _cardPadding * 2 + _rowHeight * options.length;
  final screen = MediaQuery.sizeOf(context);
  final topInset = MediaQuery.paddingOf(context).top;
  // 水平方向以按钮中心对齐，并夹紧在屏幕内（按钮通常贴近右边）。
  final left = (anchor.dx - _cardWidth / 2).clamp(
    8.0,
    screen.width - _cardWidth - 8.0,
  );
  // 默认在按钮上方留 8 的间距；上方放不下时改为按钮下方。
  var top = anchor.dy - cardHeight - 8;
  if (top < topInset + 8) top = anchor.dy + 44;

  return showGeneralDialog<PlayMode>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭播放模式选择',
    barrierColor: Colors.black12,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final theme = Theme.of(dialogContext);
      return Stack(
        children: <Widget>[
          Positioned(
            left: left,
            top: top,
            child: Material(
              key: const Key('music-mode-card'),
              elevation: 8,
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: MimaoShapes.md,
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: _cardWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: _cardPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final mode in options)
                        InkWell(
                          key: Key('music-mode-option-${mode.name}'),
                          onTap: () => Navigator.of(dialogContext).pop(mode),
                          child: SizedBox(
                            height: _rowHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    playModeIcon(mode),
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    playModeLabel(mode),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        ),
  );
}
