// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/pages/anime_cover.dart';

/// 番剧时间表：按星期分组列出当周更新。
///
/// 分组数量与顺序完全由数据源给出的 [AnimeScheduleSection] 决定；
/// 页面不猜星期，也不发额外请求。
class AnimeSchedulePage extends StatefulWidget {
  const AnimeSchedulePage({
    super.key,
    required this.dataSource,
    this.showAppBar = true,
    this.onOpenDetail,
  });

  final AnimeDataSource dataSource;

  /// 壳已提供顶部导航时设为 false，本页不再画自己的 AppBar。
  final bool showAppBar;

  final ValueChanged<AnimeSummary>? onOpenDetail;

  @override
  State<AnimeSchedulePage> createState() => _AnimeSchedulePageState();
}

class _AnimeSchedulePageState extends State<AnimeSchedulePage> {
  late Future<List<AnimeScheduleSection>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.dataSource.schedule();
  }

  @override
  void didUpdateWidget(AnimeSchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource) {
      _future = widget.dataSource.schedule();
    }
  }

  void _reload() {
    setState(() => _future = widget.dataSource.schedule());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('时间表'),
              actions: <Widget>[
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                  onPressed: _reload,
                ),
              ],
            )
          : null,
      body: FutureBuilder<List<AnimeScheduleSection>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ScheduleErrorState(onRetry: _reload);
          }
          final sections = snapshot.data ?? const <AnimeScheduleSection>[];
          if (sections.isEmpty) return const _ScheduleEmptyState();
          return _ScheduleBody(
            sections: sections,
            onOpenDetail: widget.onOpenDetail,
          );
        },
      ),
    );
  }
}

class _ScheduleBody extends StatelessWidget {
  const _ScheduleBody({required this.sections, this.onOpenDetail});

  final List<AnimeScheduleSection> sections;
  final ValueChanged<AnimeSummary>? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = sections.fold<int>(0, (sum, s) => sum + s.items.length);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '本周 ${sections.length} 天 · $total 部',
                style: textTheme.labelLarge?.apply(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final section in sections)
            _ScheduleSectionView(section: section, onOpenDetail: onOpenDetail),
        ],
      ),
    );
  }
}

class _ScheduleSectionView extends StatelessWidget {
  const _ScheduleSectionView({required this.section, this.onOpenDetail});

  final AnimeScheduleSection section;
  final ValueChanged<AnimeSummary>? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            key: ValueKey<String>('schedule-section-${section.weekday.name}'),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  section.weekday.label,
                  style: textTheme.labelLarge?.apply(
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${section.items.length} 部',
                style: textTheme.labelMedium?.apply(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (var i = 0; i < section.items.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 68,
                      color: cs.outlineVariant.withValues(alpha: .5),
                    ),
                  _ScheduleRow(
                    key: ValueKey<String>(
                      'schedule-item-${section.items[i].id}',
                    ),
                    item: section.items[i],
                    onTap: onOpenDetail == null
                        ? null
                        : () => onOpenDetail!(section.items[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({super.key, required this.item, this.onTap});

  final AnimeSummary item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 44,
              height: 62,
              child: AnimeCover(
                url: item.coverUrl,
                title: item.title,
                radius: 10,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  if (item.subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.apply(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (item.sourceName != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      '来源：${item.sourceName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.apply(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.event_busy_rounded, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('本周暂无更新时间表', style: textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '稍后再来看看',
            style: textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ScheduleErrorState extends StatelessWidget {
  const _ScheduleErrorState({required this.onRetry});

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
          const Text('时间表加载失败'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
