// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他三个模块的页面同款说明。
/// 小说模块主页（导航骨架，对齐 legado-with-MD3 的一壳 + typed 路由结构）。
///
/// 底部 NavigationBar 五 tab：书架 / 发现 / 搜索 / 书源 / 设置。设置放最右，
/// 内容由 NovelModule.buildSettings 注入；各 tab 与详情页本阶段为统一占位屏，
/// 真实抓取/解析/阅读随后续切片接入，外壳与路由契约不变。
/// 模块对壳无感知（不 import shell/）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/pages/novel_placeholder.dart';
import 'package:mimao/novel/pages/novel_routes.dart';

class NovelModulePage extends StatefulWidget {
  const NovelModulePage({
    super.key,
    this.embedded = false,
    this.settingsTab,
    this.onOpenRoute,
  });

  /// true 时由壳提供顶部「返回 + 标题」，本页不画自己的 AppBar。
  final bool embedded;

  /// 最右侧「设置」tab 的内容；由 NovelModule.buildSettings 注入。
  /// null 时用模块自己的占位说明，保证五 tab 结构恒定。
  final Widget? settingsTab;

  /// 页面内部打开 typed 路由的回调；由 NovelModule 出口接到 Navigator。
  /// null 时退化为页面内 Navigator.push（独立 widget 测试也能导航）。
  final NovelRouteOpener? onOpenRoute;

  @override
  State<NovelModulePage> createState() => _NovelModulePageState();
}

class _NovelModulePageState extends State<NovelModulePage> {
  int _index = 0;
  late final TextEditingController _controller = TextEditingController();

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
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
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: '搜索',
        ),
        NavigationDestination(
          icon: Icon(Icons.source_outlined),
          selectedIcon: Icon(Icons.source),
          label: '书源',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openRoute(NovelRoute route, {Map<String, Object?> args = const {}}) {
    final opener = widget.onOpenRoute;
    if (opener != null) {
      opener(route, args: args);
      return;
    }
    pushNovelRoute<void>(context, route, args: args);
  }

  void _submitSearch() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    // 搜索页骨架：提交后打开 typed 搜索路由占位屏，参数按契约透传。
    _openRoute(NovelRoute.search, args: <String, Object?>{'keyword': keyword});
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsTab ?? const NovelSettingsPlaceholder();
    final tabs = <Widget>[
      const NovelPlaceholderScreen(
        title: '书架',
        icon: Icons.local_library,
        description: '已收藏的书籍将在这里列出。\n书架与本地缓存随数据层切片接入。',
      ),
      const NovelPlaceholderScreen(
        title: '发现',
        icon: Icons.explore,
        description: '书源提供的发现/榜单将在这里展示。\n发现规则解析随书源引擎切片接入。',
      ),
      _buildSearchTab(),
      NovelPlaceholderScreen(
        title: '书源',
        icon: Icons.source,
        description: '书源的导入、启停与调试将在这里管理。\n书源仓库随书源引擎切片接入。',
        action: NovelPlaceholderImportButton(
          key: const Key('novel-source-import'),
          onPressed: () => _openRoute(NovelRoute.sourceManage),
        ),
      ),
      SafeArea(child: SingleChildScrollView(child: settings)),
    ];
    // 索引防御：settingsTab 在两次 build 之间变化时夹紧，避免越界。
    if (_index >= tabs.length) _index = tabs.length - 1;

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('小说')),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations,
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchBar(
            controller: _controller,
            hintText: '搜索书名 / 作者',
            leading: const Icon(Icons.search),
            trailing: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                tooltip: '搜索',
                onPressed: _submitSearch,
              ),
            ],
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submitSearch(),
          ),
        ),
        const Expanded(
          child: NovelPlaceholderScreen(
            title: '搜索',
            icon: Icons.search,
            description:
                '输入关键词并搜索，结果列表与详情将在这里展示。\n'
                '搜索解析随书源引擎切片接入。',
          ),
        ),
      ],
    );
  }
}

/// 默认设置占位（buildSettings 未注入真实内容时显示）。
class NovelSettingsPlaceholder extends StatelessWidget {
  const NovelSettingsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const NovelPlaceholderScreen(
      title: '设置',
      icon: Icons.settings,
      description: '小说模块的阅读/书源/离线设置将在这里。\n设置项随后续切片接入。',
    );
  }
}
