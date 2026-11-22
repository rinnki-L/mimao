// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「首页」：最近阅读 + 阅读统计 + 今日目标 + 书源状态 + 我的书架横条。
///
/// 所有数字来自本地库：最近阅读 = novel_history 最新一条，累计阅读 = 历史条数，
/// 阅读时长 = 阅读时长按天表之和（阅读器未接入时为 0，不估算）。书源卡读真实
/// 书源仓库；没有任何数据时给"为什么空 + 下一步做什么"的空态。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class NovelHomePage extends StatefulWidget {
  const NovelHomePage({
    super.key,
    required this.active,
    this.collect,
    this.history,
    this.stats,
    this.sourceImporter,
    this.openRoute,
    this.onSelectTab,
  });

  /// 当前 tab 是否可见；从别的 tab 切回来时重读本地数据。
  final bool active;

  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelStatsApi? stats;
  final NovelSourceImporter? sourceImporter;
  final NovelRouteOpener? openRoute;
  final ValueChanged<int>? onSelectTab;

  @override
  State<NovelHomePage> createState() => _NovelHomePageState();
}

class _NovelHomePageState extends State<NovelHomePage> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
    if (becameActive || servicesChanged) _reload();
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

    return _HomeData(
      recent: recent,
      collects: collects,
      stats: stats,
      sources: sources,
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
      _toast('阅读统计未接线，目标暂时不能保存。');
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
                    key: const Key('novel-home-settings'),
                    icon: Icons.settings_outlined,
                    tooltip: '小说设置',
                    onPressed: () => _openRoute(NovelRoute.settings),
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
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _RecentReadingCard(
                          item: data.recent.isEmpty ? null : data.recent.first,
                          onOpen: _openBook,
                          onOpenHistory: () => _openRoute(NovelRoute.history),
                          onGoShelf: () => widget.onSelectTab?.call(1),
                          onImportSource: () =>
                              _openRoute(NovelRoute.sourceManage),
                        ),
                        const SizedBox(height: 16),
                        _StatsRow(
                          stats: data.stats,
                          statsWired: widget.stats != null,
                        ),
                        const SizedBox(height: 16),
                        _ShelfStrip(
                          collects: data.collects,
                          onOpen: _openBook,
                          onGoShelf: () => widget.onSelectTab?.call(1),
                          onImportSource: () =>
                              _openRoute(NovelRoute.sourceManage),
                        ),
                        const SizedBox(height: 16),
                        _GoalCard(
                          stats: data.stats,
                          onEdit: () => _editGoal(data),
                        ),
                        const SizedBox(height: 16),
                        _SourceCard(
                          sources: data.sources,
                          wired: widget.sourceImporter != null,
                          onManage: () => _openRoute(NovelRoute.sourceManage),
                          onOpenSubscribe: () => widget.onSelectTab?.call(3),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _RecentReadingCard(
                              item: data.recent.isEmpty
                                  ? null
                                  : data.recent.first,
                              onOpen: _openBook,
                              onOpenHistory: () =>
                                  _openRoute(NovelRoute.history),
                              onGoShelf: () => widget.onSelectTab?.call(1),
                              onImportSource: () =>
                                  _openRoute(NovelRoute.sourceManage),
                            ),
                            const SizedBox(height: 16),
                            _StatsRow(
                              stats: data.stats,
                              statsWired: widget.stats != null,
                            ),
                            const SizedBox(height: 16),
                            _GoalCard(
                              stats: data.stats,
                              onEdit: () => _editGoal(data),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 380,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _SourceCard(
                              sources: data.sources,
                              wired: widget.sourceImporter != null,
                              onManage: () =>
                                  _openRoute(NovelRoute.sourceManage),
                              onOpenSubscribe: () =>
                                  widget.onSelectTab?.call(3),
                            ),
                            const SizedBox(height: 16),
                            const _CapabilityCard(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _ShelfStrip(
                collects: data.collects,
                onOpen: _openBook,
                onGoShelf: () => widget.onSelectTab?.call(1),
                onImportSource: () => _openRoute(NovelRoute.sourceManage),
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
  final String? error;

  String get subtitle {
    final enabled = sources.where((s) => s.enabled).length;
    if (sources.isNotEmpty) {
      return '本地阅读 · ${sources.length} 个书源（$enabled 启用）';
    }
    return '本地阅读 · 书源引擎尚未接入';
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
    required this.onImportSource,
  });

  final NovelHistoryItem? item;
  final ValueChanged<NovelSummary> onOpen;
  final VoidCallback onOpenHistory;
  final VoidCallback onGoShelf;
  final VoidCallback onImportSource;

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
            _RecentEmpty(onGoShelf: onGoShelf, onImportSource: onImportSource)
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
  const _RecentEmpty({required this.onGoShelf, required this.onImportSource});

  final VoidCallback onGoShelf;
  final VoidCallback onImportSource;

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
                '读过的书会在这里接着读。当前书源引擎尚未接入，可以先导入书源，'
                '或在书架查看本地收藏。',
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
                  OutlinedButton.icon(
                    key: const Key('novel-home-import-source'),
                    onPressed: onImportSource,
                    icon: const Icon(Icons.add_link),
                    label: const Text('导入书源'),
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
        ? '今天还没有阅读记录。阅读器接入后，阅读页停留时间会自动累计到这里。'
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
    required this.onManage,
    required this.onOpenSubscribe,
  });

  final List<NovelBookSource> sources;
  final bool wired;
  final VoidCallback onManage;
  final VoidCallback onOpenSubscribe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = sources.where((s) => s.enabled).length;
    final status = !wired
        ? '书源功能未接线'
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
            sources.isEmpty
                ? '打开书源网站，点网页里的「一键导入」即可把书源存到本机。'
                : '书源按分组展示在「订阅」页；发现页可按分组筛选和启停。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                key: const Key('novel-home-manage-source'),
                onPressed: onManage,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('管理'),
              ),
              OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.add_link),
                label: const Text('导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(icon: Icons.construction, title: '书源引擎状态'),
          const SizedBox(height: 10),
          Text(
            '跨源搜索、目录抓取与正文阅读仍在接入中。当前版本可以先导入、分组和'
            '启停书源；书架与阅读记录读取真实本地库。',
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
    required this.onImportSource,
  });

  final List<NovelCollectItem> collects;
  final ValueChanged<NovelSummary> onOpen;
  final VoidCallback onGoShelf;
  final VoidCallback onImportSource;

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
                    '也可以先去「发现」导入书源。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onImportSource,
                  child: const Text('导入书源'),
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
