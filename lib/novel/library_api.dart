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
NovelRef novelRefOf(NovelSummary book) =>
    NovelRef(id: book.id, sourceName: book.sourceName);

/// 一条收藏（权威行 + 可重建的书籍快照）。
class NovelCollectItem {
  const NovelCollectItem({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.book,
    required this.collectedAt,
  });

  final NovelRef ref;
  final String title;
  final String? coverUrl;

  /// 收藏时落底的书籍 JSON 反序列化结果；旧数据/坏数据为 null。
  final NovelSummary? book;

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
}

/// 搜索历史门面。
abstract interface class NovelSearchHistoryApi {
  Future<void> record(String keyword);

  Future<List<String>> recent({int limit = 20});

  Future<void> clear();
}
