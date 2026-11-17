// 番剧 UI 数据模型——规则引擎（A 线）与页面之间的契约。
//
// 这些类型刻意保持扁平、只含展示所需字段：A 线引擎把 XPath 抽取结果
// 适配成这些类型即可驱动 UI，页面不认识引擎内部的规则/HTML 结构。
// 字段命名同时对齐 Kazumi 规则里的 title/cover/detailUrl 语义。

/// 搜索结果 / 时间表里的一个番剧条目（列表项）。
class AnimeSummary {
  /// 稳定标识，用于列表 key 与详情查询。可由 detailUrl 派生。
  final String id;

  final String title;

  /// 封面地址；空字符串表示没有封面（UI 用占位图兜底）。
  final String coverUrl;

  /// 详情页地址，规则引擎据此继续抓取剧集。
  final String detailUrl;

  /// 一句话状态，如「更新至第 12 话」。
  final String? subtitle;

  /// 来源站点名，如「樱花动漫」。
  final String? sourceName;

  const AnimeSummary({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.detailUrl,
    this.subtitle,
    this.sourceName,
  });
}

/// 详情页里的一集。
class AnimeEpisode {
  /// 从 1 开始的集数。
  final int number;

  final String title;

  /// 播放地址——UI 只透传，不在这里碰播放器。
  final String url;

  /// 时长文本，如「24:00」。
  final String? duration;

  const AnimeEpisode({
    required this.number,
    required this.title,
    required this.url,
    this.duration,
  });
}

/// 番剧详情（规则引擎「详情抽取」的输出）。
class AnimeDetail {
  final String title;

  /// 空字符串表示没有封面。
  final String coverUrl;

  final String detailUrl;

  /// 简介正文；空字符串表示来源未提供。
  final String description;

  final String? sourceName;

  /// 标签/题材，如「科幻」「治愈」。
  final List<String> tags;

  final List<AnimeEpisode> episodes;

  const AnimeDetail({
    required this.title,
    required this.coverUrl,
    required this.detailUrl,
    required this.description,
    this.sourceName,
    this.tags = const <String>[],
    this.episodes = const <AnimeEpisode>[],
  });
}

/// 星期——时间表分组的键。
enum AnimeWeekday {
  monday('周一'),
  tuesday('周二'),
  wednesday('周三'),
  thursday('周四'),
  friday('周五'),
  saturday('周六'),
  sunday('周日');

  const AnimeWeekday(this.label);

  final String label;

  /// 由日期取星期，供真实数据源按当天归档。
  static AnimeWeekday fromDate(DateTime date) => switch (date.weekday) {
    DateTime.monday => monday,
    DateTime.tuesday => tuesday,
    DateTime.wednesday => wednesday,
    DateTime.thursday => thursday,
    DateTime.friday => friday,
    DateTime.saturday => saturday,
    DateTime.sunday => sunday,
    _ => monday,
  };
}

/// 时间表的一天：星期 + 当天更新的番剧。
class AnimeScheduleSection {
  final AnimeWeekday weekday;
  final List<AnimeSummary> items;

  const AnimeScheduleSection({required this.weekday, required this.items});
}
