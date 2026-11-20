// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/pages/anime_cover.dart';
import 'package:mimao/anime/pages/anime_error_state.dart';
import 'package:mimao/anime/pages/anime_image_mirror.dart';
import 'package:mimao/core/theme.dart';

/// 番剧详情页——Kazumi 式「元数据 + 选源观看」。
///
/// 搜索主源是 Bangumi（只带元数据/封面，没有剧集）。进详情页后：
/// 1. 先展示 Bangumi 元数据（封面/标题/简介/评分/首播/标签）与追番按钮；
/// 2. 并发向所有已装规则搜「同一部番」的可观看来源；
/// 3. 多来源：列出来源供用户选，选中后才抓该源剧集（Kazumi source_sheet 流程）；
///    单来源（fixture/规则直连）：自动选中，行为与之前一致。
class AnimeDetailPage extends StatefulWidget {
  const AnimeDetailPage({
    super.key,
    required this.dataSource,
    required this.summary,
    this.initiallyFavorite = false,
    this.onFavoriteChanged,
    this.onEpisodeTap,
    this.mirror,
  });

  final AnimeDataSource dataSource;

  /// 搜索/时间表带进来的条目（Bangumi 条目或规则条目）。
  final AnimeSummary summary;

  final bool initiallyFavorite;
  final ValueChanged<bool>? onFavoriteChanged;

  /// 封面镜像开关控制器；null 时封面不走代理（保持既有行为）。
  final AnimeImageAccelerationController? mirror;

  /// 点剧集：连同选中的播放源与详情回调，模块层据此映射剧集/请求头。
  final void Function(
    AnimeSummary source,
    AnimeDetail detail,
    AnimeEpisode episode,
  )?
  onEpisodeTap;

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage> {
  late bool _isFavorite;

  /// 可观看来源（所有规则按标题搜到的同一部番）。
  late Future<List<AnimeSummary>> _sourcesFuture;

  /// 当前选中的来源；多来源时由用户点选，单来源时自动选中。
  AnimeSummary? _selectedSource;

  /// 选中来源的剧集详情。
  Future<AnimeDetail>? _detailFuture;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initiallyFavorite;
    _reload();
  }

  @override
  void didUpdateWidget(AnimeDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource ||
        oldWidget.summary.id != widget.summary.id) {
      _reload();
    }
  }

  void _reload() {
    _selectedSource = null;
    _detailFuture = null;
    _sourcesFuture = widget.dataSource.watchSources(
      widget.summary,
      keyword: widget.summary.title,
    );
    // 单来源：自动选中并抓剧集（fixture/规则直连的既有行为）。
    // 不在 build 里 setState——在 future 完成后处理。
    _sourcesFuture
        .then((sources) {
          if (!mounted || _selectedSource != null || sources.length != 1) {
            return;
          }
          setState(() {
            _selectedSource = sources.first;
            _detailFuture = widget.dataSource.detail(sources.first);
          });
        })
        .catchError((Object _) {});
  }

  /// 选中一个播放来源：抓该源剧集。
  void _selectSource(AnimeSummary source) {
    if (source.id == _selectedSource?.id &&
        source.sourceName == _selectedSource?.sourceName) {
      return;
    }
    setState(() {
      _selectedSource = source;
      _detailFuture = widget.dataSource.detail(source);
    });
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    widget.onFavoriteChanged?.call(_isFavorite);
  }

  void _retrySources() => setState(_reload);

  void _retryDetail() {
    final source = _selectedSource;
    if (source != null) {
      setState(() => _detailFuture = widget.dataSource.detail(source));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('番剧详情'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: FutureBuilder<List<AnimeSummary>>(
        future: _sourcesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final sources = snapshot.data ?? const <AnimeSummary>[];
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _MetaHeader(summary: widget.summary, mirror: widget.mirror),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  key: const Key('favorite-button'),
                  onPressed: _toggleFavorite,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: Icon(
                    _isFavorite
                        ? Icons.bookmark_added_rounded
                        : Icons.bookmark_add_outlined,
                  ),
                  label: Text(_isFavorite ? '已追番' : '追番'),
                ),
                const SizedBox(height: 16),
                if (snapshot.hasError)
                  AnimeRetryErrorState(
                    message: '来源加载失败',
                    onRetry: _retrySources,
                  )
                else if (sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '没有可用的观看来源',
                      style: Theme.of(context).textTheme.bodyMedium?.apply(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else ...<Widget>[
                  _SourceSelector(
                    sources: sources,
                    selected: _selectedSource,
                    onSelected: _selectSource,
                  ),
                  const SizedBox(height: 16),
                  _EpisodesSection(
                    detailFuture: _detailFuture,
                    selectedSource: _selectedSource,
                    hasSources: sources.isNotEmpty,
                    onRetry: _retryDetail,
                    onEpisodeTap: widget.onEpisodeTap,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bangumi 元数据区：封面 / 标题 / 评分 / 首播 / 简介 / 标签。
class _MetaHeader extends StatelessWidget {
  const _MetaHeader({required this.summary, this.mirror});

  final AnimeSummary summary;
  final AnimeImageAccelerationController? mirror;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 116,
          height: 174,
          child: AnimeCover(
            url: summary.coverUrl,
            title: summary.title,
            radius: 20,
            mirror: mirror,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                summary.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineSmall,
              ),
              if (summary.rating != null) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Icon(Icons.star_rounded, size: 16, color: cs.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      '评分 ${summary.rating!.toStringAsFixed(1)}',
                      style: textTheme.labelMedium?.apply(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              if (summary.airDate.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '首播 ${summary.airDate}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.apply(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (summary.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final tag in summary.tags.take(4))
                      _TagChip(label: tag),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 来源选择：列出所有规则的来源，点选后才抓该源剧集（Kazumi source_sheet）。
class _SourceSelector extends StatelessWidget {
  const _SourceSelector({
    required this.sources,
    required this.selected,
    required this.onSelected,
  });

  final List<AnimeSummary> sources;
  final AnimeSummary? selected;
  final ValueChanged<AnimeSummary> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.alt_route_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              sources.length > 1 ? '选择来源观看（${sources.length} 个来源）' : '观看来源',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.apply(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            for (final source in sources)
              ChoiceChip(
                key: ValueKey<String>(
                  'source-chip-${source.sourceName ?? ''}-${source.id}',
                ),
                label: Text(source.sourceName ?? '未知规则'),
                selected:
                    source.sourceName == selected?.sourceName &&
                    source.id == selected?.id,
                onSelected: (_) => onSelected(source),
              ),
          ],
        ),
      ],
    );
  }
}

/// 剧集区：未选来源时提示；选中后抓该源详情并显示剧集。
class _EpisodesSection extends StatelessWidget {
  const _EpisodesSection({
    required this.detailFuture,
    required this.selectedSource,
    required this.hasSources,
    required this.onRetry,
    this.onEpisodeTap,
  });

  final Future<AnimeDetail>? detailFuture;
  final AnimeSummary? selectedSource;
  final bool hasSources;
  final VoidCallback onRetry;
  final void Function(
    AnimeSummary source,
    AnimeDetail detail,
    AnimeEpisode episode,
  )?
  onEpisodeTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final future = detailFuture;
    if (future == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.touch_app_outlined,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              hasSources ? '请选择一个来源以加载剧集' : '暂无可用来源',
              style: textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return FutureBuilder<AnimeDetail>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return AnimeRetryErrorState(message: '剧集加载失败', onRetry: onRetry);
        }
        final detail = snapshot.data!;
        final source = selectedSource!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('简介', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail.description.isEmpty ? '暂无简介' : detail.description,
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Text('剧集', style: textTheme.titleMedium),
                const Spacer(),
                Text(
                  '共 ${detail.episodes.length} 集',
                  style: textTheme.labelMedium?.apply(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (detail.episodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '暂无剧集',
                  style: textTheme.bodyMedium?.apply(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final episode in detail.episodes)
                _EpisodeTile(
                  episode: episode,
                  onTap: onEpisodeTap == null
                      ? null
                      : () => onEpisodeTap!(source, detail, episode),
                ),
          ],
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: cs.secondaryContainer,
      side: BorderSide.none,
      labelStyle: Theme.of(
        context,
      ).textTheme.labelSmall?.apply(color: cs.onSecondaryContainer),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, this.onTap});

  final AnimeEpisode episode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: MimaoShapes.md,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: Key('episode-${episode.number}'),
          onTap: onTap,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            child: Text(
              '${episode.number}',
              style: textTheme.labelMedium?.apply(
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
          title: Text(
            episode.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyLarge,
          ),
          subtitle: episode.duration == null
              ? null
              : Text(
                  episode.duration!,
                  style: textTheme.bodySmall?.apply(color: cs.onSurfaceVariant),
                ),
          trailing: onTap == null
              ? null
              : Icon(Icons.play_arrow_rounded, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
