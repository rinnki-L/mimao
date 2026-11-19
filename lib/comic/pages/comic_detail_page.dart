// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/pages/comic_cover.dart';
import 'package:mimao/core/theme.dart';

/// 漫画详情页：封面 / 标题 / 简介 + 章节列表 + 收藏 / 开始阅读按钮。
///
/// 通过 [ComicDataSource.detail] 异步取数据；收藏状态暂由本页持有，
/// 点击后经 [onFavoriteChanged] 交给上层（后续接收藏服务）。
/// 开始阅读经 [onStartReading] 回调，连同当前详情与所选章节一起交给上层，
/// 本页不碰阅读器。
class ComicDetailPage extends StatefulWidget {
  const ComicDetailPage({
    super.key,
    required this.dataSource,
    required this.summary,
    this.initiallyFavorite = false,
    this.onFavoriteChanged,
    this.onStartReading,
    this.onChapterTap,
  });

  final ComicDataSource dataSource;

  /// 从搜索带进来的条目，详情地址在 [ComicSummary.detailUrl]。
  final ComicSummary summary;

  final bool initiallyFavorite;
  final ValueChanged<bool>? onFavoriteChanged;

  /// 「开始阅读」按钮回调：上层据此打开阅读器。
  /// 未指定章节时 [chapter] 为 null，表示从第一章（或历史进度）开始。
  final void Function(ComicDetail detail, ComicChapter? chapter)?
  onStartReading;

  /// 点单章回调（与「开始阅读」共用同一装配出口，但明确区分入口）。
  final void Function(ComicDetail detail, ComicChapter chapter)? onChapterTap;

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  late Future<ComicDetail> _future;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initiallyFavorite;
    _future = widget.dataSource.detail(widget.summary);
  }

  @override
  void didUpdateWidget(ComicDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource ||
        oldWidget.summary.id != widget.summary.id) {
      // 同一个 widget 被复用到另一部漫画时，收藏态必须跟着新条目重置，
      // 否则会显示上一部漫画的收藏状态。
      _isFavorite = widget.initiallyFavorite;
      _future = widget.dataSource.detail(widget.summary);
    }
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    widget.onFavoriteChanged?.call(_isFavorite);
  }

  void _retry() {
    setState(() => _future = widget.dataSource.detail(widget.summary));
  }

  void _startReading(ComicDetail detail, [ComicChapter? chapter]) {
    widget.onStartReading?.call(detail, chapter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画详情'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: FutureBuilder<ComicDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _DetailErrorState(onRetry: _retry);
          }
          return _DetailBody(
            detail: snapshot.data!,
            isFavorite: _isFavorite,
            onFavoriteToggle: _toggleFavorite,
            onStartReading: widget.onStartReading == null
                ? null
                : () => _startReading(snapshot.data!),
            onChapterTap:
                widget.onChapterTap == null && widget.onStartReading == null
                ? null
                : (chapter) {
                    if (widget.onChapterTap != null) {
                      widget.onChapterTap!(snapshot.data!, chapter);
                    } else {
                      _startReading(snapshot.data!, chapter);
                    }
                  },
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
    this.onStartReading,
    this.onChapterTap,
  });

  final ComicDetail detail;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback? onStartReading;
  final void Function(ComicChapter chapter)? onChapterTap;

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
                child: ComicCover(
                  url: detail.coverUrl,
                  title: detail.title,
                  radius: 20,
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
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
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
                  label: Text(isFavorite ? '已收藏' : '收藏'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('start-reading-button'),
                  onPressed: onStartReading,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.auto_stories_rounded),
                  label: const Text('开始阅读'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
              Text('章节', style: textTheme.titleMedium),
              const Spacer(),
              Text(
                '共 ${detail.chapters.length} 章',
                style: textTheme.labelMedium?.apply(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (detail.chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '暂无章节',
                style: textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final chapter in detail.chapters)
              _ChapterTile(
                chapter: chapter,
                onTap: onChapterTap == null
                    ? null
                    : () => onChapterTap!(chapter),
              ),
        ],
      ),
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

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter, this.onTap});

  final ComicChapter chapter;
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
          key: Key('chapter-${chapter.number}'),
          onTap: onTap,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            child: Text(
              '${chapter.number}',
              style: textTheme.labelMedium?.apply(
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
          title: Text(
            chapter.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyLarge,
          ),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({required this.onRetry});

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
          const Text('详情加载失败'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
