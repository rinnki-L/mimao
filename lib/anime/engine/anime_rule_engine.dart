/// 规则引擎的编排层：抓网页 + 跑 XPath + 返回结构化条目。
///
/// 上层只需要：
/// ```dart
/// final engine = AnimeRuleEngine();
/// final hits = await engine.search(rule, '芙莉莲');
/// final episodes = await engine.detail(rule, hits.items.first.absoluteUrl);
/// ```
/// 网络与解析都可注入替换，便于测试与后续换 HTTP 客户端。
library;

import '../request/web_client.dart';
import 'extractor.dart';
import 'result.dart';
import 'rule.dart';

/// 番剧规则引擎。
class AnimeRuleEngine {
  AnimeRuleEngine({AnimeHttpClient? client, RuleExtractor? extractor})
    : _client = client ?? AnimeWebClient(),
      _extractor = extractor ?? const RuleExtractor();

  final AnimeHttpClient _client;
  final RuleExtractor _extractor;

  /// 用规则搜索关键词。
  ///
  /// 搜索 URL 里的 `@keyword` 会被编码替换；`usePost` 规则会把 query 参数
  /// 改放到表单体里（Kazumi 同款行为）。命中过滤由站点完成，若要本地过滤，
  /// 对结果调用 [filterSearchResults]。
  Future<RuleParseResult<RuleSearchResult>> search(
    AnimeRule rule,
    String keyword, {
    Map<String, String> cookies = const <String, String>{},
  }) async {
    final prepared = _prepareSearchRequest(rule, keyword);
    if (prepared == null) {
      return const RuleParseResult<RuleSearchResult>(
        diagnostics: ['规则缺少 searchURL 或 searchURL 不是绝对 URL'],
      );
    }

    try {
      final response = await _client.fetch(
        prepared.url,
        options: AnimeFetchOptions(
          method: prepared.method,
          userAgent: rule.userAgent,
          referer: rule.referer,
          cookies: cookies,
          formData: prepared.formData,
        ),
      );
      if (!response.isSuccessful) {
        return RuleParseResult<RuleSearchResult>(
          diagnostics: ['搜索请求失败：HTTP ${response.statusCode}'],
        );
      }
      return _extractor.parseSearch(response.body, rule);
    } catch (error) {
      return RuleParseResult<RuleSearchResult>(diagnostics: ['搜索请求失败：$error']);
    }
  }

  /// 抓取详情页并抽取剧集。
  Future<RuleParseResult<RuleEpisode>> detail(
    AnimeRule rule,
    String detailUrl, {
    Map<String, String> cookies = const <String, String>{},
  }) async {
    final url = normalizeRuleUrl(rule.baseUrl, detailUrl);
    if (url.isEmpty) {
      return const RuleParseResult<RuleEpisode>(diagnostics: ['详情地址为空']);
    }
    try {
      final response = await _client.fetch(
        url,
        options: AnimeFetchOptions(
          userAgent: rule.userAgent,
          referer: rule.referer.isEmpty ? rule.baseUrl : rule.referer,
          cookies: cookies,
        ),
      );
      if (!response.isSuccessful) {
        return RuleParseResult<RuleEpisode>(
          diagnostics: ['详情请求失败：HTTP ${response.statusCode}'],
        );
      }
      return _extractor.parseDetail(response.body, rule);
    } catch (error) {
      return RuleParseResult<RuleEpisode>(diagnostics: ['详情请求失败：$error']);
    }
  }

  /// 播放地址与请求头：把剧集地址交给播放器时，通常还要带规则里的 UA/Referer。
  ({String url, Map<String, String> headers}) playTarget(
    AnimeRule rule,
    RuleEpisode episode,
  ) {
    final url = episode.absoluteUrl.isEmpty
        ? normalizeRuleUrl(rule.baseUrl, episode.url)
        : episode.absoluteUrl;
    final userAgent = rule.userAgent.trim();
    final referer = rule.referer.trim().isEmpty
        ? rule.baseUrl.trim()
        : rule.referer.trim();
    return (
      url: url,
      headers: <String, String>{
        'User-Agent': userAgent.isEmpty ? defaultAnimeUserAgent : userAgent,
        if (referer.isNotEmpty) 'Referer': referer,
      },
    );
  }

  _PreparedSearchRequest? _prepareSearchRequest(
    AnimeRule rule,
    String keyword,
  ) {
    final fullUrl = rule.search.buildUrl(keyword);
    if (fullUrl.isEmpty) return null;
    final uri = Uri.tryParse(fullUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    if (!rule.usePost) {
      return _PreparedSearchRequest(url: fullUrl, method: 'GET');
    }

    final query = uri.queryParameters;
    final postUrl = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return _PreparedSearchRequest(
      url: postUrl.toString(),
      method: 'POST',
      formData: query.isEmpty ? null : Map<String, String>.from(query),
    );
  }
}

class _PreparedSearchRequest {
  const _PreparedSearchRequest({
    required this.url,
    required this.method,
    this.formData,
  });

  final String url;
  final String method;
  final Map<String, String>? formData;
}
