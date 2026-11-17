import 'package:drift/drift.dart';

import 'comic_db.dart';
import 'comic_models.dart';

/// 图片缓存元数据仓储：只写模块内部 `comic_image_cache` 表。
///
/// 这里只记录"哪张图缓存在哪个文件路径"，不负责图片字节的下载/解码（本轮无
/// 真实下载器）。缓存不是书架条目，无 core 投影。
class ComicImageCacheStore {
  final ComicDb db;

  ComicImageCacheStore(this.db);

  Future<void> put({
    required String cacheKey,
    required ComicRef ref,
    String chapterId = '',
    required String filePath,
    DateTime? cachedAt,
  }) async {
    await db
        .into(db.comicImageCacheEntries)
        .insertOnConflictUpdate(
          ComicImageCacheEntriesCompanion.insert(
            cacheKey: cacheKey,
            id: ref.id,
            sourceName: ref.sourceName,
            chapterId: Value(chapterId),
            filePath: filePath,
            cachedAt: cachedAt ?? DateTime.now(),
          ),
        );
  }

  Future<ComicImageCacheRow?> find(String cacheKey) => (db.select(
    db.comicImageCacheEntries,
  )..where((t) => t.cacheKey.equals(cacheKey))).getSingleOrNull();

  Future<List<ComicImageCacheRow>> forComic(ComicRef ref, {String? chapterId}) {
    final query = db.select(db.comicImageCacheEntries)
      ..where((t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName));
    if (chapterId != null) {
      query.where((t) => t.chapterId.equals(chapterId));
    }
    return query.get();
  }

  Future<void> remove(String cacheKey) async {
    await (db.delete(
      db.comicImageCacheEntries,
    )..where((t) => t.cacheKey.equals(cacheKey))).go();
  }

  Future<void> clearComic(ComicRef ref) async {
    await (db.delete(db.comicImageCacheEntries)..where(
          (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
        ))
        .go();
  }
}
