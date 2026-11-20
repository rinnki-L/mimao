// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他三个模块的页面同款说明。
/// 小说模块主页（一壳 + typed 路由结构，对齐 legado-with-MD3）。
///
/// 底部 NavigationBar 五 tab：书架 / 发现 / 搜索 / 书源 / 设置。设置放最右，
/// 内容由 NovelModule.buildSettings 注入。书架/搜索/设置已接本地数据层三服务
/// （收藏/历史/搜索历史真实读写并投影统一书架）；发现/书源管理/搜索结果/
/// 阅读页仍是占位——抓取流水线（书源引擎）尚无实现，属能力边界而非假联通。
/// 模块对壳无感知（不 import shell/）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_placeholder.dart';
import 'package:mimao/novel/pages/novel_routes.dart';

class NovelModulePage extends StatefulWidget {
  const NovelModulePage({
    super.key,
    this.embedded = false,
    this.settingsTab,
    this.onOpenRoute,
    this.collect,
    this.history,
    this.searchHistory,
  });

  /// true 时由壳提供顶部「返回 + 标题」，本页不画自己的 AppBar。
  final bool embedded;

  /// 最右侧「设置」tab 的内容；由 NovelModule.buildSettings 注入。
  /// null 时用模块自己的占位说明，保证五 tab 结构恒定。
  final Widget? settingsTab;

  /// 页面内部打开 typed 路由的回调；由 NovelModule 出口接到 Navigator。
  /// null 时退化为页面内 Navigator.push（独立 widget 测试也能导航）。
  final NovelRouteOpener? onOpenRoute;

  /// 本地数据层三服务（由 NovelModule 注入）。null 时对应 tab 显示空态占位，
  /// 保证无依赖的骨架测试与"未接线"场景不崩。
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;

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

  Future<void> _submitSearch() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    // 搜索词真实落本地库（搜索历史），结果页仍是 typed 路由占位——
    // 书源引擎无实现，不假装能搜到书。
    await widget.searchHistory?.record(keyword);
    if (!mounted) return;
    _openRoute(NovelRoute.search, args: <String, Object?>{'keyword': keyword});
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsTab ?? const NovelSettingsPlaceholder();
    final tabs = <Widget>[
      _buildShelfTab(),
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

  /// 书架：真实读收藏表 + 阅读历史表（两者都经投影进统一书架）。
  Widget _buildShelfTab() {
    final collect = widget.collect;
    final history = widget.history;
    if (collect == null && history == null) {
      return const NovelPlaceholderScreen(
        title: '书架',
        icon: Icons.local_library,
        description: '已收藏的书籍将在这里列出。\n书架与本地缓存随数据层切片接入。',
      );
    }
    return FutureBuilder<_ShelfData>(
      future: _loadShelf(collect, history),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data ?? const _ShelfData();
        if (data.isEmpty) {
          return const NovelPlaceholderScreen(
            title: '书架',
            icon: Icons.local_library,
            description: '还没有收藏或阅读记录。\n收藏书籍、开始阅读后会出现在这里。',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: <Widget>[
            if (data.recent.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, top: 4),
                child: Text(
                  '继续阅读',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            for (final item in data.recent)
              _BookTile(
                title: item.book.title,
                subtitle: item.chapterCount > 0
                    ? '看到第 ${item.chapterIndex} 章 · 共 ${item.chapterCount} 章'
                    : '已打开',
                icon: Icons.history_edu_outlined,
              ),
            if (data.collects.isNotEmpty && data.recent.isNotEmpty)
              const SizedBox(height: 12),
            if (data.collects.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '我的收藏',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            for (final item in data.collects)
              _BookTile(
                title: item.title,
                subtitle: item.authorText,
                icon: Icons.bookmark_border,
              ),
          ],
        );
      },
    );
  }

  Future<_ShelfData> _loadShelf(
    NovelCollectApi? collect,
    NovelHistoryApi? history,
  ) async {
    final collects = collect == null
        ? const <NovelCollectItem>[]
        : await collect.list();
    final recent = history == null
        ? const <NovelHistoryItem>[]
        : await history.recent(limit: 20);
    return _ShelfData(collects: collects, recent: recent);
  }

  Widget _buildSearchTab() {
    final searchHistory = widget.searchHistory;
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
        Expanded(
          child: searchHistory == null
              ? const NovelPlaceholderScreen(
                  title: '搜索',
                  icon: Icons.search,
                  description:
                      '输入关键词并搜索，结果列表与详情将在这里展示。\n'
                      '搜索解析随书源引擎切片接入。',
                )
              : _buildSearchHistory(searchHistory),
        ),
      ],
    );
  }

  /// 搜索历史：真实读本地库，点条目回填搜索框。
  Widget _buildSearchHistory(NovelSearchHistoryApi api) {
    return FutureBuilder<List<String>>(
      future: api.recent(),
      builder: (context, snapshot) {
        final terms = snapshot.data ?? const <String>[];
        if (snapshot.connectionState == ConnectionState.done && terms.isEmpty) {
          return const NovelPlaceholderScreen(
            title: '搜索',
            icon: Icons.search,
            description: '还没有搜索记录。\n输入关键词后，历史会保存在这里。',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '搜索历史',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final term in terms)
                  InputChip(
                    label: Text(term),
                    onPressed: () => _controller.text = term,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '搜索结果需书源引擎支持，当前仅记录历史。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

/// 书架列表的一行（本地数据，不带网络图——封面留给阅读页）。
class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 书架页聚合的本地数据快照。
class _ShelfData {
  const _ShelfData({this.collects = const [], this.recent = const []});

  final List<NovelCollectItem> collects;
  final List<NovelHistoryItem> recent;

  bool get isEmpty => collects.isEmpty && recent.isEmpty;
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
