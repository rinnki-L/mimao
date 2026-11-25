// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart。
// 选区菜单：长按选词后菜单出现，划线/笔记可用并落库；区间不含段首缩进。
//
// 翻页模式不挂自定义菜单（避免破坏点按/翻页手势），这里只覆盖滚动模式。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

const _source = NovelBookSource(
  key: 'src1',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

final _chapters = <NovelChapter>[
  const NovelChapter(
    id: 'https://site.test/book/1/1',
    title: '第一章',
    index: 0,
    url: 'https://site.test/book/1/1',
  ),
];

class _ShortEngine implements NovelOnlineEngine {
  @override
  void close() {}

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async =>
      const <NovelExploreKind>[];

  @override
  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async =>
      NovelDetail(ref: ref, title: '测试书', author: '作者', chapters: _chapters);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => NovelContent(
    chapterId: chapter.id,
    title: chapter.title,
    paragraphs: <String>[
      '第一段测试文字，长按选词后应该能划线。',
      '第二段测试文字，用来验证段落锚点。',
      // 撑出可滚动高度：下滑加书签依赖 overscroll，内容不足一屏不会触发。
      for (var i = 0; i < 40; i++) '填充段落$i，用来撑出滚动距离。',
    ],
  );
}

class _FixedStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

void main() {
  testWidgets('长按选词弹出复制/划线/笔记/搜索，划线按段内偏移落库', (tester) async {
    final db = NovelDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = NovelBookmarkService(db);

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '测试书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book/1',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: _ShortEngine(),
          sourceStore: _FixedStore(),
          settingsStore: MemoryNovelReaderSettingsStore(
            const NovelReaderSettings(),
          ),
          bookmarks: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第一段贴着顶栏，顶栏展开时会被盖住；用第二段做选词，行为相同。
    await tester.longPress(find.textContaining('第二段测试文字'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-selection-copy')), findsOneWidget);
    expect(find.byKey(const Key('novel-selection-mark')), findsOneWidget);
    expect(find.byKey(const Key('novel-selection-note')), findsOneWidget);
    expect(find.byKey(const Key('novel-selection-search')), findsOneWidget);

    final mark = tester.widget<TextButton>(
      find.byKey(const Key('novel-selection-mark')),
    );
    expect(mark.onPressed, isNotNull, reason: '长按选中的词应可划线');

    await tester.tap(find.byKey(const Key('novel-selection-mark')));
    await tester.pumpAndSettle();

    final markings = await service.markingsForChapter('book1', 0);
    expect(markings, hasLength(1));
    expect(markings.single.paragraph, 1);
    // 落库偏移不含段首缩进，且 start < end、落在段落长度内。
    expect(markings.single.startOffset, greaterThanOrEqualTo(0));
    expect(markings.single.endOffset, greaterThan(markings.single.startOffset));
    expect(markings.single.endOffset, lessThanOrEqualTo(20));
  });

  testWidgets('下滑加书签：默认关不响应；开启后顶部下拉加一条', (tester) async {
    final opened = <NovelDb>[];
    addTearDown(() async {
      for (final db in opened) {
        await db.close();
      }
    });
    Future<NovelBookmarkService> pumpReader({
      required bool swipeDownBookmark,
    }) async {
      final db = NovelDb.forTesting(NativeDatabase.memory());
      opened.add(db);
      final service = NovelBookmarkService(db);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelReaderPage(
            key: UniqueKey(),
            bookId: 'book1',
            title: '测试书',
            sourceKey: 'src1',
            bookUrl: 'https://site.test/book/1',
            chapterIndex: 0,
            chapters: _chapters,
            onlineEngine: _ShortEngine(),
            sourceStore: _FixedStore(),
            settingsStore: MemoryNovelReaderSettingsStore(
              NovelReaderSettings(swipeDownBookmark: swipeDownBookmark),
            ),
            bookmarks: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    // 默认关：顶部继续下拉不写书签。
    var service = await pumpReader(swipeDownBookmark: false);
    await tester.drag(
      find.byKey(const Key('novel-reader-scroll')),
      const Offset(0, 260),
    );
    await tester.pumpAndSettle();
    expect(await service.bookmarksForBook('book1'), isEmpty);

    // 打开手势：同一次下拉只加一条。
    service = await pumpReader(swipeDownBookmark: true);
    await tester.drag(
      find.byKey(const Key('novel-reader-scroll')),
      const Offset(0, 260),
    );
    await tester.pumpAndSettle();
    final bookmarks = await service.bookmarksForBook('book1');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.chapterName, '第一章');
  });

  testWidgets('点击已有划线打开编辑面板，删除后划线消失', (tester) async {
    final db = NovelDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = NovelBookmarkService(db);
    final marking = await service.addMarking(
      anchor: const NovelTextAnchor(
        bookId: 'book1',
        sourceKey: 'src1',
        chapterIndex: 0,
        paragraph: 1,
        charOffset: 2,
      ),
      endOffset: 6,
      style: NovelMarkingStyle.yellow,
      note: '已有的备注',
      chapterName: '第一章',
      paragraphLength: 20,
    );
    expect(marking, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '测试书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book/1',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: _ShortEngine(),
          sourceStore: _FixedStore(),
          settingsStore: MemoryNovelReaderSettingsStore(
            const NovelReaderSettings(),
          ),
          bookmarks: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 找到第二段的 RenderParagraph，按落库偏移（+段首缩进）算出划线的屏幕位置。
    final richFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('第二段测试文字'),
    );
    final rich = tester.renderObject<RenderParagraph>(richFinder);
    final boxes = rich.getBoxesForSelection(
      const TextSelection(baseOffset: 4, extentOffset: 8),
    );
    expect(boxes, isNotEmpty);
    await tester.tapAt(rich.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();

    expect(find.text('编辑划线'), findsOneWidget);
    expect(find.text('已有的备注'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-marking-delete')));
    await tester.pumpAndSettle();
    expect(await service.markingsForChapter('book1', 0), isEmpty);
  });
}
