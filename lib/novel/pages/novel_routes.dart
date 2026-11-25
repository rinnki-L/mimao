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
  read('novel/read', '阅读', Icons.auto_stories),
  search('novel/search', '搜索', Icons.search),
  sourceManage('novel/source-manage', '规则管理', Icons.source),

  /// 书源编辑器（表单 / 原始 JSON 双模式）。参数：`sourceKey`（编辑已有源，
  /// 缺省 = 新建）、`raw`（新建时的初始 JSON 文本）。
  sourceEdit('novel/source-edit', '编辑书源', Icons.edit_note),

  /// 书源调试面板。**只在 debug 构建注册**（注册处用 `kDebugMode` 把关，
  /// release 里这个路由落到占位屏，页面代码也不会被打包）。
  /// 参数：`sourceKey`（预选书源）。
  sourceDebug('novel/source-debug', '书源调试', Icons.bug_report_outlined),
  history('novel/history', '阅读记录', Icons.history),
  stats('novel/stats', '阅读统计', Icons.insights),
  bookmarks('novel/bookmarks', '书签', Icons.bookmark_border),
  settings('novel/settings', '设置', Icons.settings),

  /// 本地书导入（TXT / EPUB / Markdown）；带 `relocateBookId` 时是重新定位。
  importBook('novel/import-book', '添加本地书', Icons.file_open_outlined),

  /// TXT 目录规则管理（导入本地 TXT 时按这些规则分章）。
  txtRules('novel/txt-rules', 'TXT 目录规则', Icons.format_list_numbered);

  const NovelRoute(this.routeName, this.label, this.icon);

  /// 稳定路由名，同时作为 `RouteSettings.name`（dev/navigate 可寻址）。
  final String routeName;

  /// 占位屏与 AppBar 标题。
  final String label;

  /// 占位屏图标。
  final IconData icon;
}

/// 模块内部打开 typed 路由的统一回调签名。
///
/// 返回 Future：调用方（书架/首页/详情）据此在路由返回后重读本地数据，
/// 避免「取消收藏后返回，卡片还在」。
typedef NovelRouteOpener =
    Future<void> Function(NovelRoute route, {Map<String, Object?> args});

/// typed 路由 → 真实页面构造器注册表。
///
/// 骨架期所有路由都落到 [NovelRoutePage] 占位屏；某路由实现就绪后（如书源管理）
/// 在装配处调 [registerNovelRoutePage] 注入构造器，路由名与参数契约保持不变。
/// 构造器接收路由参数，返回该路由的真实页面。
typedef NovelRoutePageBuilder = Widget Function(Map<String, Object?> args);

final Map<NovelRoute, NovelRoutePageBuilder> _novelRoutePages =
    <NovelRoute, NovelRoutePageBuilder>{};

/// 注册/替换某路由的真实页面构造器（传 null 撤销，回到占位屏）。
void registerNovelRoutePage(NovelRoute route, NovelRoutePageBuilder? builder) {
  if (builder == null) {
    _novelRoutePages.remove(route);
  } else {
    _novelRoutePages[route] = builder;
  }
}

/// 仅供测试：清空路由构造器注册表。
void resetNovelRoutePagesForTest() => _novelRoutePages.clear();

/// Push 一个 typed 路由：注册了真实页面就打开它，否则落到占位屏。
///
/// [args] 同时进 `RouteSettings.arguments` 与占位屏的参数展示区——后续真实页面
/// 按同样契约读取参数（如 `keyword` / `bookId`），骨架期即可验证传参链路。
Future<T?> pushNovelRoute<T extends Object?>(
  BuildContext context,
  NovelRoute route, {
  Map<String, Object?> args = const <String, Object?>{},
}) {
  final pageBuilder = _novelRoutePages[route];
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: route.routeName, arguments: args),
      builder: (_) =>
          pageBuilder?.call(args) ?? NovelRoutePage(route: route, args: args),
    ),
  );
}

/// 页面内导航的统一入口：注入了 opener 就走它（便于测试观察），否则本地 push。
Future<void> openNovelRoute(
  BuildContext context,
  NovelRouteOpener? opener,
  NovelRoute route, {
  Map<String, Object?> args = const <String, Object?>{},
}) {
  if (opener != null) return opener(route, args: args);
  return pushNovelRoute<void>(context, route, args: args);
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
