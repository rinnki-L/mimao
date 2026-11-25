// 删除墓碑：书签/划线删除写墓碑、墓碑保留期、v8→v9 迁移。
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_plan.dart';
import 'package:mimao/novel/backup/novel_tombstone_service.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';

void main() {
  late NovelDb db;
  late NovelBookmarkService bookmarks;
  late NovelTombstoneService tombstones;

  setUp(() {
    db = NovelDb.forTesting(NativeDatabase.memory());
    bookmarks = NovelBookmarkService(db);
    tombstones = NovelTombstoneService(db);
  });

  tearDown(() => db.close());

  NovelTextAnchor anchor({
    int chapter = 3,
    int paragraph = 1,
    int offset = 10,
  }) => NovelTextAnchor(
    bookId: 'b1',
    chapterIndex: chapter,
    paragraph: paragraph,
    charOffset: offset,
  );

  test('删书签写墓碑，键与合并口径一致', () async {
    final created = await bookmarks.addBookmark(
      anchor: anchor(),
      chapterName: '第三章',
      bookTitle: '三体',
    );
    expect(await tombstones.load(), isEmpty);

    await bookmarks.removeBookmark(created.id);

    final rows = await tombstones.load();
    expect(rows, hasLength(1));
    expect(rows.single.kind, novelTombstoneBookmark);
    expect(rows.single.key, 'b1||3|1|10|10');
  });

  test('同一位置再点一次（toggle 删）也写墓碑', () async {
    final first = await bookmarks.toggleBookmark(
      anchor: anchor(chapter: 5),
      chapterName: '第五章',
    );
    expect(first.removed, isFalse);

    final second = await bookmarks.toggleBookmark(
      anchor: anchor(chapter: 5),
      chapterName: '第五章',
    );
    expect(second.removed, isTrue);
    final rows = await tombstones.load();
    expect(rows.single.key, 'b1||5|1|10|10');
  });

  test('删划线写墓碑，键带区间', () async {
    final marking = await bookmarks.addMarking(
      anchor: anchor(paragraph: 2, offset: 4),
      endOffset: 12,
      style: NovelMarkingStyle.yellow,
      chapterName: '第三章',
      bookTitle: '三体',
    );
    expect(marking, isNotNull);

    await bookmarks.removeMarking(marking!.id);

    final rows = await tombstones.load();
    expect(rows.single.kind, novelTombstoneMarking);
    expect(rows.single.key, 'b1||3|2|4|12');
  });

  test('整本删书签：每条都留墓碑', () async {
    await bookmarks.addBookmark(anchor: anchor(chapter: 1), chapterName: '一');
    await bookmarks.addBookmark(anchor: anchor(chapter: 2), chapterName: '二');

    await bookmarks.removeBookmarksForBook('b1');

    expect((await tombstones.load()).length, 2);
  });

  test('墓碑保留期：超过 90 天被 prune 掉', () async {
    final now = DateTime.utc(2026, 11, 25);
    await tombstones.record(
      kind: novelTombstoneBookmark,
      key: 'old',
      at: now.subtract(const Duration(days: 91)),
    );
    await tombstones.record(
      kind: novelTombstoneBookmark,
      key: 'fresh',
      at: now.subtract(const Duration(days: 3)),
    );
    await tombstones.prune(now: now);

    final rows = await tombstones.load(now: now);
    expect(rows.map((row) => row.key), <String>['fresh']);
  });

  test('同键重复删除只留最新一次（主键覆盖）', () async {
    await tombstones.record(
      kind: novelTombstoneBookmark,
      key: 'k',
      at: DateTime.utc(2026, 11, 1),
    );
    await tombstones.record(
      kind: novelTombstoneBookmark,
      key: 'k',
      at: DateTime.utc(2026, 11, 20),
    );
    final rows = await tombstones.load();
    expect(rows, hasLength(1));
    // drift 按本地时区读回（本机 UTC+8），比较先后而不是对象相等。
    expect(rows.single.deletedAt.isAfter(DateTime.utc(2026, 11, 19)), isTrue);
    expect(rows.single.deletedAt.isBefore(DateTime.utc(2026, 11, 21)), isTrue);
  });

  test('v8→v9 迁移：建墓碑表，旧数据一行不动', () async {
    await db
        .into(db.novelCollectEntries)
        .insert(
          NovelCollectEntriesCompanion.insert(
            id: 'b1',
            title: '老书',
            collectedAt: DateTime.utc(2026, 11, 1),
          ),
        );
    await (db.delete(db.novelTombstoneEntries)).go();

    final migrator = Migrator(db);
    await db.migration.onUpgrade(migrator, 8, 9);

    expect(await db.select(db.novelCollectEntries).get(), hasLength(1));
    expect(await db.select(db.novelTombstoneEntries).get(), isEmpty);
    // 表真的建出来了：写一行再读得回来。
    await tombstones.record(kind: novelTombstoneBookmark, key: 'k1');
    expect(await db.select(db.novelTombstoneEntries).get(), hasLength(1));
  });
}
