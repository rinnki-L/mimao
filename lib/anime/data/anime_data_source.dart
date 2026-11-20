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

  /// 列出同一部番剧在「所有已装规则」下可观看的条目，供详情页「换源/选规则」。
  ///
  /// [keyword] 通常是条目标题：规则站点靠它再搜一遍才能定位同一部番在
  /// 自己站上的详情地址。默认实现只返回 [item] 自身（单来源，保持既有行为），
  /// 多规则实现（[RuleAnimeDataSource]）会并发搜所有规则并做标题匹配。
  ///
  /// 返回的每一项都是可直接喂给 [detail] 的 [AnimeSummary]（携带各自的
  /// sourceName 与 detailUrl）；播放器据此解析正确的规则与请求头。
  Future<List<AnimeSummary>> watchSources(
    AnimeSummary item, {
    required String keyword,
  }) async => <AnimeSummary>[item];

  /// 本周更新时间表，按星期分组。
  Future<List<AnimeScheduleSection>> schedule();
}
