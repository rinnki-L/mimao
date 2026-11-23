/// legado `AnalyzeByXPath` 的 Dart 重译：`//...` 规则交给
/// `xpath_selector_html_parser`（同一份 `package:html` DOM）。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'rule_splitter.dart';

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
      final temp = _query(part);
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
      final temp = _queryObjects(part);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return _combine(results, splitter.elementsType);
  }

  List<String> _query(String rule) {
    try {
      final result = HtmlXPath.node(_root).query(rule);
      final attrs = <String>[
        for (final attr in result.attrs)
          if (attr != null) attr,
      ];
      if (attrs.isNotEmpty) return attrs;
      return <String>[
        for (final node in result.nodes)
          if ((node.text ?? '').isNotEmpty) node.text!,
      ];
    } on Object {
      return const <String>[];
    }
  }

  List<Object> _queryObjects(String rule) {
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
