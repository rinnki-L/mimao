// 章节评论面板：列表、回复栈、分页加载、加载/空/错误三态。
//
// 对照 Venera-Next `chapter_comments.dart` 的展示结构（头像/昵称/时间/正文/
// 回复数），本仓只做只读浏览：发评论与点赞需要登录态与写接口，不在本轮范围。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:async';

import 'package:flutter/material.dart';

import 'reader_comments.dart';

/// 章节评论面板（底部弹层内容）。
class ReaderCommentsSheet extends StatefulWidget {
  const ReaderCommentsSheet({
    super.key,
    required this.comicId,
    required this.episodeId,
    required this.source,
    this.chapterTitle,
  });

  final String comicId;
  final String episodeId;
  final NovelCommentSource source;
  final String? chapterTitle;

  @override
  State<ReaderCommentsSheet> createState() => _ReaderCommentsSheetState();
}

class _ReaderCommentsSheetState extends State<ReaderCommentsSheet> {
  late final NovelCommentsController _controller = NovelCommentsController(
    source: widget.source,
    comicId: widget.comicId,
    episodeId: widget.episodeId,
  );
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _scroll.addListener(_onScroll);
    unawaited(_controller.reload());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      unawaited(_controller.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final comments = _controller.comments;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  if (_controller.replyTo != null)
                    IconButton(
                      key: const Key('reader-comments-back'),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '返回评论列表',
                      onPressed: () => unawaited(_controller.back()),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _controller.replyTo == null
                              ? '章节评论'
                              : '回复 ${_controller.replyToUserName ?? ''}',
                          style: theme.textTheme.titleLarge,
                        ),
                        if (widget.chapterTitle != null &&
                            _controller.replyTo == null)
                          Text(
                            widget.chapterTitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('reader-comments-close'),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(child: _buildBody(theme, comments)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<NovelComment> comments) {
    final scheme = theme.colorScheme;
    if (_controller.loading && comments.isEmpty) {
      return const Center(
        key: Key('reader-comments-loading'),
        child: CircularProgressIndicator(),
      );
    }
    final error = _controller.error;
    if (error != null && comments.isEmpty) {
      return Center(
        key: const Key('reader-comments-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.forum_outlined,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('评论加载失败', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                error,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('reader-comments-retry'),
                onPressed: () => unawaited(
                  _controller.replyTo == null
                      ? _controller.reload()
                      : _controller.loadMore(),
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (comments.isEmpty) {
      return Center(
        key: const Key('reader-comments-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.forum_outlined,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                _controller.replyTo == null ? '这一章还没有评论' : '这条评论还没有回复',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '评论由漫画源提供；有些源不开放评论，或需要登录后才能看到。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      key: const Key('reader-comments-list'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: comments.length + 1,
      separatorBuilder: (_, index) => index >= comments.length - 1
          ? const SizedBox.shrink()
          : Divider(
              height: 20,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
      itemBuilder: (context, index) {
        if (index == comments.length) return _buildFooter(theme);
        return _CommentTile(
          comment: comments[index],
          onOpenReplies: () =>
              unawaited(_controller.openReplies(comments[index])),
        );
      },
    );
  }

  Widget _buildFooter(ThemeData theme) {
    if (_controller.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          key: Key('reader-comments-loading-more'),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    final error = _controller.error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: <Widget>[
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_controller.loadMore()),
              child: const Text('重试加载更多'),
            ),
          ],
        ),
      );
    }
    if (!_controller.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          key: const Key('reader-comments-end'),
          child: Text(
            '没有更多评论了',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onOpenReplies});

  final NovelComment comment;
  final VoidCallback onOpenReplies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final replies = comment.replyCount ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 16,
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundImage: comment.avatar == null || comment.avatar!.isEmpty
              ? null
              : NetworkImage(comment.avatar!),
          child: Text(
            comment.userName.isEmpty ? '?' : comment.userName.characters.first,
            style: theme.textTheme.labelMedium,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      comment.userName.isEmpty ? '匿名' : comment.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  if (comment.time != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(
                      comment.time!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(comment.content, style: theme.textTheme.bodyMedium),
              if (replies > 0) ...<Widget>[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onOpenReplies,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('查看 $replies 条回复'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
