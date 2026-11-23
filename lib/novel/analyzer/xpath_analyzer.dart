/// legado `AnalyzeByXPath` 的 Dart 重译。
///
/// 主路径走自写的 [simpleXPath]（覆盖书源常用的 `//`、`/`、`@attr`、`text()`、
/// 属性/文本谓词与 `contains`）；只有遇到复杂轴/函数时才回落到
/// `xpath_selector_html_parser`。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mimao/novel/analyzer/jsoup_selector.dart' show jsoupText;
import 'package:mimao/novel/analyzer/rule_splitter.dart';
import 'package:mimao/novel/analyzer/simple_xpath.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

class XPathAnalyzer {
  XPathAnalyzer(Object content) : _root = _rootOf(content);

  final Element _root;

  static Element _rootOf(Object content) {
    if (content is Element) return content;
    if (content is Document) {
      return content.documentElement ?? html_parser.parse('').documentElement!;
    }
    final parsed = html_parser.parse(content.toString());
    return parsed.documentElement!;
  }

  String? getString(String rule) {
    final values = getStringList(rule);
    if (values.isEmpty) return null;
    return values.join('\n');
  }

  List<String> getStringList(String rule) {
    if (rule.isEmpty) return const <String>[];
    final splitter = RuleSplitter(rule);
    final rules = splitter.splitRule(const <String>['&&', '||', '%%']);
    final results = <List<String>>[];
    for (final part in rules) {
      final temp = <String>[
        for (final value in _query(part))
          if (value is Element)
            jsoupText(value)
          else if (value is Text)
            value.data.trim()
          else
            '$value',
      ].where((value) => value.isNotEmpty).toList();
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return _combine(results, splitter.elementsType);
  }

  /// 取节点列表：元素返回原始 Element，文本/属性返回字符串。
  List<Object> getElements(String rule) {
    if (rule.isEmpty) return const <Object>[];
    final splitter = RuleSplitter(rule);
    final rules = splitter.splitRule(const <String>['&&', '||', '%%']);
    final results = <List<Object>>[];
    for (final part in rules) {
      final temp = _query(part);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return _combine(results, splitter.elementsType);
  }

  List<Object> _query(String rule) {
    try {
      final values = simpleXPath(_root, rule.trim());
      return <Object>[
        for (final value in values)
          if (value is Element || value is Text) value else '$value',
      ];
    } on FormatException {
      return _queryWithPackage(rule);
    } on Object {
      return _queryWithPackage(rule);
    }
  }

  List<Object> _queryWithPackage(String rule) {
    try {
      final result = HtmlXPath.node(_root).query(rule);
      final attrs = <Object>[
        for (final attr in result.attrs)
          if (attr != null) attr,
      ];
      if (attrs.isNotEmpty) return attrs;
      return <Object>[
        for (final node in result.nodes)
          if (node.isElement) node.node else (node.text ?? ''),
      ];
    } on Object {
      return const <Object>[];
    }
  }

  static List<T> _combine<T>(List<List<T>> results, String type) {
    if (results.isEmpty) return <T>[];
    if (type == '%%') {
      final out = <T>[];
      for (var i = 0; i < results.first.length; i++) {
        for (final list in results) {
          if (i < list.length) out.add(list[i]);
        }
      }
      return out;
    }
    return <T>[for (final list in results) ...list];
  }
}