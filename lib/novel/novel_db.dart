import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mimao/novel/device_id.dart';
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

  /// 用户手写备注（自由文本，空串 = 无备注）。与"分组/系列"不同，它是
  /// 给人看的碎碎念，不参与筛选与排序。
  TextColumn get note => text().withDefault(const Constant(''))();

  /// 自定义封面：本地图片路径（复制进应用支持目录后存的绝对路径）；
  /// null = 继续用书籍自带的 coverUrl。
  TextColumn get customCoverPath => text().nullable()();

  /// 所属系列（`novel_series.id`）；null = 不属于任何系列。
  /// 系列与分组正交：分组是"我把它放哪"，系列是"这本书属于哪个作品集"。
  IntColumn get seriesId => integer().nullable()();

  DateTimeColumn get collectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 书架系列（作品集）：一组同系列的书（如三部曲）在书架上归组显示。
///
/// 单独一张表而不是往收藏行写系列名字符串：重命名系列只改一行，
/// 删除系列只把成员 seriesId 置空，不会把书名/分组连带改坏。
@DataClassName('NovelSeriesRow')
class NovelSeriesEntries extends Table {
  @override
  String get tableName => 'novel_series';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  DateTimeColumn get createdAt => dateTime()();
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

/// 阅读记录：**设备 × 书 × 章 × 本地日** 一行（v7 起，取代 `novel_reading_day`）。
///
/// 旧表是「一天一行」，没有书/章/设备维度，做不了时间轴、章节维度和区 11 的
/// 多设备合并。现在每个维度都留一格：
/// - 日聚合 = 按 [day] 求和（本机聚合视图，首页/我的页继续走）；
/// - 时间轴 = 按 [day] 分组、再按 [bookId] 聚合；
/// - 章节维度 = 按 (bookId, chapterIndex) 聚合；
/// - 多设备 = 写入时带本机 [deviceId]，同步时按设备维度合并，不互相覆盖。
///
/// 主键带 [chapterIndex] 而不是只有设备×书×日：同一本书同一天读了两章要能
/// 分开记，否则章节维度拿不到每章时长。章号 1 起、0 = 未知；旧数据迁移来的行
/// 没有书/章信息，落在 bookId='' + chapterIndex=0，只进日聚合。
@DataClassName('NovelReadRecordRow')
class NovelReadRecords extends Table {
  @override
  String get tableName => 'novel_read_record';

  /// 设备 ID（`novel_pref.device_id`；旧数据迁移时填本机）。
  TextColumn get deviceId => text()();

  /// 书籍主键；空串 = 旧数据/未关联书籍。
  TextColumn get bookId => text()();

  /// 书名快照：时间轴不必回查收藏/历史表，删书后记录仍可读。
  TextColumn get bookTitle => text().withDefault(const Constant(''))();

  /// 章号（1 起；0 = 未知），与 `novel_history.chapter_index` 同口径。
  IntColumn get chapterIndex => integer().withDefault(const Constant(0))();

  TextColumn get chapterName => text().withDefault(const Constant(''))();

  /// 本地日期 `yyyy-MM-dd`（阅读时长按用户本地日切分）。
  TextColumn get day => text()();

  IntColumn get seconds => integer().withDefault(const Constant(0))();

  DateTimeColumn get firstReadAt => dateTime()();

  DateTimeColumn get lastReadAt => dateTime()();

  @override
  Set<Column> get primaryKey => {deviceId, bookId, chapterIndex, day};
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

/// 朗读音频缓存索引（L2）：一段一行的 wav 元数据。
///
/// 文件落在应用支持目录的 `novel_tts_cache/`，这里只存索引；`cacheKey` 是
/// `(书, 章节, 段落, 音色, 语速)` 的可读键的 sha256，命中后直接播文件、
/// 免重合成。容量按 [lastUsedAt] 淘汰最久未用的行，并删除对应文件。
@DataClassName('NovelTtsCacheRow')
class NovelTtsCacheEntries extends Table {
  @override
  String get tableName => 'novel_tts_cache';

  /// sha256(bookId|chapterKey|paragraph|voice|rate)。
  TextColumn get cacheKey => text()();

  TextColumn get path => text()();

  /// 文件字节数，用于容量统计。
  IntColumn get bytes => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

/// 本地导入的书（TXT / EPUB / Markdown 第二条通路）。
///
/// 文件**不进库**：只记原地路径，阅读时按需读。目录解析结果落 [tocJson]
/// （TXT/Markdown 是章节的字节区间，EPUB 是 spine 里的 href），这样打开书
/// 不必每次重扫全文；文件被移动/删除时由服务抛 `NovelLocalFileMissing`，
/// 页面给「重新定位文件」入口。
///
/// 主键与收藏/历史/书签同一个 [id] 口径（`local:…`），进度、书签、划线、
/// 替换规则、TTS 全部复用现有链路，不需要第二套表。
@DataClassName('NovelLocalBookRow')
class NovelLocalBooks extends Table {
  @override
  String get tableName => 'novel_local_book';

  TextColumn get id => text()();

  /// 导入时的绝对路径（重新定位后改写这里）。
  TextColumn get path => text()();

  TextColumn get title => text()();

  TextColumn get author => text().withDefault(const Constant(''))();

  /// `txt` / `epub` / `md`。
  TextColumn get format => text()();

  /// 嗅探到的编码名（utf-8 / utf-16le / gbk / gb18030 / big5）；EPUB 为空。
  TextColumn get encoding => text().nullable()();

  IntColumn get byteSize => integer().withDefault(const Constant(0))();

  IntColumn get chapterCount => integer().withDefault(const Constant(0))();

  /// 目录 JSON：`[{"t": 标题, "s": 起始字节, "e": 结束字节, "h": href}]`。
  TextColumn get tocJson => text().withDefault(const Constant('[]'))();

  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// TXT 目录规则：一行一条正则，按 [sortOrder] 顺序尝试；命中即分章。
///
/// 与 legado 的 `TxtTocRule` 同构（name/rule/enable），但只存正则本身：
/// 预览匹配结果由导入页用真实文件跑，规则表不存示例文本。
@DataClassName('NovelTxtTocRuleRow')
class NovelTxtTocRules extends Table {
  @override
  String get tableName => 'novel_txt_toc_rule';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  /// 正则表达式（对每一行整行匹配）。
  TextColumn get pattern => text()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 内置规则：可停用、可改，删除后可用「恢复默认」找回。
  BoolColumn get builtin => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime()();
}

@DriftDatabase(
  tables: [
    NovelCollectEntries,
    NovelSeriesEntries,
    NovelHistoryEntries,
    NovelSearchTerms,
    NovelPrefs,
    NovelReadRecords,
    NovelBookmarkEntries,
    NovelMarkingEntries,
    NovelHighlightRules,
    NovelContentOverrides,
    NovelTtsCacheEntries,
    NovelLocalBooks,
    NovelTxtTocRules,
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
  int get schemaVersion => 8;

  /// v1 → v2：书架分组列 + 模块 kv + 阅读时长按天表。三者都是增量，旧行无需
  /// 回填（groupName 缺省 null、今日/总时长从 0 起算）。
  ///
  /// v2 → v3：书签与划线两张新表；纯增量，旧表一行都不动。
  ///
  /// v3 → v4：高亮规则表 + 单章内容覆盖表；同样纯增量，已有书签/划线不动。
  ///
  /// v4 → v5：朗读音频缓存索引表；旧表一行不动，缓存文件由服务按需重建。
  ///
  /// v5 → v6：收藏行加备注 / 自定义封面 / 系列归属三列，另建系列表。
  /// 旧行三个新列取默认值（备注空串、封面 null、系列 null），无需回填。
  ///
  /// v6 → v7：本地书表 + TXT 目录规则表（本地 TXT/EPUB/Markdown 第二条通路）。
  /// 纯增量；规则表首次读取时由服务补内置规则，迁移不写业务数据。
  ///
  /// v7 → v8：阅读记录从「一天一行」的 `novel_reading_day` 换成
  /// 「设备 × 书 × 章 × 日」的 `novel_read_record`，为时间轴/章节维度/区 11
  /// 的多设备同步打底。旧表的每一天迁成一行 `deviceId = 本机`、
  /// `bookId = ''`、`chapterIndex = 0` 的记录（只进日聚合，不进时间轴/章节维度），
  /// 迁完删旧表。迁移本身幂等：新表主键冲突走覆盖，重复执行不会翻倍。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(novelCollectEntries, novelCollectEntries.groupName);
        await m.createTable(novelPrefs);
        // 老版本在这里建 `novel_reading_day`；v8 已把它换成 `novel_read_record`，
        // 表类也删了。v1 用户升上来时这张表本来就是空的，直接不建，v8 的
        // 迁移对「旧表不存在」是安全的。
      }
      if (from < 3) {
        await m.createTable(novelBookmarkEntries);
        await m.createTable(novelMarkingEntries);
      }
      if (from < 4) {
        await m.createTable(novelHighlightRules);
        await m.createTable(novelContentOverrides);
      }
      if (from < 5) {
        await m.createTable(novelTtsCacheEntries);
      }
      if (from < 6) {
        await m.createTable(novelSeriesEntries);
        await m.addColumn(novelCollectEntries, novelCollectEntries.note);
        await m.addColumn(
          novelCollectEntries,
          novelCollectEntries.customCoverPath,
        );
        await m.addColumn(novelCollectEntries, novelCollectEntries.seriesId);
      }
      if (from < 7) {
        await m.createTable(novelLocalBooks);
        await m.createTable(novelTxtTocRules);
      }
      if (from < 8) {
        await _migrateReadingRecords(m);
      }
    },
  );

  /// v7 → v8 的阅读记录迁移。拆成独立方法便于单测直接驱动（不依赖 drift 的
  /// 版本门），也便于 `onUpgrade` 之外的重跑。
  ///
  /// 幂等要点：
  /// - 建表用 `createTable`（drift 会先 `CREATE TABLE IF NOT EXISTS`）；
  /// - 旧表不存在（新装用户走 onCreate / 已迁移过）直接跳过；
  /// - 写入用主键冲突覆盖，同一天迁两次仍是同一行；
  /// - 旧表迁完即删，再跑时 `hasTable` 为 false，天然短路。
  Future<void> _migrateReadingRecords(Migrator m) async {
    await m.createTable(novelReadRecords);
    if (!await _tableExists('novel_reading_day')) return;
    final deviceId = await ensureDeviceId();
    final legacy = await customSelect(
      'SELECT day, seconds FROM novel_reading_day',
      readsFrom: <ResultSetImplementation<dynamic, dynamic>>{},
    ).get();
    final now = DateTime.now();
    for (final row in legacy) {
      final day = row.read<String>('day');
      final seconds = row.read<int>('seconds');
      if (day.isEmpty || seconds <= 0) continue;
      await into(novelReadRecords).insert(
        NovelReadRecordsCompanion.insert(
          deviceId: deviceId,
          bookId: '',
          day: day,
          seconds: Value<int>(seconds),
          firstReadAt: _dayStartFor(day, fallback: now),
          lastReadAt: _dayStartFor(day, fallback: now),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
    await customStatement('DROP TABLE IF EXISTS novel_reading_day');
  }

  /// 旧表是否存在（`sqlite_master` 查询，drift 的 Migrator 没有公开探测）。
  Future<bool> _tableExists(String name) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable<Object>>[Variable<String>(name)],
    ).get();
    return rows.isNotEmpty;
  }

  /// 日键 → 当天零点；坏数据回落到 [fallback]（迁移不能因为一行坏日期中断）。
  static DateTime _dayStartFor(String day, {required DateTime fallback}) {
    final parts = day.split('-');
    if (parts.length != 3) return fallback;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final date = int.tryParse(parts[2]);
    if (year == null || month == null || date == null) return fallback;
    return DateTime(year, month, date);
  }

  /// 本机设备 ID：首次读取时生成 UUID 并落模块 kv，之后恒定返回同一个值。
  ///
  /// 生成/写回在同一事务里，避免两个并发首读各生成一个 ID（后者覆盖前者
  /// 会让先写入的阅读记录变成「别的设备」）。
  Future<String> ensureDeviceId() async {
    final existing = await readPref(novelPrefDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    return transaction(() async {
      final raced = await readPref(novelPrefDeviceId);
      if (raced != null && raced.isNotEmpty) return raced;
      final generated = generateNovelDeviceId();
      await writePref(novelPrefDeviceId, generated);
      return generated;
    });
  }

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
