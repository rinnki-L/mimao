import 'package:drift/drift.dart';
import 'package:mimao/core/library.dart';

import 'comic_db.dart';
import 'comic_models.dart';
import 'comic_projection.dart';

/// 漫画收藏服务。
///
/// 双记账：`comic_collect` 是权威；每次写内部表后立即经
/// [syncComicProjection] 把 `starred` 与公共列投影到统一书架。
class ComicCollectService {
  final ComicDb db;
  final LibraryRepository library;

  ComicCollectService(this.db, this.library);

  /// 收藏（幂等）：已存在则更新元数据并刷新收藏时间。
  Future<void> collect(
    ComicRef ref, {
    required String title,
    String? coverUrl,
    String payload = '{}',
    DateTime? collectedAt,
  }) async {
    await db
        .into(db.comicCollectEntries)
        .insertOnConflictUpdate(
          ComicCollectEntriesCompanion.insert(
            id: ref.id,
            sourceName: ref.sourceName,
            title: title,
            coverUrl: Value(coverUrl),
            payload: Value(payload),
            collectedAt: collectedAt ?? DateTime.now(),
          ),
        );
    await syncComicProjection(db: db, library: library, ref: ref);
  }

  /// 取消收藏（幂等）。内部行删除后仍写最后一笔投影，把 starred 校正为 false；
  /// 若该作品有阅读历史，历史行会继续作为投影标题/进度的权威。
  Future<void> remove(ComicRef ref) async {
    final existing = await db.collectRow(ref);
    if (existing == null) return;
    await (db.delete(db.comicCollectEntries)..where(
          (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
        ))
        .go();
    await syncComicProjection(
      db: db,
      library: library,
      ref: ref,
      fallbackTitle: existing.title,
      fallbackCoverUrl: existing.coverUrl,
      touchedAt: existing.collectedAt,
    );
  }

  Future<bool> isCollected(ComicRef ref) async =>
      await db.collectRow(ref) != null;

  Future<ComicCollectEntry?> find(ComicRef ref) async {
    final row = await db.collectRow(ref);
    return row == null ? null : _fromRow(row);
  }

  /// 收藏列表，按收藏时间倒序。
  Future<List<ComicCollectEntry>> all() async {
    final rows = await (db.select(
      db.comicCollectEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.collectedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  ComicCollectEntry _fromRow(ComicCollectRow row) => ComicCollectEntry(
    ref: ComicRef(id: row.id, sourceName: row.sourceName),
    title: row.title,
    coverUrl: row.coverUrl,
    payload: row.payload,
    collectedAt: row.collectedAt,
  );
}
