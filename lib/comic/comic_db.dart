import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'comic_models.dart';

part 'comic_db.g.dart';

/// 漫画模块的**内部权威库**（双记账的"模块库"一侧）。
///
/// 与 `core/db.dart` 的 `media_entries` 投影表刻意分开：
/// - 这里存模块自己的完整数据（收藏私有 payload、阅读页、搜索词、下载任务、
///   图片缓存、本地漫画元数据）；
/// - `media_entries` 只由 `comic_projection.dart` 在持久化点/打开点写入公共列。
/// 两库同进程打开，测试各自用 `NativeDatabase.memory()`。
@DataClassName('ComicCollectRow')
class ComicCollectEntries extends Table {
  @override
  String get tableName => 'comic_collect';

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

@DataClassName('ComicHistoryRow')
class ComicHistoryEntries extends Table {
  @override
  String get tableName => 'comic_history';

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  /// 打开历史时来源可能已下线，标题/封面随历史一起留底。
  TextColumn get title => text()();
  TextColumn get coverUrl => text().nullable()();

  /// 章节 id（可选，仅作展示辅助；进度权威是 page/pageCount）。
  TextColumn get chapterId => text().withDefault(const Constant(''))();

  IntColumn get page => integer().withDefault(const Constant(0))();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get openedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, sourceName};
}

@DataClassName('ComicSearchTermRow')
class ComicSearchTerms extends Table {
  @override
  String get tableName => 'comic_search_term';

  TextColumn get term => text()();

  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {term};
}

@DataClassName('ComicDownloadRow')
class ComicDownloadTasks extends Table {
  @override
  String get tableName => 'comic_download_task';

  /// 任务 id（模块内唯一，不与媒体主键绑定）。
  TextColumn get taskId => text()();

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  /// 章节 id；整本下载时留空串。
  TextColumn get chapterId => text().withDefault(const Constant(''))();

  /// 状态机字符串：pending/running/done/failed；合法性由 download.dart 把守。
  TextColumn get status => text()();

  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();

  /// 仅 failed 时有值。
  TextColumn get error => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {taskId};
}

@DataClassName('ComicImageCacheRow')
class ComicImageCacheEntries extends Table {
  @override
  String get tableName => 'comic_image_cache';

  /// 缓存键：章节下每张图的稳定标识（如 URL 或本地相对路径）。
  TextColumn get cacheKey => text()();

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  TextColumn get chapterId => text().withDefault(const Constant(''))();

  /// 缓存文件路径（模块自己定，core 不解释）。
  TextColumn get filePath => text()();

  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

@DataClassName('ComicLocalRow')
class ComicLocalEntries extends Table {
  @override
  String get tableName => 'comic_local';

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  TextColumn get title => text()();
  TextColumn get folderPath => text()();

  TextColumn get coverPath => text().nullable()();

  IntColumn get pageCount => integer().withDefault(const Constant(0))();

  /// 模块私有 JSON；core 投影不解析。
  TextColumn get payload => text().withDefault(const Constant('{}'))();

  DateTimeColumn get importedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, sourceName};
}

@DriftDatabase(
  tables: [
    ComicCollectEntries,
    ComicHistoryEntries,
    ComicSearchTerms,
    ComicDownloadTasks,
    ComicImageCacheEntries,
    ComicLocalEntries,
  ],
)
class ComicDb extends _$ComicDb {
  /// 生产构造：与 core 库同目录，文件名区分（mimao_comic.sqlite）。
  ComicDb() : super(driftDatabase(name: 'mimao_comic'));

  /// 测试构造：注入内存/临时 executor（NativeDatabase.memory()）。
  ComicDb.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  Future<ComicCollectRow?> collectRow(ComicRef ref) =>
      (select(comicCollectEntries)..where(
            (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
          ))
          .getSingleOrNull();

  Future<ComicHistoryRow?> historyRow(ComicRef ref) =>
      (select(comicHistoryEntries)..where(
            (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
          ))
          .getSingleOrNull();

  Future<ComicLocalRow?> localRow(ComicRef ref) =>
      (select(comicLocalEntries)..where(
            (t) => t.id.equals(ref.id) & t.sourceName.equals(ref.sourceName),
          ))
          .getSingleOrNull();

  Future<ComicDownloadRow?> downloadRow(String taskId) => (select(
    comicDownloadTasks,
  )..where((t) => t.taskId.equals(taskId))).getSingleOrNull();
}
