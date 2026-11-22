// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/download.dart' show ComicDownloadStatus;
import 'package:mimao/comic/download_api.dart';
import 'package:mimao/comic/pages/comic_cover.dart';
import 'package:mimao/core/theme.dart';

/// 漫画详情页（2026-11-22 排版拍板：对齐参考应用 VeneraNext 的详情页结构，
/// 用本 app 的 MD3 token 实现）：
///
///   头部（封面 + 大标题 + 来源小字）
///   → 操作行（收藏 / 稍后阅读 两个切换按钮）
///   → 按钮行（下载全部 tonal + 开始/继续阅读 filled）
///   → 「上次阅读」进度信息条（有进度才显示）
///   ─ 分隔线 ─ 简介 ─ 分隔线 ─ 信息（标签 chip 行）─ 分隔线 ─ 章节（网格）。
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
    this.progressText,
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

  /// 下载能力；null（本地漫画/未接线）时章节格不显示下载指示区。
  final ComicDownloadApi? downloads;

  /// 本地漫画详情：隐藏下载按钮（已在本机）。
  final bool isLocal;

  /// 「上次阅读」进度文案（如「第 1/96 章 - 第1話 - P60」），模块层在打开
  /// 详情前从跨源历史取好。null/空：不显示进度信息条，且「开始阅读」
  /// 不切换成「继续阅读」。
  final String? progressText;

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  late Future<ComicDetail> _future;
  late bool _isFavorite;
  late bool _isReadLater;
  List<ComicChapterDownload> _downloadTasks = const <ComicChapterDownload>[];

  /// 章节展示顺序（true = 升序）。仅影响展示顺序，章节 number/数据不动；
  /// 状态放本 State（_DetailBody 是 StatelessWidget）。
  bool _ascending = true;

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

  void _setAscending(bool value) {
    setState(() => _ascending = value);
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
            ascending: _ascending,
            onAscendingChanged: _setAscending,
            progressText: widget.progressText,
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
    required this.ascending,
    required this.onAscendingChanged,
    this.progressText,
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

  /// 章节展示顺序与切换回调（状态在 [_ComicDetailPageState]）。
  final bool ascending;
  final ValueChanged<bool> onAscendingChanged;

  /// 「上次阅读」进度文案；null/空：不显示进度信息条，按钮文案为「开始阅读」。
  final String? progressText;

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

  bool get _hasSource {
    final sourceName = detail.sourceName;
    return sourceName != null && sourceName.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progress = progressText;
    final hasProgress = progress != null && progress.isNotEmpty;
    final chapters = ascending
        ? detail.chapters
        : detail.chapters.reversed.toList(growable: false);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(cs, textTheme),
          const SizedBox(height: 16),
          _buildActionRow(),
          const SizedBox(height: 12),
          _buildButtonRow(hasProgress),
          if (hasProgress) ...<Widget>[
            const SizedBox(height: 12),
            _buildProgressBar(cs, textTheme, progress),
          ],
          const SizedBox(height: 20),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 16),
          _buildDescriptionSection(cs, textTheme),
          if (_hasSource || detail.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 16),
            _buildInfoSection(),
          ],
          const SizedBox(height: 20),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 16),
          _buildChapterSection(cs, textTheme, chapters),
        ],
      ),
    );
  }

  /// 头部：封面在左（128×184、大圆角），右侧大标题（最多 3 行）+ 来源小字。
  Widget _buildHeader(ColorScheme cs, TextTheme textTheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 128,
          height: 184,
          child: ComicCover(
            url: detail.coverUrl,
            title: detail.title,
            radius: MimaoRadii.lg,
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
              if (_hasSource) ...<Widget>[
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
            ],
          ),
        ),
      ],
    );
  }

  /// 操作行：收藏 / 稍后阅读两个切换按钮（未选描边、已选 tonal，默认药丸）。
  Widget _buildActionRow() {
    const style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 40)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        if (isFavorite)
          FilledButton.tonalIcon(
            key: const Key('favorite-button'),
            onPressed: onFavoriteToggle,
            style: style,
            icon: const Icon(Icons.bookmark_added_rounded),
            label: const Text('已收藏'),
          )
        else
          OutlinedButton.icon(
            key: const Key('favorite-button'),
            onPressed: onFavoriteToggle,
            style: style,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('收藏'),
          ),
        if (isReadLater)
          FilledButton.tonalIcon(
            key: const Key('read-later-button'),
            onPressed: onReadLaterToggle,
            style: style,
            icon: const Icon(Icons.watch_later_rounded),
            label: const Text('已加入'),
          )
        else
          OutlinedButton.icon(
            key: const Key('read-later-button'),
            onPressed: onReadLaterToggle,
            style: style,
            icon: const Icon(Icons.watch_later_outlined),
            label: const Text('稍后阅读'),
          ),
      ],
    );
  }

  /// 按钮行：下载全部（tonal）+ 开始/继续阅读（filled）等宽大按钮。
  /// 无下载能力（本地漫画/未接线）时整行只剩开始阅读。
  Widget _buildButtonRow(bool hasProgress) {
    return Row(
      children: <Widget>[
        if (onDownloadAll != null) ...<Widget>[
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: onDownloadAll,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('下载全部'),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: FilledButton.icon(
            key: const Key('start-reading-button'),
            onPressed: onStartReading,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.auto_stories_rounded),
            label: Text(hasProgress ? '继续阅读' : '开始阅读'),
          ),
        ),
      ],
    );
  }

  /// 「上次阅读」进度信息条：有进度才显示（圆角信息条 + 历史图标 + 小字）。
  ///
  /// 宽度包裹内容（Venera 参考同款药丸条）：Column 是 stretch，需要 Align
  /// 放宽约束让容器收缩到文字长；文字超长时仍在屏宽处截断。
  Widget _buildProgressBar(
    ColorScheme cs,
    TextTheme textTheme,
    String progress,
  ) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: MimaoShapes.md,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.history_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '上次阅读：$progress',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 简介区：区块标题 + 正文；空简介回落「暂无简介」。
  Widget _buildDescriptionSection(ColorScheme cs, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
      ],
    );
  }

  /// 信息区：每行 = 左侧标签 chip + 右侧若干值 chip（替代原头部的 tags）。
  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_hasSource) _infoRow('来源', <String>[detail.sourceName!]),
        if (detail.tags.isNotEmpty) ...<Widget>[
          if (_hasSource) const SizedBox(height: 10),
          _infoRow('标签', detail.tags),
        ],
      ],
    );
  }

  Widget _infoRow(String label, List<String> values) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _InfoLabelChip(label: label),
        for (final value in values) _InfoValueChip(label: value),
      ],
    );
  }

  /// 章节区：区块头（标题 + 计数 + 升序/降序切换 + 下载全部）+ 网格按钮。
  Widget _buildChapterSection(
    ColorScheme cs,
    TextTheme textTheme,
    List<ComicChapter> chapters,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('章节', style: textTheme.titleMedium),
            const SizedBox(width: 8),
            Text(
              '共 ${detail.chapters.length} 章',
              style: textTheme.labelMedium?.apply(color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('升序')),
                ButtonSegment<bool>(value: false, label: Text('降序')),
              ],
              selected: <bool>{ascending},
              showSelectedIcon: false,
              // 3.50 的 SegmentedButton 没有 visualDensity 直参，
              // 收紧（紧凑 + 贴合内容高度）只能经 ButtonStyle。
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (Set<bool> selection) =>
                  onAscendingChanged(selection.first),
            ),
            if (onDownloadAll != null) ...<Widget>[
              const SizedBox(width: 8),
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
        if (chapters.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '暂无章节',
              style: textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 48,
              crossAxisSpacing: 12,
              mainAxisSpacing: 10,
            ),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return _ChapterCell(
                chapter: chapter,
                download: _taskFor(chapter),
                onDownload: onDownloadChapter == null
                    ? null
                    : () => onDownloadChapter!(chapter),
                onCancelDownload: onCancelDownload,
                onTap: onChapterTap == null
                    ? null
                    : () => onChapterTap!(chapter),
              );
            },
          ),
      ],
    );
  }
}

/// 信息区的行首标签 chip（「来源」「标签」）：secondaryContainer 药丸底。
class _InfoLabelChip extends StatelessWidget {
  const _InfoLabelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: MimaoShapes.pill,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer),
      ),
    );
  }
}

/// 信息区的值 chip（来源名、各标签）：灰底小字药丸，同一行可排一串。
class _InfoValueChip extends StatelessWidget {
  const _InfoValueChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: MimaoShapes.pill,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: cs.onSurface),
      ),
    );
  }
}

/// 章节网格的一个 cell（约 220 宽、48 高的圆角按钮，非列表行）。
class _ChapterCell extends StatelessWidget {
  const _ChapterCell({
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
    // 下载指示区（26 宽）：有任务显状态图标；无任务但具备下载能力时是
    // 「下载本章」入口；无下载能力的 cell 整个指示区省略。
    final Widget? indicator;
    if (download != null) {
      indicator = _ChapterDownloadIndicator(
        chapter: chapter,
        download: download!,
        onRetry: onDownload,
        onCancel: onCancelDownload,
      );
    } else if (onDownload != null) {
      indicator = IconButton(
        key: Key('download-chapter-${chapter.number}'),
        tooltip: '下载本章',
        icon: const Icon(Icons.download_outlined, size: 18),
        onPressed: onDownload,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        // 3.50 的 IconButton 没有 tapTargetSize 直参，走 styleFrom 收紧。
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    } else {
      indicator = null;
    }
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: MimaoShapes.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('chapter-${chapter.number}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              ),
              if (indicator != null) SizedBox(width: 26, child: indicator),
            ],
          ),
        ),
      ),
    );
  }
}

/// 章节格右缘的下载状态：等待/进度/完成/失败重试。
///
/// 尺寸收进 26 宽的指示区（cell 总高 48）：图标 18、IconButton compact +
/// shrinkWrap + 4 内边距、运行中进度圈 22×22 + 2 内边距，保证不溢出 cell。
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
          size: 18,
          color: cs.primary,
          key: Key('download-done-${chapter.number}'),
        ),
      );
    }
    if (task.isFailed) {
      return IconButton(
        key: Key('download-retry-${chapter.number}'),
        tooltip: '下载失败，点击重试：${task.message}',
        icon: Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
        onPressed: onRetry,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    if (task.status == ComicDownloadStatus.pending) {
      return IconButton(
        key: Key('download-pending-${chapter.number}'),
        tooltip: '等待下载，点击取消',
        icon: Icon(
          Icons.schedule_rounded,
          size: 18,
          color: cs.onSurfaceVariant,
        ),
        onPressed: onCancel == null ? null : () => onCancel!(task.taskId),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    return Tooltip(
      message: task.message,
      child: InkWell(
        key: Key('download-running-${chapter.number}'),
        customBorder: const CircleBorder(),
        onTap: onCancel == null ? null : () => onCancel!(task.taskId),
        child: Padding(
          padding: const EdgeInsets.all(2),
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
