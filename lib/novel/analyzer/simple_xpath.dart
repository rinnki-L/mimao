/// 面向书源规则的 XPath 子集求值器（基于 `package:html` DOM）。
///
/// 为什么不用 `xpath_selector` 一把梭：它在 `[span]` 这种「子元素存在」谓词、
/// `..` 父轴和 `text()` 比较上会静默返回空集（实测 2026-11-23，黑岩目录
/// `//li[span]/a` 得 0）。书源里这些写法很常见，所以这里实现一个足够用的
/// 求值器：`//` / `/` / `@attr` / `text()` / 属性与文本谓词 / `contains` /
/// `starts-with` / `and` / `or` / `[n]` / `[last()]` / 并列 `|`。
///
/// 复杂轴（`ancestor::`、`following-sibling::` 等）不在这里做，调用方
/// 解析失败时回落到 `xpath_selector`。
library;

import 'package:html/dom.dart';

/// XPath 查询结果值：Element / Text / 属性字符串。
typedef XPathValue = Object;

/// 对 [root] 执行 XPath；语法不支持时抛 [FormatException]。
List<XPathValue> simpleXPath(Element root, String path) {
  final result = <XPathValue>[];
  for (final group in _splitTopLevel(path, '|')) {
    result.addAll(_evalPath(root, group.trim()));
  }
  return result;
}

List<XPathValue> _evalPath(Element root, String path) {
  if (path.isEmpty) throw FormatException('empty xpath');
  final steps = _parseSteps(path);
  var current = <Node>[root];
  for (final step in steps) {
    if (step.nodeTest.startsWith('@')) {
      // 属性轴作用在当前节点上，不是子节点。
      final attr = step.nodeTest.substring(1);
      final pool = step.descendant
          ? <Node>[for (final node in current) ..._descendantsOrSelf(node)]
          : <Node>[...current];
      final values = <String>[];
      for (final node in pool) {
        if (node is Element) {
          final value = node.attributes[attr];
          if (value != null) values.add(value);
        }
      }
      if (!step.isLast) throw FormatException('attribute in middle');
      return values;
    }
    final next = <Node>[];
    for (final node in current) {
      if (step.descendant) {
        next.addAll(_descendantsOrSelf(node));
      } else {
        next.addAll(_children(node));
      }
    }
    var selected = <Node>[];
    if (step.nodeTest == 'text()') {
      for (final node in next) {
        if (node is Element) {
          for (final child in node.nodes) {
            if (child is Text) selected.add(child);
          }
        } else if (node is Text) {
          selected.add(node);
        }
      }
    } else if (step.nodeTest == 'node()') {
      selected = next;
    } else if (step.nodeTest == '.') {
      selected = next.whereType<Element>().toList();
    } else if (step.nodeTest == '..') {
      for (final node in current) {
        final parent = node.parent;
        if (parent != null) selected.add(parent);
      }
    } else {
      final tag = step.nodeTest;
      selected = next.where((node) {
        return node is Element && (tag == '*' || node.localName == tag);
      }).toList();
    }
    for (final predicate in step.predicates) {
      selected = _applyPredicate(selected, predicate);
    }
    current = selected;
    if (current.isEmpty) break;
  }
  return <XPathValue>[
    for (final node in current)
      if (node is Element || node is Text) node,
  ];
}

class _Step {
  _Step(this.descendant, this.nodeTest, this.predicates, this.isLast);

  final bool descendant;
  final String nodeTest;
  final List<String> predicates;
  final bool isLast;
}

List<_Step> _parseSteps(String path) {
  final raw = <(bool, String)>[];
  var index = 0;
  var descendant = false;
  if (path.startsWith('//')) {
    descendant = true;
    index = 2;
  } else if (path.startsWith('/')) {
    index = 1;
  }
  final buffer = StringBuffer();
  String? quote;
  var bracket = 0;
  while (index < path.length) {
    final char = path[index];
    if (quote != null) {
      buffer.write(char);
      if (char == r'\' && index + 1 < path.length) {
        buffer.write(path[++index]);
      } else if (char == quote) {
        quote = null;
      }
      index++;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      index++;
      continue;
    }
    if (char == '[') {
      bracket++;
      buffer.write(char);
      index++;
      continue;
    }
    if (char == ']') {
      bracket--;
      buffer.write(char);
      index++;
      continue;
    }
    if (char == '/' && bracket == 0) {
      raw.add((descendant, buffer.toString()));
      buffer.clear();
      descendant = index + 1 < path.length && path[index + 1] == '/';
      index += descendant ? 2 : 1;
      continue;
    }
    buffer.write(char);
    index++;
  }
  if (buffer.isNotEmpty) raw.add((descendant, buffer.toString()));
  if (raw.isEmpty) throw FormatException('empty step');
  return <_Step>[
    for (var i = 0; i < raw.length; i++)
      _parseStep(raw[i].$1, raw[i].$2, i == raw.length - 1),
  ];
}

_Step _parseStep(bool descendant, String text, bool isLast) {
  var index = 0;
  while (index < text.length && text[index] != '[') {
    index++;
  }
  final name = text.substring(0, index).trim();
  if (name.isEmpty) throw FormatException('empty node test');
  final predicates = <String>[];
  while (index < text.length) {
    if (text[index] != '[') {
      index++;
      continue;
    }
    final end = _matchingBracket(text, index);
    if (end < 0) throw FormatException('unbalanced predicate');
    predicates.add(text.substring(index + 1, end).trim());
    index = end + 1;
  }
  return _Step(descendant, name, predicates, isLast);
}

int _matchingBracket(String text, int open) {
  var depth = 0;
  String? quote;
  for (var index = open; index < text.length; index++) {
    final char = text[index];
    if (quote != null) {
      if (char == r'') {
        index++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '[') depth++;
    if (char == ']') {
      depth--;
      if (depth == 0) return index;
    }
  }
  return -1;
}

List<Node> _descendantsOrSelf(Node node) {
  final result = <Node>[node];
  void walk(Node current) {
    for (final child in current.nodes) {
      result.add(child);
      walk(child);
    }
  }

  walk(node);
  return result;
}

Iterable<Node> _children(Node node) => node.nodes;

List<Node> _applyPredicate(List<Node> nodes, String predicate) {
  final trimmed = predicate.trim();
  if (trimmed.isEmpty) return nodes;
  final orParts = _splitTopLevelText(trimmed, ' or ');
  if (orParts.length > 1) {
    final sets = <Node>[];
    for (final part in orParts) {
      sets.addAll(_applyPredicate(nodes, part));
    }
    return _dedupe(sets);
  }
  final andParts = _splitTopLevelText(trimmed, ' and ');
  if (andParts.length > 1) {
    var current = nodes;
    for (final part in andParts) {
      current = _applyPredicate(current, part);
    }
    return current;
  }
  if (trimmed == 'last()') return nodes.isEmpty ? nodes : <Node>[nodes.last];
  final intValue = int.tryParse(trimmed);
  if (intValue != null) {
    final index = intValue - 1;
    return index >= 0 && index < nodes.length ? <Node>[nodes[index]] : <Node>[];
  }
  final position = RegExp(
    r'^position\(\)\s*([<>=!]+)\s*(\d+)$',
  ).firstMatch(trimmed);
  if (position != null) {
    final op = position.group(1)!;
    final value = int.parse(position.group(2)!);
    return <Node>[
      for (var i = 0; i < nodes.length; i++)
        if (_compareInt(i + 1, op, value)) nodes[i],
    ];
  }
  final notExpr = RegExp(r'^not\((.*)\)$', dotAll: true).firstMatch(trimmed);
  if (notExpr != null) {
    final excluded = _applyPredicate(nodes, notExpr.group(1)!).toSet();
    return <Node>[
      for (final node in nodes)
        if (!excluded.contains(node)) node,
    ];
  }
  // 子元素存在：`[span]`
  if (RegExp(r'^[\w*:-]+$').hasMatch(trimmed)) {
    return <Node>[
      for (final node in nodes)
        if (node is Element &&
            node.children.any(
              (child) =>
                  trimmed == '*' ||
                  child.localName == trimmed ||
                  child.localName == trimmed.split(':').last,
            ))
          node,
    ];
  }
  // 属性比较
  final attr = RegExp(
    r'''^@([\w:-]+)\s*(=|!=)\s*(['"])(.*)\3$''',
    dotAll: true,
  ).firstMatch(trimmed);
  if (attr != null) {
    final name = attr.group(1)!;
    final op = attr.group(2)!;
    final value = attr.group(4)!;
    return <Node>[
      for (final node in nodes)
        if (node is Element &&
            _stringCompare(node.attributes[name] ?? '', op, value))
          node,
    ];
  }
  final attrExists = RegExp(r'^@([\w:-]+)$').firstMatch(trimmed);
  if (attrExists != null) {
    final name = attrExists.group(1)!;
    return <Node>[
      for (final node in nodes)
        if (node is Element && node.attributes.containsKey(name)) node,
    ];
  }
  // text()/string() 比较
  final textCompare = RegExp(
    r'''^(text\(\)|string\(\)|\.)\s*(=|!=|contains|starts-with)\s*(['"])(.*)\3$''',
    dotAll: true,
  ).firstMatch(trimmed);
  if (textCompare != null) {
    final op = textCompare.group(2)!;
    final value = textCompare.group(4)!;
    return <Node>[
      for (final node in nodes)
        if (_textOf(node).trim() case final text
            when _stringCompare(text, op, value))
          node,
    ];
  }
  final containsAttr = RegExp(
    r'''^contains\(@([\w:-]+),\s*(['"])(.*)\2\)$''',
    dotAll: true,
  ).firstMatch(trimmed);
  if (containsAttr != null) {
    final name = containsAttr.group(1)!;
    final value = containsAttr.group(3)!;
    return <Node>[
      for (final node in nodes)
        if (node is Element && (node.attributes[name] ?? '').contains(value))
          node,
    ];
  }
  final startsAttr = RegExp(
    r'''^starts-with\(@([\w:-]+),\s*(['"])(.*)\2\)$''',
    dotAll: true,
  ).firstMatch(trimmed);
  if (startsAttr != null) {
    final name = startsAttr.group(1)!;
    final value = startsAttr.group(3)!;
    return <Node>[
      for (final node in nodes)
        if (node is Element && (node.attributes[name] ?? '').startsWith(value))
          node,
    ];
  }
  final containsText = RegExp(
    r'''^contains\((text\(\)|string\(\)|\.),\s*(['"])(.*)\2\)$''',
    dotAll: true,
  ).firstMatch(trimmed);
  if (containsText != null) {
    final value = containsText.group(3)!;
    return <Node>[
      for (final node in nodes)
        if (_textOf(node).contains(value)) node,
    ];
  }
  // `.//tag` / `./tag` 存在性
  final relative = RegExp(r'^(\.//|\./)([\w*:-]+)$').firstMatch(trimmed);
  if (relative != null) {
    final descendant = relative.group(1) == './/';
    final tag = relative.group(2)!;
    return <Node>[
      for (final node in nodes)
        if (node is Element && _hasTag(node, tag, descendant)) node,
    ];
  }
  throw FormatException('unsupported predicate: $trimmed');
}

bool _hasTag(Element node, String tag, bool descendant) {
  if (descendant) {
    return node.querySelectorAll(tag).isNotEmpty;
  }
  return node.children.any((child) => tag == '*' || child.localName == tag);
}

bool _compareInt(int left, String op, int right) {
  switch (op) {
    case '<':
      return left < right;
    case '<=':
      return left <= right;
    case '>':
      return left > right;
    case '>=':
      return left >= right;
    case '=':
      return left == right;
    case '!=':
      return left != right;
    default:
      return false;
  }
}

bool _stringCompare(String left, String op, String right) {
  switch (op) {
    case '=':
      return left.trim() == right;
    case '!=':
      return left.trim() != right;
    case 'contains':
      return left.contains(right);
    case 'starts-with':
      return left.startsWith(right);
    default:
      return false;
  }
}

String _textOf(Node node) {
  if (node is Text) return node.text;
  if (node is Element) return node.text;
  return '';
}

List<String> _splitTopLevel(String text, String separator) {
  final result = <String>[];
  var start = 0;
  var bracket = 0;
  String? quote;
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (quote != null) {
      if (char == r'\') {
        index++;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '[' || char == '(') bracket++;
    if (char == ']' || char == ')') bracket--;
    if (bracket == 0 && text.startsWith(separator, index)) {
      result.add(text.substring(start, index));
      index += separator.length - 1;
      start = index + 1;
    }
  }
  result.add(text.substring(start));
  return result;
}

List<String> _splitTopLevelText(String text, String separator) {
  return _splitTopLevel(text, separator);
}

List<Node> _dedupe(List<Node> nodes) {
  final seen = Set<Node>.identity();
  return <Node>[
    for (final node in nodes)
      if (seen.add(node)) node,
  ];
}
