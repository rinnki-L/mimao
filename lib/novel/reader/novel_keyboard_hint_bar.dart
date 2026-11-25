// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart。
// 阅读页的「按键提示浮层」：桌面端可选，列出当前生效的几组快捷键。
//
// 只是提示，不抢焦点（外层套 IgnorePointer）：始终可读，但不会挡住点按正文。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/reader/novel_keyboard_assist.dart';

class NovelKeyboardHintBar extends StatelessWidget {
  const NovelKeyboardHintBar({
    super.key,
    required this.bindings,
    required this.foreground,
    required this.muted,
    required this.background,
    this.maxItems = 6,
  });

  final List<NovelKeyboardBinding> bindings;

  /// 画布正文色 / 次级色 / 卡片底色（跟随阅读背景明暗，不走 ColorScheme）。
  final Color foreground;
  final Color muted;
  final Color background;

  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final items = normalizedNovelKeyboardBindings(bindings);
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = items.take(maxItems).toList();
    final hidden = items.length - shown.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background.withValues(alpha: .82),
        borderRadius: MimaoShapes.md,
        border: Border.all(color: muted.withValues(alpha: .35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final item in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: muted.withValues(alpha: .18),
                      borderRadius: MimaoShapes.sm,
                    ),
                    child: Text(
                      item.keys,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: MimaoFonts.regular,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.action.label,
                    style: textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: MimaoFonts.regular,
                    ),
                  ),
                ],
              ),
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '还有 $hidden 条（在键盘辅助里看全部）',
                style: textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: MimaoFonts.regular,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
