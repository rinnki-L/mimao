import 'package:drift/drift.dart';
import 'package:mimao/core/library.dart';

import 'comic_db.dart';
import 'comic_models.dart';
import 'comic_projection.dart';

/// 漫画阅读历史服务——双记账的"打开点校正"主要发生在这里。
///
/// - [saveProgress] 是**持久化点**：先写内部 `comic_history`，紧接着投影；
/// - [open] 是**打开点**：以内部库权威值覆盖投影（把漏写/写旧的投影校正回来）。
class ComicHistoryService {
  final ComicDb db;
  final LibraryRepository library;

  ComicHistoryService(this.db, this.library);

  /// 打开某部漫画（从时间线点进详情/阅读器）时的校正动作。
  ///
  /// 只在内部库确实有阅读记录时写投影：没有记录的作品不应因为"点开看了一眼
  /// 详情"就凭空出现在书架时间线里。
  Future<void> open(ComicRef ref) async {
    if (await db.historyRow(ref) == null) return;
    await syncComicProjection(db: db, library: library, ref: ref);
  }

  /// 记录/更新阅读进度（持久化点）。返回内部库的权威行。
  Future<ComicReadEntry> saveProgress(
    ComicRef ref, {
    required String title,
    String? coverUrl,
    String chapterId = '',
    required int page,
    int pageCount = 0,
    DateTime? openedAt,
  }) async {
    if (page < 0 || pageCount < 0) {
      throw ArgumentError('阅读进度不能为负数');
    }
    final at = openedAt ?? DateTime.now();
    await db
        .into(db.comicHistoryEntries)
        .insertOnConflictUpdate(
          ComicHistoryEntriesCompanion.insert(
            id: ref.id,
            sourceName: ref.sourceName,
            title: title,
            coverUrl: Value(coverUrl),
            chapterId: Value(chapterId),
            page: Value(page),
            pageCount: Value(pageCount),
            openedAt: at,
          ),
        );
    await syncComicProjection(db: db, library: library, ref: ref);
    return ComicReadEntry(
      ref: ref,
      title: title,
      coverUrl: coverUrl,
      chapterId: chapterId,
      page: page,
      pageCount: pageCount,
      openedAt: at,
    );
  }

  Future<ComicReadEntry?> latest(ComicRef ref) async {
    final row = await db.historyRow(ref);
    return row == null ? null : _fromRow(row);
  }

  /// 最近阅读列表，按打开时间倒序（"继续阅读"的数据源）。
  Future<List<ComicReadEntry>> recent({int limit = 20}) async {
    final rows =
        await (db.select(db.comicHistoryEntries)
              ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
              ..limit(limit))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  ComicReadEntry _fromRow(ComicHistoryRow row) => ComicReadEntry(
    ref: ComicRef(id: row.id, sourceName: row.sourceName),
    title: row.title,
    coverUrl: row.coverUrl,
    chapterId: row.chapterId,
    page: row.page,
    pageCount: row.pageCount,
    openedAt: row.openedAt,
  );
}
