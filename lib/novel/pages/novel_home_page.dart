// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「首页」：最近阅读 + 阅读统计 + 今日目标 + 书源状态 + 我的书架横条。
///
/// 所有数字来自本地库：最近阅读 = novel_history 最新一条，累计阅读 = 历史条数，
/// 阅读时长 = 阅读时长按天表之和（没有记录时为 0，不估算）。
/// 书源卡读真实书源仓库；没有任何数据时给"为什么空 + 下一步做什么"的空态。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/navigation.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/home/home_module_config.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_backup_page.dart';
import 'package:mimao/novel/pages/home/home_module_manager.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/webdav_backup.dart';

class NovelHomePage extends StatefulWidget {
  const NovelHomePage({
    super.key,
    required this.active,
    this.refreshTick = 0,
    this.collect,
    this.history,
    this.searchHistory,
    this.stats,
    this.sourceImporter,
    this.engineWired = false,
    this.openRoute,
    this.onSelectTab,
    this.prefs,
    this.backupService,
  });

  /// 当前 tab 是否可见；从别的 tab 切回来时重读本地数据。
  final bool active;

  /// 从详情/阅读返回时递增，触发重新读取最近阅读与统计。
  final int refreshTick;

  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final NovelStatsApi? stats;
  final NovelSourceImporter? sourceImporter;

  /// 在线书源引擎是否已由模块注入；书源引擎卡据此说明可用范围。
  final bool engineWired;

  final NovelRouteOpener? openRoute;
  final ValueChanged<int>? onSelectTab;

  /// 模块 kv（存 WebDAV 配置与偏好）；null 时不显示备份卡。
  final NovelPrefsApi? prefs;

  /// WebDAV 备份服务（装配处构造）；null 时备份卡显示能力边界说明。
  final NovelWebDavBackupService? backupService;

  @override
  State<NovelHomePage> createState() => _NovelHomePageState();
}

class _NovelHomePageState extends State<NovelHomePage> with RouteAware {
  late Future<_HomeData> _future;

  /// 首页模块配置（开关/顺序/自定义分组卡片）。读失败用默认清单，
  /// 默认清单刻意等于改造前的排布。
  NovelHomeModuleConfig _modules = const NovelHomeModuleConfig(
    NovelHomeModuleConfig.defaults,
  );

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  PageRoute<dynamic>? _route;
  bool _routeSubscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      if (_routeSubscribed && _route != null) {
        mimaoRouteObserver.unsubscribe(this);
      }
      _route = route;
      mimaoRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed) mimaoRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    if (widget.active) _reload();
  }

  @override
  void didUpdateWidget(NovelHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = !oldWidget.active && widget.active;
    final servicesChanged =
        oldWidget.collect != widget.collect ||
        oldWidget.history != widget.history ||
        oldWidget.stats != widget.stats ||
        oldWidget.sourceImporter != widget.sourceImporter;
    if (becameActive ||
        servicesChanged ||
        oldWidget.refreshTick != widget.refreshTick) {
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_HomeData> _load() async {
    final errors = <String>[];

    var recent = const <NovelHistoryItem>[];
    final history = widget.history;
    if (history != null) {
      try {
        recent = await history.recent(limit: 30);
      } on Object catch (error) {
        errors.add('阅读记录读取失败：$error');
      }
    }

    var collects = const <NovelCollectItem>[];
    final collect = widget.collect;
    if (collect != null) {
      try {
        collects = await collect.list();
      } on Object catch (error) {
        errors.add('收藏读取失败：$error');
      }
    }

    var stats = const NovelStats(
      booksRead: 0,
      collected: 0,
      totalSeconds: 0,
      todaySeconds: 0,
      goalMinutes: novelDefaultGoalMinutes,
    );
    final statsApi = widget.stats;
    if (statsApi != null) {
      try {
        stats = await statsApi.snapshot();
      } on Object catch (error) {
        errors.add('阅读统计读取失败：$error');
      }
    }

    var sources = const <NovelBookSource>[];
    final importer = widget.sourceImporter;
    if (importer != null) {
      try {
        sources = await importer.store.loadAll();
      } on Object catch (error) {
        errors.add('书源读取失败：$error');
      }
    }

    var webDavConfigured = false;
    DateTime? lastBackupAt;
    var modules = const NovelHomeModuleConfig(NovelHomeModuleConfig.defaults);
    final prefs = widget.prefs;
    if (prefs != null) {
      try {
        // 只读地址键：首页卡片不需要完整配置（完整配置会去碰系统安全存储）。
        final url = await prefs.read(novelWebDavUrlKey);
        webDavConfigured = url != null && url.trim().isNotEmpty;
        lastBackupAt = DateTime.tryParse(
          await prefs.read(novelWebdavLastBackupAtKey) ?? '',
        );
      } on Object catch (error) {
        errors.add('WebDAV 配置读取失败：$error');
      }
      try {
        modules = NovelHomeModuleConfig.decode(
          await prefs.read(novelPrefHomeModules),
        );
      } on Object catch (error) {
        errors.add('首页模块配置读取失败：$error');
      }
    }
    if (mounted) _modules = modules;

    return _HomeData(
      recent: recent,
      collects: collects,
      stats: stats,
      sources: sources,
      webDavConfigured: webDavConfigured,
      lastBackupAt: lastBackupAt,
      modules: modules,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  Future<void> _openRoute(
    NovelRoute route, {
    Map<String, Object?> args = const <String, Object?>{},
  }) async {
    await openNovelRoute(context, widget.openRoute, route, args: args);
    if (mounted) _reload();
  }

  Future<void> _openBook(NovelSummary book) => _openRoute(
    NovelRoute.bookInfo,
    args: <String, Object?>{'bookId': book.id, 'title': book.title},
  );

  Future<void> _editGoal(_HomeData data) async {
    final statsApi = widget.stats;
    if (statsApi == null) {
      _toast('阅读统计服务未启用，目标暂时不能保存。重启应用后再试。');
      return;
    }
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => NovelGoalDialog(initialMinutes: data.stats.goalMinutes),
    );
    if (minutes == null) return;
    try {
      await statsApi.setGoalMinutes(minutes);
    } on Object catch (error) {
      if (mounted) _toast('保存目标失败：$error');
      return;
    }
    if (mounted) _reload();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 首页 WebDAV 卡：地址配置在弹层里做，备份/预览/恢复/撤销统一进备份中心。
  Future<void> _openWebDav(NovelPrefsApi prefs) async {
    NovelWebDavConfig? current;
    try {
      // 记得住密码就回填；安全存储出问题也不该让弹层打不开。
      current = await readWebDavConfig(prefs);
    } on Object {
      current = null;
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<_WebDavAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WebDavSheet(prefs: prefs, config: current),
    );
    if (action == null || !mounted) return;
    if (action == _WebDavAction.openCenter) {
      final service = widget.backupService;
      if (service == null) {
        _toast('备份服务未启用，重启应用后再试。');
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: const RouteSettings(name: 'novel/backup'),
          builder: (_) => NovelBackupPage(service: service, prefs: prefs),
        ),
      );
      if (changed == true && mounted) _reload();
      return;
    }
    if (action == _WebDavAction.configure) {
      if (mounted) _reload();
    }
  }

  // ---------------------------------------------------------------------------
  // 模块化渲染

  /// 按配置渲染首页模块。
  ///
  /// 宽窗保持改造前的两栏骨架：主栏（最近阅读/统计/目标/自定义分组）与
  /// 侧栏（书源/引擎）并排，整行模块（书架横条/备份）铺满。窄窗一律单列，
  /// 顺序完全按配置。模块被关掉时不占位，不会留空隙。
  Widget _buildModules(
    BuildContext context,
    _HomeData data, {
    required bool wide,
  }) {
    final modules = data.modules.enabledModules;
    if (modules.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: <Widget>[
            Text('首页模块都被关掉了', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '在下面的「管理模块」里重新打开至少一个模块。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => _openModuleManager(data),
              child: const Text('管理模块'),
            ),
          ],
        ),
      );
    }
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final module in modules) ...<Widget>[
            _buildModule(context, data, module),
            const SizedBox(height: 16),
          ],
        ],
      );
    }
    final main = <NovelHomeModule>[];
    final side = <NovelHomeModule>[];
    final full = <NovelHomeModule>[];
    for (final module in modules) {
      switch (module.kind.slot) {
        case NovelHomeModuleSlot.main:
          main.add(module);
        case NovelHomeModuleSlot.side:
          side.add(module);
        case NovelHomeModuleSlot.full:
          full.add(module);
      }
    }
    // 主栏或侧栏被全部关掉时，另一栏直接占满，不留 380px 的空洞。
    final onlyMain = side.isEmpty;
    final onlySide = main.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!onlySide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final module in main) ...<Widget>[
                      _buildModule(context, data, module),
                      if (module != main.last) const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
              if (!onlyMain) ...<Widget>[
                const SizedBox(width: 20),
                SizedBox(
                  width: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final module in side) ...<Widget>[
                        _buildModule(context, data, module),
                        if (module != side.last) const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        for (final module in full) ...<Widget>[
          if (module != full.first || !onlySide) const SizedBox(height: 24),
          _buildModule(context, data, module),
        ],
      ],
    );
  }

  /// 单个模块 → Widget。未知/未实现的模块返回空盒，不抛错。
  Widget _buildModule(
    BuildContext context,
    _HomeData data,
    NovelHomeModule module,
  ) {
    return switch (module.kind) {
      NovelHomeModuleKind.recent => _RecentReadingCard(
        item: data.recent.isEmpty ? null : data.recent.first,
        onOpen: _openBook,
        onOpenHistory: () => _openRoute(NovelRoute.history),
        onGoShelf: () => widget.onSelectTab?.call(1),
      ),
      NovelHomeModuleKind.stats => _StatsRow(
        stats: data.stats,
        statsWired: widget.stats != null,
      ),
      NovelHomeModuleKind.goal => _GoalCard(
        stats: data.stats,
        onEdit: () => _editGoal(data),
      ),
      NovelHomeModuleKind.source => _SourceCard(
        sources: data.sources,
        wired: widget.sourceImporter != null,
        onOpenSubscribe: () => widget.onSelectTab?.call(3),
      ),
      NovelHomeModuleKind.capability => _CapabilityCard(
        wired: widget.engineWired,
      ),
      NovelHomeModuleKind.shelfStrip => _ShelfStrip(
        collects: data.collects,
        onOpen: _openBook,
        onGoShelf: () => widget.onSelectTab?.call(1),
      ),
      // 没有 prefs 就没法读写 WebDAV 配置，整卡不渲染（配置里留着，注入后自动出现）。
      NovelHomeModuleKind.webdav =>
        widget.prefs == null
            ? const SizedBox.shrink()
            : _WebDavBackupCard(
                configured: data.webDavConfigured,
                lastBackupAt: data.lastBackupAt,
                onOpen: () => _openWebDav(widget.prefs!),
              ),
      NovelHomeModuleKind.customGroup => _CustomGroupCard(
        groupName: module.groupName ?? '',
        collects: data.collects,
        onOpen: _openBook,
        onGoShelf: () => widget.onSelectTab?.call(1),
        onEdit: () => _openModuleManager(data),
      ),
    };
  }

  /// 保存模块配置：先落 kv 再刷新，写失败只提示不清空界面。
  Future<void> _saveModules(NovelHomeModuleConfig config) async {
    setState(() => _modules = config);
    final prefs = widget.prefs;
    if (prefs == null) {
      _toast('偏好服务未启用，模块设置本次有效但不能保存。重启应用后再试。');
      return;
    }
    try {
      await prefs.write(novelPrefHomeModules, config.encode());
    } on Object catch (error) {
      _toast('保存模块设置失败：$error');
    }
    if (mounted) _reload();
  }

  Future<void> _openModuleManager(_HomeData data) async {
    final result = await showNovelHomeModuleManager(
      context,
      config: _modules,
      availableGroups: <String>{
        for (final item in data.collects)
          if (item.groupName != null && item.groupName!.isNotEmpty)
            item.groupName!,
      }.toList()..sort(),
    );
    if (result == null) return;
    await _saveModules(result);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NovelLoadingState(label: '正在读取本地阅读数据…');
        }
        final data = snapshot.data ?? _HomeData.empty;
        if (snapshot.hasError) {
          return NovelErrorState(
            message: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        return NovelPageContent(
          child: ListView(
            children: <Widget>[
              NovelPageHeader(
                title: '首页',
                subtitle: data.subtitle,
                actions: <Widget>[
                  NovelCircleAction(
                    key: const Key('novel-home-search'),
                    icon: Icons.search,
                    tooltip: '搜索',
                    onPressed: () => _openRoute(NovelRoute.search),
                  ),
                  NovelCircleAction(
                    key: const Key('novel-home-modules'),
                    icon: Icons.dashboard_customize_outlined,
                    tooltip: '管理首页模块',
                    onPressed: () => _openModuleManager(data),
                  ),
                ],
              ),
              if (data.error != null) ...<Widget>[
                _DataWarning(message: data.error!, onRetry: _reload),
                const SizedBox(height: 16),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  return _buildModules(context, data, wide: wide);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 首页聚合快照。
class _HomeData {
  const _HomeData({
    required this.recent,
    required this.collects,
    required this.stats,
    required this.sources,
    this.webDavConfigured = false,
    this.lastBackupAt,
    this.modules = const NovelHomeModuleConfig(NovelHomeModuleConfig.defaults),
    this.error,
  });

  static const _HomeData empty = _HomeData(
    recent: <NovelHistoryItem>[],
    collects: <NovelCollectItem>[],
    stats: NovelStats(
      booksRead: 0,
      collected: 0,
      totalSeconds: 0,
      todaySeconds: 0,
      goalMinutes: novelDefaultGoalMinutes,
    ),
    sources: <NovelBookSource>[],
  );

  final List<NovelHistoryItem> recent;
  final List<NovelCollectItem> collects;
  final NovelStats stats;
  final List<NovelBookSource> sources;
  final bool webDavConfigured;
  final DateTime? lastBackupAt;
  final NovelHomeModuleConfig modules;
  final String? error;

  String get subtitle {
    final enabled = sources.where((s) => s.enabled).length;
    if (sources.isNotEmpty) {
      return '本地阅读 · ${sources.length} 个书源（$enabled 启用）';
    }
    return '本地阅读 · 书源引擎已就绪';
  }
}

class _DataWarning extends StatelessWidget {
  const _DataWarning({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, size: 20, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 最近阅读大卡：封面 + 书名/作者 + 进度 + 进度条。
class _RecentReadingCard extends StatelessWidget {
  const _RecentReadingCard({
    required this.item,
    required this.onOpen,
    required this.onOpenHistory,
    required this.onGoShelf,
  });

  final NovelHistoryItem? item;
  final ValueChanged<NovelSummary> onOpen;
  final VoidCallback onOpenHistory;
  final VoidCallback onGoShelf;

  @override
  Widget build(BuildContext context) {
    final data = item;
    return NovelCard(
      onTap: data == null ? null : () => onOpen(data.book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(
            icon: Icons.bookmark_outline,
            title: '最近阅读',
            trailing: TextButton(
              onPressed: onOpenHistory,
              child: const Text('全部记录'),
            ),
          ),
          const SizedBox(height: 14),
          if (data == null)
            _RecentEmpty(onGoShelf: onGoShelf)
          else
            _RecentBody(item: data),
        ],
      ),
    );
  }
}

class _RecentBody extends StatelessWidget {
  const _RecentBody({required this.item});

  final NovelHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final percent = novelBookPercent(
      chapterIndex: item.chapterIndex,
      chapterCount: item.chapterCount,
    );
    final progress = (percent ?? 0) / 100;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 92,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: NovelBookCover(
                    url: item.book.coverUrl,
                    title: item.book.title,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: NovelCoverBadge(
                    text: percent == null ? '未读' : '$percent%',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.book.title,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                item.book.author.isEmpty ? '作者未知' : item.book.author,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Text(
                novelProgressText(
                  chapterIndex: item.chapterIndex,
                  chapterCount: item.chapterCount,
                ),
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(MimaoRadii.pill),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.schedule, size: 15, color: cs.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    '上次阅读 · ${novelRelativeTime(item.openedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '继续阅读',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentEmpty extends StatelessWidget {
  const _RecentEmpty({required this.onGoShelf});

  final VoidCallback onGoShelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 72,
          height: 96,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(MimaoRadii.md),
          ),
          child: Icon(Icons.auto_stories_outlined, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('还没有最近阅读', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '读过的书会在这里接着读。先在「订阅 → 导入规则」导入书源，'
                '再去搜索页找书；本地收藏可以直接去书架看。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: onGoShelf,
                    icon: const Icon(Icons.local_library_outlined),
                    label: const Text('去书架'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.statsWired});

  final NovelStats stats;
  final bool statsWired;

  @override
  Widget build(BuildContext context) {
    final (durationValue, durationUnit) = novelDurationParts(
      stats.totalSeconds,
    );
    final cards = <Widget>[
      Expanded(
        child: NovelStatCard(
          icon: Icons.bar_chart,
          label: '累计阅读',
          value: statsWired ? '${stats.booksRead}' : '—',
          unit: '本',
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: NovelStatCard(
          icon: Icons.schedule,
          label: '阅读时长',
          value: statsWired ? durationValue : '—',
          unit: durationUnit,
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[cards[0], const SizedBox(height: 12), cards[2]],
          );
        }
        return Row(children: cards);
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.stats, required this.onEdit});

  final NovelStats stats;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final goal = stats.goalMinutes;
    final minutes = stats.todayMinutes;
    final remaining = goal - minutes;
    final caption = goal <= 0
        ? '还没有设置今日目标。点右侧按钮设一个时长，完成后这里会填满。'
        : minutes == 0
        ? '今天还没有阅读记录。在阅读页停留的时间会自动累计到这里。'
        : remaining > 0
        ? '今天已读 $minutes 分钟，还差 $remaining 分钟达成目标。'
        : '今天已读 $minutes 分钟，目标已达成。';
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Icon(
              Icons.local_fire_department_outlined,
              size: 17,
              color: cs.primary,
            ),
            const SizedBox(width: 6),
            Text(
              goal <= 0 ? '目标未设置' : '目标 $goal 分钟',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(
            icon: Icons.flag_outlined,
            title: '今日阅读目标',
            trailing: _EditGoalButton(onPressed: onEdit),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final gauge = NovelReadingGauge(
                progress: stats.goalProgress,
                minutes: minutes,
                goalMinutes: goal,
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  children: <Widget>[gauge, const SizedBox(height: 12), info],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 240, child: gauge),
                  const SizedBox(width: 24),
                  Expanded(child: info),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EditGoalButton extends StatelessWidget {
  const _EditGoalButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '设置今日阅读目标',
      icon: const Icon(Icons.edit_outlined),
      onPressed: onPressed,
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.sources,
    required this.wired,
    required this.onOpenSubscribe,
  });

  final List<NovelBookSource> sources;
  final bool wired;
  final VoidCallback onOpenSubscribe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = sources.where((s) => s.enabled).length;
    final status = !wired
        ? '书源功能未启用'
        : sources.isEmpty
        ? '还没有书源'
        : '已导入 ${sources.length} 个书源 · $enabled 个启用';
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(
            icon: Icons.source_outlined,
            title: '书源',
            trailing: TextButton(
              onPressed: onOpenSubscribe,
              child: const Text('订阅页'),
            ),
          ),
          const SizedBox(height: 10),
          Text(status, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            !wired
                ? '当前版本没有加载书源仓库，无法导入书源。重启应用后再试。'
                : sources.isEmpty
                ? '打开书源网站，点网页里的「一键导入」即可把书源存到本机。'
                : '书源订阅与管理都在「订阅」页；发现页可按分组筛选和启停。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.wired});

  final bool wired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(
            icon: wired ? Icons.check_circle_outline : Icons.construction,
            title: '书源引擎',
          ),
          const SizedBox(height: 10),
          Text(
            wired
                ? '已接入：搜索、发现分类、目录抓取与正文阅读都走已导入的书源。'
                      '还没导入书源的话，先去「订阅 → 导入规则」。'
                : '未启用：当前只能导入、分组和启停书源，搜索仅匹配本地书架与'
                      '阅读记录。重启应用后再试。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfStrip extends StatelessWidget {
  const _ShelfStrip({
    required this.collects,
    required this.onOpen,
    required this.onGoShelf,
  });

  final List<NovelCollectItem> collects;
  final ValueChanged<NovelSummary> onOpen;
  final VoidCallback onGoShelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('我的书架', style: theme.textTheme.titleLarge)),
            TextButton(onPressed: onGoShelf, child: const Text('查看全部')),
          ],
        ),
        const SizedBox(height: 10),
        if (collects.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(MimaoRadii.lg),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.collections_bookmark_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '书架还是空的。收藏一本书后会在这里横向排列；'
                    '可以先去「订阅」导入规则，再去搜索页找书。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          NovelCoverStrip(
            itemCount: collects.length > 12 ? 12 : collects.length,
            itemBuilder: (context, index) {
              final item = collects[index];
              return _ShelfStripItem(
                item: item,
                onTap: () => onOpen(
                  item.book ??
                      NovelSummary(
                        id: item.ref.id,
                        title: item.title,
                        coverUrl: item.coverUrl ?? '',
                      ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// 自定义分组卡片：首页展示某个书架分组的封面横条。
///
/// 分组是书架收藏行上的字段，所以这里直接用收藏快照过滤，不额外查库。
class _CustomGroupCard extends StatelessWidget {
  const _CustomGroupCard({
    required this.groupName,
    required this.collects,
    required this.onOpen,
    required this.onGoShelf,
    required this.onEdit,
  });

  final String groupName;
  final List<NovelCollectItem> collects;
  final ValueChanged<NovelSummary> onOpen;
  final VoidCallback onGoShelf;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final items = <NovelCollectItem>[
      for (final item in collects)
        if (item.groupName == groupName) item,
    ];
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(
            icon: Icons.folder_outlined,
            title: groupName.isEmpty ? '分组' : groupName,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(onPressed: onGoShelf, child: const Text('去书架')),
                IconButton(
                  tooltip: '管理首页模块',
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  onPressed: onEdit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              '「$groupName」里还没有书。去书架把书加入这个分组，或换一张卡片。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            NovelCoverStrip(
              itemCount: items.length > 12 ? 12 : items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _ShelfStripItem(
                  item: item,
                  onTap: () => onOpen(
                    item.book ??
                        NovelSummary(
                          id: item.ref.id,
                          title: item.title,
                          coverUrl: item.coverUrl ?? '',
                        ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ShelfStripItem extends StatelessWidget {
  const _ShelfStripItem({required this.item, required this.onTap});

  final NovelCollectItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MimaoRadii.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 2 / 3,
                child: NovelBookCover(
                  url: item.coverUrl ?? item.book?.coverUrl ?? '',
                  title: item.title,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _WebDavAction { configure, openCenter }

/// 首页 WebDAV 备份卡：显示是否已配置与上次备份时间，点按进备份中心。
class _WebDavBackupCard extends StatelessWidget {
  const _WebDavBackupCard({
    required this.configured,
    required this.onOpen,
    this.lastBackupAt,
  });

  final bool configured;
  final DateTime? lastBackupAt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final subtitle = !configured
        ? '未配置 · 点按填入 WebDAV 地址，备份书架、进度与书源'
        : lastBackupAt == null
        ? '已配置 · 还没有备份过'
        : '已配置 · 上次备份 ${novelRelativeTime(lastBackupAt!)}'
              ' · 进度同步 / 恢复预览 / 撤销';
    return NovelCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_outlined, color: cs.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('WebDAV 备份', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// WebDAV 配置 + 操作面板（bottom sheet）。
class _WebDavSheet extends StatefulWidget {
  const _WebDavSheet({required this.prefs, required this.config});

  final NovelPrefsApi prefs;
  final NovelWebDavConfig? config;

  @override
  State<_WebDavSheet> createState() => _WebDavSheetState();
}

class _WebDavSheetState extends State<_WebDavSheet> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _url = TextEditingController(text: config?.url ?? '');
    _user = TextEditingController(text: config?.user ?? '');
    _password = TextEditingController(text: config?.password ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = NovelWebDavConfig(
      url: _url.text.trim(),
      user: _user.text.trim(),
      password: _password.text,
    );
    if (!config.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填入完整的 http(s) WebDAV 地址')),
        );
      }
      return;
    }
    final saved = await writeWebDavConfig(widget.prefs, config);
    if (!mounted) return;
    if (saved.passwordSource == NovelPasswordSource.legacyKv) {
      // 不静默失败：安全存储不可用时说清楚，让用户决定要不要留密码。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本机安全存储不可用，密码暂时存在模块数据库里；可在备份中心清空密码')),
      );
      return;
    }
    Navigator.pop(context, _WebDavAction.configure);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('WebDAV 备份', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '书架、阅读记录、进度、书签划线、书源与偏好会打成一个 JSON 包上传到'
            '下面地址；恢复前会先给你看「新增 / 更新 / 冲突」的预览，不会直接清库。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('novel-webdav-url'),
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://dav.example.com/mimao/novel.json',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: '用户名（可选）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              labelText: '密码（可选）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('novel-webdav-save'),
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存配置'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('novel-webdav-open-center'),
            onPressed: () => Navigator.pop(context, _WebDavAction.openCenter),
            icon: const Icon(Icons.cloud_sync_outlined),
            label: const Text('打开备份中心'),
          ),
        ],
      ),
    );
  }
}
