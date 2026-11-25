// 书签/划线数据层回归：往返、同位置去重、换源重定位、区间校验、v2→v3 迁移。
//
// 用内存 drift 库直接驱动服务与迁移策略，不碰插件；UI 行为另有页面测试与
// 截图（mimao-dev）覆盖。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';

/// 最小 QueryExecutorUser：让 executor 通过 ensureOpen 的开启检查。
class _OpenUser implements QueryExecutorUser {
  _OpenUser(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

NovelChapter _chapter(String title, int index) =>
    NovelChapter(id: 'c$index', title: title, index: index, url: 'u$index');

NovelTextAnchor _anchor({
  int chapter = 0,
  int paragraph = 0,
  int charOffset = 0,
  String sourceKey = 'src-a',
}) => NovelTextAnchor(
  bookId: 'book-1',
  sourceKey: sourceKey,
  chapterIndex: chapter,
  paragraph: paragraph,
  charOffset: charOffset,
);

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

  group('书签', () {
    test('加 → 读 → 同位置再点删除 → 再加回来（往返 + 去重）', () async {
      final added = await service.toggleBookmark(
        anchor: _anchor(paragraph: 3, charOffset: 7),
        chapterName: '第一章',
        bookTitle: '测试书',
        bookAuthor: '作者',
        bookUrl: 'https://example.com/book/1',
        excerpt: '一句话摘录',
        now: DateTime(2026, 11, 25, 10),
      );
      expect(added.removed, isFalse);
      expect(added.bookmark.id, greaterThan(0));

      final list = await service.bookmarksForBook('book-1');
      expect(list, hasLength(1));
      expect(list.single.paragraph, 3);
      expect(list.single.charOffset, 7);
      expect(list.single.chapterName, '第一章');
      expect(list.single.bookUrl, 'https://example.com/book/1');
      expect(list.single.excerpt, '一句话摘录');
      expect(list.single.unresolved, isFalse);

      // 同一位置（bookId + sourceKey + 章 + 段 + 偏移）再点 = 删除。
      final removed = await service.toggleBookmark(
        anchor: _anchor(paragraph: 3, charOffset: 7),
        chapterName: '第一章',
      );
      expect(removed.removed, isTrue);
      expect(await service.bookmarksForBook('book-1'), isEmpty);

      // 再点 = 重新新建，id 不沿用旧行。
      final again = await service.toggleBookmark(
        anchor: _anchor(paragraph: 3, charOffset: 7),
        chapterName: '第一章',
      );
      expect(again.removed, isFalse);
      expect(await service.bookmarksForBook('book-1'), hasLength(1));
    });

    test('同位置重复 addBookmark 收敛成一条，不产生重复行', () async {
      for (var i = 0; i < 3; i++) {
        await service.addBookmark(
          anchor: _anchor(paragraph: 1),
          chapterName: '第一章',
        );
      }
      final rows = await db.select(db.novelBookmarkEntries).get();
      expect(rows, hasLength(1));
    });

    test('目录角标：按章去重；不同源的书签都算这本书', () async {
      await service.addBookmark(
        anchor: _anchor(chapter: 0, paragraph: 0),
        chapterName: '第一章',
      );
      await service.addBookmark(
        anchor: _anchor(chapter: 2, paragraph: 1),
        chapterName: '第三章',
      );
      await service.addBookmark(
        anchor: _anchor(chapter: 2, paragraph: 4),
        chapterName: '第三章',
      );
      expect(await service.bookmarkedChapterIndexes('book-1'), <int>{0, 2});
    });

    test('换源重定位：按章标题找到新下标；找不到标「无法定位」但保留', () async {
      await service.addBookmark(
        anchor: _anchor(chapter: 0, paragraph: 2, charOffset: 5),
        chapterName: '第一章 开端',
        bookTitle: '测试书',
      );
      await service.addBookmark(
        anchor: _anchor(chapter: 1, paragraph: 0),
        chapterName: '第二章 风起',
        bookTitle: '测试书',
      );
      await service.addBookmark(
        anchor: _anchor(chapter: 2, paragraph: 1),
        chapterName: '只在旧源存在的章',
        bookTitle: '测试书',
      );

      // 新源目录整体后移一章，且第一章标题多了空格/标点。
      final chapters = <NovelChapter>[
        _chapter('序章', 0),
        _chapter('第一章：开端！', 1),
        _chapter('第二章 风起', 2),
      ];
      final result = await service.relocateBookmarks(
        'book-1',
        chapters,
        sourceKey: 'src-b',
      );
      expect(result.total, 3);
      expect(result.relocated, 2);
      expect(result.unresolved, 1);

      final list = await service.bookmarksForBook('book-1');
      final byName = <String, NovelBookmark>{
        for (final bookmark in list) bookmark.chapterName: bookmark,
      };
      expect(byName['第一章 开端']!.chapterIndex, 1);
      expect(byName['第一章 开端']!.unresolved, isFalse);
      expect(byName['第二章 风起']!.chapterIndex, 2);
      expect(byName['只在旧源存在的章']!.unresolved, isTrue);
      // 失败的行保留旧源标记，避免它被新源的章节视图误收。
      expect(byName['只在旧源存在的章']!.sourceKey, 'src-a');
      // 失败的那条没被删：总数仍是 3。
      expect(list, hasLength(3));
      // 重定位后行上的 sourceKey 跟到新源，后续去重仍按新源算。
      expect(byName['第二章 风起']!.sourceKey, 'src-b');
    });

    test('空章名的老数据：章下标仍在范围内不算失败', () async {
      await service.addBookmark(anchor: _anchor(chapter: 1), chapterName: '');
      final result = await service.relocateBookmarks('book-1', <NovelChapter>[
        _chapter('第一章', 0),
        _chapter('第二章', 1),
      ], sourceKey: 'src-b');
      expect(result.unresolved, 0);
      final list = await service.bookmarksForBook('book-1');
      expect(list.single.unresolved, isFalse);
      expect(list.single.chapterIndex, 1);
    });

    test('删除单条 + 清空本书', () async {
      final a = await service.addBookmark(
        anchor: _anchor(paragraph: 0),
        chapterName: '第一章',
      );
      await service.addBookmark(
        anchor: _anchor(paragraph: 1),
        chapterName: '第一章',
      );
      expect(await service.removeBookmark(a.id), isTrue);
      expect(await service.bookmarksForBook('book-1'), hasLength(1));
      await service.removeBookmarksForBook('book-1');
      expect(await service.bookmarksForBook('book-1'), isEmpty);
    });
  });

  group('划线区间', () {
    test('start > end 自动交换', () async {
      final marking = await service.addMarking(
        anchor: _anchor(paragraph: 0, charOffset: 8),
        endOffset: 3,
        style: NovelMarkingStyle.yellow,
        chapterName: '第一章',
        paragraphLength: 20,
      );
      expect(marking, isNotNull);
      expect(marking!.startOffset, 3);
      expect(marking.endOffset, 8);
    });

    test('越界 clamp 到段落长度；零长度拒绝落库', () async {
      final clamped = await service.addMarking(
        anchor: _anchor(paragraph: 0, charOffset: 5),
        endOffset: 999,
        style: NovelMarkingStyle.yellow,
        chapterName: '第一章',
        paragraphLength: 12,
      );
      expect(clamped!.startOffset, 5);
      expect(clamped.endOffset, 12);

      final empty = await service.addMarking(
        anchor: _anchor(paragraph: 0, charOffset: 5),
        endOffset: 5,
        style: NovelMarkingStyle.yellow,
        chapterName: '第一章',
        paragraphLength: 12,
      );
      expect(empty, isNull);
      expect(await service.markingsForChapter('book-1', 0), hasLength(1));
    });

    test('样式往返（颜色/装饰）+ 备注可改可删', () async {
      final marking = await service.addMarking(
        anchor: _anchor(paragraph: 2, charOffset: 1),
        endOffset: 6,
        style: const NovelMarkingStyle(
          colorArgb: 0x6664B5F6,
          decoration: NovelMarkingDecoration.wavy,
        ),
        note: '初版备注',
        chapterName: '第一章',
        paragraphLength: 30,
      );
      final read = (await service.markingsForChapter('book-1', 0)).single;
      expect(read.style.colorArgb, 0x6664B5F6);
      expect(read.style.decoration, NovelMarkingDecoration.wavy);
      expect(read.note, '初版备注');
      expect(read.paragraph, 2);

      final updated = await service.updateMarking(
        marking!.id,
        style: const NovelMarkingStyle(
          colorArgb: 0x6666BB6A,
          decoration: NovelMarkingDecoration.underline,
        ),
        note: '改过的备注',
        paragraphLength: 30,
      );
      expect(updated!.style.decoration, NovelMarkingDecoration.underline);
      expect(updated.note, '改过的备注');

      expect(await service.removeMarking(marking.id), isTrue);
      expect(await service.markingsForChapter('book-1', 0), isEmpty);
    });

    test('换源重定位划线：标题匹配则跟章，否则标 unresolved', () async {
      await service.addMarking(
        anchor: _anchor(chapter: 1, charOffset: 2),
        endOffset: 5,
        style: NovelMarkingStyle.yellow,
        chapterName: '第二章',
        paragraphLength: 20,
      );
      await service.addMarking(
        anchor: _anchor(chapter: 4, charOffset: 2),
        endOffset: 5,
        style: NovelMarkingStyle.yellow,
        chapterName: '消失了',
        paragraphLength: 20,
      );
      final result = await service.relocateMarkings('book-1', <NovelChapter>[
        _chapter('第一章', 0),
        _chapter('第二章', 1),
      ], sourceKey: 'src-b');
      expect(result.relocated, 1);
      expect(result.unresolved, 1);
      final rows = await db.select(db.novelMarkingEntries).get();
      expect(rows, hasLength(2));
      expect(rows.where((row) => row.unresolved), hasLength(1));
      final found = await service.markingsForChapter('book-1', 1);
      expect(found, hasLength(1));
      expect(found.single.unresolved, isFalse);
    });
  });

  group('迁移', () {
    test('v2→v3：旧行保留，新表可用', () async {
      final executor = NativeDatabase.memory();
      final user = _OpenUser(2);
      await executor.ensureOpen(user);
      await executor.runCustom(
        'CREATE TABLE novel_collect (id TEXT NOT NULL PRIMARY KEY, '
        'title TEXT NOT NULL, cover_url TEXT NULL, payload TEXT NOT NULL '
        "DEFAULT '{}', group_name TEXT NULL, collected_at INTEGER NOT NULL)",
      );
      await executor.runCustom(
        'INSERT INTO novel_collect (id, title, payload, collected_at) '
        "VALUES ('b1', '老书', '{}', 0)",
      );

      final db2 = NovelDb.forTesting(executor);
      addTearDown(db2.close);
      final migrator = Migrator(db2);
      await db2.migration.onUpgrade(migrator, 2, 3);

      final oldRows = await db2.select(db2.novelCollectEntries).get();
      expect(oldRows, hasLength(1));
      expect(oldRows.single.title, '老书');

      final service2 = NovelBookmarkService(db2);
      await service2.addBookmark(anchor: _anchor(), chapterName: '第一章');
      expect(await service2.bookmarksForBook('book-1'), hasLength(1));
      await service2.addMarking(
        anchor: _anchor(charOffset: 1),
        endOffset: 4,
        style: NovelMarkingStyle.yellow,
        chapterName: '第一章',
        paragraphLength: 10,
      );
      expect(await service2.markingsForChapter('book-1', 0), hasLength(1));
    });

    test('v1→v3：一次升级同时补 v2 的列/表与 v3 的新表', () async {
      final executor = NativeDatabase.memory();
      final user = _OpenUser(1);
      await executor.ensureOpen(user);
      await executor.runCustom(
        'CREATE TABLE novel_collect (id TEXT NOT NULL PRIMARY KEY, '
        'title TEXT NOT NULL, cover_url TEXT NULL, payload TEXT NOT NULL '
        "DEFAULT '{}', collected_at INTEGER NOT NULL)",
      );
      await executor.runCustom(
        'INSERT INTO novel_collect (id, title, payload, collected_at) '
        "VALUES ('b1', '老书', '{}', 0)",
      );

      final db1 = NovelDb.forTesting(executor);
      addTearDown(db1.close);
      final migrator = Migrator(db1);
      await db1.migration.onUpgrade(migrator, 1, 3);

      final oldRows = await db1.select(db1.novelCollectEntries).get();
      expect(oldRows.single.id, 'b1');
      expect(oldRows.single.groupName, isNull);

      await db1
          .into(db1.novelPrefs)
          .insert(NovelPrefsCompanion.insert(key: 'k', value: 'v'));
      expect((await db1.select(db1.novelPrefs).get()).single.value, 'v');

      final service1 = NovelBookmarkService(db1);
      await service1.addBookmark(anchor: _anchor(), chapterName: '第一章');
      expect(await service1.bookmarksForBook('book-1'), hasLength(1));
    });
  });
}
