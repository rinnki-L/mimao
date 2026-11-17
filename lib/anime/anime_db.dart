import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'anime_models.dart';

part 'anime_db.g.dart';

/// 番剧模块的**内部权威库**（双记账的"模块库"一侧）。
///
/// 与 `core/db.dart` 的 `media_entries` 投影表刻意分开：
/// - 这里存模块自己的完整数据（收藏私有 payload、进度秒数、弹幕缓存……）；
/// - `media_entries` 只由 `anime_projection.dart` 在持久化点/打开点写入公共列。
/// 两库同进程打开，测试各自用 `NativeDatabase.memory()`。
@DataClassName('AnimeCollectRow')
class AnimeCollectEntries extends Table {
  @override
  String get tableName => 'anime_collect';

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  /// 模块私有 JSON；投影里的 payload 是投影函数另写的摘要，不是这一列。
  TextColumn get payload => text().withDefault(const Constant('{}'))();

  DateTimeColumn get collectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, sourceName};
}

@DataClassName('AnimeHistoryRow')
class AnimeHistoryEntries extends Table {
  @override
  String get tableName => 'anime_history';

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  /// 打开历史时来源可能已下线，标题/封面随历史一起留底。
  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  IntColumn get episode => integer().withDefault(const Constant(0))();

  IntColumn get positionSec => integer().withDefault(const Constant(0))();

  IntColumn get durationSec => integer().withDefault(const Constant(0))();

  DateTimeColumn get openedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, sourceName};
}

@DataClassName('AnimeSearchTermRow')
class AnimeSearchTerms extends Table {
  @override
  String get tableName => 'anime_search_term';

  TextColumn get term => text()();

  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {term};
}

@DataClassName('AnimeDanmakuCacheRow')
class AnimeDanmakuCacheEntries extends Table {
  @override
  String get tableName => 'anime_danmaku_cache';

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  IntColumn get episode => integer()();

  /// `List<DanmakuComment>` 的 JSON 串；缓存的唯一格式由 danmaku.dart 定义。
  TextColumn get commentsJson => text()();

  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, sourceName, episode};
}

@DriftDatabase(
  tables: [
    AnimeCollectEntries,
    AnimeHistoryEntries,
    AnimeSearchTerms,
    AnimeDanmakuCacheEntries,
  ],
)
class AnimeDb extends _$AnimeDb {
  /// 生产构造：与 core 库同目录，文件名区分（mimao_anime.sqlite）。
  AnimeDb() : super(driftDatabase(name: 'mimao_anime'));

  /// 测试构造：注入内存/临时 executor（NativeDatabase.memory()）。
  AnimeDb.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  Future<AnimeCollectRow?> collectRow(AnimeRef ref) =>
      (select(animeCollectEntries)..where(
            (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
          ))
          .getSingleOrNull();

  Future<AnimeHistoryRow?> historyRow(AnimeRef ref) =>
      (select(animeHistoryEntries)..where(
            (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
          ))
          .getSingleOrNull();

  Future<AnimeDanmakuCacheRow?> danmakuCacheRow(AnimeRef ref, int episode) =>
      (select(animeDanmakuCacheEntries)..where(
            (t) =>
                t.id.equals(ref.id) &
                t.sourceName.equals(ref.sourceName) &
                t.episode.equals(episode),
          ))
          .getSingleOrNull();
}
