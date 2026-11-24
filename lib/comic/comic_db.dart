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

/// 稍后阅读：详情页点「稍后阅读」后落在这里，主页卡片据此展示。
///
/// 与收藏刻意分表：稍后阅读是「待读队列」，不参与 core 书架投影（不占
/// starred 位、不进时间线）；用户从卡片打开详情即视为已消费，可手动移除。
@DataClassName('ComicReadLaterRow')
class ComicReadLaterEntries extends Table {
  @override
  String get tableName => 'comic_read_later';

  TextColumn get id => text()();
  TextColumn get sourceName => text()();

  TextColumn get title => text()();
  TextColumn get coverUrl => text().nullable()();

  /// 源内的详情标识（通常就是 [id]）留底，便于将来换源/迁移。
  TextColumn get detailUrl => text().withDefault(const Constant(''))();

  DateTimeColumn get addedAt => dateTime()();

  /// 模块私有 JSON（预留；core 不解释）。
  TextColumn get payload => text().withDefault(const Constant('{}'))();

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

/// 单张图片收藏（对齐 Venera-Next 的 image_favorites）。
///
/// 一行 = 「某部漫画某章第 N 张图被收藏」。主键用
/// {sourceName, comicId, chapterId, page} 而不是自增 id：同一张图重复收藏
/// 天然幂等，跨进程/跨设备合并也不会产生重复行。
///
/// [imageUrl] 存的是源给的图片地址（只作展示与回跳，不保证长期有效）；
/// 阅读器回跳时按 chapterId + page 定位，不依赖地址还能打开。
@DataClassName('ComicImageFavoriteRow')
class ComicImageFavoriteEntries extends Table {
  @override
  String get tableName => 'comic_image_favorite';

  TextColumn get sourceName => text()();
  TextColumn get comicId => text()();
  TextColumn get chapterId => text()();
  IntColumn get page => integer()();

  /// 漫画标题 / 章节标题：历史里删了书也要能显示。
  TextColumn get comicTitle => text()();
  TextColumn get chapterTitle => text().withDefault(const Constant(''))();

  /// 图片地址与封面（可为空：本地漫画走 file://）。
  TextColumn get imageUrl => text().withDefault(const Constant(''))();
  TextColumn get coverUrl => text().nullable()();

  /// 详情地址：回跳时据此重新拉章节列表（本地漫画为空，走本地内容读取）。
  TextColumn get detailUrl => text().withDefault(const Constant(''))();

  /// 章内总页数与章序号（1 基），用于"跳到该图"与排序。
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  IntColumn get chapterNumber => integer().withDefault(const Constant(0))();

  DateTimeColumn get collectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sourceName, comicId, chapterId, page};
}

@DriftDatabase(
  tables: [
    ComicCollectEntries,
    ComicHistoryEntries,
    ComicReadLaterEntries,
    ComicSearchTerms,
    ComicDownloadTasks,
    ComicImageCacheEntries,
    ComicLocalEntries,
    ComicImageFavoriteEntries,
  ],
)
class ComicDb extends _$ComicDb {
  /// 生产构造：与 core 库同目录，文件名区分（mimao_comic.sqlite）。
  ComicDb() : super(driftDatabase(name: 'mimao_comic'));

  /// 测试构造：注入内存/临时 executor（NativeDatabase.memory()）。
  ComicDb.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  /// v1 → v2：新增「稍后阅读」表。旧库不重建，只补表（drift 的
  /// `createTable` 在 SQLite 上是幂等的 IF NOT EXISTS 语义）。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(comicReadLaterEntries);
      }
      // v2 → v3：新增「图片收藏」表；旧数据不动。
      if (from < 3) {
        await m.createTable(comicImageFavoriteEntries);
      }
    },
  );

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
