// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/pages/anime_cover.dart';
import 'package:mimao/anime/pages/anime_error_state.dart';
import 'package:mimao/anime/pages/anime_image_mirror.dart';
import 'package:mimao/core/theme.dart';

/// 番剧详情页：封面 / 标题 / 简介 + 剧集列表 + 追番按钮。
///
/// 通过 [AnimeDataSource.detail] 异步取数据；追番状态暂由本页持有，
/// 点击后经 [onFavoriteChanged] 交给上层（后续接收藏服务）。
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

  /// 从搜索/时间表带进来的条目，详情地址在 [AnimeSummary.detailUrl]。
  final AnimeSummary summary;

  final bool initiallyFavorite;
  final ValueChanged<bool>? onFavoriteChanged;

  /// 封面镜像开关控制器；null 时封面不走代理（保持既有行为）。
  final AnimeImageAccelerationController? mirror;

  /// 播放器接线前留空；提供时剧集行才显示播放图标并可点击。
  /// 连同当前 [AnimeDetail] 与选中的播放源一起回调，模块层据此映射剧集列表、
  /// initialIndex 与规则请求头——换源后回传的是新来源，保证头与播放器一致。
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
  late Future<AnimeDetail> _future;
  late bool _isFavorite;

  /// 换源候选：当前规则 + 其它规则搜到的同一部番。默认只有当前条目
  /// （数据源不支持换源时保持单来源行为）。
  Future<List<AnimeSummary>>? _sourcesFuture;
  AnimeSummary? _selectedSource;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initiallyFavorite;
    _selectedSource = widget.summary;
    _future = widget.dataSource.detail(widget.summary);
    _sourcesFuture = widget.dataSource.watchSources(
      widget.summary,
      keyword: widget.summary.title,
    );
  }

  @override
  void didUpdateWidget(AnimeDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource ||
        oldWidget.summary.id != widget.summary.id) {
      _selectedSource = widget.summary;
      _future = widget.dataSource.detail(widget.summary);
      _sourcesFuture = widget.dataSource.watchSources(
        widget.summary,
        keyword: widget.summary.title,
      );
    }
  }

  /// 选中另一个规则来源：用该来源重抓详情与剧集。
  void _selectSource(AnimeSummary source) {
    if (source.id == _selectedSource?.id &&
        source.sourceName == _selectedSource?.sourceName) {
      return;
    }
    setState(() {
      _selectedSource = source;
      _future = widget.dataSource.detail(source);
    });
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    widget.onFavoriteChanged?.call(_isFavorite);
  }

  void _retry() {
    setState(
      () =>
          _future = widget.dataSource.detail(_selectedSource ?? widget.summary),
    );
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
      body: FutureBuilder<AnimeDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return AnimeRetryErrorState(message: '详情加载失败', onRetry: _retry);
          }
          return _DetailBody(
            detail: snapshot.data!,
            isFavorite: _isFavorite,
            sourcesFuture: _sourcesFuture,
            selectedSource: _selectedSource ?? widget.summary,
            onSourceSelected: _selectSource,
            onFavoriteToggle: _toggleFavorite,
            onEpisodeTap: widget.onEpisodeTap,
            mirror: widget.mirror,
          );
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.selectedSource,
    required this.onSourceSelected,
    this.sourcesFuture,
    this.onEpisodeTap,
    this.mirror,
  });

  final AnimeDetail detail;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final void Function(
    AnimeSummary source,
    AnimeDetail detail,
    AnimeEpisode episode,
  )?
  onEpisodeTap;

  final Future<List<AnimeSummary>>? sourcesFuture;
  final AnimeSummary selectedSource;
  final ValueChanged<AnimeSummary> onSourceSelected;
  final AnimeImageAccelerationController? mirror;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 116,
                height: 174,
                child: AnimeCover(
                  url: detail.coverUrl,
                  title: detail.title,
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
                      detail.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall,
                    ),
                    if (detail.sourceName != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.public_rounded,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '来源：${detail.sourceName}',
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
                    if (detail.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final tag in detail.tags) _TagChip(label: tag),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const Key('favorite-button'),
            onPressed: onFavoriteToggle,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: Icon(
              isFavorite
                  ? Icons.bookmark_added_rounded
                  : Icons.bookmark_add_outlined,
            ),
            label: Text(isFavorite ? '已追番' : '追番'),
          ),
          const SizedBox(height: 16),
          _SourceSelector(
            sourcesFuture: sourcesFuture,
            selected: selectedSource,
            onSelected: onSourceSelected,
          ),
          const SizedBox(height: 16),
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
                style: textTheme.labelMedium?.apply(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (detail.episodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '暂无剧集',
                style: textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final episode in detail.episodes)
              _EpisodeTile(
                episode: episode,
                onTap: onEpisodeTap == null
                    ? null
                    : () => onEpisodeTap!(selectedSource, detail, episode),
              ),
        ],
      ),
    );
  }
}

/// 换源选择器：列出所有已装规则里搜到的同一部番，点选即切换播放规则。
///
/// [sourcesFuture] 为 null（fixture/单来源）时不渲染任何内容，保持原界面。
/// 只有一条来源时也不显示，避免无意义的一行。加载中/失败静默跳过，不挡详情。
class _SourceSelector extends StatelessWidget {
  const _SourceSelector({
    required this.sourcesFuture,
    required this.selected,
    required this.onSelected,
  });

  final Future<List<AnimeSummary>>? sourcesFuture;
  final AnimeSummary selected;
  final ValueChanged<AnimeSummary> onSelected;

  @override
  Widget build(BuildContext context) {
    final future = sourcesFuture;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<AnimeSummary>>(
      future: future,
      builder: (context, snapshot) {
        final sources = snapshot.data;
        if (sources == null || sources.length < 2) {
          return const SizedBox.shrink();
        }
        final cs = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.alt_route_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '选择规则观看（${sources.length} 个来源）',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.apply(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final source in sources)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey<String>(
                          'source-chip-${source.sourceName ?? ''}-${source.id}',
                        ),
                        label: Text(source.sourceName ?? '未知规则'),
                        selected:
                            source.sourceName == selected.sourceName &&
                            source.id == selected.id,
                        onSelected: (_) => onSelected(source),
                      ),
                    ),
                ],
              ),
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
    // 真 MD3 Chip（此前是手搓 Container 药丸）；色调维持 secondaryContainer。
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
