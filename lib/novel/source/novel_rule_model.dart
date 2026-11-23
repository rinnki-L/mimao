/// Legado（阅读）三类可导入规则：书源 / 订阅源 / 替换规则。
///
/// 三者的 JSON 形状不同（书源看 `bookSourceUrl`，订阅源看 `sourceUrl`，替换规则
/// 看 `pattern` + `replacement`），导入时必须能识别出来分别落库；深链
/// `yuedu://<kind>/importonline?src=…` 的 host 也直接给出类型。
/// 这里只做与平台/IO 无关的建模、识别与替换执行，抓取与落盘在 importer / store。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 一类可导入规则的种类。`label` 用于界面与导入结果文案，`deepLinkHost`
/// 对应 Legado 深链 `yuedu://<host>/importonline?src=…` 的 host。
enum NovelRuleKind {
  bookSource('书源', 'booksource'),
  rssSource('订阅源', 'rsssource'),
  replaceRule('替换规则', 'replacerule');

  const NovelRuleKind(this.label, this.deepLinkHost);

  final String label;
  final String deepLinkHost;

  /// 从深链 host（不区分大小写）反查种类；不认识返回 null。
  static NovelRuleKind? fromDeepLinkHost(String host) {
    final normalized = host.trim().toLowerCase();
    for (final kind in NovelRuleKind.values) {
      if (kind.deepLinkHost == normalized) return kind;
    }
    return null;
  }
}

/// 按 JSON 对象的字段识别规则种类（自动识别用）。
///
/// 只认足够独特的键：书源有 `bookSourceUrl` / `ruleSearch`，订阅源有
/// `sourceUrl` / `ruleArticles`，替换规则同时有 `pattern` 与 `replacement`。
/// 认不出返回 null，由调用方决定是报错还是按用户显式选的类型硬解。
NovelRuleKind? detectNovelRuleKind(Map<String, dynamic> item) {
  if (item.containsKey('bookSourceUrl') ||
      item.containsKey('bookSourceName') ||
      item.containsKey('bookSourceType') ||
      item.containsKey('ruleSearch') ||
      item.containsKey('ruleToc')) {
    return NovelRuleKind.bookSource;
  }
  if (item.containsKey('sourceUrl') ||
      item.containsKey('sourceName') ||
      item.containsKey('ruleArticles') ||
      item.containsKey('ruleArticleList') ||
      item.containsKey('articleStyle')) {
    return NovelRuleKind.rssSource;
  }
  if (item.containsKey('pattern') && item.containsKey('replacement')) {
    return NovelRuleKind.replaceRule;
  }
  return null;
}

/// 按首个条目的字段识别整份文件的种类；文件为空或认不出返回 null。
NovelRuleKind? detectNovelRuleKindInFile(List<Map<String, dynamic>> items) {
  if (items.isEmpty) return null;
  return detectNovelRuleKind(items.first);
}

/// 一条已导入的 Legado 订阅源（RSS）。
///
/// 只保留模块当前用得上的字段；[raw] 留完整 JSON，后续 RSS 阅读切片直接消费。
class NovelRssSource {
  const NovelRssSource({
    required this.key,
    required this.name,
    required this.url,
    required this.group,
    required this.enabled,
    required this.raw,
  });

  /// 稳定文件主键：URL 的 sha1（40 位 hex），短且规避路径分隔符。
  final String key;
  final String name;
  final String url;
  final String group;
  final bool enabled;
  final Map<String, dynamic> raw;

  static String keyFor(String url) =>
      sha1.convert(utf8.encode(url.trim().toLowerCase())).toString();

  factory NovelRssSource.fromLegado(Map<String, dynamic> json) {
    final url = '${json['sourceUrl'] ?? ''}'.trim();
    final name = '${json['sourceName'] ?? ''}'.trim();
    return NovelRssSource(
      key: keyFor(url),
      name: name.isEmpty ? url : name,
      url: url,
      group: '${json['sourceGroup'] ?? ''}'.trim(),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      raw: json,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'name': name,
    'url': url,
    'group': group,
    'enabled': enabled,
    'raw': raw,
  };

  factory NovelRssSource.fromJson(Map<String, Object?> json) => NovelRssSource(
    key: '${json['key'] ?? ''}',
    name: '${json['name'] ?? ''}',
    url: '${json['url'] ?? ''}',
    group: '${json['group'] ?? ''}',
    enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    raw: Map<String, dynamic>.from(
      json['raw'] as Map? ?? const <String, Object?>{},
    ),
  );

  NovelRssSource copyWith({bool? enabled}) => NovelRssSource(
    key: key,
    name: name,
    url: url,
    group: group,
    enabled: enabled ?? this.enabled,
    raw: raw,
  );
}

/// 一条 Legado 替换规则（正文/标题的净化替换）。
///
/// `scope` 是「作用范围」原文（书源地址 / 书名等），空表示全部书籍；
/// `scopeTitle` / `scopeContent` 决定作用于标题还是正文，Legado 默认只见正文。
class NovelReplaceRule {
  const NovelReplaceRule({
    required this.key,
    required this.name,
    required this.pattern,
    required this.replacement,
    required this.isRegex,
    required this.enabled,
    required this.scope,
    required this.scopeTitle,
    required this.scopeContent,
    required this.raw,
  });

  /// 稳定文件主键：名称 + 规则原文的 sha1，同规则重复导入覆盖、改内容算新规则。
  final String key;
  final String name;
  final String pattern;
  final String replacement;
  final bool isRegex;
  final bool enabled;
  final String scope;
  final bool scopeTitle;
  final bool scopeContent;
  final Map<String, dynamic> raw;

  static String keyFor(String name, String pattern, String replacement) => sha1
      .convert(utf8.encode('$name\u0000$pattern\u0000$replacement'))
      .toString();

  factory NovelReplaceRule.fromLegado(Map<String, dynamic> json) {
    final name = '${json['name'] ?? ''}'.trim();
    final pattern = '${json['pattern'] ?? ''}';
    final replacement = '${json['replacement'] ?? ''}';
    return NovelReplaceRule(
      key: keyFor(name, pattern, replacement),
      name: name.isEmpty ? pattern : name,
      pattern: pattern,
      replacement: replacement,
      isRegex: json['isRegex'] is bool ? json['isRegex'] as bool : false,
      enabled: json['isEnabled'] is bool ? json['isEnabled'] as bool : true,
      scope: '${json['scope'] ?? ''}'.trim(),
      scopeTitle: json['scopeTitle'] == true,
      // Legado 的替换规则默认作用于正文；缺字段时按这个默认走。
      scopeContent: json['scopeContent'] is bool
          ? json['scopeContent'] as bool
          : true,
      raw: json,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'name': name,
    'pattern': pattern,
    'replacement': replacement,
    'isRegex': isRegex,
    'enabled': enabled,
    'scope': scope,
    'scopeTitle': scopeTitle,
    'scopeContent': scopeContent,
    'raw': raw,
  };

  factory NovelReplaceRule.fromJson(Map<String, Object?> json) =>
      NovelReplaceRule(
        key: '${json['key'] ?? ''}',
        name: '${json['name'] ?? ''}',
        pattern: '${json['pattern'] ?? ''}',
        replacement: '${json['replacement'] ?? ''}',
        isRegex: json['isRegex'] == true,
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
        scope: '${json['scope'] ?? ''}',
        scopeTitle: json['scopeTitle'] == true,
        scopeContent: json['scopeContent'] is bool
            ? json['scopeContent'] as bool
            : true,
        raw: Map<String, dynamic>.from(
          json['raw'] as Map? ?? const <String, Object?>{},
        ),
      );

  NovelReplaceRule copyWith({bool? enabled}) => NovelReplaceRule(
    key: key,
    name: name,
    pattern: pattern,
    replacement: replacement,
    isRegex: isRegex,
    enabled: enabled ?? this.enabled,
    scope: scope,
    scopeTitle: scopeTitle,
    scopeContent: scopeContent,
    raw: raw,
  );

  /// 规则是否作用于这本书。
  ///
  /// `scope` 为空 = 全局；含 `&&` 时要求各段都命中（AND），否则逗号/顿号/竖线
  /// 分隔的任一段命中即可（OR）。命中 = 段文本出现在书名 / 书源 key / 书源地址里
  /// （大小写不敏感）。这是 Legado 作用范围的务实子集：够用、可解释，不猜未知语法。
  bool appliesToBook({
    required String bookTitle,
    required String sourceKey,
    required String bookUrl,
  }) {
    final raw = scope.trim();
    if (raw.isEmpty) return true;
    final haystack = '$bookTitle\u0000$sourceKey\u0000$bookUrl'.toLowerCase();
    bool hit(String part) {
      final token = part.trim().toLowerCase();
      return token.isNotEmpty && haystack.contains(token);
    }

    final andParts = raw
        .split('&&')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (andParts.length > 1) return andParts.every(hit);
    final orParts = raw
        .split(RegExp(r'[|,，;；、\s]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return orParts.isEmpty || orParts.any(hit);
  }
}

/// 依次执行替换规则。坏正则 / 空规则跳过，不打断整段正文。
///
/// 与 Legado 一致：替换后整段变空白时保留原文，避免规则写错把正文清空。
String applyReplaceRules(String input, Iterable<NovelReplaceRule> rules) {
  var result = input;
  for (final rule in rules) {
    if (rule.pattern.isEmpty || !rule.enabled) continue;
    try {
      final next = rule.isRegex
          ? result.replaceAllMapped(
              RegExp(rule.pattern),
              (match) => _expandJavaReplacement(rule.replacement, match),
            )
          : result.replaceAll(rule.pattern, rule.replacement);
      if (next.trim().isNotEmpty) result = next;
    } on Object {
      // 坏正则或非法替换：跳过这条，保留上一步结果。
    }
  }
  return result;
}

/// 展开 Java 风格替换串里的 `$1`…`$99` 与 `\` 转义。
String _expandJavaReplacement(String replacement, Match match) {
  final out = StringBuffer();
  for (var i = 0; i < replacement.length; i++) {
    final char = replacement[i];
    if (char == '\\' && i + 1 < replacement.length) {
      out.write(replacement[++i]);
      continue;
    }
    if (char == r'$' && i + 1 < replacement.length) {
      var cursor = i + 1;
      while (cursor < replacement.length &&
          replacement.codeUnitAt(cursor) >= 0x30 &&
          replacement.codeUnitAt(cursor) <= 0x39) {
        cursor++;
      }
      if (cursor > i + 1) {
        final index = int.parse(replacement.substring(i + 1, cursor));
        if (index < match.groupCount + 1) {
          out.write(match.group(index) ?? '');
        }
        i = cursor - 1;
        continue;
      }
    }
    out.write(char);
  }
  return out.toString();
}
