// 单张图片收藏（收藏/取消/查询/列表）。
//
// 对照 Venera-Next `image_favorite_actions.dart` 的语义：
// - 同一张图重复收藏是幂等操作（主键天然去重）；
// - 第 1 页（封面页）不允许取消收藏：它通常是这部作品在收藏页的代表图，
//   取消会让整部作品从收藏列表里消失，所以返回 [ImageFavoriteResult.protectedCover]；
// - 取消收藏后该部作品没有任何图片时，整条记录一起消失（不保留空壳）。
//
// 与上游的差别：上游把收藏存成"作品 → 章 → 图"的嵌套 JSON；本仓用扁平表，
// 主键 {sourceName, comicId, chapterId, page}，查询与去重都交给 SQL。

import 'package:drift/drift.dart';

import 'comic_db.dart';

/// 收藏操作结果。
enum ImageFavoriteResult {
  /// 已收藏。
  collected,

  /// 已取消收藏。
  uncollected,

  /// 第一页（封面）不允许取消。
  protectedCover,
}

/// 一次收藏请求需要的全部信息。
class ImageFavoriteInput {
  const ImageFavoriteInput({
    required this.sourceName,
    required this.comicId,
    required this.comicTitle,
    required this.chapterId,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.page,
    required this.pageCount,
    required this.imageUrl,
    this.coverUrl,
    this.detailUrl = '',
  });

  final String sourceName;
  final String comicId;
  final String comicTitle;
  final String chapterId;

  /// 1 基章序号；0 表示未知（本地漫画可能是 0）。
  final int chapterNumber;
  final String chapterTitle;

  /// 1 基章内页。
  final int page;
  final int pageCount;
  final String imageUrl;
  final String? coverUrl;

  /// 详情地址：回跳阅读器时用它重新解析章节。
  final String detailUrl;

  /// 是否封面页（第 1 页）。
  bool get isFirstPage => page <= 1;
}

/// 一张已收藏的图片。
class ImageFavorite {
  const ImageFavorite({
    required this.sourceName,
    required this.comicId,
    required this.comicTitle,
    required this.chapterId,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.page,
    required this.pageCount,
    required this.imageUrl,
    this.coverUrl,
    this.detailUrl = '',
    required this.collectedAt,
  });

  final String sourceName;
  final String comicId;
  final String comicTitle;
  final String chapterId;
  final int chapterNumber;
  final String chapterTitle;
  final int page;
  final int pageCount;
  final String imageUrl;
  final String? coverUrl;
  final String detailUrl;
  final DateTime collectedAt;

  bool get isFirstPage => page <= 1;

  /// 图片缓存身份：收藏页据此直接取已缓存的字节。
  String get cacheIdentity => imageUrl;

  static ImageFavorite fromRow(ComicImageFavoriteRow row) => ImageFavorite(
    sourceName: row.sourceName,
    comicId: row.comicId,
    comicTitle: row.comicTitle,
    chapterId: row.chapterId,
    chapterNumber: row.chapterNumber,
    chapterTitle: row.chapterTitle,
    page: row.page,
    pageCount: row.pageCount,
    imageUrl: row.imageUrl,
    coverUrl: row.coverUrl,
    detailUrl: row.detailUrl,
    collectedAt: row.collectedAt,
  );
}

/// 图片收藏服务。
class ComicImageFavoriteService {
  ComicImageFavoriteService(this.db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ComicDb db;

  /// 收藏时间来源；测试注入固定/递增时钟，避免同一毫秒内并列。
  final DateTime Function() _now;

  /// 某部作品的全部收藏（按章号、页号升序）。
  Future<List<ImageFavorite>> forComic(
    String sourceName,
    String comicId,
  ) async {
    final rows =
        await (db.select(db.comicImageFavoriteEntries)
              ..where(
                (t) =>
                    t.sourceName.equals(sourceName) & t.comicId.equals(comicId),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.chapterNumber),
                (t) => OrderingTerm.asc(t.page),
              ]))
            .get();
    return <ImageFavorite>[for (final row in rows) ImageFavorite.fromRow(row)];
  }

  /// 最近收藏（跨作品，收藏页首屏用）。
  Future<List<ImageFavorite>> recent({int limit = 200}) async {
    final rows =
        await (db.select(db.comicImageFavoriteEntries)
              ..orderBy([
                (t) => OrderingTerm.desc(t.collectedAt),
                (t) => OrderingTerm.desc(t.chapterNumber),
                (t) => OrderingTerm.desc(t.page),
              ])
              ..limit(limit))
            .get();
    return <ImageFavorite>[for (final row in rows) ImageFavorite.fromRow(row)];
  }

  /// 某一张图是否已收藏。
  Future<bool> contains({
    required String sourceName,
    required String comicId,
    required String chapterId,
    required int page,
  }) async {
    final row = await _findRow(
      sourceName: sourceName,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
    );
    return row != null;
  }

  /// 收藏 / 取消收藏（幂等）。第一页取消会被拒。
  Future<ImageFavoriteResult> toggle(ImageFavoriteInput input) async {
    final existing = await _findRow(
      sourceName: input.sourceName,
      comicId: input.comicId,
      chapterId: input.chapterId,
      page: input.page,
    );
    if (existing != null) {
      // 封面页是这部作品在收藏列表里的代表图，取消会让整部作品消失。
      if (input.isFirstPage) return ImageFavoriteResult.protectedCover;
      await (db.delete(db.comicImageFavoriteEntries)..where(
            (t) =>
                t.sourceName.equals(input.sourceName) &
                t.comicId.equals(input.comicId) &
                t.chapterId.equals(input.chapterId) &
                t.page.equals(input.page),
          ))
          .go();
      return ImageFavoriteResult.uncollected;
    }

    await db
        .into(db.comicImageFavoriteEntries)
        .insertOnConflictUpdate(
          ComicImageFavoriteEntriesCompanion.insert(
            sourceName: input.sourceName,
            comicId: input.comicId,
            chapterId: input.chapterId,
            page: input.page,
            comicTitle: input.comicTitle,
            chapterTitle: Value(input.chapterTitle),
            imageUrl: Value(input.imageUrl),
            coverUrl: Value(input.coverUrl),
            detailUrl: Value(input.detailUrl),
            pageCount: Value(input.pageCount),
            chapterNumber: Value(input.chapterNumber),
            collectedAt: _now(),
          ),
        );
    return ImageFavoriteResult.collected;
  }

  /// 移除某部作品的全部图片收藏（作品被删/换源时清理）。
  Future<int> removeComic(String sourceName, String comicId) =>
      (db.delete(db.comicImageFavoriteEntries)..where(
            (t) => t.sourceName.equals(sourceName) & t.comicId.equals(comicId),
          ))
          .go();

  /// 收藏总数（收藏页徽标用）。
  Future<int> count() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM comic_image_favorite')
        .getSingle();
    return row.read<int>('c');
  }

  Future<ComicImageFavoriteRow?> _findRow({
    required String sourceName,
    required String comicId,
    required String chapterId,
    required int page,
  }) {
    return (db.select(db.comicImageFavoriteEntries)..where(
          (t) =>
              t.sourceName.equals(sourceName) &
              t.comicId.equals(comicId) &
              t.chapterId.equals(chapterId) &
              t.page.equals(page),
        ))
        .getSingleOrNull();
  }
}
