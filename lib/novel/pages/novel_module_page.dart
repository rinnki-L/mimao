// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说模块主页壳：五个一级入口（首页 / 书架 / 发现 / 订阅 / 我的）+ 自适应导航。
///
/// 宽窗（>= 900）用左侧自绘侧栏（2026-11-22 与漫画/音乐统一：悬停高亮
/// 锚定原位、内容在药丸内缩进，原 NavigationRail 移除），窄窗仍用底部
/// NavigationBar——桌面优先但不牺牲 Android 单手区。内容页只认注入的服务缝，
/// 书源引擎未接入的入口一律给可操作的能力边界说明，不造假数据。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/booklist_io.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_discover_page.dart';
import 'package:mimao/novel/pages/novel_home_page.dart';
import 'package:mimao/novel/pages/novel_profile_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_shelf_page.dart';
import 'package:mimao/novel/pages/novel_subscribe_page.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';

class NovelModulePage extends StatefulWidget {
  const NovelModulePage({
    super.key,
    this.embedded = false,
    this.onOpenRoute,
    this.collect,
    this.history,
    this.searchHistory,
    this.sourceImporter,
    this.onlineEngine,
    this.stats,
    this.prefs,
    this.booklistGate,
  });

  /// true 时由壳提供顶部「返回 + 标题」，本页不画自己的 AppBar。
  final bool embedded;

  /// 页面内部打开 typed 路由的回调；由 NovelModule 出口接到 Navigator。
  /// null 时退化为页面内 Navigator.push（独立 widget 测试也能导航）。
  final NovelRouteOpener? onOpenRoute;

  /// 本地数据层三服务（由 NovelModule 注入）。null 时对应区域显示空态，
  /// 保证无依赖的骨架测试与"未接线"场景不崩。
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;

  /// 书源导入门面（由 NovelModule 注入）。null 时书源页显示能力边界说明。
  final NovelSourceImporter? sourceImporter;

  /// 在线书源引擎（由 NovelModule 注入）；null 时发现/搜索走本地能力。
  final NovelOnlineEngine? onlineEngine;

  /// 阅读统计/模块偏好（生产注入同一实例）。null 时统计显示 0、偏好用默认值。
  final NovelStatsApi? stats;
  final NovelPrefsApi? prefs;

  /// 书单文件选择缝；null 时书架页用 file_picker 生产实现（测试可注入 fake）。
  final NovelBooklistFileGate? booklistGate;

  @override
  State<NovelModulePage> createState() => _NovelModulePageState();
}

class _NovelModulePageState extends State<NovelModulePage> {
  static const double _sidebarBreakpoint = 900;

  int _index = 0;

  Future<void> _openRoute(
    NovelRoute route, {
    Map<String, Object?> args = const <String, Object?>{},
  }) async {
    final opener = widget.onOpenRoute;
    if (opener != null) {
      await opener(route, args: args);
      return;
    }
    await pushNovelRoute<void>(context, route, args: args);
  }

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  List<Widget> _buildTabs() {
    return <Widget>[
      NovelHomePage(
        active: _index == 0,
        collect: widget.collect,
        history: widget.history,
        stats: widget.stats,
        sourceImporter: widget.sourceImporter,
        openRoute: _openRoute,
        onSelectTab: _selectTab,
      ),
      NovelShelfPage(
        active: _index == 1,
        collect: widget.collect,
        history: widget.history,
        prefs: widget.prefs,
        booklistGate: widget.booklistGate,
        openRoute: _openRoute,
        onSelectTab: _selectTab,
      ),
      NovelDiscoverPage(
        active: _index == 2,
        sourceImporter: widget.sourceImporter,
        onlineEngine: widget.onlineEngine,
        openRoute: _openRoute,
      ),
      NovelSubscribePage(
        active: _index == 3,
        sourceImporter: widget.sourceImporter,
        openRoute: _openRoute,
      ),
      NovelProfilePage(
        active: _index == 4,
        collect: widget.collect,
        history: widget.history,
        searchHistory: widget.searchHistory,
        stats: widget.stats,
        sourceImporter: widget.sourceImporter,
        openRoute: _openRoute,
        onSelectTab: _selectTab,
      ),
    ];
  }

  static const List<NavigationDestination> _barDestinations =
      <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.local_library_outlined),
          selectedIcon: Icon(Icons.local_library),
          label: '书架',
        ),
        NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore),
          label: '发现',
        ),
        NavigationDestination(
          icon: Icon(Icons.rss_feed),
          selectedIcon: Icon(Icons.rss_feed),
          label: '订阅',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: '我的',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _sidebarBreakpoint;
        final content = IndexedStack(index: _index, children: _buildTabs());
        if (!wide) {
          return Scaffold(
            appBar: widget.embedded ? null : AppBar(title: const Text('小说')),
            body: content,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectTab,
              destinations: _barDestinations,
            ),
          );
        }
        final theme = Theme.of(context);
        return Scaffold(
          appBar: widget.embedded ? null : AppBar(title: const Text('小说')),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SafeArea(
                right: false,
                bottom: false,
                child: _NovelSidebar(
                  currentIndex: _index,
                  onSelect: _selectTab,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

/// 侧边栏导航项：与漫画/音乐模块同款记录。
typedef _NovelSidebarDestination = ({
  String key,
  IconData icon,
  IconData selectedIcon,
  String label,
});

const List<_NovelSidebarDestination> _sidebarDestinations =
    <_NovelSidebarDestination>[
      (
        key: 'novel-sidebar-home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: '首页',
      ),
      (
        key: 'novel-sidebar-shelf',
        icon: Icons.local_library_outlined,
        selectedIcon: Icons.local_library,
        label: '书架',
      ),
      (
        key: 'novel-sidebar-discover',
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore,
        label: '发现',
      ),
      (
        key: 'novel-sidebar-subscribe',
        icon: Icons.rss_feed,
        selectedIcon: Icons.rss_feed,
        label: '订阅',
      ),
      (
        key: 'novel-sidebar-profile',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: '我的',
      ),
    ];

/// 模块层左侧边栏（2026-11-22 与漫画/音乐统一为自绘侧栏，替代
/// NavigationRail）。
///
/// 顶部模块标识图标 + 五个导航行（图标 + 文字横排，选中态为 M3 rail 式
/// 选中指示垫：药丸底色只垫图标后面）。悬停/选中的高亮药丸区域锚定
/// 原位（外边距 12），内容在药丸内部再缩进 8——高亮与内容的相对位置
/// 与音乐模块一致。右缘 1px outlineVariant 与内容区分隔（由模块层的
/// VerticalDivider 提供）。窗口 < 900 回退底部 NavigationBar（不变）。
class _NovelSidebar extends StatelessWidget {
  const _NovelSidebar({required this.currentIndex, required this.onSelect});

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('novel-sidebar'),
      width: 240,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: <Widget>[
          // 模块标识：沿用原 NavigationRail 的 leading 图标。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Icon(Icons.menu_book_outlined, color: cs.primary),
          ),
          for (final (index, destination) in _sidebarDestinations.indexed)
            _destinationRow(
              context: context,
              itemKey: destination.key,
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: destination.label,
              selected: index == currentIndex,
              onTap: () => onSelect(index),
            ),
        ],
      ),
    );
  }

  /// 一条导航行：与音乐模块 `_destinationRow` 同款——高亮药丸区域从 12
  /// 起，宽窗内容在药丸内部再缩进 8；选中态为 M3 rail 式选中指示垫
  /// （56×32 药丸只垫图标）。
  Widget _destinationRow({
    required BuildContext context,
    required String itemKey,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 24,
      color: fg,
    );
    return Padding(
      key: Key(itemKey),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: MimaoShapes.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: MimaoShapes.pill,
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              children: <Widget>[
                // 内容相对高亮药丸右缩进 8（与音乐模块一致）。
                const SizedBox(width: 8),
                AnimatedContainer(
                  width: 56,
                  height: 32,
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected ? cs.secondaryContainer : null,
                    borderRadius: MimaoShapes.pill,
                  ),
                  alignment: Alignment.center,
                  child: iconWidget,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: selected
                          ? MimaoFonts.bold
                          : MimaoFonts.regular,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
