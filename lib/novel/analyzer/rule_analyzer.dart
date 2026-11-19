/// 书源规则解析器窄接口（M5 地基切片）。
///
/// 只有接口，零实现：真实的选择器（CSS/XPath/JSONPath/Regex）与 JS 执行
/// 由后续切片以可注入实现的方式提供，本切片不碰网页、不执行 JS。
library;

import 'package:mimao/novel/analyzer/rule_models.dart';

abstract class RuleAnalyzer {
  Future<List<String>> parse(String content, Rule rule);
}
