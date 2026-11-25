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

  /// 书架自定义分组名；null = 未分组。单本书只属于一个分组（与书架分组
  /// 管理的"一组多本"对应，足够覆盖筛选场景，不做多标签）。
  TextColumn get groupName => text().nullable()();

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

  /// 当前读到的章号（从 1 起；0 表示无进度）。
  /// 注意：书源引擎产出的 `NovelChapter.index` 是 0 起（对齐 legado），
  /// 阅读页落库时 +1 转成章号（novel_reader_page.dart），续读时再 -1 取目录
  /// 下标（novel_book_detail_page.dart）。0 是"没读"哨兵，不是第 1 章。
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

/// 模块私有 kv（阅读目标、书架布局、排序等）。刻意不进 core `app_settings`：
/// 那是壳/全局设置表，模块设置留在模块自己的库里（architecture §3.3）。
@DataClassName('NovelPrefRow')
class NovelPrefs extends Table {
  @override
  String get tableName => 'novel_pref';

  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 按天聚合的阅读时长（秒）。写入方是阅读页（退出 / 切章时结算）；
/// 统计卡与今日目标都从这里取数，不估算、不造假。
@DataClassName('NovelReadingDayRow')
class NovelReadingDays extends Table {
  @override
  String get tableName => 'novel_reading_day';

  /// 本地日期 `yyyy-MM-dd`（阅读时长按用户本地日切分）。
  TextColumn get day => text()();

  IntColumn get seconds => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {day};
}

/// 书签：锚点一律是 (章下标, 段落下标, 段内字符偏移)，不用页码/比例。
///
/// 列名对齐上游 legado 的 Bookmark（bookName/bookAuthor/chapterIndex/
/// chapterPos/bookText），章节标题用来在换源后按「标题 + 段落」重定位。
/// 同一本书换源会换 [sourceKey]：去重只看 bookId + 源 + 章 + 段 + 偏移。
@DataClassName('NovelBookmarkRow')
class NovelBookmarkEntries extends Table {
  @override
  String get tableName => 'bookmark';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get bookId => text()();

  TextColumn get sourceKey => text().withDefault(const Constant(''))();

  /// 书名列（参考上游 bookName）：全书书签列表按书分组时不必回查收藏表。
  TextColumn get bookTitle => text().withDefault(const Constant(''))();

  TextColumn get bookAuthor => text().withDefault(const Constant(''))();

  /// 书源详情页地址：从书签列表重新打开阅读器时重建 NovelRef 用
  /// （跨会话没有内存里的 detail 可依）。
  TextColumn get bookUrl => text().withDefault(const Constant(''))();

  /// 0 起章下标（引擎口径，与 [NovelLocator.chapterIndex] 一致）。
  IntColumn get chapterIndex => integer()();

  /// 0 起段落下标；-1 表示章标题。
  IntColumn get paragraph => integer().withDefault(const Constant(0))();

  /// 段内字符偏移（不含段首缩进）。
  IntColumn get charOffset => integer().withDefault(const Constant(0))();

  TextColumn get chapterName => text().withDefault(const Constant(''))();

  TextColumn get excerpt => text().withDefault(const Constant(''))();

  /// 换源后按章标题/段落尽力重定位；失败置 true，列表里标「无法定位」，
  /// 不删行（上游同样保留书签，跳转前再问用户）。
  BoolColumn get unresolved => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
}

/// 划线/笔记：与书签同构的锚点，加一个段内区间 [startOffset, endOffset)。
///
/// 样式落 [styleJson]（颜色 + 装饰），笔记落 [note]；渲染层只加背景/装饰，
/// 不插 Widget，正文行高不受影响。
@DataClassName('NovelMarkingRow')
class NovelMarkingEntries extends Table {
  @override
  String get tableName => 'marking';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get bookId => text()();

  TextColumn get sourceKey => text().withDefault(const Constant(''))();

  TextColumn get bookTitle => text().withDefault(const Constant(''))();

  TextColumn get bookAuthor => text().withDefault(const Constant(''))();

  TextColumn get bookUrl => text().withDefault(const Constant(''))();

  IntColumn get chapterIndex => integer()();

  IntColumn get paragraph => integer().withDefault(const Constant(0))();

  IntColumn get startOffset => integer().withDefault(const Constant(0))();

  IntColumn get endOffset => integer().withDefault(const Constant(0))();

  TextColumn get chapterName => text().withDefault(const Constant(''))();

  /// `{"color": <argb>, "decoration": "background|underline|wavy"}`。
  TextColumn get styleJson => text().withDefault(const Constant('{}'))();

  TextColumn get note => text().withDefault(const Constant(''))();

  BoolColumn get unresolved => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// 高亮规则：正则 → 日夜两套样式，[bookId] 为空表示全局。
///
/// 规则与书签/划线不同：它不改正文、不落段落区间，只描述「什么样的文字
/// 画成什么样」；渲染时按当前段落文本现场匹配。颜色存 ARGB 整数，避免
/// 用户在深/浅主题间切换后旧规则变色。
@DataClassName('NovelHighlightRuleRow')
class NovelHighlightRules extends Table {
  @override
  String get tableName => 'novel_highlight_rule';

  IntColumn get id => integer().autoIncrement()();

  /// 空串 = 全局；非空只对该 bookId 生效。
  TextColumn get bookId => text().withDefault(const Constant(''))();

  TextColumn get name => text().withDefault(const Constant(''))();

  /// 正则表达式（高亮只支持正则）。
  TextColumn get pattern => text()();

  IntColumn get foregroundLight => integer()();

  IntColumn get backgroundLight => integer().nullable()();

  IntColumn get foregroundDark => integer()();

  IntColumn get backgroundDark => integer().nullable()();

  BoolColumn get underline => boolean().withDefault(const Constant(false))();

  BoolColumn get bold => boolean().withDefault(const Constant(false))();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 导入时的原始 JSON（手工新建为 `{}`）。
  TextColumn get raw => text().withDefault(const Constant('{}'))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// 单章正文的本地覆盖：用户编辑后优先于网络/缓存正文，随时可恢复原样。
///
/// 主键用 `(bookId, sourceKey, chapterKey)`：换源后 chapterKey 会变，旧覆盖
/// 仍按原源留着，不误套到新源的同一章上。`chapterKey` 取章节 id（进不了
/// 目录索引时退回 url），与引擎的 [NovelChapter.id] 口径一致。
@DataClassName('NovelContentOverrideRow')
class NovelContentOverrides extends Table {
  @override
  String get tableName => 'novel_content_override';

  TextColumn get bookId => text()();

  TextColumn get sourceKey => text().withDefault(const Constant(''))();

  TextColumn get chapterKey => text()();

  TextColumn get chapterTitle => text().withDefault(const Constant(''))();

  /// 编辑后的章节标题；空串表示沿用原章节标题。
  TextColumn get title => text().withDefault(const Constant(''))();

  /// 正文段落 JSON 数组（`["第一段", "第二段"]`）。
  TextColumn get paragraphsJson => text()();

  IntColumn get paragraphCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId, sourceKey, chapterKey};
}

@DriftDatabase(
  tables: [
    NovelCollectEntries,
    NovelHistoryEntries,
    NovelSearchTerms,
    NovelPrefs,
    NovelReadingDays,
    NovelBookmarkEntries,
    NovelMarkingEntries,
    NovelHighlightRules,
    NovelContentOverrides,
  ],
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
  int get schemaVersion => 4;

  /// v1 → v2：书架分组列 + 模块 kv + 阅读时长按天表。三者都是增量，旧行无需
  /// 回填（groupName 缺省 null、今日/总时长从 0 起算）。
  ///
  /// v2 → v3：书签与划线两张新表；纯增量，旧表一行都不动。
  ///
  /// v3 → v4：高亮规则表 + 单章内容覆盖表；同样纯增量，已有书签/划线不动。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(novelCollectEntries, novelCollectEntries.groupName);
        await m.createTable(novelPrefs);
        await m.createTable(novelReadingDays);
      }
      if (from < 3) {
        await m.createTable(novelBookmarkEntries);
        await m.createTable(novelMarkingEntries);
      }
      if (from < 4) {
        await m.createTable(novelHighlightRules);
        await m.createTable(novelContentOverrides);
      }
    },
  );

  /// 单行读取辅助（收藏）；null 表示无行。
  Future<NovelCollectRow?> collectRow(NovelRef ref) => (select(
    novelCollectEntries,
  )..where((t) => t.id.equals(ref.id))).getSingleOrNull();

  /// 单行读取辅助（历史）；null 表示无行。
  Future<NovelHistoryRow?> historyRow(NovelRef ref) => (select(
    novelHistoryEntries,
  )..where((t) => t.id.equals(ref.id))).getSingleOrNull();

  /// 模块 kv 读取（服务层另有带类型语义的包装）。
  Future<String?> readPref(String key) async {
    final row = await (select(
      novelPrefs,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 模块 kv 写入。
  Future<void> writePref(String key, String value) => into(
    novelPrefs,
  ).insertOnConflictUpdate(NovelPrefsCompanion.insert(key: key, value: value));
}
