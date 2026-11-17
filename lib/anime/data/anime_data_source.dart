import 'package:mimao/anime/data/anime_models.dart';

/// 番剧 UI 的唯一数据入口（抽象）。
///
/// A 线规则引擎就绪后提供一个实现：把 XPath 抽取结果适配成
/// [AnimeSummary] / [AnimeDetail] / [AnimeScheduleSection]。页面、fixture 与
/// widget 测试都只依赖本接口，不依赖 dio、Hive 或规则模型——换实现不改 UI。
///
/// 联调映射（引擎 `RuleSearchResult` / `RuleEpisode` → 本接口）：
///   - `absoluteUrl` → [AnimeSummary.detailUrl]（同时可作为 id）
///   - `absoluteCoverUrl` → [AnimeSummary.coverUrl]
///   - `RuleEpisode.absoluteUrl` → [AnimeEpisode.url]
///   - `RuleEpisode.title` → [AnimeEpisode.title]；number 按列表顺序生成
/// 空字符串表示「没有封面/没有简介」，页面会显示占位与空态，不需要 null。
abstract interface class AnimeDataSource {
  /// 按关键词搜索。空关键词通常返回推荐/全部（fixture 语义）。
  Future<List<AnimeSummary>> search(String keyword);

  /// 取详情（含剧集）。实现方用 [item] 的 detailUrl 抓取。
  Future<AnimeDetail> detail(AnimeSummary item);

  /// 本周更新时间表，按星期分组。
  Future<List<AnimeScheduleSection>> schedule();
}
