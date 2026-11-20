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
/// 空关键词返回空列表（不在启动即打 Bangumi）；Bangumi 失败/无结果时回退到
/// 规则数据源的 search，避免网络异常时功能全废。
library;

import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/bangumi_api.dart';

/// 两态 host 提供者（由 registry 注入，读当前图片加速模式的 Bangumi host）。
typedef BangumiBaseUrlProvider = String Function();

class BangumiAnimeDataSource implements AnimeDataSource {
  BangumiAnimeDataSource({
    required this.bangumi,
    required this.ruleSource,
    required this.baseUrlFor,
  });

  final BangumiClient bangumi;

  /// 规则数据源（提供 watchSources / detail / schedule）。
  final AnimeDataSource ruleSource;

  /// 当前 Bangumi host（直连/镜像，随图片加速模式切换）。
  final BangumiBaseUrlProvider baseUrlFor;

  @override
  Future<List<AnimeSummary>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return const <AnimeSummary>[];

    try {
      final response = await bangumi.searchSubjects(
        query,
        baseUrl: baseUrlFor(),
        limit: 20,
      );
      if (response.isSuccessful && response.subjects.isNotEmpty) {
        return <AnimeSummary>[
          for (final subject in response.subjects)
            if (subject.displayName.trim().isNotEmpty)
              AnimeSummary(
                // Bangumi id 作为稳定主键：同一部番跨规则来源共享详情页身份。
                id: 'bgm://${subject.id}',
                title: subject.displayName,
                coverUrl: subject.coverUrl,
                // Bangumi 条目没有 detailUrl；留空，detail/watchSources 用标题定位。
                detailUrl: '',
                subtitle: subject.airDate.isEmpty
                    ? null
                    : '首播 ${subject.airDate}',
                bangumiId: subject.id,
                description: subject.summary,
                rating: subject.rating,
                airDate: subject.airDate,
                tags: subject.tags,
              ),
        ];
      }
    } on Object {
      // Bangumi 失败回退规则搜索，保证网络异常时仍能出结果。
    }
    return ruleSource.search(keyword);
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
