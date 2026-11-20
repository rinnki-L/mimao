/// Kazumi 式组合数据源：Bangumi 提供搜索/元数据，规则站点提供播放源与剧集。
///
/// 数据流（对齐 Kazumi：Bangumi 只做壳，规则按标题搜 src）：
/// - [search]：只走 Bangumi API，得到干净、只含相关条目的 [AnimeSummary]，
///   带 bangumiId/cover/description/rating/airDate/tags；
/// - [watchSources]：用 Bangumi 条目的标题（searchKeyword）委托规则数据源，
///   并发搜所有已装规则，得到可观看的来源列表供用户选；
/// - [detail]：委托规则数据源（Bangumi 条目本身没有剧集，必须先选源）；
/// - [schedule]：规则站点没有周时间表数据，恒空（与现状一致）。
///
/// 空关键词返回空列表（不在启动即打 Bangumi）。搜索**只走 Bangumi**——
/// 绝不在 Bangumi 无结果/失败时回退规则站点搜索，否则结果会混入规则站点的
/// 模糊匹配垃圾，破坏「统一搜索逻辑」（用户实测反馈）。规则站点只在详情页
/// 选源观看时用（watchSources / detail），不参与搜索结果生成。
library;

import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/bangumi_api.dart';

class BangumiAnimeDataSource implements AnimeDataSource {
  BangumiAnimeDataSource({
    required this.bangumi,
    required this.ruleSource,
    required this.baseUrl,
  });

  final BangumiClient bangumi;

  /// 规则数据源（提供 watchSources / detail / schedule）。
  final AnimeDataSource ruleSource;

  /// Bangumi 搜索 host——照抄 Kazumi 固定官方直连 api.bgm.tv，与图片加速解耦。
  final String baseUrl;

  @override
  Future<List<AnimeSummary>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return const <AnimeSummary>[];

    // Kazumi bangumiSearch：异常返回 null；items 已在 API 层做 nameCn 过滤 + id 去重。
    // 数据源层再兜一层：客户端万一抛异常也返回空，绝不回退规则站点。
    final BangumiSearchPage? page;
    try {
      page = await bangumi.bangumiSearch(query, baseUrl: baseUrl, limit: 20);
    } on Object {
      return const <AnimeSummary>[];
    }
    if (page == null) return const <AnimeSummary>[];
    return <AnimeSummary>[
      for (final item in page.items)
        AnimeSummary(
          // Bangumi id 作为稳定主键：同一部番跨规则来源共享详情页身份。
          id: 'bgm://${item.id}',
          title: item.displayName,
          coverUrl: item.coverUrl,
          // Bangumi 条目没有 detailUrl；留空，detail/watchSources 用标题定位。
          detailUrl: '',
          subtitle: item.airDate.isEmpty ? null : '首播 ${item.airDate}',
          bangumiId: item.id,
          description: item.summary,
          rating: item.ratingScore > 0 ? item.ratingScore : null,
          airDate: item.airDate,
          tags: item.tags,
        ),
    ];
  }

  @override
  Future<List<AnimeSummary>> watchSources(
    AnimeSummary item, {
    required String keyword,
  }) {
    // Kazumi source_sheet 同款：用标题让规则站点搜播放源。
    return ruleSource.watchSources(
      item,
      keyword: keyword.trim().isEmpty ? item.title : keyword.trim(),
    );
  }

  @override
  Future<AnimeDetail> detail(AnimeSummary item) {
    // Bangumi 条目没有剧集；调用方应先 watchSources 选一个规则来源再 detail。
    // 直接对 Bangumi 条目取详情时，回退规则层的空详情语义，不抛异常。
    return ruleSource.detail(item);
  }

  @override
  Future<List<AnimeScheduleSection>> schedule() => ruleSource.schedule();
}
