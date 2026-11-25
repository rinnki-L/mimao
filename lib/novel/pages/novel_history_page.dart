// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 阅读记录页：两个视角同一页。
///
/// - **时间轴**（默认）：按天分组，显示当天读了哪些书、各多久、读到第几章；
///   数据来自 `NovelStatsApi.timeline()`（设备 × 书 × 章 × 日的记录）。
/// - **书目**：按最近打开倒序列出书，可单条删除、一键清空、点进书籍详情。
///   删除单条与清空都会被双记账收尾（仍有收藏则投影回未读，无收藏则摘投影行）。
///
/// 两个视角分工不同：时间轴回答「我哪天读了什么」，书目回答「这本书读到哪了」
/// 并提供清理入口。旧版只有书目视角，时间轴是这次新增的，因此旧测试仍按书目
/// 断言（先切到书目）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

class NovelHistoryPage extends StatefulWidget {
  const NovelHistoryPage({super.key, this.history, this.stats, this.openRoute});

  final NovelHistoryApi? history;

  /// 时间轴数据源；null 时该视角显示能力说明（不伪造）。
  final NovelStatsApi? stats;

  final NovelRouteOpener? openRoute;

  @override
  State<NovelHistoryPage> createState() => _NovelHistoryPageState();
}

class _NovelHistoryPageState extends State<NovelHistoryPage> {
  late Future<List<NovelHistoryItem>> _booksFuture;
  late Future<List<NovelReadDay>> _timelineFuture;
  bool _timeline = true;

  @override
  void initState() {
    super.initState();
    _booksFuture = _loadBooks();
    _timelineFuture = _loadTimeline();
  }

  Future<List<NovelHistoryItem>> _loadBooks() async {
    final api = widget.history;
    if (api == null) return const <NovelHistoryItem>[];
    return api.recent(limit: 300);
  }

  Future<List<NovelReadDay>> _loadTimeline() async {
    final api = widget.stats;
    if (api == null) return const <NovelReadDay>[];
    return api.timeline();
  }

  void _reload() {
    setState(() {
      _booksFuture = _loadBooks();
      _timelineFuture = _loadTimeline();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBook(NovelHistoryItem item) async {
    await openNovelRoute(
      context,
      widget.openRoute,
      NovelRoute.bookInfo,
      args: <String, Object?>{'bookId': item.book.id, 'title': item.book.title},
    );
    if (mounted) _reload();
  }

  /// 时间轴里的书也点进详情：bookId 为空（旧数据）时不可点。
  Future<void> _openBookById(String bookId, String title) async {
    if (bookId.isEmpty) return;
    await openNovelRoute(
      context,
      widget.openRoute,
      NovelRoute.bookInfo,
      args: <String, Object?>{'bookId': bookId, 'title': title},
    );
    if (mounted) _reload();
  }

  Future<void> _remove(NovelHistoryItem item) async {
    final api = widget.history;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除《${item.book.title}》的阅读记录？'),
        content: const Text('阅读进度会丢失；收藏的书仍留在书架。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.remove(item.book.id);
      _reload();
      _toast('已删除这条记录');
    } on Object catch (error) {
      _toast('删除失败：$error');
    }
  }

  Future<void> _clearAll() async {
    final api = widget.history;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部阅读记录？'),
        content: const Text('所有阅读进度会被删除；收藏的书仍留在书架，进度回到未读。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.clear();
      _reload();
      _toast('阅读记录已清空');
    } on Object catch (error) {
      _toast('清空失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读记录'),
        actions: <Widget>[
          if (!_timeline)
            FutureBuilder<List<NovelHistoryItem>>(
              future: _booksFuture,
              builder: (context, snapshot) {
                final hasItems =
                    (snapshot.data ?? const <NovelHistoryItem>[]).isNotEmpty;
                return IconButton(
                  tooltip: '清空阅读记录',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: hasItems ? _clearAll : null,
                );
              },
            ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('时间轴'),
                        icon: Icon(Icons.timeline),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('书目'),
                        icon: Icon(Icons.menu_book_outlined),
                      ),
                    ],
                    selected: <bool>{_timeline},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      setState(() {
                        _timeline = selection.first;
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _timeline ? _buildTimeline() : _buildBooks()),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return FutureBuilder<List<NovelReadDay>>(
      future: _timelineFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NovelLoadingState(label: '正在读取阅读记录…');
        }
        if (snapshot.hasError) {
          return NovelErrorState(
            message: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (widget.stats == null) {
          return const NovelEmptyState(
            icon: Icons.timeline,
            title: '时间轴还没有数据源',
            message: '阅读统计服务未接入；书目视角仍可用。',
          );
        }
        final days = snapshot.data ?? const <NovelReadDay>[];
        if (days.isEmpty) {
          return const NovelEmptyState(
            icon: Icons.timeline,
            title: '还没有阅读时长记录',
            message:
                '阅读器在退出或换章时按「书 + 章 + 当天」结算时长。'
                '读几页再回来看，这里会按天列出读了什么。',
          );
        }
        return NovelPageContent(
          maxWidth: 900,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: ListView.builder(
            itemCount: days.length,
            itemBuilder: (context, index) =>
                _TimelineDay(day: days[index], onOpenBook: _openBookById),
          ),
        );
      },
    );
  }

  Widget _buildBooks() {
    return FutureBuilder<List<NovelHistoryItem>>(
      future: _booksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NovelLoadingState(label: '正在读取阅读记录…');
        }
        if (snapshot.hasError) {
          return NovelErrorState(
            message: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        final items = snapshot.data ?? const <NovelHistoryItem>[];
        if (items.isEmpty) {
          return const NovelEmptyState(
            icon: Icons.history,
            title: '还没有阅读记录',
            message: '打开一本书开始阅读后，进度会记在这里。',
          );
        }
        return NovelPageContent(
          maxWidth: 900,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _HistoryRow(
              item: items[index],
              onTap: () => _openBook(items[index]),
              onRemove: () => _remove(items[index]),
            ),
          ),
        );
      },
    );
  }
}

/// 时间轴的一天：日期 + 当天总时长，下面是当天读过的书。
class _TimelineDay extends StatelessWidget {
  const _TimelineDay({required this.day, required this.onOpenBook});

  final NovelReadDay day;
  final Future<void> Function(String bookId, String title) onOpenBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (totalValue, totalUnit) = novelDurationParts(day.seconds);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  novelDayLabel(day.day),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '$totalValue $totalUnit',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: cs.outlineVariant, width: 2),
                ),
              ),
              padding: const EdgeInsets.only(left: 15),
              child: Column(
                children: <Widget>[
                  for (final book in day.books)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TimelineBook(
                        book: book,
                        onTap: () => onOpenBook(book.bookId, book.title),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineBook extends StatelessWidget {
  const _TimelineBook({required this.book, required this.onTap});

  final NovelReadBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (value, unit) = novelDurationParts(book.seconds);
    final title = book.title.isEmpty ? '未知书籍' : book.title;
    final chapter = novelChapterLabel(
      chapterIndex: book.chapterIndex,
      chapterName: book.chapterName,
    );
    return NovelCard(
      onTap: book.bookId.isEmpty ? null : onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 40,
            height: 56,
            child: NovelBookCover(url: '', title: title),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  chapter,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('$value $unit', style: theme.textTheme.bodySmall),
          if (book.bookId.isNotEmpty) ...<Widget>[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final NovelHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 52,
            height: 76,
            child: NovelBookCover(
              url: item.book.coverUrl,
              title: item.book.title,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.book.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.book.author.isEmpty ? '作者未知' : item.book.author,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  novelProgressText(
                    chapterIndex: item.chapterIndex,
                    chapterCount: item.chapterCount,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '上次阅读 · ${novelRelativeTime(item.openedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除这条记录',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
