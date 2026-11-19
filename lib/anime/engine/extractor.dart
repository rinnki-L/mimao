/// XPath 抽取引擎：把「规则（数据）+ 网页（HTML）」变成结构化条目。
///
/// 语义对齐 Kazumi 的 `XPathRuleStrategy`：
/// - 搜索：`searchList` 选出条目容器，再在容器内用 `searchName`/`searchResult`
///   取标题与链接；
/// - 详情：`chapterRoads` 选出线路，再在线路内用 `chapterResult` 取剧集，
///   标题取节点文本、地址取节点属性（默认 `href`）；
/// - 地址用规则的 `baseURL` 归一化成绝对 URL（与 Kazumi `normalizeEpisodeUrl`
///   同规则：同站统一协议、去尾斜杠、去空 query）。
///
/// 所有错误都收敛成 [RuleParseResult.diagnostics]，不向上抛异常：一条坏规则
/// 只应让这一源返回空列表，不能让整个搜索/详情页崩溃。
library;

import 'package:xpath_selector/xpath_selector.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'result.dart';
import 'rule.dart';

/// 无状态抽取器；可安全复用。
class RuleExtractor {
  const RuleExtractor();

  /// 详情页封面抽取结果：原始值与基于 baseURL 归一化的绝对地址。
  /// 没有可用选择器 / 抽不到内容时两者都是空串。
  ({String coverUrl, String absoluteCoverUrl}) parseDetailCover(
    String html,
    AnimeRule rule,
  ) {
    final diagnostics = <String>[];
    final root = _parseDocument(html, diagnostics);
    if (root == null) return (coverUrl: '', absoluteCoverUrl: '');
    return _coverFromRoot(root, rule);
  }

  /// 从已解析的文档根节点取详情封面。
  ({String coverUrl, String absoluteCoverUrl}) _coverFromRoot<T>(
    XPath<T> root,
    AnimeRule rule,
  ) {
    final selector = rule.detail.cover.trim();
    if (selector.isEmpty || !isSupportedXPathSelector(selector)) {
      return (coverUrl: '', absoluteCoverUrl: '');
    }
    try {
      // 根节点是 XPath（查询器）而非 XPathNode，直接用 query 取属性，语义与
      // _firstAttribute 一致：先取结果里的属性值，再回退到节点自身的 src。
      final result = root.query(selector);
      var cover = result.attrs.firstWhere(
        (item) => item != null,
        orElse: () => null,
      );
      cover ??= result.node?.attributes['src'];
      final coverUrl = (cover ?? '').trim();
      return (
        coverUrl: coverUrl,
        absoluteCoverUrl: coverUrl.isEmpty
            ? ''
            : normalizeRuleUrl(rule.baseUrl, coverUrl),
      );
    } catch (_) {
      // 封面是可选增强：解析失败就回退，不让整个详情页失败。
      return (coverUrl: '', absoluteCoverUrl: '');
    }
  }

  /// 解析搜索结果页。
  RuleParseResult<RuleSearchResult> parseSearch(String html, AnimeRule rule) {
    final diagnostics = <String>[];
    if (!rule.search.hasValidSelectors) {
      return RuleParseResult<RuleSearchResult>(
        diagnostics: ['搜索规则不完整或 XPath 不受支持（只支持 // 开头）'],
      );
    }

    final root = _parseDocument(html, diagnostics);
    if (root == null) {
      return RuleParseResult<RuleSearchResult>(diagnostics: diagnostics);
    }

    final List<XPathNode<dynamic>> nodes;
    try {
      nodes = root.query(rule.search.list).nodes;
    } catch (error) {
      return RuleParseResult<RuleSearchResult>(
        diagnostics: [...diagnostics, '搜索列表 XPath 无法执行：$error'],
      );
    }

    final items = <RuleSearchResult>[];
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      try {
        final title = _firstText(node, rule.search.title);
        final url = _firstAttribute(node, rule.search.link);
        if (title.isEmpty || url.isEmpty) {
          diagnostics.add('第 ${index + 1} 个搜索结果缺少标题或链接，已跳过');
          continue;
        }
        final cover = rule.search.cover.isEmpty
            ? ''
            : _firstAttribute(node, rule.search.cover, attribute: 'src');
        items.add(
          RuleSearchResult(
            title: title,
            url: url,
            coverUrl: cover,
            absoluteUrl: normalizeRuleUrl(rule.baseUrl, url),
            absoluteCoverUrl: cover.isEmpty
                ? ''
                : normalizeRuleUrl(rule.baseUrl, cover),
          ),
        );
      } catch (error) {
        diagnostics.add('第 ${index + 1} 个搜索结果解析失败：$error');
      }
    }

    return RuleParseResult<RuleSearchResult>(
      items: items,
      diagnostics: diagnostics,
    );
  }

  /// 解析详情页，按线路顺序返回扁平化的剧集列表。
  RuleParseResult<RuleEpisode> parseDetail(String html, AnimeRule rule) {
    final diagnostics = <String>[];
    if (!rule.detail.hasValidSelectors || !rule.play.isSupported) {
      return RuleParseResult<RuleEpisode>(
        diagnostics: ['详情规则不完整或 XPath 不受支持（只支持 // 开头）'],
      );
    }

    final root = _parseDocument(html, diagnostics);
    if (root == null) {
      return RuleParseResult<RuleEpisode>(diagnostics: diagnostics);
    }

    // 详情封面与剧集同一次解析，避免二次抓取；可选字段，抽不到就是空串。
    final cover = _coverFromRoot(root, rule);

    final List<XPathNode<dynamic>> roads;
    try {
      roads = root.query(rule.detail.roads).nodes;
    } catch (error) {
      return RuleParseResult<RuleEpisode>(
        diagnostics: [...diagnostics, '播放线路 XPath 无法执行：$error'],
      );
    }

    final items = <RuleEpisode>[];
    for (var roadIndex = 0; roadIndex < roads.length; roadIndex++) {
      final road = roads[roadIndex];
      final roadName = '播放线路${roadIndex + 1}';
      final List<XPathNode<dynamic>> episodeNodes;
      try {
        episodeNodes = road.queryXPath(rule.detail.episodes).nodes;
      } catch (error) {
        diagnostics.add('$roadName 的剧集 XPath 无法执行：$error');
        continue;
      }

      for (
        var episodeIndex = 0;
        episodeIndex < episodeNodes.length;
        episodeIndex++
      ) {
        final node = episodeNodes[episodeIndex];
        try {
          final url = (node.attributes[rule.play.urlAttribute] ?? '').trim();
          if (url.isEmpty) {
            diagnostics.add('$roadName 第 ${episodeIndex + 1} 集缺少播放地址，已跳过');
            continue;
          }
          final rawTitle = _collapseWhitespace(node.text ?? '');
          items.add(
            RuleEpisode(
              title: rawTitle.isEmpty ? '第${episodeIndex + 1}集' : rawTitle,
              url: url,
              absoluteUrl: normalizeRuleUrl(rule.baseUrl, url),
              roadIndex: roadIndex + 1,
              roadName: roadName,
            ),
          );
        } catch (error) {
          diagnostics.add('$roadName 第 ${episodeIndex + 1} 集解析失败：$error');
        }
      }
    }

    return RuleParseResult<RuleEpisode>(
      items: items,
      diagnostics: diagnostics,
      coverUrl: cover.coverUrl,
      absoluteCoverUrl: cover.absoluteCoverUrl,
    );
  }

  XPath<dynamic>? _parseDocument(String html, List<String> diagnostics) {
    try {
      return HtmlXPath.html(html);
    } catch (error) {
      diagnostics.add('HTML 解析失败：$error');
      return null;
    }
  }
}

/// 本地搜索命中过滤（真实搜索由站点完成；这一步用于规则试跑与聚合过滤）。
List<RuleSearchResult> filterSearchResults(
  Iterable<RuleSearchResult> results,
  String keyword,
) {
  final query = keyword.trim().toLowerCase();
  if (query.isEmpty) return List<RuleSearchResult>.of(results);
  return results
      .where((item) => item.title.toLowerCase().contains(query))
      .toList(growable: false);
}

/// 把页面上的原始 href 归一化为稳定的绝对 URL。
///
/// 移植自 Kazumi `normalizeEpisodeUrl` 的语义（非拷贝代码）：
/// - 相对路径基于 [baseUrl] 补全；
/// - 与 [baseUrl] 同站（同 host、同显式端口）时协议统一到 baseUrl，
///   跨站保持原协议（规则站点可能只支持 http）；
/// - 去掉 path 多余尾斜杠（根路径 `/` 保留）、空 query；
/// - 无法解析为绝对 URL 时原样返回去空白后的输入。
String normalizeRuleUrl(String baseUrl, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final rawUri = Uri.tryParse(trimmed);
  final baseUri = Uri.tryParse(baseUrl.trim());
  final hasValidBase =
      baseUri != null && baseUri.hasScheme && baseUri.host.isNotEmpty;

  Uri? resolved;
  if (rawUri != null && rawUri.hasScheme && rawUri.host.isNotEmpty) {
    resolved = rawUri;
  } else if (hasValidBase) {
    try {
      resolved = baseUri.resolve(trimmed);
    } catch (_) {
      resolved = null;
    }
  }
  if (resolved == null || resolved.host.isEmpty) return trimmed;

  if (hasValidBase &&
      _isHttpScheme(baseUri.scheme) &&
      _isHttpScheme(resolved.scheme) &&
      resolved.scheme != baseUri.scheme &&
      resolved.host == baseUri.host &&
      resolved.hasPort == baseUri.hasPort &&
      (!resolved.hasPort || resolved.port == baseUri.port)) {
    resolved = resolved.replace(scheme: baseUri.scheme);
  }

  var path = resolved.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final hasQuery = resolved.hasQuery && resolved.query.isNotEmpty;
  final hasFragment = resolved.hasFragment && resolved.fragment.isNotEmpty;

  return Uri(
    scheme: resolved.scheme,
    host: resolved.host,
    port: resolved.hasPort ? resolved.port : null,
    path: path,
    query: hasQuery ? resolved.query : null,
    fragment: hasFragment ? resolved.fragment : null,
  ).toString();
}

String _firstText<T>(XPathNode<T> node, String selector) {
  final result = node.queryXPath(selector);
  final attribute = result.attrs.firstWhere(
    (value) => value != null,
    orElse: () => null,
  );
  if (attribute != null) return _collapseWhitespace(attribute);
  return _collapseWhitespace(result.node?.text ?? '');
}

String _firstAttribute<T>(
  XPathNode<T> node,
  String selector, {
  String attribute = 'href',
}) {
  final result = node.queryXPath(selector);
  final value = result.attrs.firstWhere(
    (item) => item != null,
    orElse: () => null,
  );
  if (value != null) return value.trim();
  final target = result.node;
  if (target == null) return '';
  return (target.attributes[attribute] ?? '').trim();
}

/// Kazumi 会把剧集标题里的空白全部删掉；这里折叠为单空格，
/// 保留「第01话 启程」这类可读性，同时让对比测试稳定。
String _collapseWhitespace(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isHttpScheme(String scheme) => scheme == 'http' || scheme == 'https';
