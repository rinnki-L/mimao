// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 阅读记录整页：按打开时间倒序列出历史，可单条删除、一键清空、点进书籍详情。
/// 删除单条与清空都会被双记账收尾（仍有收藏则投影回未读，无收藏则摘投影行）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

class NovelHistoryPage extends StatefulWidget {
  const NovelHistoryPage({super.key, this.history, this.openRoute});

  final NovelHistoryApi? history;
  final NovelRouteOpener? openRoute;

  @override
  State<NovelHistoryPage> createState() => _NovelHistoryPageState();
}

class _NovelHistoryPageState extends State<NovelHistoryPage> {
  late Future<List<NovelHistoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<NovelHistoryItem>> _load() async {
    final api = widget.history;
    if (api == null) return const <NovelHistoryItem>[];
    return api.recent(limit: 300);
  }

  void _reload() {
    setState(() {
      _future = _load();
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
          FutureBuilder<List<NovelHistoryItem>>(
            future: _future,
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
        ],
      ),
      body: FutureBuilder<List<NovelHistoryItem>>(
        future: _future,
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
              message:
                  '打开一本书开始阅读后，进度会记在这里。'
                  '开始阅读一本书后，进度会自动记录在这里。',
            );
          }
          return NovelPageContent(
            maxWidth: 900,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
