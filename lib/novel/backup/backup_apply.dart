/// 执行恢复计划 + 精确撤销。
///
/// 执行前把**每一行的原值**写进 journal（本地文件，最多留 3 份）；撤销按 journal
/// 反向回滚，并且只回滚"当前值仍等于本次写入值"的行——恢复之后用户又改过的
/// 数据不会被连坐抹掉。
///
/// 落库一律走 `NovelDb` + 各服务的**唯一写入口**（收藏/历史写内部表后调
/// `syncNovelProjection`），不另开一套旁路，否则统一书架会和内部库对不上。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:mimao/core/library.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_file_store.dart';
import 'package:mimao/novel/backup/backup_plan.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_projection.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_reader_position.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart'
    show NovelSourceStorage;

/// 撤销 journal 的一个文件名前缀。
const String novelBackupUndoPrefix = 'undo-';

/// 最多保留几份撤销 journal（再多也只是占空间）。
const int novelBackupUndoKeep = 3;

/// journal 里的一条：某张逻辑表某一行的前后值。
class NovelBackupJournalEntry {
  const NovelBackupJournalEntry({
    required this.table,
    required this.key,
    required this.before,
    required this.after,
  });

  /// `collect` / `history` / `position` / `series` / `bookmark` / `marking` /
  /// `readRecord` / `tombstone` / `source` / `searchKeyword` / `pref`。
  final String table;

  /// 定位这一行所需的自然键。
  final Map<String, Object?> key;

  /// 原值；null = 原本不存在。
  final Map<String, Object?>? before;

  /// 本次写入的值。
  final Map<String, Object?>? after;

  Map<String, Object?> toJson() => <String, Object?>{
    'table': table,
    'key': key,
    if (before != null) 'before': before,
    if (after != null) 'after': after,
  };

  factory NovelBackupJournalEntry.fromJson(Map<String, Object?> json) =>
      NovelBackupJournalEntry(
        table: '${json['table'] ?? ''}',
        key: Map<String, Object?>.from(
          json['key'] as Map? ?? const <String, Object?>{},
        ),
        before: json['before'] is Map
            ? Map<String, Object?>.from(json['before']! as Map)
            : null,
        after: json['after'] is Map
            ? Map<String, Object?>.from(json['after']! as Map)
            : null,
      );
}

/// 一次恢复的撤销凭据。
class NovelBackupJournal {
  const NovelBackupJournal({
    required this.startedAt,
    required this.deviceId,
    required this.entries,
    this.label = '',
  });

  final DateTime startedAt;
  final String deviceId;
  final List<NovelBackupJournalEntry> entries;

  /// 恢复来源的一句描述（"来自 Windows-PC · 2026-11-25 15:02"）。
  final String label;

  String encode() => jsonEncode(<String, Object?>{
    'version': 1,
    'startedAt': startedAt.toIso8601String(),
    'deviceId': deviceId,
    'label': label,
    'entries': <Object?>[for (final entry in entries) entry.toJson()],
  });

  static NovelBackupJournal? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, Object?>.from(decoded);
      final entries = <NovelBackupJournalEntry>[];
      final rawEntries = map['entries'];
      if (rawEntries is List) {
        for (final item in rawEntries) {
          if (item is! Map) continue;
          entries.add(
            NovelBackupJournalEntry.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
      return NovelBackupJournal(
        startedAt:
            DateTime.tryParse('${map['startedAt'] ?? ''}') ?? DateTime.now(),
        deviceId: '${map['deviceId'] ?? ''}',
        label: '${map['label'] ?? ''}',
        entries: entries,
      );
    } on Object {
      return null;
    }
  }

  /// 这次恢复实际改了多少行。
  int get rowCount => entries.length;
}

/// 执行结果。
class NovelBackupApplyReport {
  const NovelBackupApplyReport({
    required this.applied,
    required this.failed,
    required this.errors,
    required this.journalName,
  });

  final int applied;
  final int failed;
  final List<String> errors;

  /// 撤销时用的 journal 文件名；null = 没有改动、不生成 journal。
  final String? journalName;
}

/// 撤销结果。
class NovelBackupUndoReport {
  const NovelBackupUndoReport({
    required this.restored,
    required this.skipped,
    required this.errors,
  });

  final int restored;

  /// 恢复之后又被改过、因此没有回滚的行数。
  final int skipped;
  final List<String> errors;
}

/// 计划里各逻辑表的执行顺序：系列先建，收藏/历史次之，进度再次（依赖书已存在），
/// 其余顺序无关。
const Map<NovelBackupTarget, int> _targetOrder = <NovelBackupTarget, int>{
  NovelBackupTarget.series: 0,
  NovelBackupTarget.collect: 1,
  NovelBackupTarget.progress: 2,
  NovelBackupTarget.bookmark: 3,
  NovelBackupTarget.marking: 4,
  NovelBackupTarget.readRecord: 5,
  NovelBackupTarget.tombstone: 6,
  NovelBackupTarget.source: 7,
  NovelBackupTarget.searchKeyword: 8,
  NovelBackupTarget.pref: 9,
};

class NovelBackupApplier {
  NovelBackupApplier({
    required this.db,
    this.library,
    this.sourceStorage,
    this.prefs,
    this.files,
    this.deviceId,
  });

  final NovelDb db;
  final LibraryRepository? library;
  final NovelSourceStorage? sourceStorage;
  final NovelPrefsApi? prefs;
  final NovelBackupFileStore? files;
  final String? deviceId;

  Future<String> _device() async => deviceId ?? await db.ensureDeviceId();

  // ── 执行 ────────────────────────────────────────────────────────────────

  /// 执行计划并写 journal。单条失败不中断，汇总进 [NovelBackupApplyReport]。
  ///
  /// [writeJournal] 为 false 时不写撤销记录与兜底快照（进度同步这种高频、小范围
  /// 的写不做整套回滚——它的合并规则本身就是幂等的）。
  Future<NovelBackupApplyReport> apply(
    NovelBackupPlan plan, {
    String label = '',
    DateTime? now,
    bool writeJournal = true,
  }) async {
    final at = now ?? DateTime.now();
    final device = await _device();
    final ops = <NovelBackupOp>[...plan.ops]
      ..sort(
        (a, b) => (_targetOrder[a.target] ?? 99).compareTo(
          _targetOrder[b.target] ?? 99,
        ),
      );
    final entries = <NovelBackupJournalEntry>[];
    final errors = <String>[];
    final touchedBooks = <String>{};
    var applied = 0;

    for (final op in ops) {
      try {
        final added = await _applyOp(
          op,
          entries,
          at: at,
          touched: touchedBooks,
        );
        applied += added;
      } on Object catch (error) {
        errors.add('${op.target.label}「${op.label}」失败：$error');
      }
    }

    await _syncProjections(touchedBooks);

    String? journalName;
    if (writeJournal && entries.isNotEmpty && files != null) {
      journalName = '$novelBackupUndoPrefix${at.millisecondsSinceEpoch}.json';
      final journal = NovelBackupJournal(
        startedAt: at,
        deviceId: device,
        label: label,
        entries: entries,
      );
      await files!.write(journalName, journal.encode());
      await _trimJournals();
    }
    return NovelBackupApplyReport(
      applied: applied,
      failed: errors.length,
      errors: errors,
      journalName: journalName,
    );
  }

  Future<int> _applyOp(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
    required Set<String> touched,
  }) async {
    switch (op.target) {
      case NovelBackupTarget.series:
        return _applySeries(op, entries, at: at);
      case NovelBackupTarget.collect:
        return _applyCollect(op, entries, at: at, touched: touched);
      case NovelBackupTarget.progress:
        return _applyProgress(op, entries, at: at, touched: touched);
      case NovelBackupTarget.bookmark:
        return _applyBookmark(op, entries, at: at);
      case NovelBackupTarget.marking:
        return _applyMarking(op, entries, at: at);
      case NovelBackupTarget.readRecord:
        return _applyReadRecord(op, entries);
      case NovelBackupTarget.tombstone:
        return _applyTombstone(op, entries, at: at);
      case NovelBackupTarget.source:
        return _applySource(op, entries);
      case NovelBackupTarget.searchKeyword:
        return _applySearchKeyword(op, entries, at: at);
      case NovelBackupTarget.pref:
        return _applyPref(op, entries);
    }
  }

  Future<int> _applySeries(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
  }) async {
    final series = NovelBackupSeries.fromJson(op.payload);
    final existing = (await (db.select(
      db.novelSeriesEntries,
    )..where((t) => t.name.equals(series.name))).getSingleOrNull());
    if (existing != null) return 0;
    final row = <String, Object?>{
      'name': series.name,
      'createdAt': (series.createdAt ?? at).toIso8601String(),
    };
    final id = await db
        .into(db.novelSeriesEntries)
        .insert(
          NovelSeriesEntriesCompanion.insert(
            name: series.name,
            createdAt: series.createdAt ?? at,
          ),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'series',
        key: <String, Object?>{'name': series.name},
        before: null,
        after: <String, Object?>{...row, 'id': id},
      ),
    );
    return 1;
  }

  Future<int> _applyCollect(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
    required Set<String> touched,
  }) async {
    final collect = NovelBackupCollect.fromJson(op.payload);
    final book = collect.book;
    if (book.id.isEmpty) return 0;
    final existing = await db.collectRow(NovelRef(id: book.id));
    final seriesId = collect.seriesName == null
        ? existing?.seriesId
        : await _seriesIdFor(collect.seriesName!, at: at, entries: entries);
    final payload = jsonEncode(book.toJson());
    final row = <String, Object?>{
      'id': book.id,
      'title': book.title,
      'coverUrl': book.coverUrl.isEmpty ? (existing?.coverUrl) : book.coverUrl,
      'payload': payload,
      'groupName': collect.groupName ?? existing?.groupName,
      'note': collect.note.isEmpty ? (existing?.note ?? '') : collect.note,
      // 自定义封面是本机路径，绝不跟着备份走（`LESSON.md` §三）。
      'customCoverPath': existing?.customCoverPath,
      'seriesId': seriesId,
      'collectedAt': (collect.updatedAt ?? existing?.collectedAt ?? at)
          .toIso8601String(),
    };
    if (_sameRow(_collectRowJson(existing), row)) return 0;
    await db
        .into(db.novelCollectEntries)
        .insertOnConflictUpdate(
          NovelCollectEntriesCompanion.insert(
            id: book.id,
            title: book.title,
            coverUrl: Value<String?>(
              book.coverUrl.isEmpty ? existing?.coverUrl : book.coverUrl,
            ),
            payload: Value<String>(payload),
            groupName: Value<String?>(collect.groupName ?? existing?.groupName),
            note: Value<String>(
              collect.note.isEmpty ? (existing?.note ?? '') : collect.note,
            ),
            customCoverPath: Value<String?>(existing?.customCoverPath),
            seriesId: Value<int?>(seriesId),
            collectedAt: collect.updatedAt ?? existing?.collectedAt ?? at,
          ),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'collect',
        key: <String, Object?>{'id': book.id},
        before: _collectRowJson(existing),
        after: row,
      ),
    );
    touched.add(book.id);
    return 1;
  }

  Future<int> _applyProgress(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
    required Set<String> touched,
  }) async {
    final bookId = '${op.payload['bookId'] ?? ''}';
    if (bookId.isEmpty) return 0;
    final book = op.payload['book'] is Map
        ? NovelSummary.fromJson(
            Map<String, Object?>.from(op.payload['book']! as Map),
          )
        : null;
    final existing = await db.historyRow(NovelRef(id: bookId));
    final chapterIndex = op.payload['chapterIndex'] is num
        ? (op.payload['chapterIndex']! as num).toInt()
        : 0;
    final chapterCount = op.payload['chapterCount'] is num
        ? (op.payload['chapterCount']! as num).toInt()
        : 0;
    final readCount = op.payload['readCount'] is num
        ? (op.payload['readCount']! as num).toInt()
        : (existing?.readCount ?? 1);
    final openedAt =
        DateTime.tryParse('${op.payload['updatedAt'] ?? ''}') ??
        existing?.openedAt ??
        at;
    final title = book?.title ?? existing?.title ?? bookId;
    final row = <String, Object?>{
      'id': bookId,
      'title': title,
      'coverUrl': book == null || book.coverUrl.isEmpty
          ? existing?.coverUrl
          : book.coverUrl,
      'chapterIndex': chapterIndex,
      'chapterCount': chapterCount,
      'openedAt': openedAt.toIso8601String(),
      'readCount': readCount,
      'payload': book == null ? existing?.payload : jsonEncode(book.toJson()),
    };
    if (!_sameRow(_historyRowJson(existing), row)) {
      await db
          .into(db.novelHistoryEntries)
          .insertOnConflictUpdate(
            NovelHistoryEntriesCompanion.insert(
              id: bookId,
              title: title,
              coverUrl: Value<String?>(
                book == null || book.coverUrl.isEmpty
                    ? existing?.coverUrl
                    : book.coverUrl,
              ),
              chapterIndex: Value<int>(chapterIndex),
              chapterCount: Value<int>(chapterCount),
              openedAt: openedAt,
              readCount: Value<int>(readCount),
              payload: Value<String>(
                book == null
                    ? (existing?.payload ?? '{}')
                    : jsonEncode(book.toJson()),
              ),
            ),
          );
      entries.add(
        NovelBackupJournalEntry(
          table: 'history',
          key: <String, Object?>{'id': bookId},
          before: _historyRowJson(existing),
          after: row,
        ),
      );
    }
    touched.add(bookId);

    // 章内位置单独成一条 journal：它存在模块 kv 的一张 map 里。
    final locator = NovelLocator.fromJson(op.payload['locator']);
    if (locator != null) {
      await _applyPosition(bookId, locator, entries, at: at);
    }
    return 1;
  }

  Future<void> _applyPosition(
    String bookId,
    NovelLocator locator,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
  }) async {
    final api = prefs;
    if (api == null) return;
    final sourceKey = locator.sourceKey;
    final storageKey = NovelReaderPositionStore.keyFor(
      bookId,
      sourceKey: sourceKey,
    );
    final raw = await api.read(novelPrefReaderPositions);
    final map = _decodePositionMap(raw);
    final before = _mapOf(map[storageKey]);
    final position = NovelReaderPosition(
      chapterUrl: '',
      chapterId: '',
      chapterIndex: locator.chapterIndex,
      locator: locator,
    );
    final after = <String, Object?>{
      ...position.toJson(),
      'updatedAt': at.millisecondsSinceEpoch,
    };
    if (_sameRow(before, after)) return;
    map[storageKey] = after;
    await api.write(novelPrefReaderPositions, jsonEncode(map));
    entries.add(
      NovelBackupJournalEntry(
        table: 'position',
        key: <String, Object?>{'storageKey': storageKey},
        before: before,
        after: after,
      ),
    );
  }

  Future<int> _applyBookmark(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
  }) async {
    final item = NovelBackupBookmark.fromJson(op.payload);
    final existing = await _bookmarkRowOf(item);
    final row = <String, Object?>{
      'bookId': item.bookId,
      'sourceKey': item.sourceKey,
      'bookTitle': item.bookTitle,
      'bookAuthor': item.bookAuthor,
      'bookUrl': item.bookUrl,
      'chapterIndex': item.chapterIndex,
      'paragraph': item.paragraph,
      'charOffset': item.charOffset,
      'chapterName': item.chapterName,
      'excerpt': item.excerpt,
      'unresolved': item.unresolved,
      'createdAt': item.createdAt.toIso8601String(),
    };
    if (_sameRow(_bookmarkRowJson(existing), row)) return 0;
    if (existing != null) {
      await (db.delete(
        db.novelBookmarkEntries,
      )..where((t) => t.id.equals(existing.id))).go();
    }
    await db
        .into(db.novelBookmarkEntries)
        .insert(
          NovelBookmarkEntriesCompanion.insert(
            bookId: item.bookId,
            sourceKey: Value<String>(item.sourceKey),
            bookTitle: Value<String>(item.bookTitle),
            bookAuthor: Value<String>(item.bookAuthor),
            bookUrl: Value<String>(item.bookUrl),
            chapterIndex: item.chapterIndex,
            paragraph: Value<int>(item.paragraph),
            charOffset: Value<int>(item.charOffset),
            chapterName: Value<String>(item.chapterName),
            excerpt: Value<String>(item.excerpt),
            unresolved: Value<bool>(item.unresolved),
            createdAt: item.createdAt,
          ),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'bookmark',
        key: <String, Object?>{
          'bookId': item.bookId,
          'sourceKey': item.sourceKey,
          'chapterIndex': item.chapterIndex,
          'paragraph': item.paragraph,
          'charOffset': item.charOffset,
        },
        before: _bookmarkRowJson(existing),
        after: row,
      ),
    );
    return 1;
  }

  Future<int> _applyMarking(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
  }) async {
    final item = NovelBackupMarking.fromJson(op.payload);
    final existing = await _markingRowOf(item);
    final row = <String, Object?>{
      'bookId': item.bookId,
      'sourceKey': item.sourceKey,
      'bookTitle': item.bookTitle,
      'bookAuthor': item.bookAuthor,
      'bookUrl': item.bookUrl,
      'chapterIndex': item.chapterIndex,
      'paragraph': item.paragraph,
      'startOffset': item.startOffset,
      'endOffset': item.endOffset,
      'chapterName': item.chapterName,
      'styleJson': item.styleJson,
      'note': item.note,
      'unresolved': item.unresolved,
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
    };
    if (_sameRow(_markingRowJson(existing), row)) return 0;
    if (existing != null) {
      await (db.delete(
        db.novelMarkingEntries,
      )..where((t) => t.id.equals(existing.id))).go();
    }
    await db
        .into(db.novelMarkingEntries)
        .insert(
          NovelMarkingEntriesCompanion.insert(
            bookId: item.bookId,
            sourceKey: Value<String>(item.sourceKey),
            bookTitle: Value<String>(item.bookTitle),
            bookAuthor: Value<String>(item.bookAuthor),
            bookUrl: Value<String>(item.bookUrl),
            chapterIndex: item.chapterIndex,
            paragraph: Value<int>(item.paragraph),
            startOffset: Value<int>(item.startOffset),
            endOffset: Value<int>(item.endOffset),
            chapterName: Value<String>(item.chapterName),
            styleJson: Value<String>(item.styleJson),
            note: Value<String>(item.note),
            unresolved: Value<bool>(item.unresolved),
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
          ),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'marking',
        key: <String, Object?>{
          'bookId': item.bookId,
          'sourceKey': item.sourceKey,
          'chapterIndex': item.chapterIndex,
          'paragraph': item.paragraph,
          'startOffset': item.startOffset,
          'endOffset': item.endOffset,
        },
        before: _markingRowJson(existing),
        after: row,
      ),
    );
    return 1;
  }

  Future<int> _applyReadRecord(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries,
  ) async {
    final item = NovelBackupReadRecord.fromJson(op.payload);
    if (item.day.isEmpty) return 0;
    final key = <String, Object?>{
      'deviceId': item.deviceId,
      'bookId': item.bookId,
      'chapterIndex': item.chapterIndex,
      'day': item.day,
    };
    final existing =
        await (db.select(db.novelReadRecords)..where(
              (t) =>
                  t.deviceId.equals(item.deviceId) &
                  t.bookId.equals(item.bookId) &
                  t.chapterIndex.equals(item.chapterIndex) &
                  t.day.equals(item.day),
            ))
            .getSingleOrNull();
    final row = <String, Object?>{
      ...key,
      'bookTitle': item.bookTitle,
      'chapterName': item.chapterName,
      'seconds': item.seconds,
      'firstReadAt': item.firstReadAt.toIso8601String(),
      'lastReadAt': item.lastReadAt.toIso8601String(),
    };
    if (_sameRow(_readRecordRowJson(existing), row)) return 0;
    await db
        .into(db.novelReadRecords)
        .insertOnConflictUpdate(
          NovelReadRecordsCompanion.insert(
            deviceId: item.deviceId,
            bookId: item.bookId,
            bookTitle: Value<String>(item.bookTitle),
            chapterIndex: Value<int>(item.chapterIndex),
            chapterName: Value<String>(item.chapterName),
            day: item.day,
            seconds: Value<int>(item.seconds),
            firstReadAt: item.firstReadAt,
            lastReadAt: item.lastReadAt,
          ),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'readRecord',
        key: key,
        before: _readRecordRowJson(existing),
        after: row,
      ),
    );
    return 1;
  }

  Future<int> _applyTombstone(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
  }) async {
    if (op.action == NovelBackupAction.delete) {
      // 远端墓碑赢：删本地那条，并把墓碑记在本地。
      final kind = '${op.payload['kind'] ?? ''}';
      final localKey = '${op.payload['localKey'] ?? ''}';
      final removed = kind == novelTombstoneBookmark
          ? await _deleteBookmarkByKey(localKey, entries)
          : await _deleteMarkingByKey(localKey, entries);
      final tombstone = NovelBackupTombstone(
        kind: kind,
        key: '${op.payload['key'] ?? ''}',
        deviceId: '${op.payload['deviceId'] ?? await _device()}',
        deletedAt: DateTime.tryParse('${op.payload['deletedAt'] ?? ''}') ?? at,
      );
      final wrote = await _upsertTombstone(tombstone, entries);
      return removed + wrote;
    }
    final tombstone = NovelBackupTombstone.fromJson(op.payload);
    return _upsertTombstone(tombstone, entries);
  }

  Future<int> _upsertTombstone(
    NovelBackupTombstone tombstone,
    List<NovelBackupJournalEntry> entries,
  ) async {
    if (tombstone.kind.isEmpty || tombstone.key.isEmpty) return 0;
    final existing =
        await (db.select(db.novelTombstoneEntries)..where(
              (t) =>
                  t.kind.equals(tombstone.kind) &
                  t.targetKey.equals(tombstone.key),
            ))
            .getSingleOrNull();
    final row = <String, Object?>{
      'kind': tombstone.kind,
      'targetKey': tombstone.key,
      'deviceId': tombstone.deviceId,
      'deletedAt': tombstone.deletedAt.toIso8601String(),
    };
    if (_sameRow(_tombstoneRowJson(existing), row)) return 0;
    await db
        .into(db.novelTombstoneEntries)
        .insertOnConflictUpdate(
          NovelTombstoneEntriesCompanion.insert(
            kind: tombstone.kind,
            targetKey: tombstone.key,
            deviceId: Value<String>(tombstone.deviceId),
            deletedAt: tombstone.deletedAt,
          ),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'tombstone',
        key: <String, Object?>{
          'kind': tombstone.kind,
          'targetKey': tombstone.key,
        },
        before: _tombstoneRowJson(existing),
        after: row,
      ),
    );
    return 1;
  }

  Future<int> _applySource(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries,
  ) async {
    final storage = sourceStorage;
    if (storage == null) return 0;
    final source = NovelBookSource.fromJson(op.payload);
    if (source.key.isEmpty) return 0;
    final before = await _sourceJson(storage, source.key);
    await storage.saveAll(<NovelBookSource>[source]);
    final after = await _sourceJson(storage, source.key);
    if (_sameRow(before, after)) return 0;
    entries.add(
      NovelBackupJournalEntry(
        table: 'source',
        key: <String, Object?>{'key': source.key},
        before: before,
        after: after,
      ),
    );
    return 1;
  }

  Future<int> _applySearchKeyword(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries, {
    required DateTime at,
  }) async {
    final keyword = '${op.payload['keyword'] ?? ''}'.trim();
    if (keyword.isEmpty) return 0;
    final existing = await (db.select(
      db.novelSearchTerms,
    )..where((t) => t.keyword.equals(keyword))).getSingleOrNull();
    if (existing != null) return 0;
    await db
        .into(db.novelSearchTerms)
        .insert(
          NovelSearchTermsCompanion.insert(
            keyword: keyword,
            searchedAt: at,
            hits: const Value<int>(1),
          ),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'searchKeyword',
        key: <String, Object?>{'keyword': keyword},
        before: null,
        after: <String, Object?>{'keyword': keyword},
      ),
    );
    return 1;
  }

  Future<int> _applyPref(
    NovelBackupOp op,
    List<NovelBackupJournalEntry> entries,
  ) async {
    final api = prefs;
    if (api == null) return 0;
    final key = '${op.payload['key'] ?? ''}';
    final value = '${op.payload['value'] ?? ''}';
    if (key.isEmpty) return 0;
    final before = await api.read(key);
    if (before == value) return 0;
    await api.write(key, value);
    entries.add(
      NovelBackupJournalEntry(
        table: 'pref',
        key: <String, Object?>{'key': key},
        before: before == null
            ? null
            : <String, Object?>{'key': key, 'value': before},
        after: <String, Object?>{'key': key, 'value': value},
      ),
    );
    return 1;
  }

  // ── 撤销 ────────────────────────────────────────────────────────────────

  /// 最近一次恢复的 journal；没有返回 null。
  Future<NovelBackupJournal?> latestJournal() async {
    final store = files;
    if (store == null) return null;
    final names =
        (await store.list())
            .where((name) => name.startsWith(novelBackupUndoPrefix))
            .toList()
          ..sort();
    if (names.isEmpty) return null;
    return NovelBackupJournal.decode(await store.read(names.last));
  }

  /// 撤销指定 journal（缺省 = 最近一次）。
  Future<NovelBackupUndoReport> undo({String? journalName}) async {
    final store = files;
    if (store == null) {
      return const NovelBackupUndoReport(
        restored: 0,
        skipped: 0,
        errors: <String>['本地快照目录不可用，无法撤销'],
      );
    }
    var name = journalName;
    if (name == null) {
      final names =
          (await store.list())
              .where((item) => item.startsWith(novelBackupUndoPrefix))
              .toList()
            ..sort();
      if (names.isEmpty) {
        return const NovelBackupUndoReport(
          restored: 0,
          skipped: 0,
          errors: <String>['没有可撤销的恢复记录'],
        );
      }
      name = names.last;
    }
    final journal = NovelBackupJournal.decode(await store.read(name));
    if (journal == null) {
      return const NovelBackupUndoReport(
        restored: 0,
        skipped: 0,
        errors: <String>['撤销记录已损坏，无法回滚'],
      );
    }

    var restored = 0;
    var skipped = 0;
    final errors = <String>[];
    final touchedBooks = <String>{};
    for (final entry in journal.entries.reversed) {
      try {
        final result = await _undoEntry(entry, touchedBooks);
        if (result == _UndoOutcome.restored) restored++;
        if (result == _UndoOutcome.skipped) skipped++;
      } on Object catch (error) {
        errors.add('${entry.table} 回滚失败：$error');
      }
    }
    await _syncProjections(touchedBooks);
    await store.delete(name);
    await _trimJournals();
    return NovelBackupUndoReport(
      restored: restored,
      skipped: skipped,
      errors: errors,
    );
  }

  Future<_UndoOutcome> _undoEntry(
    NovelBackupJournalEntry entry,
    Set<String> touched,
  ) async {
    final current = await _readRow(entry.table, entry.key);
    if (entry.after != null && !_sameRow(current, entry.after)) {
      // 恢复之后又被改过：以用户后来的改动为准，不回滚这一行。
      return _UndoOutcome.skipped;
    }
    final before = entry.before;
    if (before == null) {
      await _deleteRow(entry.table, entry.key);
    } else {
      await _writeRow(entry.table, entry.key, before);
    }
    final bookId = '${entry.key['bookId'] ?? entry.key['id'] ?? ''}';
    if (bookId.isNotEmpty) touched.add(bookId);
    return _UndoOutcome.restored;
  }

  // ── 行读取 / 写入 / 删除（journal 用同一套 JSON 口径） ────────────────

  Future<Map<String, Object?>?> _readRow(
    String table,
    Map<String, Object?> key,
  ) async {
    switch (table) {
      case 'collect':
        return _collectRowJson(
          await db.collectRow(NovelRef(id: '${key['id'] ?? ''}')),
        );
      case 'history':
        return _historyRowJson(
          await db.historyRow(NovelRef(id: '${key['id'] ?? ''}')),
        );
      case 'position':
        final api = prefs;
        if (api == null) return null;
        final map = _decodePositionMap(
          await api.read(novelPrefReaderPositions),
        );
        return _mapOf(map['${key['storageKey'] ?? ''}']);
      case 'series':
        final row =
            await (db.select(db.novelSeriesEntries)
                  ..where((t) => t.name.equals('${key['name'] ?? ''}')))
                .getSingleOrNull();
        return row == null
            ? null
            : <String, Object?>{
                'name': row.name,
                'createdAt': row.createdAt.toIso8601String(),
                'id': row.id,
              };
      case 'bookmark':
        return _bookmarkRowJson(await _bookmarkRowByKey(key));
      case 'marking':
        return _markingRowJson(await _markingRowByKey(key));
      case 'readRecord':
        final row =
            await (db.select(db.novelReadRecords)..where(
                  (t) =>
                      t.deviceId.equals('${key['deviceId'] ?? ''}') &
                      t.bookId.equals('${key['bookId'] ?? ''}') &
                      t.chapterIndex.equals(
                        key['chapterIndex'] is num
                            ? (key['chapterIndex']! as num).toInt()
                            : 0,
                      ) &
                      t.day.equals('${key['day'] ?? ''}'),
                ))
                .getSingleOrNull();
        return _readRecordRowJson(row);
      case 'tombstone':
        final row =
            await (db.select(db.novelTombstoneEntries)..where(
                  (t) =>
                      t.kind.equals('${key['kind'] ?? ''}') &
                      t.targetKey.equals('${key['targetKey'] ?? ''}'),
                ))
                .getSingleOrNull();
        return _tombstoneRowJson(row);
      case 'source':
        final storage = sourceStorage;
        if (storage == null) return null;
        return _sourceJson(storage, '${key['key'] ?? ''}');
      case 'searchKeyword':
        final row =
            await (db.select(db.novelSearchTerms)
                  ..where((t) => t.keyword.equals('${key['keyword'] ?? ''}')))
                .getSingleOrNull();
        return row == null ? null : <String, Object?>{'keyword': row.keyword};
      case 'pref':
        final api = prefs;
        if (api == null) return null;
        final value = await api.read('${key['key'] ?? ''}');
        return value == null
            ? null
            : <String, Object?>{'key': key['key'], 'value': value};
    }
    return null;
  }

  Future<void> _writeRow(
    String table,
    Map<String, Object?> key,
    Map<String, Object?> row,
  ) async {
    switch (table) {
      case 'collect':
        await db
            .into(db.novelCollectEntries)
            .insertOnConflictUpdate(
              NovelCollectEntriesCompanion.insert(
                id: '${row['id'] ?? ''}',
                title: '${row['title'] ?? ''}',
                coverUrl: Value<String?>(row['coverUrl'] as String?),
                payload: Value<String>('${row['payload'] ?? '{}'}'),
                groupName: Value<String?>(row['groupName'] as String?),
                note: Value<String>('${row['note'] ?? ''}'),
                customCoverPath: Value<String?>(
                  row['customCoverPath'] as String?,
                ),
                seriesId: Value<int?>(
                  row['seriesId'] is num
                      ? (row['seriesId']! as num).toInt()
                      : null,
                ),
                collectedAt:
                    DateTime.tryParse('${row['collectedAt'] ?? ''}') ??
                    DateTime.now(),
              ),
            );
        return;
      case 'history':
        await db
            .into(db.novelHistoryEntries)
            .insertOnConflictUpdate(
              NovelHistoryEntriesCompanion.insert(
                id: '${row['id'] ?? ''}',
                title: '${row['title'] ?? ''}',
                coverUrl: Value<String?>(row['coverUrl'] as String?),
                chapterIndex: Value<int>(
                  row['chapterIndex'] is num
                      ? (row['chapterIndex']! as num).toInt()
                      : 0,
                ),
                chapterCount: Value<int>(
                  row['chapterCount'] is num
                      ? (row['chapterCount']! as num).toInt()
                      : 0,
                ),
                openedAt:
                    DateTime.tryParse('${row['openedAt'] ?? ''}') ??
                    DateTime.now(),
                readCount: Value<int>(
                  row['readCount'] is num
                      ? (row['readCount']! as num).toInt()
                      : 1,
                ),
                payload: Value<String>('${row['payload'] ?? '{}'}'),
              ),
            );
        return;
      case 'position':
        final api = prefs;
        if (api == null) return;
        final map = _decodePositionMap(
          await api.read(novelPrefReaderPositions),
        );
        map['${key['storageKey'] ?? ''}'] = row;
        await api.write(novelPrefReaderPositions, jsonEncode(map));
        return;
      case 'series':
        final name = '${row['name'] ?? ''}';
        final existing = await (db.select(
          db.novelSeriesEntries,
        )..where((t) => t.name.equals(name))).getSingleOrNull();
        if (existing != null) return;
        await db
            .into(db.novelSeriesEntries)
            .insert(
              NovelSeriesEntriesCompanion.insert(
                name: name,
                createdAt:
                    DateTime.tryParse('${row['createdAt'] ?? ''}') ??
                    DateTime.now(),
              ),
            );
        return;
      case 'bookmark':
        final existing = await _bookmarkRowByKey(key);
        if (existing != null) {
          await (db.delete(
            db.novelBookmarkEntries,
          )..where((t) => t.id.equals(existing.id))).go();
        }
        await db
            .into(db.novelBookmarkEntries)
            .insert(
              NovelBookmarkEntriesCompanion.insert(
                bookId: '${row['bookId'] ?? ''}',
                sourceKey: Value<String>('${row['sourceKey'] ?? ''}'),
                bookTitle: Value<String>('${row['bookTitle'] ?? ''}'),
                bookAuthor: Value<String>('${row['bookAuthor'] ?? ''}'),
                bookUrl: Value<String>('${row['bookUrl'] ?? ''}'),
                chapterIndex: row['chapterIndex'] is num
                    ? (row['chapterIndex']! as num).toInt()
                    : 0,
                paragraph: Value<int>(
                  row['paragraph'] is num
                      ? (row['paragraph']! as num).toInt()
                      : 0,
                ),
                charOffset: Value<int>(
                  row['charOffset'] is num
                      ? (row['charOffset']! as num).toInt()
                      : 0,
                ),
                chapterName: Value<String>('${row['chapterName'] ?? ''}'),
                excerpt: Value<String>('${row['excerpt'] ?? ''}'),
                unresolved: Value<bool>(row['unresolved'] == true),
                createdAt:
                    DateTime.tryParse('${row['createdAt'] ?? ''}') ??
                    DateTime.now(),
              ),
            );
        return;
      case 'marking':
        final existing = await _markingRowByKey(key);
        if (existing != null) {
          await (db.delete(
            db.novelMarkingEntries,
          )..where((t) => t.id.equals(existing.id))).go();
        }
        await db
            .into(db.novelMarkingEntries)
            .insert(
              NovelMarkingEntriesCompanion.insert(
                bookId: '${row['bookId'] ?? ''}',
                sourceKey: Value<String>('${row['sourceKey'] ?? ''}'),
                bookTitle: Value<String>('${row['bookTitle'] ?? ''}'),
                bookAuthor: Value<String>('${row['bookAuthor'] ?? ''}'),
                bookUrl: Value<String>('${row['bookUrl'] ?? ''}'),
                chapterIndex: row['chapterIndex'] is num
                    ? (row['chapterIndex']! as num).toInt()
                    : 0,
                paragraph: Value<int>(
                  row['paragraph'] is num
                      ? (row['paragraph']! as num).toInt()
                      : 0,
                ),
                startOffset: Value<int>(
                  row['startOffset'] is num
                      ? (row['startOffset']! as num).toInt()
                      : 0,
                ),
                endOffset: Value<int>(
                  row['endOffset'] is num
                      ? (row['endOffset']! as num).toInt()
                      : 0,
                ),
                chapterName: Value<String>('${row['chapterName'] ?? ''}'),
                styleJson: Value<String>('${row['styleJson'] ?? '{}'}'),
                note: Value<String>('${row['note'] ?? ''}'),
                unresolved: Value<bool>(row['unresolved'] == true),
                createdAt:
                    DateTime.tryParse('${row['createdAt'] ?? ''}') ??
                    DateTime.now(),
                updatedAt:
                    DateTime.tryParse('${row['updatedAt'] ?? ''}') ??
                    DateTime.now(),
              ),
            );
        return;
      case 'readRecord':
        await db
            .into(db.novelReadRecords)
            .insertOnConflictUpdate(
              NovelReadRecordsCompanion.insert(
                deviceId: '${row['deviceId'] ?? ''}',
                bookId: '${row['bookId'] ?? ''}',
                bookTitle: Value<String>('${row['bookTitle'] ?? ''}'),
                chapterIndex: Value<int>(
                  row['chapterIndex'] is num
                      ? (row['chapterIndex']! as num).toInt()
                      : 0,
                ),
                chapterName: Value<String>('${row['chapterName'] ?? ''}'),
                day: '${row['day'] ?? ''}',
                seconds: Value<int>(
                  row['seconds'] is num ? (row['seconds']! as num).toInt() : 0,
                ),
                firstReadAt:
                    DateTime.tryParse('${row['firstReadAt'] ?? ''}') ??
                    DateTime.now(),
                lastReadAt:
                    DateTime.tryParse('${row['lastReadAt'] ?? ''}') ??
                    DateTime.now(),
              ),
            );
        return;
      case 'tombstone':
        await db
            .into(db.novelTombstoneEntries)
            .insertOnConflictUpdate(
              NovelTombstoneEntriesCompanion.insert(
                kind: '${row['kind'] ?? ''}',
                targetKey: '${row['targetKey'] ?? ''}',
                deviceId: Value<String>('${row['deviceId'] ?? ''}'),
                deletedAt:
                    DateTime.tryParse('${row['deletedAt'] ?? ''}') ??
                    DateTime.now(),
              ),
            );
        return;
      case 'source':
        final storage = sourceStorage;
        if (storage == null) return;
        await storage.saveAll(<NovelBookSource>[NovelBookSource.fromJson(row)]);
        return;
      case 'searchKeyword':
        await db
            .into(db.novelSearchTerms)
            .insertOnConflictUpdate(
              NovelSearchTermsCompanion.insert(
                keyword: '${row['keyword'] ?? ''}',
                searchedAt:
                    DateTime.tryParse('${row['searchedAt'] ?? ''}') ??
                    DateTime.now(),
                hits: Value<int>(
                  row['hits'] is num ? (row['hits']! as num).toInt() : 1,
                ),
              ),
            );
        return;
      case 'pref':
        final api = prefs;
        if (api == null) return;
        await api.write('${row['key'] ?? ''}', '${row['value'] ?? ''}');
        return;
    }
  }

  Future<void> _deleteRow(String table, Map<String, Object?> key) async {
    switch (table) {
      case 'collect':
        await (db.delete(
          db.novelCollectEntries,
        )..where((t) => t.id.equals('${key['id'] ?? ''}'))).go();
        return;
      case 'history':
        await (db.delete(
          db.novelHistoryEntries,
        )..where((t) => t.id.equals('${key['id'] ?? ''}'))).go();
        return;
      case 'position':
        final api = prefs;
        if (api == null) return;
        final map = _decodePositionMap(
          await api.read(novelPrefReaderPositions),
        );
        map.remove('${key['storageKey'] ?? ''}');
        await api.write(novelPrefReaderPositions, jsonEncode(map));
        return;
      case 'series':
        await (db.delete(
          db.novelSeriesEntries,
        )..where((t) => t.name.equals('${key['name'] ?? ''}'))).go();
        return;
      case 'bookmark':
        final row = await _bookmarkRowByKey(key);
        if (row == null) return;
        await (db.delete(
          db.novelBookmarkEntries,
        )..where((t) => t.id.equals(row.id))).go();
        return;
      case 'marking':
        final row = await _markingRowByKey(key);
        if (row == null) return;
        await (db.delete(
          db.novelMarkingEntries,
        )..where((t) => t.id.equals(row.id))).go();
        return;
      case 'readRecord':
        await (db.delete(db.novelReadRecords)..where(
              (t) =>
                  t.deviceId.equals('${key['deviceId'] ?? ''}') &
                  t.bookId.equals('${key['bookId'] ?? ''}') &
                  t.chapterIndex.equals(
                    key['chapterIndex'] is num
                        ? (key['chapterIndex']! as num).toInt()
                        : 0,
                  ) &
                  t.day.equals('${key['day'] ?? ''}'),
            ))
            .go();
        return;
      case 'tombstone':
        await (db.delete(db.novelTombstoneEntries)..where(
              (t) =>
                  t.kind.equals('${key['kind'] ?? ''}') &
                  t.targetKey.equals('${key['targetKey'] ?? ''}'),
            ))
            .go();
        return;
      case 'source':
        final storage = sourceStorage;
        if (storage != null) await storage.delete('${key['key'] ?? ''}');
        return;
      case 'searchKeyword':
        await (db.delete(
          db.novelSearchTerms,
        )..where((t) => t.keyword.equals('${key['keyword'] ?? ''}'))).go();
        return;
      case 'pref':
        await db.removePref('${key['key'] ?? ''}');
        return;
    }
  }

  // ── 小工具 ──────────────────────────────────────────────────────────────

  Future<int?> _seriesIdFor(
    String name, {
    required DateTime at,
    required List<NovelBackupJournalEntry> entries,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final existing = await (db.select(
      db.novelSeriesEntries,
    )..where((t) => t.name.equals(trimmed))).getSingleOrNull();
    if (existing != null) return existing.id;
    final id = await db
        .into(db.novelSeriesEntries)
        .insert(
          NovelSeriesEntriesCompanion.insert(name: trimmed, createdAt: at),
        );
    entries.add(
      NovelBackupJournalEntry(
        table: 'series',
        key: <String, Object?>{'name': trimmed},
        before: null,
        after: <String, Object?>{
          'name': trimmed,
          'createdAt': at.toIso8601String(),
          'id': id,
        },
      ),
    );
    return id;
  }

  Future<NovelBookmarkRow?> _bookmarkRowOf(NovelBackupBookmark item) =>
      (db.select(db.novelBookmarkEntries)..where(
            (t) =>
                t.bookId.equals(item.bookId) &
                t.sourceKey.equals(item.sourceKey) &
                t.chapterIndex.equals(item.chapterIndex) &
                t.paragraph.equals(item.paragraph) &
                t.charOffset.equals(item.charOffset),
          ))
          .getSingleOrNull();

  Future<NovelBookmarkRow?> _bookmarkRowByKey(Map<String, Object?> key) =>
      (db.select(db.novelBookmarkEntries)..where(
            (t) =>
                t.bookId.equals('${key['bookId'] ?? ''}') &
                t.sourceKey.equals('${key['sourceKey'] ?? ''}') &
                t.chapterIndex.equals(
                  key['chapterIndex'] is num
                      ? (key['chapterIndex']! as num).toInt()
                      : 0,
                ) &
                t.paragraph.equals(
                  key['paragraph'] is num
                      ? (key['paragraph']! as num).toInt()
                      : 0,
                ) &
                t.charOffset.equals(
                  key['charOffset'] is num
                      ? (key['charOffset']! as num).toInt()
                      : 0,
                ),
          ))
          .getSingleOrNull();

  Future<NovelMarkingRow?> _markingRowOf(NovelBackupMarking item) =>
      (db.select(db.novelMarkingEntries)..where(
            (t) =>
                t.bookId.equals(item.bookId) &
                t.sourceKey.equals(item.sourceKey) &
                t.chapterIndex.equals(item.chapterIndex) &
                t.paragraph.equals(item.paragraph) &
                t.startOffset.equals(item.startOffset) &
                t.endOffset.equals(item.endOffset),
          ))
          .getSingleOrNull();

  Future<NovelMarkingRow?> _markingRowByKey(Map<String, Object?> key) =>
      (db.select(db.novelMarkingEntries)..where(
            (t) =>
                t.bookId.equals('${key['bookId'] ?? ''}') &
                t.sourceKey.equals('${key['sourceKey'] ?? ''}') &
                t.chapterIndex.equals(
                  key['chapterIndex'] is num
                      ? (key['chapterIndex']! as num).toInt()
                      : 0,
                ) &
                t.paragraph.equals(
                  key['paragraph'] is num
                      ? (key['paragraph']! as num).toInt()
                      : 0,
                ) &
                t.startOffset.equals(
                  key['startOffset'] is num
                      ? (key['startOffset']! as num).toInt()
                      : 0,
                ) &
                t.endOffset.equals(
                  key['endOffset'] is num
                      ? (key['endOffset']! as num).toInt()
                      : 0,
                ),
          ))
          .getSingleOrNull();

  Future<int> _deleteBookmarkByKey(
    String localKey,
    List<NovelBackupJournalEntry> entries,
  ) async {
    final row = await _bookmarkRowByKey(
      _anchorKeyParts(localKey, marking: false),
    );
    if (row == null) return 0;
    await (db.delete(
      db.novelBookmarkEntries,
    )..where((t) => t.id.equals(row.id))).go();
    entries.add(
      NovelBackupJournalEntry(
        table: 'bookmark',
        key: <String, Object?>{
          'bookId': row.bookId,
          'sourceKey': row.sourceKey,
          'chapterIndex': row.chapterIndex,
          'paragraph': row.paragraph,
          'charOffset': row.charOffset,
        },
        before: _bookmarkRowJson(row),
        after: null,
      ),
    );
    return 1;
  }

  Future<int> _deleteMarkingByKey(
    String localKey,
    List<NovelBackupJournalEntry> entries,
  ) async {
    final row = await _markingRowByKey(
      _anchorKeyParts(localKey, marking: true),
    );
    if (row == null) return 0;
    await (db.delete(
      db.novelMarkingEntries,
    )..where((t) => t.id.equals(row.id))).go();
    entries.add(
      NovelBackupJournalEntry(
        table: 'marking',
        key: <String, Object?>{
          'bookId': row.bookId,
          'sourceKey': row.sourceKey,
          'chapterIndex': row.chapterIndex,
          'paragraph': row.paragraph,
          'startOffset': row.startOffset,
          'endOffset': row.endOffset,
        },
        before: _markingRowJson(row),
        after: null,
      ),
    );
    return 1;
  }

  /// `bookId|sourceKey|chapter|paragraph|start|end` → 查询用的键。
  Map<String, Object?> _anchorKeyParts(String raw, {required bool marking}) {
    final parts = raw.split('|');
    int at(int index) =>
        index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0;
    return <String, Object?>{
      'bookId': parts.isNotEmpty ? parts[0] : '',
      'sourceKey': parts.length > 1 ? parts[1] : '',
      'chapterIndex': at(2),
      'paragraph': at(3),
      'startOffset': at(4),
      'endOffset': at(5),
      if (!marking) 'charOffset': at(4),
    };
  }

  Future<Map<String, Object?>?> _sourceJson(
    NovelSourceStorage storage,
    String key,
  ) async {
    for (final source in await storage.loadAll()) {
      if (source.key == key) return source.toJson();
    }
    return null;
  }

  Future<void> _syncProjections(Set<String> bookIds) async {
    final repo = library;
    if (repo == null || bookIds.isEmpty) return;
    for (final bookId in bookIds) {
      try {
        await syncNovelProjection(
          db: db,
          library: repo,
          ref: NovelRef(id: bookId),
        );
      } on Object {
        // 投影失败不该让恢复整体失败；打开点会再校正一次。
      }
    }
  }

  Future<void> _trimJournals() async {
    final store = files;
    if (store == null) return;
    final names =
        (await store.list())
            .where((name) => name.startsWith(novelBackupUndoPrefix))
            .toList()
          ..sort();
    while (names.length > novelBackupUndoKeep) {
      await store.delete(names.removeAt(0));
    }
  }

  static Map<String, Object?> _decodePositionMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on Object {
      // 坏数据当空。
    }
    return <String, Object?>{};
  }
}

Map<String, Object?>? _mapOf(Object? raw) {
  if (raw is Map) return Map<String, Object?>.from(raw);
  return null;
}

enum _UndoOutcome { restored, skipped }

Map<String, Object?>? _collectRowJson(NovelCollectRow? row) => row == null
    ? null
    : <String, Object?>{
        'id': row.id,
        'title': row.title,
        'coverUrl': row.coverUrl,
        'payload': row.payload,
        'groupName': row.groupName,
        'note': row.note,
        'customCoverPath': row.customCoverPath,
        'seriesId': row.seriesId,
        'collectedAt': row.collectedAt.toIso8601String(),
      };

Map<String, Object?>? _historyRowJson(NovelHistoryRow? row) => row == null
    ? null
    : <String, Object?>{
        'id': row.id,
        'title': row.title,
        'coverUrl': row.coverUrl,
        'chapterIndex': row.chapterIndex,
        'chapterCount': row.chapterCount,
        'openedAt': row.openedAt.toIso8601String(),
        'readCount': row.readCount,
        'payload': row.payload,
      };

Map<String, Object?>? _bookmarkRowJson(NovelBookmarkRow? row) => row == null
    ? null
    : <String, Object?>{
        'bookId': row.bookId,
        'sourceKey': row.sourceKey,
        'bookTitle': row.bookTitle,
        'bookAuthor': row.bookAuthor,
        'bookUrl': row.bookUrl,
        'chapterIndex': row.chapterIndex,
        'paragraph': row.paragraph,
        'charOffset': row.charOffset,
        'chapterName': row.chapterName,
        'excerpt': row.excerpt,
        'unresolved': row.unresolved,
        'createdAt': row.createdAt.toIso8601String(),
      };

Map<String, Object?>? _markingRowJson(NovelMarkingRow? row) => row == null
    ? null
    : <String, Object?>{
        'bookId': row.bookId,
        'sourceKey': row.sourceKey,
        'bookTitle': row.bookTitle,
        'bookAuthor': row.bookAuthor,
        'bookUrl': row.bookUrl,
        'chapterIndex': row.chapterIndex,
        'paragraph': row.paragraph,
        'startOffset': row.startOffset,
        'endOffset': row.endOffset,
        'chapterName': row.chapterName,
        'styleJson': row.styleJson,
        'note': row.note,
        'unresolved': row.unresolved,
        'createdAt': row.createdAt.toIso8601String(),
        'updatedAt': row.updatedAt.toIso8601String(),
      };

Map<String, Object?>? _readRecordRowJson(NovelReadRecordRow? row) => row == null
    ? null
    : <String, Object?>{
        'deviceId': row.deviceId,
        'bookId': row.bookId,
        'bookTitle': row.bookTitle,
        'chapterIndex': row.chapterIndex,
        'chapterName': row.chapterName,
        'day': row.day,
        'seconds': row.seconds,
        'firstReadAt': row.firstReadAt.toIso8601String(),
        'lastReadAt': row.lastReadAt.toIso8601String(),
      };

Map<String, Object?>? _tombstoneRowJson(NovelTombstoneRow? row) => row == null
    ? null
    : <String, Object?>{
        'kind': row.kind,
        'targetKey': row.targetKey,
        'deviceId': row.deviceId,
        'deletedAt': row.deletedAt.toIso8601String(),
      };

/// 逐字段比较（两边都可能缺键：缺 = null）。
bool _sameRow(Map<String, Object?>? left, Map<String, Object?>? right) {
  if (left == null && right == null) return true;
  if (left == null || right == null) return false;
  final keys = <String>{...left.keys, ...right.keys};
  for (final key in keys) {
    if ('${left[key] ?? ''}' != '${right[key] ?? ''}') return false;
  }
  return true;
}
