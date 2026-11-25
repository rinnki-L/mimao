// 阅读统计与多设备阅读记录模型的单测：
// - 旧 `novel_reading_day` → 新 `novel_read_record` 迁移（幂等、可重跑）；
// - 设备维度聚合（本机视图不混别的设备）；
// - 连续阅读天数（当前/最长，含「今天还没读」）；
// - 热力图分桶（相对档位）与柱状图补零。
// 全部用内存库，不碰 path_provider。
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/device_id.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_widgets.dart' show novelChapterLabel;
import 'package:mimao/novel/stats_service.dart';

/// 最小 QueryExecutorUser：让手造旧表的 executor 通过 ensureOpen 检查。
class _OpenUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 7;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  group('device id', () {
    test('生成的是 v4 UUID，且每次不同', () {
      final ids = <String>{
        for (var i = 0; i < 32; i++) generateNovelDeviceId(),
      };
      expect(ids, hasLength(32));
      for (final id in ids) {
        expect(novelDeviceIdPattern.hasMatch(id), isTrue, reason: id);
      }
    });

    test('ensureDeviceId 首次生成、之后恒定返回同一个值', () async {
      final db = NovelDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final first = await db.ensureDeviceId();
      final second = await db.ensureDeviceId();
      expect(novelDeviceIdPattern.hasMatch(first), isTrue);
      expect(second, first);
      // 已落 kv，重开（同一库）仍读到同一个。
      expect(await db.readPref(novelPrefDeviceId), first);
    });
  });

  group('旧数据迁移', () {
    /// 手造 v7 库：有旧 `novel_reading_day`，没有新 `novel_read_record`。
    Future<NovelDb> legacyDb({
      Map<String, int> days = const <String, int>{
        '2026-11-20': 600,
        '2026-11-21': 1200,
      },
    }) async {
      final executor = NativeDatabase.memory();
      await executor.ensureOpen(_OpenUser());
      // v7 库里 `novel_pref` 已存在（v2 建的）；设备 ID 要写进它。
      await executor.runCustom(
        'CREATE TABLE novel_pref (key TEXT NOT NULL PRIMARY KEY, '
        'value TEXT NOT NULL)',
      );
      await executor.runCustom(
        'CREATE TABLE novel_reading_day ('
        'day TEXT NOT NULL PRIMARY KEY, '
        'seconds INTEGER NOT NULL DEFAULT 0, '
        'updated_at INTEGER NOT NULL)',
      );
      for (final entry in days.entries) {
        await executor.runCustom(
          'INSERT INTO novel_reading_day (day, seconds, updated_at) '
          'VALUES (?, ?, 0)',
          <Object?>[entry.key, entry.value],
        );
      }
      final db = NovelDb.forTesting(executor);
      addTearDown(db.close);
      return db;
    }

    test('每一天迁成 deviceId=本机、bookId=空、章号 0 的一行，旧表删掉', () async {
      final db = await legacyDb();
      await db.migration.onUpgrade(Migrator(db), 7, 8);

      final rows = await db.select(db.novelReadRecords).get();
      expect(rows, hasLength(2));
      final deviceId = await db.ensureDeviceId();
      for (final row in rows) {
        expect(row.deviceId, deviceId);
        expect(row.bookId, '');
        expect(row.chapterIndex, 0);
      }
      final byDay = <String, int>{for (final row in rows) row.day: row.seconds};
      expect(byDay, <String, int>{'2026-11-20': 600, '2026-11-21': 1200});

      // 旧表已删：再跑一次迁移不会重复插入，也不会报错。
      await db.migration.onUpgrade(Migrator(db), 7, 8);
      expect(await db.select(db.novelReadRecords).get(), hasLength(2));
    });

    test('迁移幂等：同一批旧数据重跑两次，时长不翻倍', () async {
      final db = await legacyDb(days: const <String, int>{'2026-11-22': 900});
      await db.migration.onUpgrade(Migrator(db), 7, 8);
      final before = (await db.select(db.novelReadRecords).get()).single;
      expect(before.seconds, 900);

      // 模拟「旧表又出现」（比如迁移中途崩溃后重放）：重建旧表再跑一次。
      await db.customStatement(
        'CREATE TABLE novel_reading_day ('
        'day TEXT NOT NULL PRIMARY KEY, '
        'seconds INTEGER NOT NULL DEFAULT 0, '
        'updated_at INTEGER NOT NULL)',
      );
      await db.customStatement(
        "INSERT INTO novel_reading_day (day, seconds, updated_at) "
        "VALUES ('2026-11-22', 900, 0)",
      );
      await db.migration.onUpgrade(Migrator(db), 7, 8);

      final after = (await db.select(db.novelReadRecords).get()).single;
      expect(after.seconds, 900);
    });

    test('旧表不存在（新装 / 已迁移）时迁移是空操作', () async {
      final db = NovelDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.migration.onUpgrade(Migrator(db), 7, 8);
      expect(await db.select(db.novelReadRecords).get(), isEmpty);
    });

    test('迁移后的旧数据仍进日聚合，但不进时间轴/章节维度', () async {
      final db = await legacyDb(
        days: const <String, int>{'2026-11-20': 600, '2026-11-21': 1200},
      );
      await db.migration.onUpgrade(Migrator(db), 7, 8);
      final stats = NovelStatsService(db);

      final overview = await stats.overview(today: DateTime(2026, 11, 21));
      expect(overview.totalSeconds, 1800);
      // 旧行没有 bookId，不算「本数」。
      expect(overview.booksRead, 0);
      expect(overview.activeDays, 2);
      expect(overview.longestStreak, 2);

      // 时间轴仍能看到这两天（bookId 为空的书条目），但章节维度为空。
      final timeline = await stats.timeline();
      expect(timeline.map((day) => day.day), <String>[
        '2026-11-21',
        '2026-11-20',
      ]);
      expect(timeline.first.seconds, 1200);
      expect(await stats.bookChapters(''), isEmpty);
    });
  });

  group('设备维度聚合', () {
    late NovelDb db;
    late NovelStatsService stats;

    setUp(() async {
      db = NovelDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      stats = NovelStatsService(db);
    });

    Future<void> insertRaw({
      required String deviceId,
      required String bookId,
      required int chapterIndex,
      required String day,
      required int seconds,
      String bookTitle = '',
      String chapterName = '',
    }) => db
        .into(db.novelReadRecords)
        .insert(
          NovelReadRecordsCompanion.insert(
            deviceId: deviceId,
            bookId: bookId,
            bookTitle: Value<String>(bookTitle),
            chapterIndex: Value<int>(chapterIndex),
            chapterName: Value<String>(chapterName),
            day: day,
            seconds: Value<int>(seconds),
            firstReadAt: DateTime(2026, 11, 20, 9),
            lastReadAt: DateTime(2026, 11, 20, 10),
          ),
        );

    test('本机快照只算本机设备，别的设备不混进来', () async {
      final local = await db.ensureDeviceId();
      await insertRaw(
        deviceId: local,
        bookId: 'b1',
        chapterIndex: 1,
        day: '2026-11-20',
        seconds: 300,
      );
      await insertRaw(
        deviceId: 'other-device',
        bookId: 'b2',
        chapterIndex: 1,
        day: '2026-11-20',
        seconds: 5000,
      );

      final snapshot = await stats.snapshot();
      expect(snapshot.totalSeconds, 300);

      final overview = await stats.overview(today: DateTime(2026, 11, 20));
      expect(overview.totalSeconds, 300);
      expect(overview.booksRead, 1);
      expect(await stats.timeline(), hasLength(1));
    });

    test('同书同章同一天累加，不同章分开记', () async {
      const target = NovelReadTarget(
        bookId: 'b1',
        bookTitle: '三体',
        chapterIndex: 1,
        chapterName: '第一章',
      );
      await stats.addReadingTime(
        const Duration(seconds: 60),
        at: DateTime(2026, 11, 20, 10),
        target: target,
      );
      await stats.addReadingTime(
        const Duration(seconds: 30),
        at: DateTime(2026, 11, 20, 11),
        target: target,
      );
      await stats.addReadingTime(
        const Duration(seconds: 45),
        at: DateTime(2026, 11, 20, 12),
        target: const NovelReadTarget(
          bookId: 'b1',
          bookTitle: '三体',
          chapterIndex: 2,
          chapterName: '第二章',
        ),
      );

      final rows = await db.select(db.novelReadRecords).get();
      expect(rows, hasLength(2));
      final chapter1 = rows.firstWhere((row) => row.chapterIndex == 1);
      expect(chapter1.seconds, 90);
      // firstReadAt 取最早、lastReadAt 取最近。
      expect(chapter1.firstReadAt, DateTime(2026, 11, 20, 10));
      expect(chapter1.lastReadAt, DateTime(2026, 11, 20, 11));

      final chapters = await stats.bookChapters('b1');
      expect(chapters.map((c) => c.chapterIndex), <int>[1, 2]);
      expect(chapters.first.seconds, 90);
      expect(chapters.last.seconds, 45);

      // 日聚合把两章加起来。
      final overview = await stats.overview(today: DateTime(2026, 11, 20));
      expect(overview.totalSeconds, 135);
      expect(overview.booksRead, 1);
    });

    test('时间轴按天分组、当天书按时长倒序', () async {
      await stats.addReadingTime(
        const Duration(seconds: 60),
        at: DateTime(2026, 11, 20, 9),
        target: const NovelReadTarget(
          bookId: 'b1',
          bookTitle: '三体',
          chapterIndex: 1,
        ),
      );
      await stats.addReadingTime(
        const Duration(seconds: 200),
        at: DateTime(2026, 11, 20, 10),
        target: const NovelReadTarget(
          bookId: 'b2',
          bookTitle: '球状闪电',
          chapterIndex: 3,
          chapterName: '第三章',
        ),
      );
      await stats.addReadingTime(
        const Duration(seconds: 90),
        at: DateTime(2026, 11, 19, 20),
        target: const NovelReadTarget(
          bookId: 'b1',
          bookTitle: '三体',
          chapterIndex: 2,
        ),
      );

      final timeline = await stats.timeline();
      expect(timeline.map((day) => day.day), <String>[
        '2026-11-20',
        '2026-11-19',
      ]);
      final day = timeline.first;
      expect(day.seconds, 260);
      expect(day.books.map((b) => b.bookId), <String>['b2', 'b1']);
      expect(day.books.first.title, '球状闪电');
      expect(day.books.first.chapterIndex, 3);
      expect(day.books.first.chapterName, '第三章');

      // limitDays 只截天数，不截书。
      expect((await stats.timeline(limitDays: 1)).single.books, hasLength(2));
    });

    test('热力图只取当年、0 秒日不返回', () async {
      await insertRaw(
        deviceId: await db.ensureDeviceId(),
        bookId: 'b1',
        chapterIndex: 1,
        day: '2026-03-02',
        seconds: 120,
      );
      await insertRaw(
        deviceId: await db.ensureDeviceId(),
        bookId: 'b1',
        chapterIndex: 1,
        day: '2025-03-02',
        seconds: 900,
      );
      await insertRaw(
        deviceId: await db.ensureDeviceId(),
        bookId: 'b1',
        chapterIndex: 1,
        day: '2026-03-03',
        seconds: 0,
      );

      final heatmap = await stats.heatmapSeconds(year: 2026);
      expect(heatmap, <String, int>{'2026-03-02': 120});
    });
  });

  group('连续阅读天数', () {
    test('当前连续：今天读了从今天数，今天没读从昨天数', () {
      final today = DateTime(2026, 11, 25);
      expect(
        novelCurrentStreak(<String>[
          '2026-11-23',
          '2026-11-24',
          '2026-11-25',
        ], today: today),
        3,
      );
      // 今天还没读，但昨天、前天读了 → 连续仍算 2（一天没过完不算断）。
      expect(
        novelCurrentStreak(<String>['2026-11-23', '2026-11-24'], today: today),
        2,
      );
      // 昨天也没读 → 0。
      expect(novelCurrentStreak(<String>['2026-11-23'], today: today), 0);
      expect(novelCurrentStreak(const <String>[], today: today), 0);
    });

    test('最长连续：跨月、乱序、重复都能算对', () {
      expect(
        novelLongestStreak(<String>[
          '2026-11-30',
          '2026-12-01',
          '2026-12-02',
          '2026-11-20',
          '2026-11-20',
          '2026-11-21',
        ]),
        3,
      );
      expect(novelLongestStreak(const <String>[]), 0);
      expect(novelLongestStreak(<String>['2026-11-25']), 1);
    });

    test('跨年连续（12-31 → 01-01）算连续', () {
      expect(novelLongestStreak(<String>['2025-12-31', '2026-01-01']), 2);
    });
  });

  group('热力图与柱状图分桶', () {
    test('热力档位按当天占最大值的比例分四档', () {
      expect(novelHeatLevel(0, 1000), 0);
      expect(novelHeatLevel(1000, 1000), 4);
      expect(novelHeatLevel(750, 1000), 3);
      expect(novelHeatLevel(500, 1000), 2);
      expect(novelHeatLevel(1, 1000), 1);
      // 有数据就至少 1 档，不会因为比例太小显示成空。
      expect(novelHeatLevel(1, 100000), 1);
    });

    test('热力分桶丢掉 0 秒日，其余映射档位', () {
      final levels = novelHeatLevels(<String, int>{
        '2026-11-20': 0,
        '2026-11-21': 100,
        '2026-11-22': 400,
      });
      expect(levels.containsKey('2026-11-20'), isFalse);
      expect(levels['2026-11-21'], 1);
      expect(levels['2026-11-22'], 4);
    });

    test('柱状图补齐连续 N 天，缺数据填 0，末位是 end 当天', () {
      final buckets = novelBarBuckets(
        <String, int>{'2026-11-24': 120, '2026-11-25': 60},
        end: DateTime(2026, 11, 25),
        count: 7,
      );
      expect(buckets, hasLength(7));
      expect(buckets.first.day, '2026-11-19');
      expect(buckets.last.day, '2026-11-25');
      expect(buckets.last.seconds, 60);
      expect(buckets[5].seconds, 120);
      expect(buckets[0].seconds, 0);
      // 跨月也对（10-30 往前 7 天跨到 10 月）。
      final crossMonth = novelBarBuckets(
        const <String, int>{},
        end: DateTime(2026, 11, 2),
        count: 5,
      );
      expect(crossMonth.first.day, '2026-10-29');
      expect(crossMonth.last.day, '2026-11-02');
    });

    test('日键解析与坏数据兜底', () {
      expect(novelDayStart('2026-11-25'), DateTime(2026, 11, 25));
      expect(() => novelDayStart('bad'), throwsFormatException);
      expect(novelDayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('章节显示名', () {
    test('章名不带章号时拼上阿拉伯数字章号', () {
      expect(
        novelChapterLabel(chapterIndex: 7, chapterName: '红岸之三'),
        '第 7 章 · 红岸之三',
      );
      expect(novelChapterLabel(chapterIndex: 3, chapterName: ''), '第 3 章');
    });

    test('章名自带章号（阿拉伯/中文/英文）时不重复拼', () {
      expect(novelChapterLabel(chapterIndex: 3, chapterName: '第 3 章'), '第 3 章');
      expect(
        novelChapterLabel(chapterIndex: 5, chapterName: '第五章 夜航'),
        '第五章 夜航',
      );
      expect(
        novelChapterLabel(chapterIndex: 2, chapterName: 'Chapter 2 The End'),
        'Chapter 2 The End',
      );
    });

    test('章号 0（未知）走哨兵文案，不编章号', () {
      expect(novelChapterLabel(chapterIndex: 0, chapterName: '序章'), '章号未知');
    });
  });
}
