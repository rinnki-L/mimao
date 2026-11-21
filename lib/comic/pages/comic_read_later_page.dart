// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 「稍后阅读」独立页：主页卡片「查看全部」进入。
///
/// 只认 [ComicReadLaterApi]；点条目交给上层 [onOpenDetail]（与主页/搜索
/// 同一条详情装配链路），长按确认后移出队列。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_poster_card.dart';

class ComicReadLaterPage extends StatefulWidget {
  const ComicReadLaterPage({super.key, required this.api, this.onOpenDetail});

  final ComicReadLaterApi api;

  /// 打开详情；返回后自动重读（详情页里可能取消稍后阅读）。
  final Future<void> Function(ComicSummary)? onOpenDetail;

  @override
  State<ComicReadLaterPage> createState() => _ComicReadLaterPageState();
}

class _ComicReadLaterPageState extends State<ComicReadLaterPage> {
  late Future<List<ComicLibraryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.readLater();
  }

  void _reload() {
    setState(() {
      _future = widget.api.readLater();
    });
  }

  Future<void> _remove(ComicSummary item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出稍后阅读？'),
        content: Text('「${item.title}」将从稍后阅读列表移除；收藏与下载不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.setReadLater(
        id: item.id,
        sourceName: item.sourceName ?? '',
        title: item.title,
        coverUrl: item.coverUrl.isEmpty ? null : item.coverUrl,
        detailUrl: item.detailUrl,
        included: false,
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('移出失败：$error')));
      }
      return;
    }
    if (mounted) _reload();
  }

  Future<void> _open(ComicSummary item) async {
    final onOpen = widget.onOpenDetail;
    if (onOpen == null) return;
    await onOpen(item);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('稍后阅读')),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ComicLibraryEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('稍后阅读加载失败'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _reload,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            final entries = snapshot.data ?? const <ComicLibraryEntry>[];
            if (entries.isEmpty) return _buildEmpty(context);
            final items = [for (final entry in entries) entry.asSummary()];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    '共 ${items.length} 部 · 长按可移出',
                    style: Theme.of(context).textTheme.bodySmall?.apply(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: ComicPosterGrid(
                      items: items,
                      keyPrefix: 'read-later',
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onOpen: widget.onOpenDetail == null ? null : _open,
                      onItemLongPress: _remove,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.watch_later_outlined,
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('还没有稍后阅读', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '在漫画详情页点「稍后阅读」，想读的漫画会收在这里。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
