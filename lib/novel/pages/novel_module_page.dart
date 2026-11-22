// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说模块主页壳：五个一级入口（首页 / 书架 / 发现 / 订阅 / 我的）+ 自适应导航。
///
/// 宽窗（>= 900）用左侧 NavigationRail（>= 1180 展开文字），窄窗仍用底部
/// NavigationBar——桌面优先但不牺牲 Android 单手区。内容页只认注入的服务缝，
/// 书源引擎未接入的入口一律给可操作的能力边界说明，不造假数据。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/booklist_io.dart';
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

  /// 阅读统计/模块偏好（生产注入同一实例）。null 时统计显示 0、偏好用默认值。
  final NovelStatsApi? stats;
  final NovelPrefsApi? prefs;

  /// 书单文件选择缝；null 时书架页用 file_picker 生产实现（测试可注入 fake）。
  final NovelBooklistFileGate? booklistGate;

  @override
  State<NovelModulePage> createState() => _NovelModulePageState();
}

class _NovelModulePageState extends State<NovelModulePage> {
  static const double _railBreakpoint = 900;
  static const double _extendedRailBreakpoint = 1180;

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

  static const List<NavigationRailDestination> _railDestinations =
      <NavigationRailDestination>[
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('首页'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.local_library_outlined),
          selectedIcon: Icon(Icons.local_library),
          label: Text('书架'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore),
          label: Text('发现'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.rss_feed),
          selectedIcon: Icon(Icons.rss_feed),
          label: Text('订阅'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('我的'),
        ),
      ];

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
        final wide = constraints.maxWidth >= _railBreakpoint;
        final extended = constraints.maxWidth >= _extendedRailBreakpoint;
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
                child: NavigationRail(
                  extended: extended,
                  labelType: extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  minWidth: 84,
                  minExtendedWidth: 200,
                  selectedIndex: _index,
                  onDestinationSelected: _selectTab,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Icon(
                      Icons.menu_book_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  destinations: _railDestinations,
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
