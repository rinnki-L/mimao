/// 规则引擎的输出模型——纯数据结构，不依赖 UI、drift、网络。
///
/// 上层（页面/统一的 `AnimeDataSource` 适配器）只消费这些类型；它们既保留
/// 页面上的原始值（`url`/`coverUrl`），也给出基于规则 `baseURL` 归一化后的
/// 绝对地址（`absoluteUrl`/`absoluteCoverUrl`），避免上层重复拼 URL。
library;

/// 搜索/列表页里的一个条目。
class RuleSearchResult {
  const RuleSearchResult({
    required this.title,
    required this.url,
    required this.coverUrl,
    required this.absoluteUrl,
    required this.absoluteCoverUrl,
  });

  /// 条目标题（已折叠多余空白）。
  final String title;

  /// 页面上抓到的原始详情链接（可能为相对路径）。
  final String url;

  /// 页面上抓到的原始封面地址；空字符串表示没有封面。
  final String coverUrl;

  /// 基于规则 `baseURL` 归一化后的详情绝对地址。
  final String absoluteUrl;

  /// 基于规则 `baseURL` 归一化后的封面绝对地址；无封面时为空。
  final String absoluteCoverUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleSearchResult &&
          other.title == title &&
          other.url == url &&
          other.coverUrl == coverUrl &&
          other.absoluteUrl == absoluteUrl &&
          other.absoluteCoverUrl == absoluteCoverUrl;

  @override
  int get hashCode =>
      Object.hash(title, url, coverUrl, absoluteUrl, absoluteCoverUrl);

  @override
  String toString() => 'RuleSearchResult($title → $url)';
}

/// 详情页里的一集。
class RuleEpisode {
  const RuleEpisode({
    required this.title,
    required this.url,
    required this.absoluteUrl,
    required this.roadIndex,
    required this.roadName,
  });

  /// 剧集标题；页面没有文字时回退为「第N集」。
  final String title;

  /// 页面上抓到的原始播放地址（可能为相对路径）。
  final String url;

  /// 归一化后的播放绝对地址——上层直接把它交给播放器。
  final String absoluteUrl;

  /// 播放线路序号（从 1 开始）。
  final int roadIndex;

  /// 播放线路名，例如「播放线路1」。
  final String roadName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleEpisode &&
          other.title == title &&
          other.url == url &&
          other.absoluteUrl == absoluteUrl &&
          other.roadIndex == roadIndex &&
          other.roadName == roadName;

  @override
  int get hashCode => Object.hash(title, url, absoluteUrl, roadIndex, roadName);

  @override
  String toString() => 'RuleEpisode($title → $url)';
}

/// 一次解析的结果：条目 + 诊断信息。
///
/// 规则写错、页面结构变了都不会抛异常，而是返回空 [items] 并在
/// [diagnostics] 里说明原因——搜索引擎可以逐条源容错，不需要 try/catch。
class RuleParseResult<T> {
  const RuleParseResult({
    this.items = const [],
    this.diagnostics = const <String>[],
    this.coverUrl = '',
  });

  final List<T> items;

  /// 解析过程中的问题（规则不完整、XPath 执行失败、单条跳过等）。
  final List<String> diagnostics;

  /// 详情页抽出的封面绝对地址（读规则 `detailCover`/`cover`）；
  /// 搜索结果不使用本字段，恒为空串。
  final String coverUrl;

  bool get isEmpty => items.isEmpty;

  @override
  String toString() =>
      'RuleParseResult(items: ${items.length}, '
      'diagnostics: ${diagnostics.length})';
}
