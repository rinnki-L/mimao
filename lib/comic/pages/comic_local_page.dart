// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 本地漫画管理页：主页「本地」卡片进入。
///
/// 列出导入或下载到本机的漫画，点条目打开本地详情，点右侧删除（确认后）
/// 同时清元数据与磁盘目录。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_cover.dart';
import 'package:mimao/core/theme.dart';

class ComicLocalPage extends StatefulWidget {
  const ComicLocalPage({super.key, required this.local, this.onOpenDetail});

  final ComicLocalApi local;

  /// 打开本地详情；返回后自动重读（详情里可能删除内容）。
  final Future<void> Function(ComicSummary)? onOpenDetail;

  @override
  State<ComicLocalPage> createState() => _ComicLocalPageState();
}

class _ComicLocalPageState extends State<ComicLocalPage> {
  late Future<List<ComicLibraryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.local.local();
  }

  void _reload() {
    setState(() {
      _future = widget.local.local();
    });
  }

  Future<void> _remove(ComicSummary item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地漫画？'),
        content: Text('「${item.title}」的本地文件与阅读记录会一起删除，无法恢复。'),
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
    if (confirmed != true || !mounted) return;
    try {
      await widget.local.remove(item);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('删除失败：$error')));
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
      appBar: AppBar(title: const Text('本地漫画')),
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
                    const Text('本地漫画加载失败'),
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
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final item = entry.asSummary();
                return Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: MimaoShapes.md,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: ValueKey<String>('local-entry-${entry.id}'),
                    onTap: widget.onOpenDetail == null
                        ? null
                        : () => _open(item),
                    leading: SizedBox(
                      width: 44,
                      height: 60,
                      child: ComicCover(
                        url: entry.coverUrl ?? '',
                        title: entry.title,
                        radius: 8,
                      ),
                    ),
                    title: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(entry.subtitle ?? '本地'),
                    trailing: IconButton(
                      key: ValueKey<String>('local-delete-${entry.id}'),
                      tooltip: '删除本地漫画',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _remove(item),
                    ),
                  ),
                );
              },
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
              Icons.download_done_outlined,
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('还没有本地漫画', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '在漫画详情页点下载，把章节保存到本机后就会出现在这里。',
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
