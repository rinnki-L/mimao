import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_projection.dart';

/// 一条收藏（权威行 + 可重建的书籍快照）。
class NovelCollectItem {
  const NovelCollectItem({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.book,
    required this.collectedAt,
  });

  final NovelRef ref;
  final String title;
  final String? coverUrl;

  /// 收藏时落底的书籍 JSON 反序列化结果；旧数据/坏数据为 null。
  final NovelSummary? book;

  final DateTime collectedAt;

  /// 「我的」页展示用作者名（无书籍快照时为空串）。
  String get authorText => book?.author ?? '';
}

/// 小说收藏服务（实现 [NovelCollectApi] 的接口缝）。
///
/// 双记账：`novel_collect` 是权威；每次写内部表后立即经
/// [syncNovelProjection] 把 `starred` 与公共列投影到统一书架。
///
/// 继承 [ChangeNotifier] 只服务于「我的」页的自动刷新：搜索页收藏后切过去
/// 能立刻看到新条目（服务不是内存状态源，通知不含任何数据）。
class NovelCollectService extends ChangeNotifier implements NovelCollectApi {
  NovelCollectService(this.db, this.library);

  final NovelDb db;
  final LibraryRepository library;

  @override
  Future<void> collect(NovelSummary book) {
    return collectRef(
      novelRefOf(book),
      title: book.title,
      coverUrl: book.coverUrl.isEmpty ? null : book.coverUrl,
      book: book,
    );
  }

  /// 收藏（幂等）：已存在则更新元数据并刷新收藏时间。
  Future<void> collectRef(
    NovelRef ref, {
    required String title,
    String? coverUrl,
    NovelSummary? book,
    DateTime? collectedAt,
  }) async {
    final at = collectedAt ?? DateTime.now();
    await db
        .into(db.novelCollectEntries)
        .insertOnConflictUpdate(
          NovelCollectEntriesCompanion.insert(
            id: ref.id,
            title: title,
            coverUrl: Value(coverUrl),
            payload: Value(book == null ? '{}' : jsonEncode(book.toJson())),
            collectedAt: at,
          ),
        );
    await syncNovelProjection(db: db, library: library, ref: ref);
    notifyListeners();
  }

  /// 取消收藏（幂等）。内部行删除后仍写最后一笔投影，把 starred 校正为 false；
  /// 若该书有阅读历史，历史行会继续作为投影标题/进度的权威。
  @override
  Future<void> remove(String bookId) async {
    final ref = NovelRef(id: bookId);
    final existing = await db.collectRow(ref);
    if (existing == null) return;
    await (db.delete(
      db.novelCollectEntries,
    )..where((t) => t.id.equals(ref.id))).go();
    await syncNovelProjection(
      db: db,
      library: library,
      ref: ref,
      fallbackTitle: existing.title,
      fallbackCoverUrl: existing.coverUrl,
      touchedAt: existing.collectedAt,
    );
    notifyListeners();
  }

  @override
  Future<bool> isCollected(String bookId) async =>
      await db.collectRow(NovelRef(id: bookId)) != null;

  @override
  Future<Set<String>> collectedIds() async {
    final rows = await db.select(db.novelCollectEntries).get();
    return <String>{for (final row in rows) row.id};
  }

  /// 收藏列表，按收藏时间倒序。
  Future<List<NovelCollectItem>> list() async {
    final rows = await (db.select(
      db.novelCollectEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.collectedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  NovelCollectItem _fromRow(NovelCollectRow row) => NovelCollectItem(
    ref: NovelRef(id: row.id),
    title: row.title,
    coverUrl: row.coverUrl,
    book: novelSummaryFromPayload(row.payload),
    collectedAt: row.collectedAt,
  );
}
