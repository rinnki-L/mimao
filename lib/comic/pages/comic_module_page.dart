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
import 'package:mimao/comic/download_api.dart';
import 'package:mimao/comic/engine/engine.dart' show ComicSourceCatalog;
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_category_page.dart';
import 'package:mimao/comic/pages/comic_detail_page.dart';
import 'package:mimao/comic/pages/comic_discover_page.dart';
import 'package:mimao/comic/pages/comic_favorites_page.dart';
import 'package:mimao/comic/pages/comic_home_page.dart';
import 'package:mimao/comic/pages/comic_local_page.dart';
import 'package:mimao/comic/pages/comic_read_later_page.dart';
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
    this.isReadLater,
    this.onReadLaterChanged,
    this.readLater,
    this.localApi,
    this.downloads,
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

  /// 打开详情前读取稍后阅读态。
  final Future<bool> Function(ComicSummary)? isReadLater;

  /// 稍后阅读切换（模块层落库）。
  final void Function(ComicSummary item, bool included)? onReadLaterChanged;

  /// 稍后阅读整页数据入口（主页卡片「查看全部」）。
  final ComicReadLaterApi? readLater;

  /// 本地漫画管理入口（主页「本地」卡片 + 本地详情打开）。
  final ComicLocalApi? localApi;

  /// 在线漫画下载能力（详情页章节下载按钮）。
  final ComicDownloadApi? downloads;

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
    // 本地漫画走本地详情：章节来自落盘清单，不走源引擎抓取。
    if (item.sourceName == ComicLibraryEntry.localSource) {
      await _openLocalDetail(item);
      return;
    }
    // 打开点校正失败不应挡住导航：投影由下次打开再校正。
    try {
      await widget.onOpenDetail?.call(item);
    } on Object {
      // 校正是纯收益动作，失败静默。
    }
    final favorite = await _boolOr(
      widget.isFavorite?.call(item),
      fallback: false,
    );
    final readLater = await _boolOr(
      widget.isReadLater?.call(item),
      fallback: false,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/detail'),
        builder: (_) => ComicDetailPage(
          dataSource: widget.dataSource,
          summary: item,
          initiallyFavorite: favorite,
          initiallyReadLater: readLater,
          onFavoriteChanged: (v) => widget.onFavoriteChanged?.call(item, v),
          onReadLaterChanged: (v) => widget.onReadLaterChanged?.call(item, v),
          downloads: widget.downloads,
          onStartReading: (detail, chapter) =>
              widget.onStartReading?.call(item, detail, chapter),
        ),
      ),
    );
    // 详情页里可能改过收藏/稍后阅读/下载，返回后让主页与收藏 tab 重读。
    if (mounted) setState(() => _libraryRevision++);
  }

  /// 本地漫画详情：数据源是下载时落盘的清单快照。
  Future<void> _openLocalDetail(ComicSummary item) async {
    final localApi = widget.localApi;
    if (localApi == null) {
      _showSnack('本地漫画能力未接线');
      return;
    }
    try {
      await widget.onOpenDetail?.call(item);
    } on Object {
      // 同在线路径：打开点校正是纯收益动作。
    }
    final favorite = await _boolOr(
      widget.isFavorite?.call(item),
      fallback: false,
    );
    final readLater = await _boolOr(
      widget.isReadLater?.call(item),
      fallback: false,
    );
    final ComicDetail detail;
    try {
      detail = await localApi.detail(item);
    } on Object catch (error) {
      _showSnack('本地漫画打开失败：$error');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/detail/local'),
        builder: (_) => ComicDetailPage(
          dataSource: _LocalDetailDataSource(detail),
          summary: item,
          initiallyFavorite: favorite,
          initiallyReadLater: readLater,
          isLocal: true,
          onFavoriteChanged: (v) => widget.onFavoriteChanged?.call(item, v),
          onReadLaterChanged: (v) => widget.onReadLaterChanged?.call(item, v),
          onStartReading: (detail, chapter) =>
              widget.onStartReading?.call(item, detail, chapter),
        ),
      ),
    );
    if (mounted) setState(() => _libraryRevision++);
  }

  Future<bool> _boolOr(Future<bool>? value, {required bool fallback}) async {
    if (value == null) return fallback;
    // 读取失败不应挡住导航：退回安全默认值继续打开详情。
    return value.catchError((Object _) => fallback);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 打开稍后阅读整页；返回后重读主页卡片。
  Future<void> _openReadLater() async {
    final api = widget.readLater;
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/read-later'),
        builder: (_) => ComicReadLaterPage(api: api, onOpenDetail: _openDetail),
      ),
    );
    if (mounted) setState(() => _libraryRevision++);
  }

  /// 打开本地漫画管理页；返回后重读主页「本地」卡片与区块。
  Future<void> _openLocalLibrary() async {
    final api = widget.localApi;
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/local'),
        builder: (_) => ComicLocalPage(local: api, onOpenDetail: _openDetail),
      ),
    );
    if (mounted) setState(() => _libraryRevision++);
  }

  /// 打开源管理页：模块层默认 push 内置源管理页；壳/模块出口可覆盖。
  ///
  /// 返回后自增 [_libraryRevision]：主页源管理卡片据此重读源清单——否则在
  /// 源管理页导入/启用/删除后回到主页，卡片仍显示旧统计（与详情页返回后
  /// 重读收藏/历史的做法一致）。
  Future<void> _openSources() async {
    final override = widget.onOpenSources;
    if (override != null) {
      override();
      return;
    }
    await Navigator.of(context).push<void>(
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
    if (mounted) setState(() => _libraryRevision++);
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
            // 源管理卡片读同一仓库；返回后随 _libraryRevision 重读。
            sourceLister: widget.sourceRepository.listSources,
            onOpenSettings: hasSettings ? _openSettings : null,
            // 与收藏页同一刷新信号：从详情/阅读器返回后重读历史与本地。
            refreshKey: _libraryRevision,
            readLater: widget.readLater,
            localApi: widget.localApi,
            onOpenReadLater: _openReadLater,
            onOpenLocalLibrary: _openLocalLibrary,
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

/// 本地漫画详情的静态数据源：详情已在打开前从落盘清单装配好。
///
/// 只有 [detail] 有真实内容；搜索/诊断接口是空实现（页面只会调 detail）。
class _LocalDetailDataSource implements ComicDataSource {
  const _LocalDetailDataSource(this._detail);

  final ComicDetail _detail;

  @override
  Future<ComicDetail> detail(ComicSummary item) async => _detail;

  @override
  Future<List<ComicSummary>> search(String keyword) async =>
      const <ComicSummary>[];

  @override
  List<String> takeSearchDiagnostics() => const <String>[];

  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) async =>
      const <ComicSummary>[];

  @override
  List<String> availableSourceKeys() => const <String>[];

  @override
  Future<List<String>> recentSearchTerms() async => const <String>[];
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
