import 'package:drift/drift.dart';
import 'package:mimao/core/library.dart';

import 'anime_db.dart';
import 'anime_models.dart';
import 'anime_projection.dart';

/// 番剧收藏服务。
///
/// 双记账：`anime_collect` 是权威；每次写内部表后立即经
/// [syncAnimeProjection] 把 `starred` 与公共列投影到统一书架。
class AnimeCollectService {
  final AnimeDb db;
  final LibraryRepository library;

  AnimeCollectService(this.db, this.library);

  /// 收藏（幂等）：已存在则更新元数据并刷新收藏时间。
  Future<void> collect(
    AnimeRef ref, {
    required String title,
    String? coverUrl,
    String payload = '{}',
    DateTime? collectedAt,
  }) async {
    await db
        .into(db.animeCollectEntries)
        .insertOnConflictUpdate(
          AnimeCollectEntriesCompanion.insert(
            id: ref.id,
            sourceName: ref.sourceName,
            title: title,
            coverUrl: Value(coverUrl),
            payload: Value(payload),
            collectedAt: collectedAt ?? DateTime.now(),
          ),
        );
    await syncAnimeProjection(db: db, library: library, ref: ref);
  }

  /// 取消收藏（幂等）。内部行删除后仍写最后一笔投影，把 starred 校正为 false；
  /// 若该作品有观看历史，历史行会继续作为投影标题/进度的权威。
  Future<void> remove(AnimeRef ref) async {
    final existing = await db.collectRow(ref);
    if (existing == null) return;
    await (db.delete(db.animeCollectEntries)..where(
          (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
        ))
        .go();
    await syncAnimeProjection(
      db: db,
      library: library,
      ref: ref,
      fallbackTitle: existing.title,
      fallbackCoverUrl: existing.coverUrl,
      touchedAt: existing.collectedAt,
    );
  }

  Future<bool> isCollected(AnimeRef ref) async =>
      await db.collectRow(ref) != null;

  Future<AnimeCollectEntry?> find(AnimeRef ref) async {
    final row = await db.collectRow(ref);
    return row == null ? null : _fromRow(row);
  }

  /// 收藏列表，按收藏时间倒序。
  Future<List<AnimeCollectEntry>> all() async {
    final rows = await (db.select(
      db.animeCollectEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.collectedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  AnimeCollectEntry _fromRow(AnimeCollectRow row) => AnimeCollectEntry(
    ref: AnimeRef(id: row.id, sourceName: row.sourceName),
    title: row.title,
    coverUrl: row.coverUrl,
    payload: row.payload,
    collectedAt: row.collectedAt,
  );
}
