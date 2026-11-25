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

/// 日键 → 当天零点（本地）。解析失败抛 [FormatException]。
DateTime novelDayStart(String dayKey) {
  final parts = dayKey.split('-');
  if (parts.length != 3) throw FormatException('bad day key: $dayKey');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime _addDays(DateTime day, int delta) =>
    DateTime(day.year, day.month, day.day + delta);

/// 最长连续阅读天数（[dayKeys] 可含重复；按自然日算）。
int novelLongestStreak(Iterable<String> dayKeys) {
  final days = dayKeys.toSet().map(novelDayStart).toList()..sort();
  var best = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    if (previous != null && _addDays(previous, 1) == day) {
      run += 1;
    } else {
      run = 1;
    }
    if (run > best) best = run;
    previous = day;
  }
  return best;
}

/// 当前连续阅读天数：从今天往回数；今天还没读则从昨天起算
/// （一天没过完不该显示「连续中断」）。今天、昨天都没读则为 0。
int novelCurrentStreak(Iterable<String> dayKeys, {DateTime? today}) {
  final keys = dayKeys.toSet();
  var cursor = novelDayStart(novelDayKey(today ?? DateTime.now()));
  if (!keys.contains(novelDayKey(cursor))) {
    cursor = _addDays(cursor, -1);
  }
  var streak = 0;
  while (keys.contains(novelDayKey(cursor))) {
    streak += 1;
    cursor = _addDays(cursor, -1);
  }
  return streak;
}

/// 热力图档位 0..4：0 秒 = 0 档；其余按当天占最大值的比例分四档。
///
/// 用相对档位而不是固定分钟阈值：不同人的阅读量差一个数量级，固定阈值
/// 会让重度用户整年全是最深色、轻度用户全年空白。
int novelHeatLevel(int seconds, int maxSeconds) {
  if (seconds <= 0 || maxSeconds <= 0) return 0;
  final ratio = seconds / maxSeconds;
  final level = (ratio * 4).ceil();
  return level.clamp(1, 4);
}

/// 日 → 秒 映射 → 档位映射（供热力图分桶；0 秒日不进结果）。
Map<String, int> novelHeatLevels(Map<String, int> daySeconds) {
  final maxSeconds = daySeconds.values.fold<int>(0, (a, b) => a > b ? a : b);
  return <String, int>{
    for (final entry in daySeconds.entries)
      if (entry.value > 0) entry.key: novelHeatLevel(entry.value, maxSeconds),
  };
}

/// 柱状图桶：连续 [count] 天，缺数据补 0，最后一天是 [end] 的本地日。
List<NovelBarBucket> novelBarBuckets(
  Map<String, int> daySeconds, {
  required DateTime end,
  required int count,
}) {
  final base = novelDayStart(novelDayKey(end));
  return <NovelBarBucket>[
    for (var offset = count - 1; offset >= 0; offset--)
      _bucketFor(daySeconds, _addDays(base, -offset)),
  ];
}

NovelBarBucket _bucketFor(Map<String, int> daySeconds, DateTime day) {
  final key = novelDayKey(day);
  return NovelBarBucket(day: key, seconds: daySeconds[key] ?? 0);
}

/// 阅读统计与模块 kv 的真实实现。
///
/// 统计只读内部库的 `novel_read_record`（设备 × 书 × 章 × 日）。本机聚合视图
/// 就是「deviceId = 本机」的过滤结果：首页/我的页继续走 [snapshot]，统计页走
/// [overview] / [timeline] / [bookChapters] / [heatmapSeconds]。不按章节数
/// 估算分钟，也不把别的设备的数据混进本机数字。
class NovelStatsService implements NovelStatsApi, NovelPrefsApi {
  NovelStatsService(this.db, {String? deviceId}) : _injectedDeviceId = deviceId;

  final NovelDb db;

  /// 测试/同步场景可固定设备 ID；生产为 null，首次写入时生成并落 kv。
  final String? _injectedDeviceId;

  Future<String>? _deviceIdFuture;

  Future<String> get _deviceId => _deviceIdFuture ??= _injectedDeviceId != null
      ? Future<String>.value(_injectedDeviceId)
      : db.ensureDeviceId();

  @override
  Future<NovelStats> snapshot() async {
    final historyCount = (await db.select(db.novelHistoryEntries).get()).length;
    final collectCount = (await db.select(db.novelCollectEntries).get()).length;
    final deviceId = await _deviceId;
    final rows = await (db.select(
      db.novelReadRecords,
    )..where((t) => t.deviceId.equals(deviceId))).get();
    final totalSeconds = rows.fold<int>(0, (sum, row) => sum + row.seconds);
    final today = novelDayKey(DateTime.now());
    var todaySeconds = 0;
    for (final row in rows) {
      if (row.day == today) todaySeconds += row.seconds;
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
  Future<NovelStatsOverview> overview({DateTime? today}) async {
    final deviceId = await _deviceId;
    final rows = await (db.select(
      db.novelReadRecords,
    )..where((t) => t.deviceId.equals(deviceId))).get();
    final totalSeconds = rows.fold<int>(0, (sum, row) => sum + row.seconds);
    final daySeconds = _daySeconds(rows);
    final activeDays = daySeconds.length;
    final bookIds = <String>{
      for (final row in rows)
        if (row.bookId.isNotEmpty && row.seconds > 0) row.bookId,
    };
    return NovelStatsOverview(
      totalSeconds: totalSeconds,
      booksRead: bookIds.length,
      activeDays: activeDays,
      averageSecondsPerDay: activeDays == 0 ? 0 : totalSeconds ~/ activeDays,
      currentStreak: novelCurrentStreak(daySeconds.keys, today: today),
      longestStreak: novelLongestStreak(daySeconds.keys),
      todaySeconds: daySeconds[novelDayKey(today ?? DateTime.now())] ?? 0,
    );
  }

  @override
  Future<List<NovelReadDay>> timeline({int limitDays = 0}) async {
    final deviceId = await _deviceId;
    final rows =
        await (db.select(db.novelReadRecords)
              ..where((t) => t.deviceId.equals(deviceId))
              ..orderBy([
                (t) => OrderingTerm.desc(t.day),
                (t) => OrderingTerm.desc(t.lastReadAt),
              ]))
            .get();
    final byDay = <String, List<NovelReadRecordRow>>{};
    for (final row in rows) {
      byDay.putIfAbsent(row.day, () => <NovelReadRecordRow>[]).add(row);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final limited = limitDays > 0 && days.length > limitDays
        ? days.take(limitDays)
        : days;
    return <NovelReadDay>[
      for (final day in limited) _readDay(day, byDay[day]!),
    ];
  }

  @override
  Future<List<NovelChapterStats>> bookChapters(String bookId) async {
    if (bookId.isEmpty) return const <NovelChapterStats>[];
    final deviceId = await _deviceId;
    final rows =
        await (db.select(db.novelReadRecords)..where(
              (t) =>
                  t.deviceId.equals(deviceId) &
                  t.bookId.equals(bookId) &
                  t.chapterIndex.isBiggerThanValue(0),
            ))
            .get();
    final byChapter = <int, List<NovelReadRecordRow>>{};
    for (final row in rows) {
      byChapter.putIfAbsent(row.chapterIndex, () => []).add(row);
    }
    final indexes = byChapter.keys.toList()..sort();
    return <NovelChapterStats>[
      for (final index in indexes) _chapterStats(index, byChapter[index]!),
    ];
  }

  @override
  Future<Map<String, int>> heatmapSeconds({required int year}) async {
    final deviceId = await _deviceId;
    final rows = await (db.select(
      db.novelReadRecords,
    )..where((t) => t.deviceId.equals(deviceId) & t.day.like('$year-%'))).get();
    final result = <String, int>{};
    for (final row in rows) {
      if (row.seconds <= 0) continue;
      result[row.day] = (result[row.day] ?? 0) + row.seconds;
    }
    return result;
  }

  @override
  Future<void> addReadingTime(
    Duration duration, {
    DateTime? at,
    NovelReadTarget? target,
  }) async {
    final delta = duration.inSeconds;
    if (delta <= 0) return;
    final now = at ?? DateTime.now();
    final key = novelDayKey(now);
    final bookId = target?.bookId ?? '';
    final chapterIndex = target?.chapterIndex ?? 0;
    final deviceId = await _deviceId;
    await db.transaction(() async {
      final existing =
          await (db.select(db.novelReadRecords)..where(
                (t) =>
                    t.deviceId.equals(deviceId) &
                    t.bookId.equals(bookId) &
                    t.chapterIndex.equals(chapterIndex) &
                    t.day.equals(key),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.novelReadRecords)
            .insert(
              NovelReadRecordsCompanion.insert(
                deviceId: deviceId,
                bookId: bookId,
                bookTitle: Value<String>(target?.bookTitle ?? ''),
                chapterIndex: Value<int>(chapterIndex),
                chapterName: Value<String>(target?.chapterName ?? ''),
                day: key,
                seconds: Value<int>(delta),
                firstReadAt: now,
                lastReadAt: now,
              ),
            );
      } else {
        await (db.update(db.novelReadRecords)..where(
              (t) =>
                  t.deviceId.equals(deviceId) &
                  t.bookId.equals(bookId) &
                  t.chapterIndex.equals(chapterIndex) &
                  t.day.equals(key),
            ))
            .write(
              NovelReadRecordsCompanion(
                seconds: Value<int>(existing.seconds + delta),
                lastReadAt: Value<DateTime>(now),
                // 标题/章名后到补空：换源后书名可能变，取最近一次非空。
                bookTitle: Value<String>(
                  (target?.bookTitle ?? '').isEmpty
                      ? existing.bookTitle
                      : target!.bookTitle,
                ),
                chapterName: Value<String>(
                  (target?.chapterName ?? '').isEmpty
                      ? existing.chapterName
                      : target!.chapterName,
                ),
                firstReadAt: Value<DateTime>(
                  now.isBefore(existing.firstReadAt)
                      ? now
                      : existing.firstReadAt,
                ),
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

  Map<String, int> _daySeconds(List<NovelReadRecordRow> rows) {
    final result = <String, int>{};
    for (final row in rows) {
      if (row.seconds <= 0) continue;
      result[row.day] = (result[row.day] ?? 0) + row.seconds;
    }
    return result;
  }

  NovelReadDay _readDay(String day, List<NovelReadRecordRow> rows) {
    final byBook = <String, List<NovelReadRecordRow>>{};
    for (final row in rows) {
      byBook.putIfAbsent(row.bookId, () => <NovelReadRecordRow>[]).add(row);
    }
    final books = <NovelReadBook>[
      for (final entry in byBook.entries) _readBook(entry.key, entry.value),
    ]..sort((a, b) => b.seconds.compareTo(a.seconds));
    return NovelReadDay(
      day: day,
      seconds: rows.fold<int>(0, (sum, row) => sum + row.seconds),
      books: books,
    );
  }

  NovelReadBook _readBook(String bookId, List<NovelReadRecordRow> rows) {
    var seconds = 0;
    var chapterIndex = 0;
    var chapterName = '';
    var bookTitle = '';
    DateTime? firstReadAt;
    DateTime? lastReadAt;
    for (final row in rows) {
      seconds += row.seconds;
      if (row.chapterIndex >= chapterIndex) {
        chapterIndex = row.chapterIndex;
        if (row.chapterName.isNotEmpty) chapterName = row.chapterName;
      }
      if (row.bookTitle.isNotEmpty) bookTitle = row.bookTitle;
      if (firstReadAt == null || row.firstReadAt.isBefore(firstReadAt)) {
        firstReadAt = row.firstReadAt;
      }
      if (lastReadAt == null || row.lastReadAt.isAfter(lastReadAt)) {
        lastReadAt = row.lastReadAt;
      }
    }
    return NovelReadBook(
      bookId: bookId,
      title: bookTitle,
      seconds: seconds,
      chapterIndex: chapterIndex,
      chapterName: chapterName,
      lastReadAt: lastReadAt,
    );
  }

  NovelChapterStats _chapterStats(
    int chapterIndex,
    List<NovelReadRecordRow> rows,
  ) {
    var seconds = 0;
    var chapterName = '';
    DateTime? firstReadAt;
    DateTime? lastReadAt;
    for (final row in rows) {
      seconds += row.seconds;
      if (row.chapterName.isNotEmpty) chapterName = row.chapterName;
      if (firstReadAt == null || row.firstReadAt.isBefore(firstReadAt)) {
        firstReadAt = row.firstReadAt;
      }
      if (lastReadAt == null || row.lastReadAt.isAfter(lastReadAt)) {
        lastReadAt = row.lastReadAt;
      }
    }
    return NovelChapterStats(
      chapterIndex: chapterIndex,
      chapterName: chapterName,
      seconds: seconds,
      firstReadAt: firstReadAt,
      lastReadAt: lastReadAt,
    );
  }
}
