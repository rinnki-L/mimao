// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 漫画模块层（壳钻进漫画入口后看到的那一层）。
///
/// 底部 NavigationBar 四个功能分区（用户拍板）：
///   主页 / 收藏 / 发现 / 分类
/// - **主页**：搜索入口 + 跨源阅读历史（可删/清空）+ 本地漫画 + 源管理入口；
/// - **收藏**：用户收藏的漫画；
/// - **发现**：各源站点的探索流（推荐/排行分栏）；
/// - **分类**：各源站点的分类树（无 category 时回退到探索分栏）。
///
/// 模块设置（清搜索历史等）不再占一个 tab：收在主页右上角的设置按钮里，
/// 弹底部面板展示 [settingsTab]，把底部栏留给四个功能分区。
///
/// 点任一漫画条目 → push 详情页 → 返回。模块对壳无感知（不 import shell/）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/engine/engine.dart' show ComicSourceCatalog;
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_category_page.dart';
import 'package:mimao/comic/pages/comic_detail_page.dart';
import 'package:mimao/comic/pages/comic_discover_page.dart';
import 'package:mimao/comic/pages/comic_favorites_page.dart';
import 'package:mimao/comic/pages/comic_home_page.dart';
import 'package:mimao/comic/pages/comic_source_page.dart';

class ComicModulePage extends StatefulWidget {
  const ComicModulePage({
    super.key,
    required this.dataSource,
    required this.sourceRepository,
    this.browseSource,
    this.library,
    this.sourceCatalog,
    this.embedded = false,
    this.settingsTab,
    this.onOpenDetail,
    this.onOpenSources,
    this.isFavorite,
    this.onFavoriteChanged,
    this.onStartReading,
    this.onImportSource,
    this.onDeleteSource,
  });

  final ComicDataSource dataSource;
  final ComicSourceRepository sourceRepository;

  /// 发现/分类的浏览能力；null 时这两个 tab 显示「未接线」说明而不是空屏。
  final ComicBrowseSource? browseSource;

  /// 收藏/历史/本地漫画的只读入口；null 时主页/收藏 tab 显示空态说明。
  final ComicLibraryApi? library;

  /// 源仓库目录，透传给源管理页；null 时不显示仓库区块。
  final ComicSourceCatalog? sourceCatalog;

  /// true 时由壳提供顶部"返回 + 标题"，各分区页不再画自己的 AppBar。
  final bool embedded;

  /// 模块设置面板的内容（主页右上角设置按钮弹出）；null 时按钮隐藏。
  final Widget? settingsTab;

  /// 即将打开详情（导航前的最后一个异步点）：模块层在此接
  /// ComicHistoryService.open 做打开点校正；抛错不挡导航。
  final Future<void> Function(ComicSummary item)? onOpenDetail;

  /// 打开源管理页（主页入口）；null 时用模块内置的源管理页。
  final VoidCallback? onOpenSources;

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

  /// 收藏列表刷新信号：从详情页返回后自增，收藏 tab 据此重读。
  int _libraryRevision = 0;

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
    // 详情页里可能改过收藏，返回后让收藏 tab 重读。
    if (mounted) setState(() => _libraryRevision++);
  }

  /// 打开源管理页：模块层默认 push 内置源管理页；壳/模块出口可覆盖。
  void _openSources() {
    final override = widget.onOpenSources;
    if (override != null) {
      override();
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/sources'),
        builder: (_) => ComicSourcePage(
          repository: widget.sourceRepository,
          catalog: widget.sourceCatalog,
          onImport: widget.onImportSource,
          onDelete: widget.onDeleteSource,
        ),
      ),
    );
  }

  /// 模块设置面板（底部弹出）：把原来占一个 tab 的设置内容收进来。
  Future<void> _openSettings() async {
    final settingsTab = widget.settingsTab;
    if (settingsTab == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: settingsTab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final browse = widget.browseSource;
    final hasSettings = widget.settingsTab != null;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          ComicHomePage(
            dataSource: widget.dataSource,
            library: library,
            showAppBar: !widget.embedded,
            onOpenDetail: _openDetail,
            onOpenSources: _openSources,
            onOpenSettings: hasSettings ? _openSettings : null,
            // 与收藏页同一刷新信号：从详情/阅读器返回后重读历史与本地。
            refreshKey: _libraryRevision,
          ),
          if (library != null)
            ComicFavoritesPage(
              library: library,
              showAppBar: !widget.embedded,
              onOpenDetail: _openDetail,
              refreshKey: _libraryRevision,
            )
          else
            const _NotWiredPage(
              icon: Icons.bookmark_border,
              title: '收藏',
              description: '收藏服务尚未接入。',
            ),
          if (browse != null)
            ComicDiscoverPage(
              browseSource: browse,
              showAppBar: !widget.embedded,
              onOpenDetail: _openDetail,
            )
          else
            const _NotWiredPage(
              icon: Icons.explore_outlined,
              title: '发现',
              description: '源站点浏览能力尚未接入。',
            ),
          if (browse != null)
            ComicCategoryPage(
              browseSource: browse,
              showAppBar: !widget.embedded,
              onOpenDetail: _openDetail,
            )
          else
            const _NotWiredPage(
              icon: Icons.category_outlined,
              title: '分类',
              description: '源站点浏览能力尚未接入。',
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: '分类',
          ),
        ],
      ),
    );
  }
}

/// 能力未接线时的占位（不假装有内容）。
class _NotWiredPage extends StatelessWidget {
  const _NotWiredPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
