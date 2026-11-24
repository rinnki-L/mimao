// 章节评论：模型解析、分页累加、回复栈、错误与空态。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_comments.dart';

/// 假源：按页返回预置数据，记录调用参数。
class _FakeSource implements NovelCommentSource {
  _FakeSource({required this.pages, this.errorOnPage});

  final Map<int, NovelCommentPage> pages;
  final int? errorOnPage;
  final List<({int page, String? replyTo})> calls =
      <({int page, String? replyTo})>[];

  @override
  bool get supportsChapterComments => true;

  @override
  Future<NovelCommentPage> loadChapterComments({
    required String comicId,
    required String episodeId,
    required int page,
    String? replyTo,
  }) async {
    calls.add((page: page, replyTo: replyTo));
    if (errorOnPage == page) {
      throw const NovelCommentException('源返回登录已过期');
    }
    return pages[page] ?? const NovelCommentPage(comments: <NovelComment>[]);
  }
}

NovelComment _comment(String id, {String name = '用户', String? content}) =>
    NovelComment(
      userName: name,
      content: content ?? '内容 $id',
      id: id,
      replyCount: 0,
    );

void main() {
  group('NovelComment 解析', () {
    test('缺 content 的条目被丢弃', () {
      expect(NovelComment.tryParse(<String, Object?>{'userName': 'a'}), isNull);
      expect(
        NovelComment.tryParse(<String, Object?>{'content': '   '}),
        isNull,
      );
      expect(
        NovelComment.tryParse(<String, Object?>{
          'userName': 'a',
          'content': 'hi',
        }),
        isNotNull,
      );
    });

    test('时间戳按秒/毫秒分别换算', () {
      final seconds = NovelComment.parseTime(1700000000);
      final millis = NovelComment.parseTime(1700000000000);
      expect(seconds, isNotNull);
      expect(seconds, millis, reason: '秒与毫秒应得到同一时刻');
      expect(NovelComment.parseTime('2026-01-02 03:04'), '2026-01-02 03:04');
      expect(NovelComment.parseTime(null), isNull);
      expect(NovelComment.parseTime('  '), isNull);
    });

    test('非字符串 id 也能读成字符串', () {
      final comment = NovelComment.tryParse(<String, Object?>{
        'userName': 'a',
        'content': 'hi',
        'id': 42,
      });
      expect(comment!.id, '42');
    });
  });

  group('NovelCommentsController', () {
    test('首屏加载与分页累加', () async {
      final source = _FakeSource(
        pages: <int, NovelCommentPage>{
          1: NovelCommentPage(
            comments: <NovelComment>[_comment('1'), _comment('2')],
            maxPage: 2,
          ),
          2: NovelCommentPage(
            comments: <NovelComment>[_comment('3')],
            maxPage: 2,
          ),
        },
      );
      final controller = NovelCommentsController(
        source: source,
        comicId: 'c1',
        episodeId: 'e1',
      );

      await controller.reload();
      expect(controller.comments, hasLength(2));
      expect(controller.page, 1);
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.comments, hasLength(3));
      expect(controller.page, 2);
      expect(controller.hasMore, isFalse, reason: 'maxPage=2 已到底');

      await controller.loadMore();
      expect(source.calls, hasLength(2), reason: '到底后不再请求');
      controller.dispose();
    });

    test('不知道总页数时按"本页是否为空"判断到底', () async {
      final source = _FakeSource(
        pages: <int, NovelCommentPage>{
          1: NovelCommentPage(comments: <NovelComment>[_comment('1')]),
        },
      );
      final controller = NovelCommentsController(
        source: source,
        comicId: 'c1',
        episodeId: 'e1',
      );
      await controller.reload();
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.comments, hasLength(1));
      expect(controller.hasMore, isFalse);
      controller.dispose();
    });

    test('加载失败展示可读错误，不清空已加载内容', () async {
      final source = _FakeSource(
        pages: <int, NovelCommentPage>{
          1: NovelCommentPage(
            comments: <NovelComment>[_comment('1')],
            maxPage: 3,
          ),
        },
        errorOnPage: 2,
      );
      final controller = NovelCommentsController(
        source: source,
        comicId: 'c1',
        episodeId: 'e1',
      );
      await controller.reload();
      await controller.loadMore();

      expect(controller.error, '源返回登录已过期');
      expect(controller.comments, hasLength(1), reason: '已有内容保留');
      expect(controller.loading, isFalse);
      controller.dispose();
    });

    test('进入回复列表与返回顶层', () async {
      final source = _FakeSource(
        pages: <int, NovelCommentPage>{
          1: NovelCommentPage(comments: <NovelComment>[_comment('1')]),
        },
      );
      final controller = NovelCommentsController(
        source: source,
        comicId: 'c1',
        episodeId: 'e1',
      );
      await controller.reload();

      await controller.openReplies(_comment('1', name: '阿甲'));
      expect(controller.replyTo, '1');
      expect(controller.replyToUserName, '阿甲');
      expect(source.calls.last.replyTo, '1');

      await controller.back();
      expect(controller.replyTo, isNull);
      expect(source.calls.last.replyTo, isNull);
      controller.dispose();
    });

    test('没有 id 的评论不进入回复', () async {
      final source = _FakeSource(pages: const <int, NovelCommentPage>{});
      final controller = NovelCommentsController(
        source: source,
        comicId: 'c1',
        episodeId: 'e1',
      );
      await controller.openReplies(
        const NovelComment(userName: 'a', content: 'hi'),
      );
      expect(controller.replyTo, isNull);
      expect(source.calls, isEmpty);
      controller.dispose();
    });

    test('dispose 后迟到的加载结果不写入', () async {
      final source = _FakeSource(
        pages: <int, NovelCommentPage>{
          1: NovelCommentPage(comments: <NovelComment>[_comment('1')]),
        },
      );
      final controller = NovelCommentsController(
        source: source,
        comicId: 'c1',
        episodeId: 'e1',
      );
      final loading = controller.reload();
      controller.dispose();
      await loading;
      // 不抛异常即通过；dispose 后内部状态不再对外暴露。
    });
  });
}
