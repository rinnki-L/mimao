import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mimao/core/contract.dart';

part 'db.g.dart';

/// 把 MediaType 存成文本（枚举名），读写两端显式转换。
/// 不用 `textEnum<T>()`：drift_dev 2.31 对它的泛型链解析有 bug（build_runner 崩溃）；
/// 显式 converter 反而让"字符串 ↔ 枚举"的契约一眼可见（demo 04 本就是这个意思）。
class MediaTypeConverter extends TypeConverter<MediaType, String> {
  const MediaTypeConverter();

  @override
  MediaType fromSql(String fromDb) =>
      MediaType.values.firstWhere((e) => e.name == fromDb);

  @override
  String toSql(MediaType value) => value.name;
}

/// 统一书架投影表（docs/architecture.md §3.2 的 M1 冻结最小面）。
///
/// 权威在模块内部存储；本表只是"跨类型索引 + 时间线"。写入点与校正点规则
/// 见 docs/architecture.md §3.1 的规则①-④。
@DataClassName('MediaEntryRow')
class MediaEntries extends Table {
  /// 源内唯一键，如 "kazumi:1001" / "venera:srcA:12345" / "legado:书源id:书id"。
  TextColumn get id => text()();

  TextColumn get mediaType => text().map(const MediaTypeConverter())();

  /// 来自哪个源/规则包——同一作品可从多个源打开，靠它区分。
  TextColumn get sourceName => text()();

  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  /// 各模块私有 JSON，壳永不解析（demo 04 的约定）。
  TextColumn get payload => text()();

  /// 模块写好的展示文案，如"看到第 12 话"/"第1432章 · 32%"——壳只读不解析。
  TextColumn get progressText => text()();

  /// 收藏布尔：可索引可筛选，不必退化为 payload 字符串匹配。
  /// 默认值由 facade（library.dart）的 upsert 显式写入，不靠 SQL DEFAULT。
  BoolColumn get starred => boolean()();

  DateTimeColumn get lastOpenedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  /// 复合主键：同一作品在不同源里是两条记录，时间线里都出现（demo 04）。
  @override
  Set<Column> get primaryKey => {id, mediaType, sourceName};
}

/// 应用设置 kv（同库一张表，不加新依赖——docs/architecture.md §3.3）。
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [MediaEntries, AppSettings])
class AppDb extends _$AppDb {
  /// 生产构造：drift_flutter 用 path_provider 定根，Windows 落在应用支持目录。
  AppDb() : super(driftDatabase(name: 'mimao'));

  /// 测试构造：注入内存/临时 executor（NativeDatabase.memory()）。
  AppDb.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // 番剧已下线：清掉旧库残留的 anime 投影行，否则 MediaTypeConverter
        // 读到已删除的枚举名会抛异常，整个书架渲染失败。
        await m.database.customStatement(
          "DELETE FROM media_entries WHERE media_type = 'anime'",
        );
      }
    },
  );
}
