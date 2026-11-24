// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 漫画模块「主页」分区：搜索 + 四张卡片（历史/稍后阅读/本地/源管理）+ 快捷 chips。
///
/// 分工（用户拍板）：
/// - 主页 = 搜索框 + 跨源汇总的阅读历史（可单条删/一键清空）+ 稍后阅读
///   + 本地漫画 + 源管理入口（「我的」式枢纽），四张卡片固定顺序、各带空态；
/// - 收藏 = 用户收藏的漫画；
/// - 发现 / 分类 = 各源站点的探索流与分类树。
///
/// 排版（2026-11-22 拍板，对齐参考应用 VeneraNext 的主页分区，用本项目
/// MD3 风格实现）：每张卡 = 卡头（图标 + 标题 + 纯数字计数徽标 + Spacer +
/// chevron / 清空按钮）+ 卡身（纯封面横排 [_CoverRow] 或空态引导文案），
/// 封面不带标题文字。
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
import 'package:mimao/comic/pages/comic_cover.dart';
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
    this.onOpenImageFavorites,
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

  /// 打开「图片收藏」页；null 时不显示入口。
  final VoidCallback? onOpenImageFavorites;

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
    // 本地入口只有「本地」卡片：有本地写能力时读它，否则退回只读库，
    // 不再另起一份「本地漫画」海报区（重复入口已移除）。
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
            // 固定顺序（用户拍板）：搜索框 → 历史 → 稍后阅读 → 本地 → 源管理
            // → 快捷 chips。旧的「阅读历史」「本地漫画」大海报区已并入卡片/删除。
            // 历史卡片常显（library 存在即可）——空态收进卡片，不给整页空态。
            // 卡与卡间距 12（2026-11-22 排版拍板）。
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                _buildSearchEntry(),
                const SizedBox(height: 12),
                if (widget.library != null) ...<Widget>[
                  _buildHistoryCard(data.recent),
                  const SizedBox(height: 12),
                ],
                if (widget.readLater != null) ...<Widget>[
                  _buildReadLaterCard(data.saved),
                  const SizedBox(height: 12),
                ],
                if (widget.localApi != null) ...<Widget>[
                  _buildLocalCard(data.local),
                  const SizedBox(height: 12),
                ],
                if (widget.onOpenImageFavorites != null) ...<Widget>[
                  _buildImageFavoritesCard(),
                  const SizedBox(height: 12),
                ],
                _buildSourceCard(data.sources),
                const SizedBox(height: 12),
                _buildQuickActions(),
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

  /// 阅读历史卡片：跨源最近阅读，纯封面横排预览（最多 8 条）+ 单条删 / 一键清空。
  ///
  /// 卡头（history 图标 + 标题 + 计数徽标 + 清空 TextButton）+ 卡身（纯封面
  /// 行，右下角 scrim 叠阅读进度；或空态引导）。卡片常显——空历史时也保留
  /// 入口与清空按钮，不给整页空态；清空/长按删除沿用 [_clearHistory]/
  /// [_deleteHistory] 的确认框与 SnackBar 错误处理。
  Widget _buildHistoryCard(List<ComicLibraryEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 数据仍是 recent(limit: 20)，卡片只做概览：最多展示 8 条，避免历史过多
    // 时横向列表过长；计数徽标用完整 entries 长度，展示才截断。
    final items = [for (final entry in entries.take(8)) entry.asSummary()];
    return Card(
      key: const Key('comic-home-history-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: _HomeCardHeader(
              icon: Icons.history,
              title: '阅读历史',
              count: entries.length,
              trailing: TextButton(
                key: const Key('comic-home-clear-history'),
                onPressed: _clearHistory,
                child: const Text('清空'),
              ),
            ),
          ),
          if (items.isEmpty)
            // 空态收进卡片：首行标题文案被壳层接线回归用例断言
            // （test/shell/home_test.dart），改文案须两处同步；下一行是引导说明。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('还没有阅读记录', style: textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    '搜索并阅读漫画后，会在这里按最近阅读汇总。',
                    style: textTheme.bodySmall?.apply(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _CoverRow(
                items: items,
                keyPrefix: 'home-recent',
                showProgressScrim: true,
                onOpen: widget.onOpenDetail,
                onItemLongPress: _deleteHistory,
              ),
            ),
        ],
      ),
    );
  }

  /// 稍后阅读卡片：详情页加入的待读队列，纯封面横排预览 + 整页入口。
  ///
  /// 卡头整行可点（进稍后阅读整页），卡身是纯封面行（无 scrim、无标题文字）
  /// 或空态引导——空队列也保留卡片，否则用户不知道有这个功能入口。
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
              child: _HomeCardHeader(
                icon: Icons.watch_later_outlined,
                title: '稍后阅读',
                count: items.length,
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _CoverRow(
                items: items,
                keyPrefix: 'home-read-later',
                onOpen: widget.onOpenDetail,
              ),
            ),
        ],
      ),
    );
  }

  /// 本地入口卡片：卡头（图标 + 标题 + 计数徽标 + chevron，整头可点进管理页）
  /// + 卡身（有条目时纯封面横排、无 scrim；空时引导文案）。
  Widget _buildLocalCard(List<ComicLibraryEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final items = [for (final entry in entries) entry.asSummary()];
    return Card(
      key: const Key('comic-home-local-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const Key('comic-home-local-card-tap'),
            onTap: widget.onOpenLocalLibrary,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: _HomeCardHeader(
                icon: Icons.download_done_outlined,
                title: '本地',
                count: entries.length,
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                '下载漫画后会出现在这里',
                style: textTheme.bodySmall?.apply(color: cs.onSurfaceVariant),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _CoverRow(
                items: items,
                keyPrefix: 'home-local',
                onOpen: widget.onOpenDetail,
              ),
            ),
        ],
      ),
    );
  }

  /// 源管理卡片：搜索框下方的 MD3 卡片，整卡可点。
  ///
  /// 卡头与其它卡同款（图标 + 标题 + Spacer + chevron，无计数徽标），卡身
  /// 保留启用统计副标题与前几个源 chips。无 [sourceLister]（fixture/未接线）
  /// 或读取失败时清单为空，显示导入提示而非崩；点卡片仍交给模块层的
  /// [onOpenSources] 处理。
  /// 图片收藏入口：一行卡头，点进收藏页。
  Widget _buildImageFavoritesCard() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      key: const Key('comic-home-image-favorites-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('comic-home-image-favorites-tap'),
        onTap: widget.onOpenImageFavorites,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _HomeCardHeader(
                icon: Icons.star_outline,
                title: '图片收藏',
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '阅读时收藏的单张图片',
                style: textTheme.bodySmall?.apply(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              _HomeCardHeader(
                icon: Icons.source_outlined,
                title: '源管理',
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
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
}

/// 主页卡头：图标（20，primary）+ 标题（titleMedium）+ 计数徽标 + Spacer +
/// 尾部内容（chevron / 清空按钮）。
///
/// 2026-11-22 排版拍板：四张主页卡统一参考 VeneraNext 的分区卡头形态，
/// 原先的「titleSmall + N 条/N 部文案」改成本组件。
class _HomeCardHeader extends StatelessWidget {
  const _HomeCardHeader({
    required this.icon,
    required this.title,
    this.count,
    this.trailing,
  });

  final IconData icon;
  final String title;

  /// 计数徽标数字；null 不渲染徽标（源管理卡无计数）。
  final int? count;

  /// Spacer 之后的尾部内容（chevron、清空 TextButton 等）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text(title, style: textTheme.titleMedium),
        if (count != null) ...<Widget>[
          const SizedBox(width: 8),
          _CountBadge(count: count!, cs: cs, textTheme: textTheme),
        ],
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 卡头计数徽标：圆角小矩形（MimaoShapes.sm）、弱色底（surfaceContainerHighest）、
/// 纯数字（labelMedium + onSurfaceVariant）。
///
/// 2026-11-22 排版拍板：计数文案从「N 条 / N 部」改为纯数字。
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.cs,
    required this.textTheme,
  });

  final int count;
  final ColorScheme cs;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Text(
        '$count',
        style: textTheme.labelMedium?.apply(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// 主页卡身的纯封面横排：固定高 150、项宽 110、间距 12 的横向列表，
/// 每项只有一张圆角封面（MimaoShapes.sm），不带标题文字。
///
/// 与 [ComicPosterRow]（封面 + 标题的海报卡行）并存、不改它——收藏/发现/
/// 分类等页仍用海报卡形态；主页参考 VeneraNext 只露封面，信息由 scrim
/// （历史进度）与详情页承载。横向拖动走全局 MimaoScrollBehavior，本组件
/// 不另设 ScrollBehavior。
class _CoverRow extends StatelessWidget {
  const _CoverRow({
    required this.items,
    this.keyPrefix = 'cover',
    this.showProgressScrim = false,
    this.onOpen,
    this.onItemLongPress,
  });

  final List<ComicSummary> items;

  /// 条目 key 前缀：历史 `home-recent-<id>`、稍后阅读 `home-read-later-<id>`、
  /// 本地 `home-local-<id>`。
  final String keyPrefix;

  /// true 时条目 [ComicSummary.subtitle] 非空则在封面右下角叠加进度 scrim
  /// （阅读历史专用）；false 为纯封面（稍后阅读 / 本地），subtitle 不上屏。
  final bool showProgressScrim;

  final ValueChanged<ComicSummary>? onOpen;

  /// 条目长按回调（历史卡删单条）；null 时长按无行为。
  final ValueChanged<ComicSummary>? onItemLongPress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final onOpen = this.onOpen;
          final onItemLongPress = this.onItemLongPress;
          final hasProgress =
              showProgressScrim && (item.subtitle ?? '').isNotEmpty;
          return SizedBox(
            width: 110,
            child: InkWell(
              key: ValueKey<String>('$keyPrefix-${item.id}'),
              onTap: onOpen == null ? null : () => onOpen(item),
              onLongPress: onItemLongPress == null
                  ? null
                  : () => onItemLongPress(item),
              child: ClipRRect(
                borderRadius: MimaoShapes.sm,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // 外层 ClipRRect 已定圆角：封面自带裁剪的 radius 归零，
                    // 避免同一张封面叠两层圆角。
                    ComicCover(
                      url: item.coverUrl,
                      title: item.title,
                      radius: 0,
                    ),
                    // 封面上的进度遮罩与文字：AGENTS.md 明示覆盖在封面上的
                    // 遮罩与文字是唯一允许固定黑白的地方。
                    if (hasProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.black.withValues(alpha: .75),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                            child: Text(
                              item.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.apply(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
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
