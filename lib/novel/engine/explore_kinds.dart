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
    // 必须先剥 <js>…</js> 包裹再剥 @js: 前缀：原实现只认前缀，<js>…</js>
    // 整段被 eval（<js> 不是合法 JS 标识符语句），发现分类恒失败。
    var script = text;
    final wrapped = RegExp(
      r'^<js>([\w\W]*)</js>\s*$',
      caseSensitive: false,
    ).firstMatch(script);
    if (wrapped != null) {
      script = wrapped.group(1)!;
    } else {
      script = script.replaceFirst(RegExp(r'^@js:', caseSensitive: false), '');
    }
    // @js: 贪婪吃到串尾时，尾注 `##说明` 不能进 eval（LESSON §八）。
    script = script.split('##').first.trim();
    if (script.isEmpty) return const <NovelExploreKind>[];
    final value = await analyzer.evalJs(script);
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

/// 发现分类入口的排布参数（legado `ExploreKindLayout`）。
///
/// 上游 `style.layout_flexBasisPercent` 是"占父宽度的百分比"，`layout_flexGrow`
/// 是"同一行里按权重瓜分剩余宽度"；两者都缺省时按普通等宽 chip 排。这里只
/// 做**纯计算**，具体怎么摆由页面决定——配置解析出来就一定要用上，不能
/// 解析完躺在模型里（LESSON：解析了但静默不生效）。
class NovelExploreKindSlot {
  const NovelExploreKindSlot({required this.widthFactor, required this.grow});

  /// 占父宽度的比例 0..1；null = 跟随内容宽度（chip 自适应）。
  final double? widthFactor;

  /// 行内剩余宽度权重；0 = 不参与拉伸。
  final double grow;

  bool get isFixedWidth => widthFactor != null;

  /// 单个 chip 的目标宽度：有 flexBasisPercent 就按比例，否则给 [fallback]。
  double widthFor(double available, double fallback) {
    final factor = widthFactor;
    if (factor == null) return fallback;
    return (available * factor).clamp(0.0, available);
  }

  static NovelExploreKindSlot of(NovelExploreKind kind) => NovelExploreKindSlot(
    widthFactor: _percentToFactor(kind.flexBasisPercent),
    grow: (kind.flexGrow ?? 0).clamp(0.0, 100.0),
  );

  /// legado 里这个值可能是 0..1 的小数，也可能是 0..100 的百分数。
  static double? _percentToFactor(double? value) {
    if (value == null || value <= 0) return null;
    final factor = value > 1 ? value / 100 : value;
    return factor.clamp(0.01, 1.0);
  }
}

/// 发现分类地址是否自带翻页占位（`{{page}}` / `<1,2,3>` / JS）。
bool exploreUrlHasPagePlaceholder(String url) {
  if (url.contains('{{') || url.contains('<')) return true;
  final lower = url.toLowerCase();
  return lower.startsWith('@js:') || lower.startsWith('<js>');
}

/// 给不带翻页占位的发现地址补页码（legado `ruleExplore.pageParam`）。
///
/// 语义对齐上游：`pageParam` 留空按 `page` 处理；只在 [page] > 1 时追加，
/// 第 1 页保持原地址（很多站点对 `page=1` 与无参返回不同页面）。
/// 地址自带 `{{page}}` / `<1,2>` / `@js:` 时原样返回——那些由 AnalyzeUrl
/// 的占位替换负责，再追加 query 会重复翻页。
String applyExplorePageParam(
  String url, {
  required String pageParam,
  required int page,
}) {
  if (page <= 1) return url;
  if (exploreUrlHasPagePlaceholder(url)) return url;
  final name = pageParam.trim().isEmpty ? 'page' : pageParam.trim();
  final separator = url.contains('?') ? '&' : '?';
  return '$url$separator$name=$page';
}

/// 把一组分类按 flex 参数分到行里，返回每行的 (kind 下标, 宽度比例)。
///
/// 规则与 Compose `Row` + `weight` 近似：
/// 1. `flexBasisPercent` 先占位（比例之和 > 1 时按比例缩放，不溢出）；
/// 2. `flexGrow` 均分剩下的比例；没有 flexGrow 的空位留给内容自适应；
/// 3. 一行排满就换行，未设置宽度的项在行内按剩余宽度均分。
List<List<({int index, double? factor, double grow})>> layoutExploreKindRows(
  List<NovelExploreKind> kinds,
) {
  if (kinds.isEmpty) return const <List<({int index, double? factor, double grow})>>[];
  final slots = <({int index, double? factor, double grow})>[
    for (var i = 0; i < kinds.length; i++)
      (
        index: i,
        factor: NovelExploreKindSlot.of(kinds[i]).widthFactor,
        grow: NovelExploreKindSlot.of(kinds[i]).grow,
      ),
  ];
  // 没有一行里出现任何 flex 参数：交给页面用普通 Wrap 排（保持旧观感）。
  if (slots.every((slot) => slot.factor == null && slot.grow <= 0)) {
    return <List<({int index, double? factor, double grow})>>[slots];
  }
  final rows = <List<({int index, double? factor, double grow})>>[];
  var row = <({int index, double? factor, double grow})>[];
  var used = 0.0;
  for (final slot in slots) {
    final factor = slot.factor;
    if (factor == null) {
      // 自适应宽度项：至少占 0.18，避免行里塞满无数小 chip。
      if (row.isNotEmpty && used + 0.18 > 1.0) {
        rows.add(row);
        row = <({int index, double? factor, double grow})>[];
        used = 0;
      }
      row.add(slot);
      used += 0.18;
      continue;
    }
    if (row.isNotEmpty && used + factor > 1.0001) {
      rows.add(row);
      row = <({int index, double? factor, double grow})>[];
      used = 0;
    }
    row.add(slot);
    used += factor;
  }
  if (row.isNotEmpty) rows.add(row);
  return rows;
}

