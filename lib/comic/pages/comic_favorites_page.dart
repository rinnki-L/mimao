// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 漫画模块「收藏」分区：用户收藏的漫画网格。
///
/// 数据来自 [ComicLibraryApi.collected]（C′ `ComicCollectService.all` 的
/// 只读投影）。点卡片 → 详情；详情页取消收藏后返回本页会刷新（[refreshKey]
/// 变化即重读）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_poster_card.dart';

/// 收藏分区。
class ComicFavoritesPage extends StatefulWidget {
  const ComicFavoritesPage({
    super.key,
    required this.library,
    this.showAppBar = true,
    this.onOpenDetail,
    this.refreshKey,
  });

  final ComicLibraryApi library;

  final bool showAppBar;

  final ValueChanged<ComicSummary>? onOpenDetail;

  /// 外部变化信号：值变化即重读收藏列表（如从详情页返回后模块层自增）。
  final Object? refreshKey;

  @override
  State<ComicFavoritesPage> createState() => _ComicFavoritesPageState();
}

class _ComicFavoritesPageState extends State<ComicFavoritesPage> {
  late Future<List<ComicLibraryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.library.collected();
  }

  @override
  void didUpdateWidget(ComicFavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library ||
        oldWidget.refreshKey != widget.refreshKey) {
      _future = widget.library.collected();
    }
  }

  void _reload() => setState(() => _future = widget.library.collected());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('收藏')) : null,
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ComicLibraryEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _FavoritesErrorState(onRetry: _reload);
            }
            final entries = snapshot.data ?? const <ComicLibraryEntry>[];
            if (entries.isEmpty) return const _FavoritesEmptyState();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '共 ${entries.length} 部',
                      style: Theme.of(context).textTheme.labelLarge?.apply(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        _reload();
                        await _future;
                      },
                      child: ComicPosterGrid(
                        items: [for (final e in entries) e.asSummary()],
                        keyPrefix: 'favorite',
                        onOpen: widget.onOpenDetail,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.bookmark_border, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('还没有收藏的漫画', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '在漫画详情页点收藏，作品会出现在这里。',
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

class _FavoritesErrorState extends StatelessWidget {
  const _FavoritesErrorState({required this.onRetry});

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
          const Text('收藏列表加载失败'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
