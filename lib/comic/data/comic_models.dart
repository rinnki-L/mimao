// 漫画 UI 数据契约——源引擎（A′）与页面（D′）之间的唯一接口模型。
//
// 这些类型刻意保持扁平、只含展示所需字段：A′ 源引擎把规则抽取结果适配成
// [ComicSummary] / [ComicDetail] 即可驱动 UI，页面不认识引擎内部的规则/HTML。
// 字段命名对齐 Kazumi/Venera 规则里的 title / cover / detailUrl 语义。
//
// 本文件与 lib/comic/comic_models.dart（C′ 存储线）刻意分开：后者是 drift
// 落库用的领域模型，这里是 UI 展示契约，互不 import。

/// 搜索结果里的一个漫画条目（列表项）。
class ComicSummary {
  /// 稳定标识，用于列表 key 与详情查询。可由 detailUrl 派生。
  final String id;

  final String title;

  /// 封面地址；空字符串表示没有封面（UI 用占位图兜底）。
  final String coverUrl;

  /// 详情页地址，规则引擎据此继续抓取章节。
  final String detailUrl;

  /// 一句话状态，如「更新至第 30 话」。
  final String? subtitle;

  /// 来源站点名，如「漫画DB」。
  final String? sourceName;

  const ComicSummary({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.detailUrl,
    this.subtitle,
    this.sourceName,
  });
}

/// 详情页里的一章。
class ComicChapter {
  /// 从 1 开始的序号。
  final int number;

  final String title;

  /// 章节地址——UI 只透传，不在这里碰阅读器。
  final String url;

  const ComicChapter({
    required this.number,
    required this.title,
    required this.url,
  });
}

/// 漫画详情（源引擎「详情抽取」的输出）。
class ComicDetail {
  final String title;

  /// 空字符串表示没有封面。
  final String coverUrl;

  final String detailUrl;

  /// 简介正文；空字符串表示来源未提供。
  final String description;

  final String? sourceName;

  /// 标签/题材，如「奇幻」「热血」。
  final List<String> tags;

  final List<ComicChapter> chapters;

  const ComicDetail({
    required this.title,
    required this.coverUrl,
    required this.detailUrl,
    required this.description,
    this.sourceName,
    this.tags = const <String>[],
    this.chapters = const <ComicChapter>[],
  });
}

/// 源管理页里的一条已导入来源。
///
/// 来源只用展示字段描述；启用/删除/导入动作由页面的回调注入，
/// 不在这里持有任何存储服务引用——UI 只认数据形状，不认实现。
class ComicSourceInfo {
  final String id;
  final String name;

  /// 源规则地址（页面展示用，导入时由用户给出）。
  final String url;

  final bool enabled;

  /// 该来源提供的漫画数量（展示用；可为 null 表示未知）。
  final int? comicCount;

  const ComicSourceInfo({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.comicCount,
  });

  ComicSourceInfo copyWith({bool? enabled}) => ComicSourceInfo(
    id: id,
    name: name,
    url: url,
    enabled: enabled ?? this.enabled,
    comicCount: comicCount,
  );
}
