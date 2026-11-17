/// A 线规则引擎输出 → D 线页面模型的纯函数映射。
///
/// 只做字段搬运与缺省兜底：不访问网络、不抛异常、不依赖 UI / 播放器 / drift。
/// 抽成纯函数是为了让映射本身能脱离 HTML 解析单独单测——测试直接构造
/// [RuleSearchResult] / [RuleEpisode] 即可覆盖全部字段规则。
library;

import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/engine/result.dart';
import 'package:mimao/anime/engine/rule.dart';

/// 规则在 UI 上显示的名字：trim 后为空时给一个稳定占位名。
String ruleDisplayName(AnimeRule rule) {
  final name = rule.name.trim();
  return name.isEmpty ? '未命名规则' : name;
}

/// 把一条搜索命中映射成列表项。
///
/// 标题或详情地址（trim 后）为空时返回 `null`，由调用方跳过并记诊断。
/// 字段规则：
/// - `title` ← [RuleSearchResult.title]；
/// - `coverUrl` ← [RuleSearchResult.absoluteCoverUrl]（空则空串，UI 用占位图）；
/// - `detailUrl` ← [RuleSearchResult.absoluteUrl]（空则回退 [RuleSearchResult.url]）；
/// - `id` ← 与 `detailUrl` 同源，保证同一规则内稳定；
/// - `subtitle` ← `null`（Kazumi 规则没有更新话数，不编造）；
/// - `sourceName` ← 规则名（trim；空名用「未命名规则」）。
AnimeSummary? summaryFromRule(AnimeRule rule, RuleSearchResult hit) {
  if (hit.title.trim().isEmpty) return null;
  final absoluteUrl = hit.absoluteUrl.trim();
  final detailUrl = absoluteUrl.isEmpty ? hit.url.trim() : absoluteUrl;
  if (detailUrl.isEmpty) return null;

  return AnimeSummary(
    id: detailUrl,
    title: hit.title,
    coverUrl: hit.absoluteCoverUrl,
    detailUrl: detailUrl,
    subtitle: null,
    sourceName: ruleDisplayName(rule),
  );
}

/// 把详情页抽取结果映射成 [AnimeDetail]。
///
/// `number` 从 1 开始按传入顺序生成；`roadIndex` / `roadName` 属于 A 线线路
/// 概念，D 模型没有对应字段，刻意丢弃（不拼进标题）。`duration` 恒为 null
/// （Kazumi 规则无时长选择器）。标题/封面/地址取传入的 [item]，简介与标签
/// 留空——引擎没有简介选择器，页面显示「暂无简介」，不伪造内容。
AnimeDetail detailFromRule(
  AnimeRule rule,
  AnimeSummary item,
  List<RuleEpisode> episodes,
) {
  final mapped = <AnimeEpisode>[];
  for (var index = 0; index < episodes.length; index++) {
    final episode = episodes[index];
    final absoluteUrl = episode.absoluteUrl.trim();
    mapped.add(
      AnimeEpisode(
        number: index + 1,
        title: episode.title,
        url: absoluteUrl.isEmpty ? episode.url : episode.absoluteUrl,
        duration: null,
      ),
    );
  }

  return AnimeDetail(
    title: item.title,
    coverUrl: item.coverUrl,
    detailUrl: item.detailUrl,
    description: '',
    sourceName: ruleDisplayName(rule),
    tags: const <String>[],
    episodes: mapped,
  );
}
