// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他三个模块的页面同款说明：保持类型一致、patch 可重放。
/// 小说导航骨架的 typed 路由表（对齐 legado-with-MD3 的 `MainNavKey` 思路）。
///
/// 每个路由有稳定的 [NovelRoute.routeName]（进 `RouteSettings.name`，dev/navigate
/// 可按名定位）与中文标题；[NovelRoutePage] 是统一占位屏，真实页面随后续切片
/// 把 builder 换掉即可，路由名与参数契约不变。
library;

import 'package:flutter/material.dart';

/// 小说模块内可导航的页面集合。仅冻结路由身份与展示信息，不含页面实现。
enum NovelRoute {
  bookInfo('novel/book-info', '书籍详情', Icons.menu_book),
  toc('novel/toc', '目录', Icons.list_alt),
  read('novel/read', '阅读', Icons.auto_stories),
  search('novel/search', '搜索', Icons.search),
  sourceManage('novel/source-manage', '书源管理', Icons.source),
  sourceEdit('novel/source-edit', '书源编辑', Icons.edit_note),
  settings('novel/settings', '设置', Icons.settings);

  const NovelRoute(this.routeName, this.label, this.icon);

  /// 稳定路由名，同时作为 `RouteSettings.name`（dev/navigate 可寻址）。
  final String routeName;

  /// 占位屏与 AppBar 标题。
  final String label;

  /// 占位屏图标。
  final IconData icon;
}

/// 模块内部打开 typed 路由的统一回调签名。
typedef NovelRouteOpener =
    void Function(NovelRoute route, {Map<String, Object?> args});

/// Push 一个 typed 路由占位屏。
///
/// [args] 同时进 `RouteSettings.arguments` 与占位屏的参数展示区——后续真实页面
/// 按同样契约读取参数（如 `keyword` / `bookId`），骨架期即可验证传参链路。
Future<T?> pushNovelRoute<T extends Object?>(
  BuildContext context,
  NovelRoute route, {
  Map<String, Object?> args = const <String, Object?>{},
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: route.routeName, arguments: args),
      builder: (_) => NovelRoutePage(route: route, args: args),
    ),
  );
}

/// 统一路由占位屏：显示路由身份与说明，并预留参数展示位。
class NovelRoutePage extends StatelessWidget {
  const NovelRoutePage({
    super.key,
    required this.route,
    this.args = const <String, Object?>{},
  });

  final NovelRoute route;
  final Map<String, Object?> args;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(route.label)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(route.icon, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(route.label, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '路由骨架已就绪：${route.routeName}\n页面实现随后续切片接入。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (args.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        for (final entry in args.entries)
                          Chip(label: Text('${entry.key}: ${entry.value}')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
