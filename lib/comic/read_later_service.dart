import 'package:drift/drift.dart';

import 'comic_db.dart';
import 'comic_models.dart';

/// 「稍后阅读」服务：详情页加入/移除，主页卡片读取。
///
/// 与收藏刻意分离：
/// - 不写 core 投影（不进统一书架时间线、不占收藏位）；
/// - 同一作品可同时「已收藏」且「稍后阅读」；
/// - 数据只在模块内部 `comic_read_later` 表，卸载/清模块数据即清空。
class ComicReadLaterService {
  final ComicDb db;

  ComicReadLaterService(this.db);

  /// 加入稍后阅读（幂等）：重复加入只刷新元数据与时间。
  Future<void> add(
    ComicRef ref, {
    required String title,
    String? coverUrl,
    String detailUrl = '',
    String payload = '{}',
    DateTime? addedAt,
  }) async {
    await db
        .into(db.comicReadLaterEntries)
        .insertOnConflictUpdate(
          ComicReadLaterEntriesCompanion.insert(
            id: ref.id,
            sourceName: ref.sourceName,
            title: title,
            coverUrl: Value(coverUrl),
            detailUrl: Value(detailUrl),
            payload: Value(payload),
            addedAt: addedAt ?? DateTime.now(),
          ),
        );
  }

  /// 移出稍后阅读（幂等）。
  Future<void> remove(ComicRef ref) async {
    await (db.delete(db.comicReadLaterEntries)..where(
          (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
        ))
        .go();
  }

  /// 按 [included] 加入或移除；返回操作后的状态（true = 已在稍后阅读）。
  Future<bool> set(
    ComicRef ref, {
    required bool included,
    required String title,
    String? coverUrl,
    String detailUrl = '',
    DateTime? now,
  }) async {
    if (included) {
      await add(
        ref,
        title: title,
        coverUrl: coverUrl,
        detailUrl: detailUrl,
        addedAt: now,
      );
      return true;
    }
    await remove(ref);
    return false;
  }

  Future<bool> contains(ComicRef ref) async =>
      await (db.select(db.comicReadLaterEntries)..where(
            (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
          ))
          .getSingleOrNull() !=
      null;

  Future<ComicReadLaterEntry?> find(ComicRef ref) async {
    final row =
        await (db.select(db.comicReadLaterEntries)..where(
              (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// 全部稍后阅读，按加入时间倒序。
  Future<List<ComicReadLaterEntry>> all() async {
    final rows = await (db.select(
      db.comicReadLaterEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.addedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  ComicReadLaterEntry _fromRow(ComicReadLaterRow row) => ComicReadLaterEntry(
    ref: ComicRef(id: row.id, sourceName: row.sourceName),
    title: row.title,
    coverUrl: row.coverUrl,
    detailUrl: row.detailUrl,
    payload: row.payload,
    addedAt: row.addedAt,
  );
}
