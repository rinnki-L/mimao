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
  });

  final NovelRef ref;
  final String title;
  final String? coverUrl;

  /// 收藏时落底的书籍 JSON 反序列化结果；旧数据/坏数据为 null。
  final NovelSummary? book;

  /// 书架自定义分组；null = 未分组。
  final String? groupName;

  final DateTime collectedAt;

  /// 「我的」页展示用作者名（无书籍快照时为空串）。
  String get authorText => book?.author ?? '';
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
abstract interface class NovelStatsApi {
  Future<NovelStats> snapshot();

  /// 累加一段阅读时长到本地当天。
  Future<void> addReadingTime(Duration duration, {DateTime? at});

  /// 设置今日阅读目标（分钟）；<=0 视为关闭目标。
  Future<void> setGoalMinutes(int minutes);
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
// 旧阅读器只存了字号；新阅读器设置整体存在 reader_settings，读取时会迁移。
const String novelPrefReaderFontSize = 'reader_font_size';
const String novelPrefReaderSettings = 'reader_settings';
const String novelPrefReaderPositions = 'reader_positions';

/// 每书阅读设置覆盖：一条 kv 里存 `{bookId: 部分 JSON}`。
///
/// 只存与全局设置不同的字段，避免整份复制——否则用户以后改全局时，
/// 每书那份旧快照会把改动吃掉。合并优先级：每书 > 全局 > 默认。
const String novelPrefReaderBookSettings = 'reader_book_settings';
