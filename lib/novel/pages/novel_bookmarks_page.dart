// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 书签整页：默认列出所有书的书签（按书分组），带 `bookId` 时只看一本书。
///
/// 两种消费方式：
/// - 「我的 → 书签」/ 路由：点一条直接重新打开阅读器并跳到那句话；
/// - 阅读器「全书书签」：`pickMode: true`，点一条 pop 回书签本身，由阅读器
///   在**同一个控制器**里跳转（不用重新开书，滚动位置也不丢）。
///
/// 「无法定位」不是错误态：换源后章标题对不上就保留书签并标出来，
/// 用户仍能删掉或回原书源打开，不静默丢数据。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';

class NovelBookmarksPage extends StatefulWidget {
  const NovelBookmarksPage({
    super.key,
    this.bookmarks,
    this.bookId,
    this.bookTitle,
    this.pickMode = false,
    this.openRoute,
  });

  /// 书签门面；null 时显示能力边界说明（依赖未注入）。
  final NovelBookmarkApi? bookmarks;

  /// 只看这本书；null = 所有书。
  final String? bookId;
  final String? bookTitle;

  /// true 时点一条 `Navigator.pop(bookmark)`，不自己开阅读器。
  final bool pickMode;

  /// 独立页面打开阅读器的路由入口（测试可注入）。
  final NovelRouteOpener? openRoute;

  @override
  State<NovelBookmarksPage> createState() => _NovelBookmarksPageState();
}

class _NovelBookmarksPageState extends State<NovelBookmarksPage> {
  late Future<List<NovelBookmark>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<NovelBookmark>> _load() async {
    final api = widget.bookmarks;
    if (api == null) return const <NovelBookmark>[];
    final bookId = widget.bookId;
    if (bookId != null && bookId.isNotEmpty) {
      final list = await api.bookmarksForBook(bookId);
      return _sortedForReading(list);
    }
    return api.allBookmarks();
  }

  /// 单本书内按阅读顺序（章 → 段 → 偏移）排，而不是创建时间：
  /// 翻书签时「从前往后」比「最近加的」更符合找位置的直觉。
  List<NovelBookmark> _sortedForReading(List<NovelBookmark> list) {
    final copy = List<NovelBookmark>.of(list);
    copy.sort((a, b) {
      final chapter = a.chapterIndex.compareTo(b.chapterIndex);
      if (chapter != 0) return chapter;
      final paragraph = a.paragraph.compareTo(b.paragraph);
      if (paragraph != 0) return paragraph;
      return a.charOffset.compareTo(b.charOffset);
    });
    return copy;
  }

  void _reload() => setState(() => _future = _load());

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(NovelBookmark bookmark) async {
    if (widget.pickMode) {
      Navigator.of(context).pop(bookmark);
      return;
    }
    if (bookmark.unresolved) {
      _toast('这条书签在当前书源目录里找不到对应章节；可以删除后重新加，或回原书源打开');
      return;
    }
    await openNovelRoute(
      context,
      widget.openRoute,
      NovelRoute.read,
      args: <String, Object?>{
        'bookId': bookmark.bookId,
        'title': bookmark.bookTitle,
        'author': bookmark.bookAuthor,
        'sourceKey': bookmark.sourceKey,
        'bookUrl': bookmark.bookUrl,
        'chapterIndex': bookmark.chapterIndex,
        'chapterTitle': bookmark.chapterName,
        'initialLocator': bookmark.locator,
      },
    );
    if (mounted) _reload();
  }

  Future<void> _delete(NovelBookmark bookmark) async {
    final api = widget.bookmarks;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条书签？'),
        content: Text(
          bookmark.excerpt.isEmpty
              ? '${bookmark.chapterName} · 第 ${bookmark.paragraph + 1} 段'
              : bookmark.excerpt,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.removeBookmark(bookmark.id);
      _reload();
      _toast('已删除书签');
    } on Object catch (error) {
      _toast('删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.bookId == null
        ? '书签'
        : (widget.bookTitle?.isNotEmpty == true
              ? '《${widget.bookTitle}》的书签'
              : '书签');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            key: const Key('novel-bookmarks-refresh'),
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<NovelBookmark>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const NovelLoadingState(label: '正在读取书签…');
          }
          if (snapshot.hasError) {
            return NovelErrorState(
              message: '书签读取失败：${snapshot.error}',
              onRetry: _reload,
            );
          }
          final items = snapshot.data ?? const <NovelBookmark>[];
          if (items.isEmpty) {
            return NovelEmptyState(
              icon: Icons.bookmark_border,
              title: widget.bookId == null ? '还没有任何书签' : '这本书还没有书签',
              message: widget.bookId == null
                  ? '打开一本书，在阅读器里点「加书签」（或打开「下滑加书签」手势），加过的位置都会出现在这里。'
                  : '在阅读器底栏点「加书签」，或到「阅读设置 → 菜单」打开「下滑加书签」，就能把当前位置存下来。',
            );
          }
          final groups = _group(items);
          return ListView(
            key: const Key('novel-bookmarks-list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              for (final group in groups) ...<Widget>[
                if (groups.length > 1) _BookGroupHeader(bookmark: group.first),
                for (final bookmark in group)
                  _BookmarkTile(
                    bookmark: bookmark,
                    onTap: () => _open(bookmark),
                    onDelete: () => _delete(bookmark),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 全部书签按书分组；组内保持「阅读顺序」，组顺序按最近创建。
  List<List<NovelBookmark>> _group(List<NovelBookmark> items) {
    if (widget.bookId != null && widget.bookId!.isNotEmpty) {
      return <List<NovelBookmark>>[items];
    }
    final order = <String>[];
    final grouped = <String, List<NovelBookmark>>{};
    for (final item in items) {
      if (!grouped.containsKey(item.bookId)) {
        order.add(item.bookId);
        grouped[item.bookId] = <NovelBookmark>[];
      }
      grouped[item.bookId]!.add(item);
    }
    return <List<NovelBookmark>>[
      for (final id in order) _sortedForReading(grouped[id]!),
    ];
  }
}

class _BookGroupHeader extends StatelessWidget {
  const _BookGroupHeader({required this.bookmark});

  final NovelBookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = bookmark.bookTitle.isEmpty ? '未命名书籍' : bookmark.bookTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: <Widget>[
          Icon(Icons.menu_book_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: MimaoFonts.bold,
              ),
            ),
          ),
          if (bookmark.bookAuthor.isNotEmpty)
            Text(
              bookmark.bookAuthor,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
  });

  final NovelBookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final excerpt = bookmark.excerpt.trim();
    final subtitleParts = <String>[
      if (bookmark.chapterName.isNotEmpty) bookmark.chapterName,
      '第 ${bookmark.paragraph + 1} 段',
      novelRelativeTime(bookmark.createdAt),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    bookmark.unresolved ? Icons.link_off : Icons.bookmark,
                    size: 20,
                    color: bookmark.unresolved ? scheme.error : scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        excerpt.isEmpty ? '（无摘录）' : excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (bookmark.unresolved) ...<Widget>[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: MimaoShapes.pill,
                          ),
                          child: Text(
                            '无法定位',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  key: Key('novel-bookmark-delete-${bookmark.id}'),
                  tooltip: '删除书签',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
