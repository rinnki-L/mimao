import 'package:drift/drift.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/music_db.dart';

/// 音乐搜索历史：只在模块内部库记录最近关键词。
///
/// 搜索词不是"一首歌"，在统一书架投影里没有对应行——这是双记账规则的
/// 明确例外（对齐 comic/search_history_service.dart）。
class MusicSearchHistoryService implements MusicSearchHistoryApi {
  MusicSearchHistoryService(this.db);

  final MusicDb db;

  /// 记录一个关键词：去首尾空白、忽略空串；重复关键词 `hits` 递增并刷新时间。
  ///
  /// [at] 只给测试注入固定时间用（生产走 `DateTime.now()`）。
  @override
  Future<void> record(String keyword, {DateTime? at}) async {
    final normalized = keyword.trim();
    if (normalized.isEmpty) return;
    final searchedAt = at ?? DateTime.now();
    await db.transaction(() async {
      final existing = await (db.select(
        db.musicSearchTerms,
      )..where((t) => t.keyword.equals(normalized))).getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.musicSearchTerms)
            .insert(
              MusicSearchTermsCompanion.insert(
                keyword: normalized,
                searchedAt: searchedAt,
                hits: const Value<int>(1),
              ),
            );
      } else {
        await (db.update(
          db.musicSearchTerms,
        )..where((t) => t.keyword.equals(normalized))).write(
          MusicSearchTermsCompanion(
            searchedAt: Value(searchedAt),
            hits: Value(existing.hits + 1),
          ),
        );
      }
    });
  }

  /// 最近关键词（最新的在前）。
  @override
  Future<List<String>> recent({int limit = 20}) async {
    final rows =
        await (db.select(db.musicSearchTerms)
              ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
              ..limit(limit))
            .get();
    return [for (final row in rows) row.keyword];
  }

  @override
  Future<void> clear() => db.delete(db.musicSearchTerms).go();
}
