/// 采集本机快照：把本地库读成一份 [NovelBackupDocument]。
///
/// 快照与远端文档**同一个类型**，所以合并就是两个文档相比，不需要第二套模型。
/// 采集是只读的，失败一条不影响其余（单条坏数据跳过，不让整包报废）。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_plan.dart';
import 'package:mimao/novel/backup/novel_tombstone_service.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_projection.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_reader_position.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart'
    show NovelSourceStorage;

/// 备份文件里带的设置键（白名单；凭据与设备身份由
/// [novelBackupNeverExportedPrefKeys] 挡在外面）。
const List<String> novelBackupPrefKeys = <String>[
  ..._sharedFirst,
  ..._deviceNext,
];

const List<String> _sharedFirst = <String>[
  novelPrefReaderSettings,
  novelPrefReaderFontSize,
  novelPrefReaderBookSettings,
];

const List<String> _deviceNext = <String>[
  novelPrefGoalMinutes,
  novelPrefShelfLayout,
  novelPrefShelfColumns,
  novelPrefShelfSort,
  novelPrefShelfView,
  novelPrefShelfOrder,
  novelPrefHomeModules,
];

/// 采集本机全量快照。
Future<NovelBackupDocument> collectNovelBackupSnapshot({
  required NovelDb db,
  NovelSourceStorage? sourceStorage,
  NovelPrefsApi? prefs,
  String? deviceId,
  String deviceName = '',
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final device = deviceId ?? await db.ensureDeviceId();

  final seriesNames = <int, String>{
    for (final row in await db.select(db.novelSeriesEntries).get())
      row.id: row.name,
  };

  final collects = <NovelBackupCollect>[];
  for (final row in await db.select(db.novelCollectEntries).get()) {
    final book =
        novelSummaryFromPayload(row.payload) ??
        NovelSummary(
          id: row.id,
          title: row.title,
          coverUrl: row.coverUrl ?? '',
        );
    collects.add(
      NovelBackupCollect(
        book: book,
        groupName: row.groupName,
        note: row.note,
        seriesName: row.seriesId == null ? null : seriesNames[row.seriesId!],
        updatedAt: row.collectedAt,
      ),
    );
  }

  final histories = <NovelBackupHistory>[];
  for (final row in await db.select(db.novelHistoryEntries).get()) {
    histories.add(
      NovelBackupHistory(
        book:
            novelSummaryFromPayload(row.payload) ??
            NovelSummary(
              id: row.id,
              title: row.title,
              coverUrl: row.coverUrl ?? '',
            ),
        chapterIndex: row.chapterIndex,
        chapterCount: row.chapterCount,
        readCount: row.readCount,
        openedAt: row.openedAt,
      ),
    );
  }

  final progress = _mergeProgress(
    histories: histories,
    positions: await _readReaderPositions(prefs),
  );

  final bookmarks = <NovelBackupBookmark>[];
  for (final row in await db.select(db.novelBookmarkEntries).get()) {
    bookmarks.add(
      NovelBackupBookmark(
        bookId: row.bookId,
        sourceKey: row.sourceKey,
        bookTitle: row.bookTitle,
        bookAuthor: row.bookAuthor,
        bookUrl: row.bookUrl,
        chapterIndex: row.chapterIndex,
        paragraph: row.paragraph,
        charOffset: row.charOffset,
        chapterName: row.chapterName,
        excerpt: row.excerpt,
        unresolved: row.unresolved,
        createdAt: row.createdAt,
      ),
    );
  }

  final markings = <NovelBackupMarking>[];
  for (final row in await db.select(db.novelMarkingEntries).get()) {
    markings.add(
      NovelBackupMarking(
        bookId: row.bookId,
        sourceKey: row.sourceKey,
        bookTitle: row.bookTitle,
        bookAuthor: row.bookAuthor,
        bookUrl: row.bookUrl,
        chapterIndex: row.chapterIndex,
        paragraph: row.paragraph,
        startOffset: row.startOffset,
        endOffset: row.endOffset,
        chapterName: row.chapterName,
        styleJson: row.styleJson,
        note: row.note,
        unresolved: row.unresolved,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      ),
    );
  }

  final readRecords = <NovelBackupReadRecord>[];
  for (final row in await db.select(db.novelReadRecords).get()) {
    if (row.seconds <= 0) continue;
    readRecords.add(
      NovelBackupReadRecord(
        deviceId: row.deviceId,
        bookId: row.bookId,
        bookTitle: row.bookTitle,
        chapterIndex: row.chapterIndex,
        chapterName: row.chapterName,
        day: row.day,
        seconds: row.seconds,
        firstReadAt: row.firstReadAt,
        lastReadAt: row.lastReadAt,
      ),
    );
  }

  final tombstones = pruneNovelTombstones(
    await NovelTombstoneService(db).load(now: at),
    now: at,
  );

  final sources = <NovelBookSource>[];
  final storage = sourceStorage;
  if (storage != null) {
    try {
      sources.addAll(await storage.loadAll());
    } on Object {
      // 书源目录读失败不该让整份快照失败。
    }
  }

  final searchKeywords = <String>[];
  for (final row
      in await (db.select(db.novelSearchTerms)
            ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
            ..limit(500))
          .get()) {
    searchKeywords.add(row.keyword);
  }

  final prefValues = <String, String>{};
  final prefsApi = prefs;
  if (prefsApi != null) {
    for (final key in novelBackupPrefKeys) {
      if (novelBackupNeverExportedPrefKeys.contains(key)) continue;
      final value = await prefsApi.read(key);
      if (value != null) prefValues[key] = value;
    }
  }

  return NovelBackupDocument(
    collects: collects,
    histories: histories,
    searchKeywords: searchKeywords,
    sources: sources,
    prefs: prefValues,
    exportedAt: at,
    deviceId: device,
    deviceName: deviceName,
    progress: progress,
    series: <NovelBackupSeries>[
      for (final row in await db.select(db.novelSeriesEntries).get())
        NovelBackupSeries(name: row.name, createdAt: row.createdAt),
    ],
    bookmarks: bookmarks,
    markings: markings,
    readRecords: readRecords,
    tombstones: tombstones,
  );
}

/// 章级进度 + 章内位置合成「每本一行」。
///
/// 章号口径：`novel_history.chapter_index` 是 1 起；`NovelLocator.chapterIndex`
/// 是 0 起——合成时 +1 对齐，落库时再由调用方换回各自口径。
List<NovelBackupProgress> _mergeProgress({
  required List<NovelBackupHistory> histories,
  required Map<String, _PositionEntry> positions,
}) {
  final merged = <String, NovelBackupProgress>{};

  void put(NovelBackupProgress incoming) {
    final key = incoming.key;
    final existing = merged[key];
    if (existing == null) {
      merged[key] = incoming;
      return;
    }
    final chapter = incoming.chapterIndex > existing.chapterIndex
        ? incoming.chapterIndex
        : existing.chapterIndex;
    final locator = _newerStamp(incoming.updatedAt, existing.updatedAt)
        ? incoming.locator ?? existing.locator
        : existing.locator ?? incoming.locator;
    final stamp = _newerStamp(incoming.updatedAt, existing.updatedAt)
        ? incoming.updatedAt
        : existing.updatedAt;
    merged[key] = NovelBackupProgress(
      bookId: existing.bookId,
      sourceKey: existing.sourceKey,
      chapterIndex: chapter,
      chapterCount: existing.chapterCount >= incoming.chapterCount
          ? existing.chapterCount
          : incoming.chapterCount,
      locator: locator,
      updatedAt: stamp,
    );
  }

  for (final history in histories) {
    if (history.chapterIndex <= 0) continue;
    put(
      NovelBackupProgress(
        bookId: history.book.id,
        sourceKey: history.book.sourceKey,
        chapterIndex: history.chapterIndex,
        chapterCount: history.chapterCount,
        updatedAt: history.openedAt,
      ),
    );
  }

  for (final entry in positions.values) {
    final locator = entry.locator;
    put(
      NovelBackupProgress(
        bookId: entry.bookId,
        sourceKey: entry.sourceKey,
        chapterIndex: locator.chapterIndex + 1,
        locator: locator,
        updatedAt: entry.updatedAt,
      ),
    );
  }

  return merged.values.toList(growable: false);
}

bool _newerStamp(DateTime? left, DateTime? right) {
  if (left == null) return false;
  if (right == null) return true;
  return left.isAfter(right);
}

class _PositionEntry {
  const _PositionEntry({
    required this.bookId,
    required this.sourceKey,
    required this.locator,
    this.updatedAt,
  });

  final String bookId;
  final String sourceKey;
  final NovelLocator locator;
  final DateTime? updatedAt;
}

/// 读模块 kv 的 `reader_positions`（键是 `sourceKey|bookId`，老数据只有 bookId）。
Future<Map<String, _PositionEntry>> _readReaderPositions(
  NovelPrefsApi? prefs,
) async {
  final api = prefs;
  if (api == null) return const <String, _PositionEntry>{};
  final raw = await api.read(novelPrefReaderPositions);
  if (raw == null || raw.trim().isEmpty) {
    return const <String, _PositionEntry>{};
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return const <String, _PositionEntry>{};
  }
  if (decoded is! Map) return const <String, _PositionEntry>{};

  final result = <String, _PositionEntry>{};
  for (final entry in decoded.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final map = Map<String, Object?>.from(value);
    final locator = NovelLocator.fromJson(map['locator']);
    if (locator == null) continue;
    final storageKey = '${entry.key}';
    final split = storageKey.indexOf('|');
    final sourceKey = split > 0 ? storageKey.substring(0, split) : '';
    final bookId = split > 0 ? storageKey.substring(split + 1) : storageKey;
    if (bookId.isEmpty) continue;
    final stamp = map['updatedAt'];
    result[storageKey] = _PositionEntry(
      bookId: bookId,
      sourceKey: sourceKey,
      locator: locator,
      updatedAt: stamp is num
          ? DateTime.fromMillisecondsSinceEpoch(stamp.toInt())
          : null,
    );
  }
  return result;
}

/// 位置存储键（与 [NovelReaderPositionStore.keyFor] 同口径，导出给执行层复用）。
String novelBackupPositionKey(String bookId, {String sourceKey = ''}) =>
    NovelReaderPositionStore.keyFor(bookId, sourceKey: sourceKey);
