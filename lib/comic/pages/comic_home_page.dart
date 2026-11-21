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
import 'package:mimao/core/theme.dart';
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
    this.sourceLister,
    this.onOpenSettings,
    this.refreshKey,
    this.readLater,
    this.localApi,
    this.onOpenReadLater,
    this.onOpenLocalLibrary,
  });

  final ComicDataSource dataSource;

  /// 收藏/历史/本地数据；null 时只显示搜索与源管理入口。
  final ComicLibraryApi? library;

  final bool showAppBar;

  final ValueChanged<ComicSummary>? onOpenDetail;

  /// 打开源管理（模块层 push 源管理页）。
  final VoidCallback? onOpenSources;

  /// 源清单读取器（模块层用 sourceRepository.listSources 注入）。
  ///
  /// 主页据此渲染源管理卡片的「已启用 X / 共 N」与前几个源；null（fixture /
  /// 未接线宿主）时卡片显示降级提示、不崩。
  final Future<List<ComicSourceInfo>> Function()? sourceLister;

  /// 打开模块设置（模块层弹底部面板）；null 时 AppBar 不显示设置按钮。
  final VoidCallback? onOpenSettings;

  /// 外部变化信号：值变化即重读历史/本地（从详情/阅读器返回后模块层自增）。
  /// 与收藏页同款——否则「读完一章返回主页」看到的仍是进模块时的旧快照。
  final Object? refreshKey;

  /// 稍后阅读读取入口；null 时主页不显示该卡片（未接线/测试降级）。
  final ComicReadLaterApi? readLater;

  /// 本地漫画管理入口；null 时不显示「本地」卡片。
  final ComicLocalApi? localApi;

  /// 打开「稍后阅读」整页（模块层 push，返回后自增 refreshKey）。
  final VoidCallback? onOpenReadLater;

  /// 打开「本地漫画」管理页（模块层 push，返回后自增 refreshKey）。
  final VoidCallback? onOpenLocalLibrary;

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
        oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.sourceLister != widget.sourceLister ||
        oldWidget.readLater != widget.readLater ||
        oldWidget.localApi != widget.localApi) {
      _future = _load();
    }
  }

  Future<_HomeData> _load() async {
    final library = widget.library;
    final sourceLister = widget.sourceLister;
    // 源清单读取失败不能让整页进错误态：降级为空清单，卡片显示导入提示。
    final sources = sourceLister == null
        ? const <ComicSourceInfo>[]
        : await sourceLister().catchError(
            (Object _) => const <ComicSourceInfo>[],
          );
    final readLater = widget.readLater;
    final saved = readLater == null
        ? const <ComicLibraryEntry>[]
        : await readLater.readLater();
    final localApi = widget.localApi;
    // 本地卡片与「本地漫画」区块共用同一数据源：有本地写能力时读它，
    // 避免两个入口（卡片计数 / 区块列表）因来源不同而不一致。
    final local = localApi != null
        ? await localApi.local()
        : (library == null
              ? const <ComicLibraryEntry>[]
              : await library.local());
    if (library == null) {
      return _HomeData(sources: sources, saved: saved, local: local);
    }
    final recent = await library.recent(limit: 20);
    return _HomeData(
      recent: recent,
      local: local,
      saved: saved,
      sources: sources,
    );
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
                _buildSourceCard(data.sources),
                const SizedBox(height: 8),
                if (widget.readLater != null) ...<Widget>[
                  _buildReadLaterCard(data.saved),
                  const SizedBox(height: 8),
                ],
                if (widget.localApi != null) ...<Widget>[
                  _buildLocalCard(data.local),
                  const SizedBox(height: 8),
                ],
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

  /// 稍后阅读卡片：详情页加入的待读队列，横向预览 + 整页入口。
  ///
  /// 空队列也保留卡片（显示引导文案）——否则用户不知道有这个功能入口。
  Widget _buildReadLaterCard(List<ComicLibraryEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final items = [for (final entry in entries) entry.asSummary()];
    return Card(
      key: const Key('comic-home-read-later-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const Key('comic-home-read-later-card-tap'),
            onTap: widget.onOpenReadLater,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.watch_later_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('稍后阅读', style: textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length} 部',
                    style: textTheme.bodySmall?.apply(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    items.isEmpty ? '' : '查看全部',
                    style: textTheme.labelMedium?.apply(color: cs.primary),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                '在漫画详情页点「稍后阅读」，想读的漫画会收在这里。',
                style: textTheme.bodySmall?.apply(color: cs.onSurfaceVariant),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ComicPosterRow(
                items: items,
                keyPrefix: 'home-read-later',
                height: 200,
                cardWidth: 120,
                onOpen: widget.onOpenDetail,
              ),
            ),
        ],
      ),
    );
  }

  /// 本地入口卡片：已导入/下载数量 + 管理页入口。
  Widget _buildLocalCard(List<ComicLibraryEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      key: const Key('comic-home-local-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('comic-home-local-card-tap'),
        onTap: widget.onOpenLocalLibrary,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.download_done_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('本地', style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      entries.isEmpty
                          ? '下载漫画后会出现在这里'
                          : '已保存 ${entries.length} 部 · 点击管理',
                      style: textTheme.bodySmall?.apply(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// 源管理卡片：从 chip 升级为搜索框下方的 MD3 卡片，整卡可点。
  ///
  /// 无 [sourceLister]（fixture/未接线）或读取失败时清单为空，显示导入提示
  /// 而非崩；点卡片仍交给模块层的 [onOpenSources] 处理。
  Widget _buildSourceCard(List<ComicSourceInfo> sources) {
    final onOpenSources = widget.onOpenSources;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabledCount = sources.where((s) => s.enabled).length;
    // 启用中的源优先展示，最多 5 个——卡片只做概览，完整清单在源管理页。
    final shown = <ComicSourceInfo>[
      ...sources.where((s) => s.enabled),
      ...sources.where((s) => !s.enabled),
    ].take(5).toList();
    final subtitle = sources.isEmpty
        ? '还没有导入来源，点击导入'
        : '已启用 $enabledCount / 共 ${sources.length} 个源';

    return Card(
      key: const Key('comic-home-source-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenSources,
        key: const Key('comic-home-source-card-tap'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.source_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('源管理', style: textTheme.titleSmall),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: textTheme.bodySmall?.apply(color: cs.onSurfaceVariant),
              ),
              if (shown.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final source in shown)
                      _SourceChip(source: source, cs: cs, textTheme: textTheme),
                  ],
                ),
              ],
            ],
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

/// 源管理卡片里的单个源：名称 + 启用状态小圆点。
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.source,
    required this.cs,
    required this.textTheme,
  });

  final ComicSourceInfo source;
  final ColorScheme cs;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('comic-home-source-${source.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: source.enabled ? cs.primary : cs.outline,
            ),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium,
            ),
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
    this.saved = const <ComicLibraryEntry>[],
    this.sources = const <ComicSourceInfo>[],
  });

  final List<ComicLibraryEntry> recent;
  final List<ComicLibraryEntry> local;

  /// 稍后阅读（主页卡片的数据源）。
  final List<ComicLibraryEntry> saved;

  final List<ComicSourceInfo> sources;

  bool get isEmpty => recent.isEmpty && local.isEmpty && saved.isEmpty;
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
