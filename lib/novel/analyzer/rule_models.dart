/// 书源规则领域模型（M5 地基切片）。
///
/// 对应 legado `AnalyzeRule.kt` 的解析模式 +书源内嵌 JS 规则；只定义值对象，
/// 不含任何选择器实现，也不执行 JS。
library;

/// 规则解析模式：legado 四种解析器（css/xpath/jsonPath/regex）+ js 规则。
enum RuleMode { css, xpath, jsonPath, regex, js }

/// 一条书源规则：模式 + 选择器/表达式串 + 可选的 JS 片段。
class Rule {
  const Rule({required this.mode, required this.expression, this.jsSnippet});

  final RuleMode mode;
  final String expression;
  final String? jsSnippet;
}

/// 书源（legado 书源 JSON 的领域镜像）：id/名称/基址 + 规则表。
///
/// [rules] 的键为规则名（如 search/discover/chapters/content），值对应的规则
/// 由后续解析切片消费；本切片只冻结形状。
class BookSource {
  const BookSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.rules = const <String, Rule>{},
  });

  final String id;
  final String name;
  final String baseUrl;
  final Map<String, Rule> rules;
}
