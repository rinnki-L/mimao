import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/music_models.dart';

part 'music_db.g.dart';

/// 音乐模块的**内部权威库**（双记账的"模块库"一侧）。
///
/// 与 `core/db.dart` 的 `media_entries` 投影表刻意分开：
/// - 这里存模块自己的完整数据（歌曲 JSON、播放毫秒数、搜索词）；
/// - `media_entries` 只由 `music_projection.dart` 在持久化点/打开点写入公共列。
/// 两库同进程打开，测试各自用 `NativeDatabase.memory()`。
///
/// 音乐没有源维度：主键只有 `id`，投影 `sourceName` 恒为
/// [kugouSourceName]（与 core `media_entries` 的复合主键对齐）。
@DataClassName('MusicCollectRow')
class MusicCollectEntries extends Table {
  @override
  String get tableName => 'music_collect';

  /// `MusicSong.id`（缺省时由 `musicRefOf` 回退到 hash）。
  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  /// 歌曲 JSON（完整 `MusicSong.toJson`）；投影里的 payload 是进度摘要，
  /// 不是这一列。
  TextColumn get payload => text().withDefault(const Constant('{}'))();

  DateTimeColumn get collectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MusicHistoryRow')
class MusicHistoryEntries extends Table {
  @override
  String get tableName => 'music_history';

  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  IntColumn get positionMs => integer().withDefault(const Constant(0))();

  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  DateTimeColumn get openedAt => dateTime()();

  IntColumn get playCount => integer().withDefault(const Constant(1))();

  /// 歌曲 JSON，历史续播据此重建 [MusicSong]。
  TextColumn get payload => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MusicSearchTermRow')
class MusicSearchTerms extends Table {
  @override
  String get tableName => 'music_search_term';

  TextColumn get keyword => text()();

  DateTimeColumn get searchedAt => dateTime()();

  IntColumn get hits => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {keyword};
}

@DriftDatabase(
  tables: [MusicCollectEntries, MusicHistoryEntries, MusicSearchTerms],
)
class MusicDb extends _$MusicDb {
  /// 生产构造：与 core 库同目录，文件名区分（mimao_music.sqlite）。
  ///
  /// 这里用 [LazyDatabase] 而不是 `driftDatabase(name:)`：后者的连接工厂在
  /// **构造时**就会调度 path_provider 调用，而 registry 的既有测试并不注入
  /// 音乐库（无插件环境），构造即触达插件会让整轮测试挂起。惰性 executor
  /// 让「注册音乐模块」保持零 I/O，首次真实查询才打开库。
  MusicDb() : super(_openConnection());

  /// 测试构造：注入内存/临时 executor（NativeDatabase.memory()）。
  MusicDb.forTesting(super.executor);

  static QueryExecutor _openConnection() => LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(directory.path, 'mimao_music.sqlite')),
    );
  });

  @override
  int get schemaVersion => 1;

  /// 单行读取辅助（收藏）；null 表示无行。
  Future<MusicCollectRow?> collectRow(MusicRef ref) => (select(
    musicCollectEntries,
  )..where((t) => t.id.equals(ref.id))).getSingleOrNull();

  /// 单行读取辅助（历史）；null 表示无行。
  Future<MusicHistoryRow?> historyRow(MusicRef ref) => (select(
    musicHistoryEntries,
  )..where((t) => t.id.equals(ref.id))).getSingleOrNull();
}
