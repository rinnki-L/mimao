import 'package:drift/drift.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/novel_db.dart';

/// 本地日键（`yyyy-MM-dd`）。阅读时长按用户本地日切分，跨时区不共享。
String novelDayKey(DateTime at) {
  final local = at.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// 阅读统计与模块 kv 的真实实现。
///
/// 统计只读内部库：书籍数看 `novel_history`，收藏数看 `novel_collect`，
/// 时长读按天聚合表 [NovelReadingDays]。阅读页尚未接入时这些值都是真实的 0，
/// 不按章节数估算分钟。
class NovelStatsService implements NovelStatsApi, NovelPrefsApi {
  NovelStatsService(this.db);

  final NovelDb db;

  @override
  Future<NovelStats> snapshot() async {
    final historyCount = (await db.select(db.novelHistoryEntries).get()).length;
    final collectCount = (await db.select(db.novelCollectEntries).get()).length;
    final days = await db.select(db.novelReadingDays).get();
    final totalSeconds = days.fold<int>(0, (sum, row) => sum + row.seconds);
    final today = novelDayKey(DateTime.now());
    var todaySeconds = 0;
    for (final row in days) {
      if (row.day == today) todaySeconds = row.seconds;
    }
    final rawGoal = await db.readPref(novelPrefGoalMinutes);
    final goal = int.tryParse(rawGoal ?? '') ?? novelDefaultGoalMinutes;
    return NovelStats(
      booksRead: historyCount,
      collected: collectCount,
      totalSeconds: totalSeconds,
      todaySeconds: todaySeconds,
      goalMinutes: goal < 0 ? novelDefaultGoalMinutes : goal,
    );
  }

  @override
  Future<void> addReadingTime(Duration duration, {DateTime? at}) async {
    final delta = duration.inSeconds;
    if (delta <= 0) return;
    final key = novelDayKey(at ?? DateTime.now());
    await db.transaction(() async {
      final existing = await (db.select(
        db.novelReadingDays,
      )..where((t) => t.day.equals(key))).getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.novelReadingDays)
            .insert(
              NovelReadingDaysCompanion.insert(
                day: key,
                seconds: Value<int>(delta),
                updatedAt: DateTime.now(),
              ),
            );
      } else {
        await (db.update(
          db.novelReadingDays,
        )..where((t) => t.day.equals(key))).write(
          NovelReadingDaysCompanion(
            seconds: Value<int>(existing.seconds + delta),
            updatedAt: Value<DateTime>(DateTime.now()),
          ),
        );
      }
    });
  }

  @override
  Future<void> setGoalMinutes(int minutes) => db.writePref(
    novelPrefGoalMinutes,
    (minutes < 0 ? 0 : minutes).toString(),
  );

  @override
  Future<String?> read(String key) => db.readPref(key);

  @override
  Future<void> write(String key, String value) => db.writePref(key, value);
}
