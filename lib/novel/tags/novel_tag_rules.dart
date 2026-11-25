// 标签分组规则的纯逻辑（对照 legado 的 `TagGroupRule`）。
//
// 规则 = 正则 + 标签名；命中后给书打这个标签（写在收藏行的 groupName 上，
// 与书架分组复用同一列，因此既有筛选下拉直接可用）。**只加不减**：已有
// 分组（无论是手工设的还是上一次规则写的）一律不覆盖——与上游
// `book.group or newGroupMask` 的语义一致，避免规则把用户分组冲掉。
//
// 匹配对象：分类标签（`NovelSummary.kind`，逗号切分）+ 书名。本地书没有
// 分类标签，靠书名也能命中；正则写 `^` 就能只按分类精确匹配。
library;

import 'dart:convert';

/// 一条标签分组规则。
class NovelTagRule {
  const NovelTagRule({
    this.id,
    required this.name,
    required this.pattern,
    this.colorArgb,
    this.enabled = true,
    this.sortOrder = 0,
  });

  final int? id;

  /// 标签名（= 书架分组名）。
  final String name;

  /// 正则表达式。
  final String pattern;

  /// 标签颜色 ARGB；null = 用主题默认色。
  final int? colorArgb;

  final bool enabled;
  final int sortOrder;

  bool get isValid =>
      name.trim().isNotEmpty && compileNovelTagPattern(pattern) != null;

  NovelTagRule copyWith({
    int? id,
    String? name,
    String? pattern,
    int? colorArgb,
    bool clearColor = false,
    bool? enabled,
    int? sortOrder,
  }) => NovelTagRule(
    id: id ?? this.id,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    colorArgb: clearColor ? null : (colorArgb ?? this.colorArgb),
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'pattern': pattern,
    if (colorArgb != null) 'colorArgb': colorArgb,
    'enabled': enabled,
    'order': sortOrder,
  };

  factory NovelTagRule.fromJson(Map<String, Object?> json) => NovelTagRule(
    name: '${json['name'] ?? json['groupName'] ?? ''}'.trim(),
    pattern: '${json['pattern'] ?? ''}'.trim(),
    colorArgb: json['colorArgb'] is num
        ? (json['colorArgb']! as num).toInt()
        : null,
    enabled: json['enabled'] is bool ? json['enabled']! as bool : true,
    sortOrder: json['order'] is num ? (json['order']! as num).toInt() : 0,
  );
}

/// 编译正则；坏正则返回 null（调用方跳过，不抛异常）。
RegExp? compileNovelTagPattern(String pattern) {
  final text = pattern.trim();
  if (text.isEmpty) return null;
  try {
    return RegExp(text, caseSensitive: false);
  } on FormatException {
    return null;
  }
}

/// 分类标签切分（书源 `kind` 字段是逗号分隔的串）。
List<String> splitNovelKindTags(String kind) => <String>[
  for (final tag in kind.split(RegExp(r'[,，/、]')))
    if (tag.trim().isNotEmpty) tag.trim(),
];

/// 找出第一条命中的规则（按 [rules] 给定顺序，调用方先按 sortOrder 排好）。
///
/// 停用/坏正则的规则跳过；命中 = 正则匹配任一分类标签或书名。
NovelTagRule? matchNovelTagRule({
  required Iterable<NovelTagRule> rules,
  String kind = '',
  String title = '',
}) {
  final tags = splitNovelKindTags(kind);
  for (final rule in rules) {
    if (!rule.enabled) continue;
    final regex = compileNovelTagPattern(rule.pattern);
    if (regex == null) continue;
    if (tags.any(regex.hasMatch)) return rule;
    if (title.trim().isNotEmpty && regex.hasMatch(title)) return rule;
  }
  return null;
}

/// 解析导入文本：规则数组 / 单个规则对象 / 带 `tagGroupRules` 包壳。
/// 完全解析不出规则时抛 [FormatException]。
List<NovelTagRule> decodeNovelTagRules(String text) {
  final decoded = jsonDecode(text);
  final List<Object?> rawRules;
  if (decoded is List) {
    rawRules = decoded;
  } else if (decoded is Map) {
    final nested = decoded['tagGroupRules'] ?? decoded['rules'];
    if (nested is List) {
      rawRules = nested;
    } else if (decoded.containsKey('pattern')) {
      rawRules = <Object?>[decoded];
    } else {
      throw const FormatException('文件里没有 tagGroupRules / rules 数组');
    }
  } else {
    throw const FormatException('不是合法的 JSON 对象 / 数组');
  }
  final result = <NovelTagRule>[];
  for (final raw in rawRules) {
    if (raw is! Map) continue;
    final rule = NovelTagRule.fromJson(Map<String, Object?>.from(raw));
    if (!rule.isValid) continue;
    result.add(rule);
  }
  if (result.isEmpty) {
    throw const FormatException('没有可导入的标签规则（缺标签名/正则，或正则编译不过）');
  }
  return result;
}

/// 导出成 JSON 数组（带缩进，方便用户手改）。
String encodeNovelTagRules(Iterable<NovelTagRule> rules) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert(<Object?>[for (final rule in rules) rule.toJson()]);

/// 应用到书架的结果（页面提示用）。
class NovelTagApplyResult {
  const NovelTagApplyResult({
    this.matched = 0,
    this.updated = 0,
    this.kept = 0,
    this.affectedNames = const <String>[],
  });

  /// 命中至少一条规则的书数。
  final int matched;

  /// 实际写入了分组（原本无分组）的书数。
  final int updated;

  /// 命中了但已有分组、按「只加不减」保留原值的书数。
  final int kept;

  /// 本次涉及到的标签名（去重）。
  final List<String> affectedNames;

  bool get changed => updated > 0;
}
