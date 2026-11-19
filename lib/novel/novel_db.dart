import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'novel_db.g.dart';

/// 小说模块的**内部权威库**（双记账的"模块库"一侧）。
///
/// 与 `core/db.dart` 的 `media_entries` 投影表刻意分开：
/// - 这里存模块自己的完整数据（书籍 JSON、阅读章节进度、搜索词）；
/// - `media_entries` 只由 `novel_projection.dart` 在持久化点/打开点写入公共列。
/// 两库同进程打开，测试各自用 `NativeDatabase.memory()`。
///
/// 小说有源维度但内部库主键只用 `id`（与 music 一致）；`sourceName` 只进投影，
/// 投影 `sourceName` 恒为 [novelSourceName]。
@DataClassName('NovelCollectRow')
class NovelCollectEntries extends Table {
  @override
  String get tableName => 'novel_collect';

  /// `NovelSummary.id`。
  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  /// 书籍 JSON（完整 `NovelSummary.toJson`）；投影里的 payload 是进度摘要，
  /// 不是这一列。
  TextColumn get payload => text().withDefault(const Constant('{}'))();

  DateTimeColumn get collectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NovelHistoryRow')
class NovelHistoryEntries extends Table {
  @override
  String get tableName => 'novel_history';

  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  /// 当前读到的章节序号（从 1 起；0 表示无进度）。
  IntColumn get chapterIndex => integer().withDefault(const Constant(0))();

  /// 目录总章数（<=0 表示未知）。
  IntColumn get chapterCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get openedAt => dateTime()();

  IntColumn get readCount => integer().withDefault(const Constant(1))();

  /// 书籍 JSON，历史续读据此重建 [NovelSummary]。
  TextColumn get payload => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NovelSearchTermRow')
class NovelSearchTerms extends Table {
  @override
  String get tableName => 'novel_search_term';

  TextColumn get keyword => text()();

  DateTimeColumn get searchedAt => dateTime()();

  IntColumn get hits => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {keyword};
}

@DriftDatabase(
  tables: [NovelCollectEntries, NovelHistoryEntries, NovelSearchTerms],
)
class NovelDb extends _$NovelDb {
  /// 生产构造：与 core 库同目录，文件名区分（mimao_novel.sqlite）。
  ///
  /// 这里用 [LazyDatabase] 而不是 `driftDatabase(name:)`：后者的连接工厂在
  /// **构造时**就会调度 path_provider 调用，而 registry 的既有测试并不注入
  /// 小说库（无插件环境），构造即触达插件会让整轮测试挂起。惰性 executor
  /// 让「注册小说模块」保持零 I/O，首次真实查询才打开库。
  NovelDb() : super(_openConnection());

  /// 测试构造：注入内存/临时 executor（NativeDatabase.memory()）。
  NovelDb.forTesting(super.executor);

  static QueryExecutor _openConnection() => LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      File(p.join(directory.path, 'mimao_novel.sqlite')),
    );
  });

  @override
  int get schemaVersion => 1;

  /// 单行读取辅助（收藏）；null 表示无行。
  Future<NovelCollectRow?> collectRow(NovelRef ref) => (select(
    novelCollectEntries,
  )..where((t) => t.id.equals(ref.id))).getSingleOrNull();

  /// 单行读取辅助（历史）；null 表示无行。
  Future<NovelHistoryRow?> historyRow(NovelRef ref) => (select(
    novelHistoryEntries,
  )..where((t) => t.id.equals(ref.id))).getSingleOrNull();
}
