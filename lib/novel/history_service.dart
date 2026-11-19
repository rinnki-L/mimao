import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_projection.dart';

/// 小说阅读历史服务——双记账的"打开点校正"主要发生在这里。
///
/// - [saveProgress] 是**持久化点**：先写内部 `novel_history`，紧接着投影；
/// - [open] 是**打开点**：以内部库权威值覆盖投影（把漏写/写旧的投影校正回来）。
///
/// 继承 [ChangeNotifier] 只服务于「我的」页的自动刷新（见收藏服务同款说明）。
class NovelHistoryService extends ChangeNotifier implements NovelHistoryApi {
  NovelHistoryService(this.db, this.library);

  final NovelDb db;
  final LibraryRepository library;

  @override
  Future<void> open(NovelSummary book) => openRef(novelRefOf(book));

  /// 打开某本书（从时间线/历史点进阅读）时的校正动作。
  ///
  /// 只在内部库确实有阅读记录时写投影：没读过的书不应因为"点开看了一眼"
  /// 就凭空出现在书架时间线里。
  Future<void> openRef(NovelRef ref) async {
    if (await db.historyRow(ref) == null) return;
    await syncNovelProjection(db: db, library: library, ref: ref);
  }

  @override
  Future<void> saveProgress(
    NovelSummary book,
    int chapterIndex,
    int chapterCount,
  ) {
    return saveProgressRef(
      novelRefOf(book),
      chapterIndex: chapterIndex,
      chapterCount: chapterCount,
      title: book.title,
      coverUrl: book.coverUrl.isEmpty ? null : book.coverUrl,
      book: book,
    );
  }

  /// 记录/更新阅读进度（持久化点）。同书重复写只更新一行，`readCount` 递增。
  Future<NovelHistoryItem> saveProgressRef(
    NovelRef ref, {
    required int chapterIndex,
    required int chapterCount,
    required String title,
    String? coverUrl,
    NovelSummary? book,
    DateTime? at,
  }) async {
    if (chapterIndex < 0 || chapterCount < 0) {
      throw ArgumentError('章节进度不能为负数');
    }
    final openedAt = at ?? DateTime.now();
    final encoded = book == null ? null : jsonEncode(book.toJson());

    await db.transaction(() async {
      final existing = await db.historyRow(ref);
      if (existing == null) {
        await db
            .into(db.novelHistoryEntries)
            .insert(
              NovelHistoryEntriesCompanion.insert(
                id: ref.id,
                title: title,
                coverUrl: Value(coverUrl),
                chapterIndex: Value(chapterIndex),
                chapterCount: Value(chapterCount),
                openedAt: openedAt,
                readCount: const Value<int>(1),
                payload: Value(encoded ?? '{}'),
              ),
            );
      } else {
        await (db.update(
          db.novelHistoryEntries,
        )..where((t) => t.id.equals(ref.id))).write(
          NovelHistoryEntriesCompanion(
            title: Value(title),
            coverUrl: Value(coverUrl),
            chapterIndex: Value(chapterIndex),
            chapterCount: Value(chapterCount),
            openedAt: Value(openedAt),
            readCount: Value(existing.readCount + 1),
            // 没有书籍快照时保留旧 payload，别把可重建的数据擦成 '{}'。
            payload: encoded == null ? const Value.absent() : Value(encoded),
          ),
        );
      }
    });
    await syncNovelProjection(db: db, library: library, ref: ref);
    notifyListeners();
    return NovelHistoryItem(
      book: book ?? _bookFromValues(ref, title, coverUrl),
      chapterIndex: chapterIndex,
      chapterCount: chapterCount,
      openedAt: openedAt,
    );
  }

  @override
  Future<NovelHistoryItem?> latest(String bookId) async {
    final row = await db.historyRow(NovelRef(id: bookId));
    return row == null ? null : _fromRow(row);
  }

  /// 最近阅读列表，按打开时间倒序（"继续阅读"的数据源）。
  @override
  Future<List<NovelHistoryItem>> recent({int limit = 50}) async {
    final rows =
        await (db.select(db.novelHistoryEntries)
              ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
              ..limit(limit))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  NovelHistoryItem _fromRow(NovelHistoryRow row) => NovelHistoryItem(
    book:
        novelSummaryFromPayload(row.payload) ??
        _bookFromValues(NovelRef(id: row.id), row.title, row.coverUrl),
    chapterIndex: row.chapterIndex,
    chapterCount: row.chapterCount,
    openedAt: row.openedAt,
  );

  NovelSummary _bookFromValues(NovelRef ref, String title, String? coverUrl) =>
      NovelSummary(
        id: ref.id,
        title: title,
        coverUrl: coverUrl ?? '',
        sourceName: ref.sourceName,
      );
}
