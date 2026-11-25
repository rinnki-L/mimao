// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart。
// 书签列表页：空态、带无法定位标记的列表、删除确认。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_bookmarks_page.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';

void main() {
  late NovelDb db;
  late NovelBookmarkService service;

  setUp(() {
    db = NovelDb.forTesting(NativeDatabase.memory());
    service = NovelBookmarkService(db);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('空态写清为什么空 + 下一步', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelBookmarksPage(
          bookmarks: service,
          bookId: 'book-1',
          bookTitle: '测试书',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这本书还没有书签'), findsOneWidget);
    expect(find.textContaining('加书签'), findsWidgets);
  });

  testWidgets('列表显示摘录/章节；unresolved 标「无法定位」；删除要确认', (tester) async {
    final found = await service.addBookmark(
      anchor: const NovelTextAnchor(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterIndex: 0,
        paragraph: 2,
        charOffset: 4,
      ),
      chapterName: '第一章 开端',
      bookTitle: '测试书',
      excerpt: '这一句值得回看',
      now: DateTime(2026, 11, 25, 9),
    );
    await service.addBookmark(
      anchor: const NovelTextAnchor(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterIndex: 7,
        paragraph: 1,
      ),
      chapterName: '已经消失的章',
      bookTitle: '测试书',
      excerpt: '找不到的那条',
      now: DateTime(2026, 11, 25, 10),
    );
    // 模拟换源后重定位失败：目录为空，两条都找不到。
    await service.relocateBookmarks('book-1', const <NovelChapter>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: NovelBookmarksPage(
          bookmarks: service,
          bookId: 'book-1',
          bookTitle: '测试书',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('这一句值得回看'), findsOneWidget);
    expect(find.text('找不到的那条'), findsOneWidget);
    expect(find.text('无法定位'), findsNWidgets(2));
    expect(find.textContaining('第一章 开端'), findsWidgets);

    // 删除第一条：先弹确认框，取消不动。
    await tester.tap(find.byKey(Key('novel-bookmark-delete-${found.id}')));
    await tester.pumpAndSettle();
    expect(find.text('删除这条书签？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await service.bookmarksForBook('book-1'), hasLength(2));

    await tester.tap(find.byKey(Key('novel-bookmark-delete-${found.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(await service.bookmarksForBook('book-1'), hasLength(1));

    // 重开一个列表页确认删除真的落到了 UI 数据源（同一页的刷新是异步
    // FutureBuilder，测试里不强行等它，避免引入与业务无关的时序断言）。
    await tester.pumpWidget(
      MaterialApp(
        home: NovelBookmarksPage(
          key: UniqueKey(),
          bookmarks: service,
          bookId: 'book-1',
          bookTitle: '测试书',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这一句值得回看'), findsNothing);
    expect(find.text('找不到的那条'), findsOneWidget);
  });
}
