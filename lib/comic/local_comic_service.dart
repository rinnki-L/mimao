import 'package:drift/drift.dart';
import 'package:mimao/core/library.dart';

import 'comic_db.dart';
import 'comic_models.dart';
import 'comic_projection.dart';

/// 本地漫画服务：把本地文件夹作为一部漫画导入，记录元数据。
///
/// 本地漫画 id 用 [ComicRef.local] 生成，来源恒为 `local`，与在线源天然隔离。
/// 对本地漫画"收藏"同样走 [ComicCollectService]，因此导入动作本身只写内部
/// `comic_local` 表，是否进书架时间线由收藏/打开决定；这里在导入后主动投影
/// 一次，使刚导入的本地漫画立即可见。
class ComicLocalService {
  final ComicDb db;
  final LibraryRepository library;

  ComicLocalService(this.db, this.library);

  /// 导入（幂等）：同 id 重复导入刷新元数据。
  Future<ComicLocalEntry> import({
    required ComicRef ref,
    required String title,
    required String folderPath,
    String? coverPath,
    int pageCount = 0,
    String payload = '{}',
    DateTime? importedAt,
  }) async {
    if (ref.sourceName != ComicRef.localSource) {
      throw ArgumentError('本地漫画来源必须为 ${ComicRef.localSource}');
    }
    if (pageCount < 0) {
      throw ArgumentError('页数不能为负数');
    }
    final at = importedAt ?? DateTime.now();
    await db
        .into(db.comicLocalEntries)
        .insertOnConflictUpdate(
          ComicLocalEntriesCompanion.insert(
            id: ref.id,
            sourceName: ref.sourceName,
            title: title,
            folderPath: folderPath,
            coverPath: Value(coverPath),
            pageCount: Value(pageCount),
            payload: Value(payload),
            importedAt: at,
          ),
        );
    await syncComicProjection(db: db, library: library, ref: ref);
    return ComicLocalEntry(
      ref: ref,
      title: title,
      folderPath: folderPath,
      coverPath: coverPath,
      pageCount: pageCount,
      payload: payload,
      importedAt: at,
    );
  }

  Future<ComicLocalEntry?> find(ComicRef ref) async {
    final row = await db.localRow(ref);
    return row == null ? null : _fromRow(row);
  }

  Future<List<ComicLocalEntry>> all() async {
    final rows = await (db.select(
      db.comicLocalEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.importedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<void> remove(ComicRef ref) async {
    await (db.delete(db.comicLocalEntries)..where(
          (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
        ))
        .go();
  }

  ComicLocalEntry _fromRow(ComicLocalRow row) => ComicLocalEntry(
    ref: ComicRef(id: row.id, sourceName: row.sourceName),
    title: row.title,
    folderPath: row.folderPath,
    coverPath: row.coverPath,
    pageCount: row.pageCount,
    payload: row.payload,
    importedAt: row.importedAt,
  );
}
