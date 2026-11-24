// 「图片收藏」独立页：网格展示收藏的单张图片。
//
// 数据来自 [ComicImageFavoriteService]；点缩略图回跳到该图所在章节。
// 与稍后阅读/收藏不同，这里不参与 core 书架投影——它只是阅读时的书签。

// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../image_favorite_service.dart';
import '../reader/reader_cache.dart';

/// 图片收藏页。
class ComicImageFavoritesPage extends StatefulWidget {
  const ComicImageFavoritesPage({
    super.key,
    required this.service,
    required this.cache,
    this.onOpen,
  });

  final ComicImageFavoriteService service;
  final ReaderImageCache cache;

  /// 点图回跳：由模块层装配（按 sourceName/comicId/chapterId/page 打开阅读器）。
  final Future<void> Function(ImageFavorite favorite)? onOpen;

  @override
  State<ComicImageFavoritesPage> createState() =>
      _ComicImageFavoritesPageState();
}

class _ComicImageFavoritesPageState extends State<ComicImageFavoritesPage> {
  late Future<List<ImageFavorite>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.recent();
  }

  void _reload() {
    setState(() {
      _future = widget.service.recent();
    });
  }

  Future<void> _remove(ImageFavorite favorite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏这张图？'),
        content: Text(
          '「${favorite.comicTitle}」${favorite.chapterTitle.isEmpty ? '' : ' · ${favorite.chapterTitle}'}'
          ' 第 ${favorite.page} 页',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('取消收藏'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.service.toggle(
      ImageFavoriteInput(
        sourceName: favorite.sourceName,
        comicId: favorite.comicId,
        comicTitle: favorite.comicTitle,
        chapterId: favorite.chapterId,
        chapterNumber: favorite.chapterNumber,
        chapterTitle: favorite.chapterTitle,
        page: favorite.page,
        pageCount: favorite.pageCount,
        imageUrl: favorite.imageUrl,
        coverUrl: favorite.coverUrl,
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图片收藏'),
        actions: <Widget>[
          IconButton(
            key: const Key('image-favorites-refresh'),
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<ImageFavorite>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              key: Key('image-favorites-loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            return _Message(
              key: const Key('image-favorites-error'),
              icon: Icons.error_outline,
              title: '图片收藏读取失败',
              detail: '${snapshot.error}',
              action: FilledButton(onPressed: _reload, child: const Text('重试')),
            );
          }
          final items = snapshot.data ?? const <ImageFavorite>[];
          if (items.isEmpty) {
            return const _Message(
              key: Key('image-favorites-empty'),
              icon: Icons.star_border,
              title: '还没有收藏的图片',
              detail: '阅读时点顶栏的星标，或右键菜单「收藏这张图」，就会出现在这里。',
            );
          }
          return GridView.builder(
            key: const Key('image-favorites-grid'),
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final favorite = items[index];
              return _FavoriteTile(
                favorite: favorite,
                cache: widget.cache,
                onTap: widget.onOpen == null
                    ? null
                    : () async {
                        await widget.onOpen!(favorite);
                        if (mounted) _reload();
                      },
                onRemove: () => _remove(favorite),
              );
            },
          );
        },
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.favorite,
    required this.cache,
    required this.onTap,
    required this.onRemove,
  });

  final ImageFavorite favorite;
  final ReaderImageCache cache;
  final Future<void> Function()? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      key: Key(
        'image-favorite-${favorite.sourceName}-${favorite.comicId}-${favorite.chapterId}-${favorite.page}',
      ),
      onTap: onTap == null ? null : () => onTap!(),
      onLongPress: onRemove,
      borderRadius: MimaoShapes.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: MimaoShapes.md,
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: _Thumb(favorite: favorite, cache: cache),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            favorite.comicTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '${favorite.chapterTitle.isEmpty ? '第 ${favorite.chapterNumber} 章' : favorite.chapterTitle}'
            ' · 第 ${favorite.page} 页',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 缩略图：优先读缓存字节（收藏页常与阅读器共享磁盘缓存）。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.favorite, required this.cache});

  final ImageFavorite favorite;
  final ReaderImageCache cache;

  @override
  Widget build(BuildContext context) {
    final url = favorite.imageUrl;
    if (url.isEmpty) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
    return FutureBuilder(
      future: cache.load(url),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
