// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/download.dart' show ComicDownloadStatus;
import 'package:mimao/comic/download_api.dart';
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
    this.initiallyReadLater = false,
    this.onFavoriteChanged,
    this.onReadLaterChanged,
    this.onStartReading,
    this.onChapterTap,
    this.downloads,
    this.isLocal = false,
  });

  final ComicDataSource dataSource;

  /// 从搜索带进来的条目，详情地址在 [ComicSummary.detailUrl]。
  final ComicSummary summary;

  final bool initiallyFavorite;
  final ValueChanged<bool>? onFavoriteChanged;

  /// 稍后阅读初始态与切换回调（模块层负责落库）。
  final bool initiallyReadLater;
  final ValueChanged<bool>? onReadLaterChanged;

  /// 「开始阅读」按钮回调：上层据此打开阅读器。
  /// 未指定章节时 [chapter] 为 null，表示从第一章（或历史进度）开始。
  final void Function(ComicDetail detail, ComicChapter? chapter)?
  onStartReading;

  /// 点单章回调（与「开始阅读」共用同一装配出口，但明确区分入口）。
  final void Function(ComicDetail detail, ComicChapter chapter)? onChapterTap;

  /// 下载能力；null（本地漫画/未接线）时章节行不显示下载按钮。
  final ComicDownloadApi? downloads;

  /// 本地漫画详情：隐藏下载按钮（已在本机）。
  final bool isLocal;

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  late Future<ComicDetail> _future;
  late bool _isFavorite;
  late bool _isReadLater;
  List<ComicChapterDownload> _downloadTasks = const <ComicChapterDownload>[];

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initiallyFavorite;
    _isReadLater = widget.initiallyReadLater;
    _future = widget.dataSource.detail(widget.summary);
    widget.downloads?.changes.addListener(_onDownloadsChanged);
    _loadDownloadTasks();
  }

  @override
  void dispose() {
    widget.downloads?.changes.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(ComicDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloads != widget.downloads) {
      oldWidget.downloads?.changes.removeListener(_onDownloadsChanged);
      widget.downloads?.changes.addListener(_onDownloadsChanged);
      _downloadTasks = const <ComicChapterDownload>[];
      _loadDownloadTasks();
    }
    if (oldWidget.dataSource != widget.dataSource ||
        oldWidget.summary.id != widget.summary.id) {
      // 同一个 widget 被复用到另一部漫画时，收藏/稍后阅读态必须跟着新条目
      // 重置，否则会显示上一部漫画的状态。
      _isFavorite = widget.initiallyFavorite;
      _isReadLater = widget.initiallyReadLater;
      _future = widget.dataSource.detail(widget.summary);
      _loadDownloadTasks();
    }
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    _loadDownloadTasks();
  }

  /// 重读下载任务快照；失败静默（不挡详情页展示）。
  Future<void> _loadDownloadTasks() async {
    final downloads = widget.downloads;
    if (downloads == null) return;
    try {
      final tasks = await downloads.tasksFor(widget.summary);
      if (!mounted) return;
      setState(() => _downloadTasks = tasks);
    } on Object {
      // 下载状态读失败不影响详情与阅读。
    }
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    widget.onFavoriteChanged?.call(_isFavorite);
  }

  void _toggleReadLater() {
    setState(() => _isReadLater = !_isReadLater);
    widget.onReadLaterChanged?.call(_isReadLater);
  }

  Future<void> _downloadChapter(
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    final downloads = widget.downloads;
    if (downloads == null) return;
    try {
      await downloads.downloadChapter(widget.summary, detail, chapter);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('「${chapter.title}」已加入下载')));
      await _loadDownloadTasks();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('下载失败：$error')));
      }
    }
  }

  Future<void> _downloadAll(ComicDetail detail) async {
    final downloads = widget.downloads;
    if (downloads == null) return;
    try {
      await downloads.downloadAll(widget.summary, detail);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('已加入整本下载')));
      await _loadDownloadTasks();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('下载失败：$error')));
      }
    }
  }

  Future<void> _cancelDownload(String taskId) async {
    final downloads = widget.downloads;
    if (downloads == null) return;
    await downloads.cancel(taskId);
    await _loadDownloadTasks();
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
            isReadLater: _isReadLater,
            onFavoriteToggle: _toggleFavorite,
            onReadLaterToggle: _toggleReadLater,
            downloadTasks: _downloadTasks,
            onDownloadChapter: widget.downloads == null || widget.isLocal
                ? null
                : (chapter) => _downloadChapter(snapshot.data!, chapter),
            onDownloadAll: widget.downloads == null || widget.isLocal
                ? null
                : () => _downloadAll(snapshot.data!),
            onCancelDownload: widget.downloads == null ? null : _cancelDownload,
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
    required this.isReadLater,
    required this.onFavoriteToggle,
    required this.onReadLaterToggle,
    this.downloadTasks = const <ComicChapterDownload>[],
    this.onDownloadChapter,
    this.onDownloadAll,
    this.onCancelDownload,
    this.onStartReading,
    this.onChapterTap,
  });

  final ComicDetail detail;
  final bool isFavorite;
  final bool isReadLater;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onReadLaterToggle;
  final List<ComicChapterDownload> downloadTasks;
  final void Function(ComicChapter chapter)? onDownloadChapter;
  final VoidCallback? onDownloadAll;
  final Future<void> Function(String taskId)? onCancelDownload;
  final VoidCallback? onStartReading;
  final void Function(ComicChapter chapter)? onChapterTap;

  ComicChapterDownload? _taskFor(ComicChapter chapter) {
    for (final task in downloadTasks) {
      if (task.chapterUrl == comicChapterDownloadKey(chapter)) return task;
    }
    return null;
  }

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
                child: FilledButton.tonalIcon(
                  key: const Key('read-later-button'),
                  onPressed: onReadLaterToggle,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: Icon(
                    isReadLater
                        ? Icons.watch_later_rounded
                        : Icons.watch_later_outlined,
                  ),
                  label: Text(isReadLater ? '已加入' : '稍后阅读'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('start-reading-button'),
            onPressed: onStartReading,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.auto_stories_rounded),
            label: const Text('开始阅读'),
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
              if (onDownloadAll != null) ...<Widget>[
                const SizedBox(width: 4),
                TextButton.icon(
                  key: const Key('download-all-button'),
                  onPressed: onDownloadAll,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('下载全部'),
                ),
              ],
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
                download: _taskFor(chapter),
                onDownload: onDownloadChapter == null
                    ? null
                    : () => onDownloadChapter!(chapter),
                onCancelDownload: onCancelDownload,
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
  const _ChapterTile({
    required this.chapter,
    this.download,
    this.onDownload,
    this.onCancelDownload,
    this.onTap,
  });

  final ComicChapter chapter;
  final ComicChapterDownload? download;
  final VoidCallback? onDownload;
  final Future<void> Function(String taskId)? onCancelDownload;
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (download != null)
                _ChapterDownloadIndicator(
                  chapter: chapter,
                  download: download!,
                  onRetry: onDownload,
                  onCancel: onCancelDownload,
                )
              else if (onDownload != null)
                IconButton(
                  key: Key('download-chapter-${chapter.number}'),
                  tooltip: '下载本章',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: onDownload,
                ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 章节行尾的下载状态：等待/进度/完成/失败重试。
class _ChapterDownloadIndicator extends StatelessWidget {
  const _ChapterDownloadIndicator({
    required this.chapter,
    required this.download,
    this.onRetry,
    this.onCancel,
  });

  final ComicChapter chapter;
  final ComicChapterDownload download;
  final VoidCallback? onRetry;
  final Future<void> Function(String taskId)? onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final task = download;
    if (task.isDone) {
      return Tooltip(
        message: '已下载',
        child: Icon(
          Icons.check_circle_rounded,
          color: cs.primary,
          key: Key('download-done-${chapter.number}'),
        ),
      );
    }
    if (task.isFailed) {
      return IconButton(
        key: Key('download-retry-${chapter.number}'),
        tooltip: '下载失败，点击重试：${task.message}',
        icon: Icon(Icons.error_outline_rounded, color: cs.error),
        onPressed: onRetry,
      );
    }
    if (task.status == ComicDownloadStatus.pending) {
      return IconButton(
        key: Key('download-pending-${chapter.number}'),
        tooltip: '等待下载，点击取消',
        icon: Icon(Icons.schedule_rounded, color: cs.onSurfaceVariant),
        onPressed: onCancel == null ? null : () => onCancel!(task.taskId),
      );
    }
    return Tooltip(
      message: task.message,
      child: InkWell(
        key: Key('download-running-${chapter.number}'),
        customBorder: const CircleBorder(),
        onTap: onCancel == null ? null : () => onCancel!(task.taskId),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              value: task.total > 0 ? task.progress : null,
              strokeWidth: 2.4,
            ),
          ),
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
