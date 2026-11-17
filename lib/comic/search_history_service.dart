import 'package:drift/drift.dart';

import 'comic_db.dart';

/// 漫画搜索历史：只在模块内部库记录最近关键词。
///
/// 搜索词不是"一部作品"，在统一书架投影里没有对应行——这是双记账规则
/// 的明确例外。
class ComicSearchHistoryService {
  static const int defaultMaxEntries = 10;

  final ComicDb db;
  final int maxEntries;

  ComicSearchHistoryService(this.db, {this.maxEntries = defaultMaxEntries})
    : assert(maxEntries > 0, '搜索历史上限必须为正数');

  /// 记录一个关键词：去首尾空白、忽略空串。
  ///
  /// 重复关键词只保留一行（`term` 主键 + 刷新 `lastUsedAt`），超过上限时
  /// 淘汰最久未用的条目。完成内部写入后不需要写 core 投影（非媒体条目）。
  Future<void> record(String term, {DateTime? now}) async {
    final normalized = term.trim();
    if (normalized.isEmpty) return;
    await db
        .into(db.comicSearchTerms)
        .insertOnConflictUpdate(
          ComicSearchTermsCompanion.insert(
            term: normalized,
            lastUsedAt: now ?? DateTime.now(),
          ),
        );
    final rows = await (db.select(
      db.comicSearchTerms,
    )..orderBy([(t) => OrderingTerm.desc(t.lastUsedAt)])).get();
    if (rows.length > maxEntries) {
      final stale = rows.skip(maxEntries).map((row) => row.term).toList();
      await (db.delete(
        db.comicSearchTerms,
      )..where((t) => t.term.isIn(stale))).go();
    }
  }

  /// 最近关键词（最新的在前）。
  Future<List<String>> recent({int? limit}) async {
    final rows =
        await (db.select(db.comicSearchTerms)
              ..orderBy([(t) => OrderingTerm.desc(t.lastUsedAt)])
              ..limit(limit ?? maxEntries))
            .get();
    return [for (final row in rows) row.term];
  }

  Future<void> remove(String term) async {
    final normalized = term.trim();
    if (normalized.isEmpty) return;
    await (db.delete(
      db.comicSearchTerms,
    )..where((t) => t.term.equals(normalized))).go();
  }

  Future<void> clear() async {
    await db.delete(db.comicSearchTerms).go();
  }
}
