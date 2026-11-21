// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 漫画模块「主页」分区：搜索 + 跨源阅读历史 + 本地漫画 + 源管理入口。
///
/// 分工（用户拍板）：
/// - 主页 = 搜索框 + 跨源汇总的阅读历史（可单条删/一键清空）+ 本地漫画
///   + 源管理入口（「我的」式枢纽）；
/// - 收藏 = 用户收藏的漫画；
/// - 发现 / 分类 = 各源站点的探索流与分类树。
///
/// 本页只认 [ComicDataSource]（搜索）与 [ComicLibraryApi]（本地数据）；
/// 源管理入口经 [onOpenSources] 回调交给模块层 push 源管理页，本页不认识
/// 源仓库。统一书架入口收归壳层顶栏，主页不再重复放入口。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_poster_card.dart';
import 'package:mimao/comic/pages/comic_search_page.dart' show ComicSearchPage;

/// 主页分区。
class ComicHomePage extends StatefulWidget {
  const ComicHomePage({
    super.key,
    required this.dataSource,
    this.library,
    this.showAppBar = true,
    this.onOpenDetail,
    this.onOpenSources,
    this.onOpenSettings,
    this.refreshKey,
  });

  final ComicDataSource dataSource;

  /// 收藏/历史/本地数据；null 时只显示搜索与源管理入口。
  final ComicLibraryApi? library;

  final bool showAppBar;

  final ValueChanged<ComicSummary>? onOpenDetail;

  /// 打开源管理（模块层 push 源管理页）。
  final VoidCallback? onOpenSources;

  /// 打开模块设置（模块层弹底部面板）；null 时 AppBar 不显示设置按钮。
  final VoidCallback? onOpenSettings;

  /// 外部变化信号：值变化即重读历史/本地（从详情/阅读器返回后模块层自增）。
  /// 与收藏页同款——否则「读完一章返回主页」看到的仍是进模块时的旧快照。
  final Object? refreshKey;

  @override
  State<ComicHomePage> createState() => _ComicHomePageState();
}

class _ComicHomePageState extends State<ComicHomePage> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(ComicHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library ||
        oldWidget.refreshKey != widget.refreshKey) {
      _future = _load();
    }
  }

  Future<_HomeData> _load() async {
    final library = widget.library;
    if (library == null) return const _HomeData();
    final recent = await library.recent(limit: 20);
    final local = await library.local();
    return _HomeData(recent: recent, local: local);
  }

  /// 用块体而非箭头简写：setState 回调必须返回 null，
  /// `() => _future = _load()` 会把 Future 作为返回值触发 debug 断言。
  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// 单条删除历史：先弹 MD3 确认框，确认后走库 API（含投影一致性）并重读。
  ///
  /// 失败时留在原页面并弹 SnackBar，不假装删除成功——否则 UI 与两库不一致。
  Future<void> _deleteHistory(ComicSummary item) async {
    final library = widget.library;
    if (library == null) return;
    final confirmed = await _confirm(
      title: '删除这条阅读历史？',
      content: '「${item.title}」的阅读进度将被移除；收藏与本地漫画不受影响。',
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;
    try {
      await library.removeHistoryEntry(
        id: item.id,
        sourceName: item.sourceName ?? '',
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('删除历史失败：$error')));
      }
      return;
    }
    if (mounted) _reload();
  }

  /// 清空全部历史：确认后清库并重读（UI 回到空态）。
  Future<void> _clearHistory() async {
    final library = widget.library;
    if (library == null) return;
    final confirmed = await _confirm(
      title: '清空全部阅读历史？',
      content: '所有漫画的阅读进度将被移除；收藏与本地漫画不受影响。',
      confirmLabel: '清空',
    );
    if (confirmed != true || !mounted) return;
    try {
      await library.clearHistory();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('清空历史失败：$error')));
      }
      return;
    }
    if (mounted) _reload();
  }

  /// 统一的 MD3 确认对话框；返回 true 表示用户点了确认。
  Future<bool?> _confirm({
    required String title,
    required String content,
    required String confirmLabel,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final onOpenSettings = widget.onOpenSettings;
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('漫画'),
              actions: <Widget>[
                if (onOpenSettings != null)
                  IconButton(
                    key: const Key('comic-home-settings'),
                    tooltip: '模块设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: onOpenSettings,
                  ),
              ],
            )
          : null,
      body: SafeArea(
        top: false,
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              // 读库失败不能伪装成「还没有记录」——那会让用户以为数据丢了。
              return _HomeErrorState(onRetry: _reload);
            }
            final data = snapshot.data ?? const _HomeData();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                _buildSearchEntry(),
                const SizedBox(height: 8),
                _buildQuickActions(),
                if (data.recent.isNotEmpty) ...<Widget>[
                  ComicSectionHeader(
                    title: '阅读历史',
                    trailing: TextButton(
                      key: const Key('comic-home-clear-history'),
                      onPressed: _clearHistory,
                      child: const Text('清空'),
                    ),
                  ),
                  ComicPosterRow(
                    items: [for (final entry in data.recent) entry.asSummary()],
                    keyPrefix: 'home-recent',
                    onOpen: widget.onOpenDetail,
                    onItemLongPress: _deleteHistory,
                  ),
                ],
                if (data.local.isNotEmpty) ...<Widget>[
                  const ComicSectionHeader(title: '本地漫画'),
                  ComicPosterRow(
                    items: [for (final entry in data.local) entry.asSummary()],
                    keyPrefix: 'home-local',
                    onOpen: widget.onOpenDetail,
                  ),
                ],
                if (data.isEmpty) _buildEmptyHint(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 搜索入口：主页顶部一个只读样式的搜索框，点进完整搜索页。
  ///
  /// 不直接内嵌 [ComicSearchPage]：它的输入框 + 筛选 + 历史 + 结果网格是
  /// 独立整页，内嵌进主页 ListView 会同时出现两个滚动区与两个「搜索」按钮。
  Widget _buildSearchEntry() {
    return SearchBar(
      key: const Key('comic-home-search'),
      hintText: '搜索漫画名称',
      leading: const Icon(Icons.search),
      readOnly: true,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'comic/search'),
          builder: (_) => ComicSearchPage(
            dataSource: widget.dataSource,
            onOpenDetail: widget.onOpenDetail,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final onOpenSettings = widget.onOpenSettings;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        // 源管理从 chip 升级为搜索框下方的卡片；统一书架入口收归壳层顶栏。
        // 壳已提供顶部栏（embedded）时 AppBar 不画，设置入口收进这一行，
        // 保证模块设置在任何宿主下都能打开。
        if (onOpenSettings != null && !widget.showAppBar)
          ActionChip(
            key: const Key('comic-home-settings-chip'),
            avatar: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('设置'),
            onPressed: onOpenSettings,
          ),
        ActionChip(
          key: const Key('comic-home-refresh'),
          avatar: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('刷新'),
          onPressed: _reload,
        ),
      ],
    );
  }

  Widget _buildEmptyHint() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.auto_stories_outlined,
            size: 56,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('还没有阅读记录或本地漫画', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '搜索并阅读漫画后，会在这里按最近阅读汇总。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 主页本地数据快照。
class _HomeData {
  const _HomeData({
    this.recent = const <ComicLibraryEntry>[],
    this.local = const <ComicLibraryEntry>[],
  });

  final List<ComicLibraryEntry> recent;
  final List<ComicLibraryEntry> local;

  bool get isEmpty => recent.isEmpty && local.isEmpty;
}

/// 读本地库失败时的错误态（与收藏页同一形态）。
class _HomeErrorState extends StatelessWidget {
  const _HomeErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
          const SizedBox(height: 12),
          const Text('阅读记录加载失败'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
