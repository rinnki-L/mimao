// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与小说模块其他页面同款说明。
/// 小说模块页面共用的占位骨架件（MD3 填充卡 + 统一图标/文案/说明）。
///
/// 本阶段 tab 屏不接真实解析与数据，全部用 [NovelPlaceholderScreen] 撑起结构；
/// 后续切片把每个 tab 的占位内容替换成真实列表即可，外壳不动。
library;

import 'package:flutter/material.dart';

/// 一个 tab 的占位屏：顶部标题 + 居中的 MD3 说明卡。
class NovelPlaceholderScreen extends StatelessWidget {
  const NovelPlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    this.showAppBar = false,
    this.action,
  });

  final String title;
  final IconData icon;
  final String description;

  /// 模块内嵌到壳时由壳提供顶部栏，本屏不再画自己的 AppBar。
  final bool showAppBar;

  /// 可选操作按钮（如书源页的「导入」示意）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final card = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 56, color: cs.primary),
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: 20),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!showAppBar) return card;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: card,
    );
  }
}

/// 书源页「导入」操作示意按钮（占位：点击走 [onPressed]，由模块页接到 typed 路由）。
class NovelPlaceholderImportButton extends StatelessWidget {
  const NovelPlaceholderImportButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_link),
      label: const Text('从网络导入'),
    );
  }
}
