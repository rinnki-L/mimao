/// 小说本地库门面（数据层切片）：NovelDb + 三服务共用的窄接口。
///
/// 与 music/library_api.dart 同款：接口放在契约层，页面/入口只依赖接口，
/// 具体 drift 库与服务在各自文件实现，便于并行与 fake 注入。
library;

import 'package:mimao/novel/models/novel_models.dart';

/// 小说 → 内部权威主键。
///
/// [NovelSummary.id] 是必填字段，因此这里不像音乐那样需要 hash 回退；
/// `sourceName` 随书一起带出（内部库主键仍只用 id，sourceName 只进投影）。
NovelRef novelRefOf(NovelSummary book) => NovelRef(
  id: book.id,
  sourceName: book.sourceName,
  sourceKey: book.sourceKey,
  bookUrl: book.bookUrl,
);

/// 一条收藏（权威行 + 可重建的书籍快照）。
class NovelCollectItem {
  const NovelCollectItem({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.book,
    required this.collectedAt,
    this.groupName,
    this.note = '',
    this.customCoverPath,
    this.seriesId,
  });

  final NovelRef ref;
  final String title;
  final String? coverUrl;

  /// 收藏时落底的书籍 JSON 反序列化结果；旧数据/坏数据为 null。
  final NovelSummary? book;

  /// 书架自定义分组；null = 未分组。
  final String? groupName;

  /// 手写备注（空串 = 无）。
  final String note;

  /// 自定义封面本地路径；null = 用书籍自带封面。
  final String? customCoverPath;

  /// 所属系列 id；null = 无系列。
  final int? seriesId;

  final DateTime collectedAt;

  /// 「我的」页展示用作者名（无书籍快照时为空串）。
  String get authorText => book?.author ?? '';

  /// 书架封面实际地址：自定义封面优先（本地文件），否则书源封面。
  String get effectiveCoverUrl => customCoverPath ?? book?.coverUrl ?? '';
}

/// 一个书架系列（作品集）。
class NovelSeriesItem {
  const NovelSeriesItem({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final int id;
  final String name;
  final DateTime createdAt;
}

/// 收藏门面（权威库 `novel_collect`，写后投影 core）。
abstract interface class NovelCollectApi {
  Future<void> collect(NovelSummary book);

  Future<void> remove(String bookId);

  Future<bool> isCollected(String bookId);

  /// 批量判断（列表一次性预载，避免逐行查询）。
  Future<Set<String>> collectedIds();

  /// 收藏列表，按收藏时间倒序（书架页消费）。
  Future<List<NovelCollectItem>> list();

  /// 设置一本书的书架分组；null = 移出分组。内部行不存在时是空操作。
  Future<void> setGroup(String bookId, String? groupName);

  /// 批量设置分组（选择模式下一次挪多本）。
  Future<void> setGroupFor(Iterable<String> bookIds, String? groupName);

  /// 已有分组名（按名称排序）。
  Future<List<String>> groups();

  /// 重命名分组（所有属于 [from] 的收藏行改到 [to]；[to] 为空视为移出分组）。
  Future<void> renameGroup(String from, String to);

  /// 删除分组（只解除归属，不删书）。
  Future<void> deleteGroup(String name);

  /// 写入/清空一本书的备注（空串或纯空白 = 清空）。行不存在时是空操作。
  Future<void> setNote(String bookId, String note);

  /// 设置自定义封面（本地图片路径）；null = 恢复书源封面。行不存在时是空操作。
  Future<void> setCustomCover(String bookId, String? path);

  /// 已有系列（按名称排序）。
  Future<List<NovelSeriesItem>> series();

  /// 新建系列并返回其 id；同名（去空白后）复用已有行，不重复建。
  Future<int> createSeries(String name);

  /// 重命名系列；[name] 为空视为非法，抛 [ArgumentError]。
  Future<void> renameSeries(int id, String name);

  /// 删除系列：成员行的 seriesId 置空，书都留在书架。
  Future<void> deleteSeries(int id);

  /// 批量设置系列归属；null = 移出系列。
  Future<void> setSeriesFor(Iterable<String> bookIds, int? seriesId);
}

/// 一条阅读历史（含可重建的书籍快照）。
class NovelHistoryItem {
  const NovelHistoryItem({
    required this.book,
    required this.chapterIndex,
    required this.chapterCount,
    required this.openedAt,
  });

  final NovelSummary book;
  final int chapterIndex;
  final int chapterCount;
  final DateTime openedAt;
}

/// 历史门面（权威库 `novel_history`，持久化点/打开点投影 core）。
abstract interface class NovelHistoryApi {
  /// 打开点校正：历史行不存在时不建行、不写投影。
  Future<void> open(NovelSummary book);

  /// 持久化点：写内部行（含阅读次数）并同步投影。
  Future<void> saveProgress(
    NovelSummary book,
    int chapterIndex,
    int chapterCount,
  );

  Future<NovelHistoryItem?> latest(String bookId);

  Future<List<NovelHistoryItem>> recent({int limit = 50});

  /// 删除一本书的阅读记录；无收藏时同时摘掉统一书架的投影行。
  Future<void> remove(String bookId);

  /// 清空全部阅读记录（收藏行保留，投影进度回落到未读）。
  Future<void> clear();
}

/// 搜索历史门面。
abstract interface class NovelSearchHistoryApi {
  Future<void> record(String keyword);

  Future<List<String>> recent({int limit = 20});

  Future<void> clear();
}

/// 阅读时长/数量快照（首页统计卡与「今日阅读目标」共用一次读取）。
class NovelStats {
  const NovelStats({
    required this.booksRead,
    required this.collected,
    required this.totalSeconds,
    required this.todaySeconds,
    required this.goalMinutes,
  });

  /// 有阅读记录的书籍数（「累计阅读 N 本」）。
  final int booksRead;

  /// 收藏数。
  final int collected;

  /// 累计阅读秒数（按天聚合表求和）。
  final int totalSeconds;

  /// 今日阅读秒数（本地日）。
  final int todaySeconds;

  /// 今日阅读目标（分钟）。
  final int goalMinutes;

  /// 今日目标完成度 0..1；目标 <=0 时按 0 处理。
  double get goalProgress {
    if (goalMinutes <= 0) return 0;
    final ratio = todaySeconds / 60 / goalMinutes;
    return ratio.clamp(0.0, 1.0);
  }

  /// 今日已读分钟（向下取整；不足 1 分钟显示 0）。
  int get todayMinutes => todaySeconds ~/ 60;
}

/// 统计门面：阅读时长由阅读器上报（阅读器切章/退出时累加），
/// 目标分钟数落模块 kv，不估算、不伪造。
///
/// 记录粒度是「设备 × 书 × 章 × 本地日」：本机数字一律只看 deviceId = 本机，
/// 同步进来的别的设备记录不混进首页/我的页的聚合视图。
abstract interface class NovelStatsApi {
  Future<NovelStats> snapshot();

  /// 累加一段阅读时长到本地当天。
  ///
  /// [target] 带书/章上下文：缺省（null）时记到「未知书籍 / 未知章」，
  /// 只进日聚合，不进时间轴/章节维度。
  Future<void> addReadingTime(
    Duration duration, {
    DateTime? at,
    NovelReadTarget? target,
  });

  /// 设置今日阅读目标（分钟）；<=0 视为关闭目标。
  Future<void> setGoalMinutes(int minutes);

  /// 概览：累计时长、累计本数、活跃天数、日均、当前/最长连续。
  Future<NovelStatsOverview> overview({DateTime? today});

  /// 按天分组的时间轴（倒序）。[limitDays] <= 0 表示全部天数。
  Future<List<NovelReadDay>> timeline({int limitDays = 0});

  /// 单本书的章节维度（按章号升序）。
  Future<List<NovelChapterStats>> bookChapters(String bookId);

  /// 某一年「本地日 → 秒」的原始分桶（热力图数据源；0 秒日不返回）。
  Future<Map<String, int>> heatmapSeconds({required int year});
}

/// 一次时长上报的归属：哪本书、哪一章。
class NovelReadTarget {
  const NovelReadTarget({
    required this.bookId,
    this.bookTitle = '',
    this.chapterIndex = 0,
    this.chapterName = '',
  });

  final String bookId;

  /// 书名快照，空串表示未知。
  final String bookTitle;

  /// 章号（1 起；0 = 未知）。
  final int chapterIndex;

  final String chapterName;
}

/// 概览数字（统计页顶部四卡 + 连续天数）。
class NovelStatsOverview {
  const NovelStatsOverview({
    required this.totalSeconds,
    required this.booksRead,
    required this.activeDays,
    required this.averageSecondsPerDay,
    required this.currentStreak,
    required this.longestStreak,
    required this.todaySeconds,
  });

  /// 累计阅读秒数（本机设备）。
  final int totalSeconds;

  /// 有阅读时长的书数（按 bookId 去重；不含「未知书籍」的旧记录）。
  final int booksRead;

  /// 有阅读时长的天数。
  final int activeDays;

  /// 日均秒数（累计 ÷ 活跃天数，不是自然日总数）。
  final int averageSecondsPerDay;

  /// 当前连续阅读天数（今天没读则从昨天起算）。
  final int currentStreak;

  /// 历史最长连续阅读天数。
  final int longestStreak;

  /// 今日秒数。
  final int todaySeconds;
}

/// 时间轴里的一本书（某天读了多久、读到第几章）。
class NovelReadBook {
  const NovelReadBook({
    required this.bookId,
    required this.title,
    required this.seconds,
    required this.chapterIndex,
    required this.chapterName,
    this.lastReadAt,
  });

  final String bookId;

  /// 书名快照；空串 = 旧数据未关联书籍。
  final String title;

  final int seconds;

  /// 当天读到的最远章号（1 起；0 = 未知）。
  final int chapterIndex;

  final String chapterName;

  final DateTime? lastReadAt;
}

/// 时间轴的一天。
class NovelReadDay {
  const NovelReadDay({
    required this.day,
    required this.seconds,
    required this.books,
  });

  /// 本地日 `yyyy-MM-dd`。
  final String day;

  final int seconds;

  /// 当天读过的书，按时长倒序。
  final List<NovelReadBook> books;
}

/// 单章累计（跨天合并）。
class NovelChapterStats {
  const NovelChapterStats({
    required this.chapterIndex,
    required this.chapterName,
    required this.seconds,
    this.firstReadAt,
    this.lastReadAt,
  });

  final int chapterIndex;

  final String chapterName;

  final int seconds;

  final DateTime? firstReadAt;

  final DateTime? lastReadAt;
}

/// 柱状图的一天（连续补齐，没读的填 0）。
class NovelBarBucket {
  const NovelBarBucket({required this.day, required this.seconds});

  final String day;

  final int seconds;
}

/// 模块私有 kv 门面（书架布局/排序等 UI 偏好）。
abstract interface class NovelPrefsApi {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// 默认今日阅读目标（分钟）。
const int novelDefaultGoalMinutes = 30;

/// 模块 kv 键（页面与设置页共用，避免字符串漂移）。
const String novelPrefGoalMinutes = 'reading_goal_minutes';
const String novelPrefShelfLayout = 'shelf_layout';
const String novelPrefShelfColumns = 'shelf_columns';
const String novelPrefShelfSort = 'shelf_sort';

/// 书架展示配置（`NovelShelfLayoutConfig` 的 JSON）。旧键
/// [novelPrefShelfLayout] 存的是 `grid`/`list`，读取时兼容。
const String novelPrefShelfView = 'shelf_view';

/// 书架手动顺序（拖拽排序后落库的 bookId JSON 数组）。
const String novelPrefShelfOrder = 'shelf_order';

/// 首页模块配置（`NovelHomeModuleConfig` 的 JSON）。
const String novelPrefHomeModules = 'home_modules';
// 旧阅读器只存了字号；新阅读器设置整体存在 reader_settings，读取时会迁移。
const String novelPrefReaderFontSize = 'reader_font_size';
const String novelPrefReaderSettings = 'reader_settings';
const String novelPrefReaderPositions = 'reader_positions';

/// 每书阅读设置覆盖：一条 kv 里存 `{bookId: 部分 JSON}`。
///
/// 只存与全局设置不同的字段，避免整份复制——否则用户以后改全局时，
/// 每书那份旧快照会把改动吃掉。合并优先级：每书 > 全局 > 默认。
const String novelPrefReaderBookSettings = 'reader_book_settings';
