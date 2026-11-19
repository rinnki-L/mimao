/// 番剧规则模型——KazumiRules JSON 的 Dart 视图。
///
/// Kazumi 的规则是**纯数据**：一行行 XPath 选择器描述"在搜索结果页/详情页
/// 里怎么找条目"。引擎只解释这些数据，不维护规则本身（docs/architecture.md
/// 决策修订 R1）。因此字段名与 Kazumi `Plugin` 的序列化格式保持一致：
/// `baseURL`/`searchURL`/`muliSources`（上游的拼写）等，社区规则可以原样导入。
///
/// 同时接受 `baseUrl`/`searchUrl`/`multiSources` 这几个更 Dart 风格的别名，
/// 便于手写测试规则；序列化时仍输出 Kazumi 的键名。
library;

/// Kazumi 引擎只支持以 `//` 开头的 XPath 选择器。
///
/// 这不是 xpath_selector 的限制（它支持 `/`、轴、谓词），而是上游规则的
/// 事实约定：KazumiRules 里所有选择器都以 `//` 开头。把它显式化，规则写错
/// 时能在解析前就得到"不支持"而不是某个意外的空结果。
bool isSupportedXPathSelector(String selector) {
  final value = selector.trim();
  return value.length > 2 && value.startsWith('//') && !value.startsWith('///');
}

/// 一部番剧的完整规则。
///
/// 三类规则分别落在这里：
/// - [search]：搜索页 → 条目列表（标题/链接/封面）；
/// - [detail]：详情页 → 播放线路 → 剧集节点；
/// - [play]：剧集节点 → 可播放地址的属性（Kazumi 固定为 `href`）。
///
/// 未识别的 JSON 键保存在 [extras] 并原样写回，保证导入再导出不丢上游
/// 新加的字段（例如 `deprecated`、`antiCrawlerConfig`）。
class AnimeRule {
  const AnimeRule({
    required this.name,
    this.version = '',
    this.api = '1',
    this.type = 'anime',
    this.baseUrl = '',
    this.userAgent = '',
    this.referer = '',
    this.usePost = false,
    this.useWebview = true,
    this.useNativePlayer = true,
    this.useLegacyParser = false,
    this.adBlocker = false,
    this.multiSources = true,
    this.searchMode = 'xpath',
    this.chapterMode = 'xpath',
    required this.search,
    required this.detail,
    this.play = const PlayRule(),
    this.extras = const <String, dynamic>{},
  });

  /// 从 KazumiRules 的一条 JSON 构造。类型异常一律降级为默认值，不抛异常——
  /// 一条坏规则不应该让整批导入失败（失败判定交给 [validate] / 导入器）。
  factory AnimeRule.fromJson(Map<String, dynamic> json) {
    final extras = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!_knownJsonKeys.contains(entry.key)) extras[entry.key] = entry.value;
    }
    final rawAttribute = _readString(json['playUrlAttribute']).trim();
    return AnimeRule(
      name: _readString(json['name']),
      version: _readString(json['version']),
      api: _readString(json['api'], fallback: '1'),
      type: _readString(json['type'], fallback: 'anime'),
      baseUrl: _readString(json['baseURL'] ?? json['baseUrl']),
      userAgent: _readString(json['userAgent']),
      referer: _readString(json['referer']),
      usePost: _readBool(json['usePost']),
      useWebview: _readBool(json['useWebview'], fallback: true),
      useNativePlayer: _readBool(json['useNativePlayer'], fallback: true),
      useLegacyParser: _readBool(json['useLegacyParser']),
      adBlocker: _readBool(json['adBlocker']),
      multiSources: _readBool(
        json['muliSources'] ?? json['multiSources'],
        fallback: true,
      ),
      searchMode: _readString(json['searchMode'], fallback: 'xpath'),
      chapterMode: _readString(json['chapterMode'], fallback: 'xpath'),
      search: SearchRule(
        url: _readString(json['searchURL'] ?? json['searchUrl']),
        list: _readString(json['searchList']),
        title: _readString(json['searchName']),
        link: _readString(json['searchResult']),
        cover: _readString(json['searchCover']),
      ),
      detail: DetailRule(
        roads: _readString(json['chapterRoads']),
        episodes: _readString(json['chapterResult']),
        cover: _readString(json['detailCover'] ?? json['cover']),
      ),
      play: PlayRule(
        urlAttribute: rawAttribute.isEmpty ? 'href' : rawAttribute,
      ),
      extras: extras,
    );
  }

  final String name;
  final String version;
  final String api;
  final String type;
  final String baseUrl;

  /// 空字符串表示用引擎默认 UA。
  final String userAgent;

  /// 请求播放列表时带的 Referer；空字符串表示不带。
  final String referer;

  final bool usePost;
  final bool useWebview;
  final bool useNativePlayer;
  final bool useLegacyParser;
  final bool adBlocker;
  final bool multiSources;
  final String searchMode;
  final String chapterMode;

  final SearchRule search;
  final DetailRule detail;
  final PlayRule play;

  /// 未识别的上游字段，往返时原样保留。
  final Map<String, dynamic> extras;

  bool get isDeprecated => extras['deprecated'] == true;

  /// 是否至少有一类规则可以工作（导入器用它拒绝完全无用的 JSON）。
  bool get hasUsableSelectors =>
      search.hasValidSelectors || detail.hasValidSelectors;

  /// 人类可读的规则体检结果；空列表表示规则完整。
  ///
  /// 只做静态检查（字段存在、选择器以 `//` 开头），不访问网络、不解析页面。
  List<String> validate() {
    final issues = <String>[];
    if (name.trim().isEmpty) issues.add('缺少规则名 name');
    if (!search.hasSelectors) {
      issues.add('缺少搜索规则（searchList/searchName/searchResult）');
    } else if (!search.hasValidSelectors) {
      issues.add('搜索规则 XPath 无效（只支持 // 开头）');
    }
    if (search.url.trim().isEmpty) issues.add('缺少 searchURL');
    if (!detail.hasSelectors) {
      issues.add('缺少详情规则（chapterRoads/chapterResult）');
    } else if (!detail.hasValidSelectors) {
      issues.add('详情规则 XPath 无效（只支持 // 开头）');
    }
    if (!play.isSupported) issues.add('播放地址属性为空');
    return issues;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'api': api,
      'type': type,
      'name': name,
      'version': version,
      'muliSources': multiSources,
      'useWebview': useWebview,
      'useNativePlayer': useNativePlayer,
      'usePost': usePost,
      'useLegacyParser': useLegacyParser,
      'adBlocker': adBlocker,
      'userAgent': userAgent,
      'baseURL': baseUrl,
      'searchURL': search.url,
      'searchList': search.list,
      'searchName': search.title,
      'searchResult': search.link,
      'chapterRoads': detail.roads,
      'chapterResult': detail.episodes,
      if (detail.cover.isNotEmpty) 'detailCover': detail.cover,
      'referer': referer,
      'searchMode': searchMode,
      'chapterMode': chapterMode,
      if (search.cover.isNotEmpty) 'searchCover': search.cover,
      if (play.urlAttribute != 'href') 'playUrlAttribute': play.urlAttribute,
      ...extras,
    };
  }

  @override
  String toString() => 'AnimeRule($name, api: $api, baseUrl: $baseUrl)';
}

/// 搜索规则：搜索 URL 模板 + 列表/标题/链接/封面选择器。
class SearchRule {
  const SearchRule({
    required this.url,
    required this.list,
    required this.title,
    required this.link,
    this.cover = '',
  });

  /// Kazumi 的 `searchURL`，用 `@keyword` 表示关键词占位。
  final String url;

  /// `searchList`：列表容器的 XPath。
  final String list;

  /// `searchName`：条目标题（相对容器）。
  final String title;

  /// `searchResult`：条目详情链接（相对容器，取 `href`）。
  final String link;

  /// 引擎扩展：封面（相对容器）。Kazumi 规则没有这个字段，缺省为空。
  final String cover;

  bool get hasSelectors =>
      list.isNotEmpty || title.isNotEmpty || link.isNotEmpty;

  bool get hasValidSelectors =>
      isSupportedXPathSelector(list) &&
      isSupportedXPathSelector(title) &&
      isSupportedXPathSelector(link) &&
      (cover.isEmpty || isSupportedXPathSelector(cover));

  /// 把关键词编码进搜索 URL。Kazumi 用 `@keyword`；顺带兼容 `{keyword}`。
  String buildUrl(String keyword) {
    if (url.trim().isEmpty) return '';
    final encoded = Uri.encodeQueryComponent(keyword);
    return url.replaceAll('@keyword', encoded).replaceAll('{keyword}', encoded);
  }
}

/// 详情规则：播放线路容器 + 剧集节点 + 可选详情封面。
class DetailRule {
  const DetailRule({
    required this.roads,
    required this.episodes,
    this.cover = '',
  });

  /// `chapterRoads`：播放线路（一个 tab/面板）的 XPath。
  final String roads;

  /// `chapterResult`：线路内剧集链接的 XPath（相对线路）。
  final String episodes;

  /// 引擎扩展：详情封面 XPath。读 `detailCover`/`cover`，Kazumi 原生规则没有
  /// 这个字段，缺省为空串——此时详情封面回退到搜索封面，行为完全不变。
  final String cover;

  /// 详情主干选择器：封面是可选扩展，不参与"规则是否可用"判定。
  /// 刻意只按 roads/episodes 判断——加封面不得让规则变得更严或更宽松。
  bool get hasSelectors => roads.isNotEmpty || episodes.isNotEmpty;

  /// 详情主干 XPath 合法性：不检查可选封面，非法封面最多回退到搜索封面，
  /// 不会让一条原本可用的规则失效。
  bool get hasValidSelectors =>
      isSupportedXPathSelector(roads) && isSupportedXPathSelector(episodes);
}

/// 播放规则：从剧集节点取播放地址的方式。
///
/// Kazumi 固定取 `href`；这里保留为可配置项，便于处理少数把地址放在
/// `data-url` 等属性里的站点。规则 JSON 用扩展键 `playUrlAttribute` 表达，
/// 缺省 `href`。
class PlayRule {
  const PlayRule({this.urlAttribute = 'href'});

  final String urlAttribute;

  bool get isSupported => urlAttribute.trim().isNotEmpty;
}

const Set<String> _knownJsonKeys = <String>{
  'api',
  'type',
  'name',
  'version',
  'muliSources',
  'multiSources',
  'useWebview',
  'useNativePlayer',
  'usePost',
  'useLegacyParser',
  'adBlocker',
  'userAgent',
  'baseURL',
  'baseUrl',
  'searchURL',
  'searchUrl',
  'searchList',
  'searchName',
  'searchResult',
  'searchCover',
  'chapterRoads',
  'chapterResult',
  'detailCover',
  'cover',
  'referer',
  'searchMode',
  'chapterMode',
  'playUrlAttribute',
};

String _readString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

bool _readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}
