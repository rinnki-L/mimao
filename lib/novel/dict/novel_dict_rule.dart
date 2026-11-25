// 词典查询规则的纯数据模型（对照 legado 的 `DictRule`）。
//
// 一条规则 = 一个站点：`urlRule` 用 `{{key}}` 带查询词，`showRule` 是结果
// 解析规则（空 = 直接展示返回正文）。这里只管建模、编解码与 URL 展开，
// 抓取与解析在 `novel_dict_service.dart`，页面只认这两份。
//
// JSON 字段名刻意与 Legado 的 `dictRules.json` 对齐（name / urlRule /
// showRule / enabled / sortNumber），导入导出可直接互通。
library;

import 'dart:convert';

/// 一条词典规则。
class NovelDictRule {
  const NovelDictRule({
    this.id,
    required this.name,
    required this.urlRule,
    this.showRule = '',
    this.enabled = true,
    this.sortOrder = 0,
    this.builtin = false,
  });

  /// 库内主键；null = 尚未保存。
  final int? id;

  final String name;

  /// 查询地址规则，支持 `{{key}}` 与 `,{...}` 选项（与书源同一套 AnalyzeUrl）。
  final String urlRule;

  /// 结果解析规则；空串 = 直接展示返回正文。
  final String showRule;

  final bool enabled;
  final int sortOrder;

  /// 内置规则：可改可停用，删除后能用「恢复默认」找回。
  final bool builtin;

  bool get isValid => name.trim().isNotEmpty && urlRule.trim().isNotEmpty;

  /// 是否含 `@js:` 类结果规则（需要 JS 宿主）。
  bool get showRuleNeedsJs {
    final rule = showRule.trim().toLowerCase();
    return rule.contains('@js:') || rule.contains('<js>');
  }

  NovelDictRule copyWith({
    int? id,
    String? name,
    String? urlRule,
    String? showRule,
    bool? enabled,
    int? sortOrder,
  }) => NovelDictRule(
    id: id ?? this.id,
    name: name ?? this.name,
    urlRule: urlRule ?? this.urlRule,
    showRule: showRule ?? this.showRule,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    builtin: builtin,
  );

  /// 落库/导出用：字段名与 Legado `dictRules.json` 一致。
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'urlRule': urlRule,
    'showRule': showRule,
    'enabled': enabled,
    'sortNumber': sortOrder,
  };

  /// 容错解析：缺字段的条目按可用部分保留（name/urlRule 全空的由调用方跳过）。
  factory NovelDictRule.fromJson(Map<String, Object?> json) => NovelDictRule(
    name: '${json['name'] ?? ''}'.trim(),
    urlRule: '${json['urlRule'] ?? ''}'.trim(),
    showRule: '${json['showRule'] ?? ''}'.trim(),
    enabled: json['enabled'] is bool ? json['enabled']! as bool : true,
    sortOrder: _intOf(json['sortNumber'] ?? json['sortOrder']),
    builtin: json['builtin'] == true,
  );

  static int _intOf(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

/// 查询词规范化：去首尾空白、压平换行、限长。
///
/// 选词可能带换行/标点，直接拼进 URL 会变成奇怪的查询；超过 40 字的多半
/// 是误选了整段正文，截断并交给界面提示更实在。
String normalizeNovelDictWord(String raw, {int maxLength = 40}) {
  final text = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(
        RegExp(r'^[\s\p{P}\p{S}]+|[\s\p{P}\p{S}]+$', unicode: true),
        '',
      )
      .trim();
  if (text.length <= maxLength) return text;
  return text.substring(0, maxLength).trim();
}

/// 把 `{{key}}` 替换成查询词（UTF-8 百分号编码）。
///
/// `AnalyzeUrl` 只对 query 做编码，而词典地址常把词放在路径里
/// （`https://www.zdic.net/hans/中文`），所以这里先编码再交给它；已经是
/// `%XX` 的片段不会被二次编码（`AnalyzeUrl` 的 `_isEncodedQuery` 会跳过）。
String expandNovelDictUrl(String urlRule, String word) {
  if (!urlRule.contains('{{key}}')) return urlRule;
  final encoded = Uri.encodeComponent(word);
  return urlRule.replaceAll('{{key}}', encoded);
}

/// 解析导入文本。接受三种形态：规则数组、单个规则对象、带 `dictRules`/`rules`
/// 数组的对象。完全解析不出规则时抛 [FormatException]。
List<NovelDictRule> decodeNovelDictRules(String text) {
  final decoded = jsonDecode(text);
  final List<Object?> rawRules;
  if (decoded is List) {
    rawRules = decoded;
  } else if (decoded is Map) {
    final nested = decoded['dictRules'] ?? decoded['rules'];
    if (nested is List) {
      rawRules = nested;
    } else if (decoded.containsKey('urlRule') || decoded.containsKey('name')) {
      rawRules = <Object?>[decoded];
    } else {
      throw const FormatException('文件里没有 dictRules / rules 数组');
    }
  } else {
    throw const FormatException('不是合法的 JSON 对象 / 数组');
  }
  final result = <NovelDictRule>[];
  for (final raw in rawRules) {
    if (raw is! Map) continue;
    final rule = NovelDictRule.fromJson(Map<String, Object?>.from(raw));
    if (!rule.isValid) continue;
    result.add(rule);
  }
  if (result.isEmpty) {
    throw const FormatException('没有可导入的词典规则（缺 name / urlRule）');
  }
  return result;
}

/// 导出成 Legado 兼容的 JSON 数组（带缩进，方便用户手改）。
String encodeNovelDictRules(Iterable<NovelDictRule> rules) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert(<Object?>[for (final rule in rules) rule.toJson()]);

/// 内置词典规则。
///
/// 前两条对齐上游 `dictRules.json`（汉典 / dict.cn），只把汉典那条的 `@js:`
/// 展示规则换成纯选择器——本机即使没有 JS 运行库也能解析出正文。第三条是
/// 离线示例：用 `data:` 地址演示「选词 → 查词 → 解析」整条链路，不联网也能
/// 出结果，方便验证与截图。
const List<NovelDictRule> novelDefaultDictRules = <NovelDictRule>[
  NovelDictRule(
    name: '汉典',
    urlRule: 'https://www.zdic.net/hans/{{key}}',
    showRule: '#jbjs@html',
    sortOrder: 0,
    builtin: true,
  ),
  NovelDictRule(
    name: 'dict.cn',
    urlRule: 'https://apii.dict.cn/mini.php?q={{key}}',
    showRule: 'tag.body@all',
    sortOrder: 1,
    builtin: true,
  ),
  NovelDictRule(
    name: '离线示例',
    urlRule:
        'data:text/html,<html><body><h2>词条：{{key}}</h2>'
        '<p>这是 mimao 内置的离线示例词典：不联网也能验证「选词 → 查询 → 解析」'
        '整条链路。真实词典请用「汉典」或导入 Legado 的 dictRules.json。</p>'
        '</body></html>',
    showRule: 'tag.body@html',
    sortOrder: 2,
    builtin: true,
  ),
];

/// 一次查询的结果：要么正文，要么一条可读的错误（不抛给界面）。
class NovelDictResult {
  const NovelDictResult({
    required this.ruleName,
    this.text = '',
    this.error,
    this.url = '',
  });

  final String ruleName;

  /// 解析后的纯文本（段落换行）。
  final String text;

  /// 失败原因；null = 成功。
  final String? error;

  /// 实际请求地址（「复制链接」用）。
  final String url;

  bool get ok => error == null && text.trim().isNotEmpty;
}
