// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/engine/engine.dart' show ComicSourceCatalog;
import 'package:mimao/comic/pages/comic_detail_page.dart';
import 'package:mimao/comic/pages/comic_search_page.dart';
import 'package:mimao/comic/pages/comic_source_page.dart';

/// 漫画模块层（壳钻进漫画入口后看到的那一层，设置收在本页最右 tab）。
///
/// 模块内部导航：底部 NavigationBar 在「搜索 / 源管理 / 设置」间切换；
/// 点任一漫画条目 → push 详情页 → 返回。模块对壳无感知（不 import shell/）。
/// 另三个入口（番剧/小说/音乐）在壳层随模块激活自动消失，本模块不处理它们。
/// 「设置」tab 放最右，内容由 ComicModule.buildSettings 注入；null 时不显示。
class ComicModulePage extends StatefulWidget {
  const ComicModulePage({
    super.key,
    required this.dataSource,
    required this.sourceRepository,
    this.sourceCatalog,
    this.embedded = false,
    this.settingsTab,
    this.onOpenDetail,
    this.isFavorite,
    this.onFavoriteChanged,
    this.onStartReading,
    this.onImportSource,
    this.onDeleteSource,
  });

  final ComicDataSource dataSource;
  final ComicSourceRepository sourceRepository;

  /// 源仓库目录，透传给源管理页；null 时不显示仓库区块。
  final ComicSourceCatalog? sourceCatalog;

  /// true 时由壳提供顶部"返回 + 标题"，搜索/源管理页不再画自己的 AppBar。
  final bool embedded;

  /// 最右侧「设置」tab 的内容；由模块出口 buildSettings 注入。
  final Widget? settingsTab;

  /// 即将打开详情（导航前的最后一个异步点）：模块层在此接
  /// ComicHistoryService.open 做打开点校正；抛错不挡导航。
  final Future<void> Function(ComicSummary item)? onOpenDetail;

  /// 打开详情前读取权威收藏态；由模块层接收藏服务注入。
  final Future<bool> Function(ComicSummary)? isFavorite;

  /// 收藏切换；模块层把条目一起包进回调，详情页无需认识 ComicSummary。
  final void Function(ComicSummary item, bool favorite)? onFavoriteChanged;

  /// 开始阅读；模块层把条目、详情与所选章节一起交给阅读器装配方。
  final void Function(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter? chapter,
  )?
  onStartReading;

  /// 从 URL 导入源 / 删除源的回调，透传给源管理页。
  final ValueChanged<String>? onImportSource;
  final ValueChanged<ComicSourceInfo>? onDeleteSource;

  @override
  State<ComicModulePage> createState() => _ComicModulePageState();
}

class _ComicModulePageState extends State<ComicModulePage> {
  int _index = 0;

  Future<void> _openDetail(ComicSummary item) async {
    // 打开点校正失败不应挡住导航：投影由下次打开再校正。
    try {
      await widget.onOpenDetail?.call(item);
    } on Object {
      // 校正是纯收益动作，失败静默。
    }
    // 收藏态读取失败不应挡住导航：退回"未收藏"继续打开详情。
    final favorite =
        await (widget.isFavorite?.call(item) ?? Future<bool>.value(false))
            .catchError((Object _) => false);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/detail'),
        builder: (_) => ComicDetailPage(
          dataSource: widget.dataSource,
          summary: item,
          initiallyFavorite: favorite,
          onFavoriteChanged: (v) => widget.onFavoriteChanged?.call(item, v),
          onStartReading: (detail, chapter) =>
              widget.onStartReading?.call(item, detail, chapter),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsTab = widget.settingsTab;
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: '搜索',
      ),
      const NavigationDestination(
        icon: Icon(Icons.source_outlined),
        selectedIcon: Icon(Icons.source),
        label: '源管理',
      ),
    ];
    if (settingsTab != null) {
      destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          ComicSearchPage(
            dataSource: widget.dataSource,
            showAppBar: !widget.embedded,
            onOpenDetail: _openDetail,
          ),
          ComicSourcePage(
            repository: widget.sourceRepository,
            catalog: widget.sourceCatalog,
            showAppBar: !widget.embedded,
            onImport: widget.onImportSource,
            onDelete: widget.onDeleteSource,
          ),
          if (settingsTab != null)
            SafeArea(child: SingleChildScrollView(child: settingsTab)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: destinations,
      ),
    );
  }
}
