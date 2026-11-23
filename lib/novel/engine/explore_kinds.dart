/// 发现页分类目录解析：legado 的 `exploreUrl` 有两种写法——
/// `分类名::/path/{{page}}.html` 多行文本，或 `@js:` 返回
/// `[{title,url,style:{layout_flexBasisPercent,layout_flexGrow}}]` 数组。
library;

import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/engine/lenient_json.dart';

/// 发现页的一个分类入口。
class NovelExploreKind {
  const NovelExploreKind({
    required this.name,
    required this.url,
    this.flexBasisPercent,
    this.flexGrow,
  });

  final String name;
  final String url;
  final double? flexBasisPercent;
  final double? flexGrow;
}

/// 解析分类目录；空源返回空列表，不抛错（发现页按空态处理）。
Future<List<NovelExploreKind>> parseExploreKinds(
  String exploreUrl, {
  RuleJsRunner? jsRunner,
  String? baseUrl,
  Map<String, String> variables = const <String, String>{},
  Map<String, String> sourceInfo = const <String, String>{},
}) async {
  final text = exploreUrl.trim();
  if (text.isEmpty) return const <NovelExploreKind>[];

  if (text.toLowerCase().startsWith('@js:') ||
      text.toLowerCase().startsWith('<js>')) {
    if (jsRunner == null) return const <NovelExploreKind>[];
    final analyzer = LegadoRuleAnalyzer(
      content: '',
      baseUrl: baseUrl,
      jsRunner: jsRunner,
      variables: variables,
      sourceInfo: sourceInfo,
    );
    final value = await analyzer.evalJs(
      text.replaceFirst(RegExp(r'^@js:', caseSensitive: false), ''),
    );
    return _fromValue(value);
  }

  final trimmed = text.trimLeft();
  if (trimmed.startsWith('[')) {
    return _fromValue(lenientJsonDecode(trimmed));
  }

  final kinds = <NovelExploreKind>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty) continue;
    final index = trimmedLine.indexOf('::');
    if (index <= 0) continue;
    final name = trimmedLine.substring(0, index).trim();
    final url = trimmedLine.substring(index + 2).trim();
    if (name.isEmpty || url.isEmpty) continue;
    kinds.add(NovelExploreKind(name: name, url: url));
  }
  return kinds;
}

List<NovelExploreKind> _fromValue(Object? value) {
  final list = switch (value) {
    List<Object?> value => value,
    String value => lenientJsonDecode(value),
    _ => null,
  };
  if (list is! List) return const <NovelExploreKind>[];
  final result = <NovelExploreKind>[];
  for (final item in list) {
    if (item is! Map) continue;
    final title = '${item['title'] ?? item['name'] ?? ''}'.trim();
    final url = '${item['url'] ?? ''}'.trim();
    if (title.isEmpty || url.isEmpty) continue;
    final style = item['style'] is Map ? item['style'] as Map : null;
    result.add(
      NovelExploreKind(
        name: title,
        url: url,
        flexBasisPercent: _doubleOf(style?['layout_flexBasisPercent']),
        flexGrow: _doubleOf(style?['layout_flexGrow']),
      ),
    );
  }
  return result;
}

double? _doubleOf(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
