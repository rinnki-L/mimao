// 章节评论面板：三态、分页、回复栈入口。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_comments.dart';
import 'package:mimao/comic/reader/reader_comments_sheet.dart';

class _Source implements NovelCommentSource {
  _Source({required this.pages});

  final Map<int, NovelCommentPage> pages;

  @override
  bool get supportsChapterComments => true;

  @override
  Future<NovelCommentPage> loadChapterComments({
    required String comicId,
    required String episodeId,
    required int page,
    String? replyTo,
  }) async {
    return pages[page] ?? const NovelCommentPage(comments: <NovelComment>[]);
  }
}

NovelComment _c(String id, {int replies = 0}) => NovelComment(
  userName: '用户$id',
  content: '评论正文 $id',
  id: id,
  replyCount: replies,
);

Widget _app(NovelCommentSource source) => MaterialApp(
  home: Scaffold(
    body: ReaderCommentsSheet(
      comicId: 'c1',
      episodeId: 'e1',
      source: source,
      chapterTitle: '第 1 章',
    ),
  ),
);

void main() {
  testWidgets('有评论时渲染列表与章名', (tester) async {
    await tester.pumpWidget(
      _app(
        _Source(
          pages: <int, NovelCommentPage>{
            1: NovelCommentPage(
              comments: <NovelComment>[_c('1', replies: 2), _c('2')],
              maxPage: 1,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-comments-list')), findsOneWidget);
    expect(find.text('评论正文 1'), findsOneWidget);
    expect(find.text('查看 2 条回复'), findsOneWidget);
    expect(find.text('第 1 章'), findsOneWidget);
    expect(find.byKey(const Key('reader-comments-end')), findsOneWidget);
  });

  testWidgets('空态给出原因与下一步', (tester) async {
    await tester.pumpWidget(
      _app(_Source(pages: const <int, NovelCommentPage>{})),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-comments-empty')), findsOneWidget);
    expect(find.textContaining('还没有评论'), findsOneWidget);
    expect(find.textContaining('需要登录'), findsOneWidget);
  });

  testWidgets('错误态给重试按钮，重试成功后展示列表', (tester) async {
    var failing = true;
    final source = _SwitchableSource(() => failing);
    await tester.pumpWidget(_app(source));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-comments-error')), findsOneWidget);
    expect(find.text('需要登录后才能查看评论'), findsOneWidget);

    failing = false;
    await tester.tap(find.byKey(const Key('reader-comments-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-comments-list')), findsOneWidget);
  });

  testWidgets('点「查看 N 条回复」进入回复视图，可返回', (tester) async {
    final source = _ReplyAwareSource();
    await tester.pumpWidget(_app(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看 3 条回复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('回复 用户1'), findsOneWidget);
    expect(find.text('回复内容'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-comments-back')));
    await tester.pumpAndSettle();
    expect(find.text('章节评论'), findsOneWidget);
  });
}

/// 第一次失败、之后成功的源。
class _SwitchableSource implements NovelCommentSource {
  _SwitchableSource(this.failing);

  final bool Function() failing;

  @override
  bool get supportsChapterComments => true;

  @override
  Future<NovelCommentPage> loadChapterComments({
    required String comicId,
    required String episodeId,
    required int page,
    String? replyTo,
  }) async {
    if (failing()) throw const NovelCommentException('需要登录后才能查看评论');
    return NovelCommentPage(comments: <NovelComment>[_c('1')], maxPage: 1);
  }
}

/// 顶层评论带回复数；进入回复后返回另一条内容。
class _ReplyAwareSource implements NovelCommentSource {
  @override
  bool get supportsChapterComments => true;

  @override
  Future<NovelCommentPage> loadChapterComments({
    required String comicId,
    required String episodeId,
    required int page,
    String? replyTo,
  }) async {
    if (replyTo == null) {
      return NovelCommentPage(
        comments: <NovelComment>[_c('1', replies: 3)],
        maxPage: 1,
      );
    }
    return const NovelCommentPage(
      comments: <NovelComment>[
        NovelComment(userName: '回复者', content: '回复内容', id: 'r1'),
      ],
      maxPage: 1,
    );
  }
}
