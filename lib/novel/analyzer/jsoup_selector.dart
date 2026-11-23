/// JSoup 选择器方言的 Dart 实现（书源规则里 `tag.div`、`class.x`、`!0`、
/// `:contains(...)`、`[href~=regex]` 这些不是标准 CSS）。
///
/// 只依赖 `package:html` 的 DOM；支持 legado 书源实际用到的语法：
/// - 组合符：后代（空格）、`>`、`+`、`~`；
/// - 简单选择器：标签、`*`、`.class`、`#id`、属性（`=` `!=` `^=` `$=` `*=` `~=` `|=`）；
/// - JSoup 伪类：`:contains` `:containsOwn` `:matches` `:not` `:has`
///   `:first` `:last` `:eq` `:lt` `:gt` `:first-child` `:last-child`
///   `:nth-child` `:only-child` `:empty` `:root`。
///
/// 解析失败返回 null，由调用方回落到 `html` 包的标准 CSS 选择器，避免一条
/// 罕见规则把整本书的目录打空。
library;

import 'package:html/dom.dart';

/// 在 [root] 的后代里按 JSoup 语义选择元素；语法不支持时返回 null。
List<Element>? jsoupSelect(Element root, String selector) {
  final groups = _parseSelector(selector);
  if (groups == null) return null;
  final result = <Element>[];
  final seen = Set<Element>.identity();
  for (final steps in groups) {
    for (final element in _selectSteps(root, steps)) {
      if (seen.add(element)) result.add(element);
    }
  }
  return result;
}

enum _Combinator { descendant, child, adjacent, sibling }

class _Step {
  _Step(this.combinator, this.compound);

  final _Combinator combinator;
  final _Compound compound;
}

class _Compound {
  final List<_Simple> simples = <_Simple>[];
}

sealed class _Simple {
  const _Simple();
}

class _Tag extends _Simple {
  const _Tag(this.name);
  final String name;
}

class _Class extends _Simple {
  const _Class(this.name);
  final String name;
}

class _Id extends _Simple {
  const _Id(this.name);
  final String name;
}

class _Attribute extends _Simple {
  const _Attribute(this.name, this.operator, this.value, this.regex);

  final String name;
  final String? operator;
  final String? value;
  final RegExp? regex;
}

class _Pseudo extends _Simple {
  const _Pseudo(this.name, [this.argument]);

  final String name;
  final String? argument;
}

class _Not extends _Simple {
  const _Not(this.groups);
  final List<List<_Step>> groups;
}

class _Has extends _Simple {
  const _Has(this.groups);
  final List<List<_Step>> groups;
}

List<Element> _selectSteps(Element root, List<_Step> steps) {
  if (steps.isEmpty) return const <Element>[];
  var current = <Element>[root];
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final next = <Element>[];
    final seen = Set<Element>.identity();
    for (final node in current) {
      final pool = i == 0
          ? _descendants(node)
          : switch (step.combinator) {
              _Combinator.descendant => _descendants(node),
              _Combinator.child => node.children,
              _Combinator.adjacent => <Element>[
                if (node.nextElementSibling != null) node.nextElementSibling!,
              ],
              _Combinator.sibling => _followingSiblings(node),
            };
      for (final candidate in pool) {
        if (_matches(candidate, step.compound) && seen.add(candidate)) {
          next.add(candidate);
        }
      }
    }
    current = next;
    if (current.isEmpty) return current;
  }
  return current;
}

/// 从元素反向匹配整条选择器链（`:not` / `:has` 用）。
bool _matchesChain(Element element, List<_Step> steps, int index) {
  if (!_matches(element, steps[index].compound)) return false;
  if (index == 0) return true;
  switch (steps[index].combinator) {
    case _Combinator.child:
      final parent = element.parent;
      return parent is Element && _matchesChain(parent, steps, index - 1);
    case _Combinator.adjacent:
      final previous = element.previousElementSibling;
      return previous != null && _matchesChain(previous, steps, index - 1);
    case _Combinator.sibling:
      final siblings = element.parentNode?.children ?? const <Element>[];
      final position = siblings.indexOf(element);
      for (var i = position - 1; i >= 0; i--) {
        if (_matchesChain(siblings[i], steps, index - 1)) return true;
      }
      return false;
    case _Combinator.descendant:
      var parent = element.parent;
      while (parent is Element) {
        if (_matchesChain(parent, steps, index - 1)) return true;
        parent = parent.parent;
      }
      return false;
  }
}

Iterable<Element> _descendants(Element root) {
  final list = <Element>[];
  void walk(Element element) {
    for (final child in element.children) {
      list.add(child);
      walk(child);
    }
  }

  walk(root);
  return list;
}

Iterable<Element> _followingSiblings(Element element) {
  final siblings = element.parentNode?.children ?? const <Element>[];
  final index = siblings.indexOf(element);
  if (index < 0) return const <Element>[];
  return siblings.skip(index + 1);
}

bool _matches(Element element, _Compound compound) {
  for (final simple in compound.simples) {
    if (!_matchesSimple(element, simple)) return false;
  }
  return true;
}

bool _matchesSimple(Element element, _Simple simple) {
  switch (simple) {
    case _Tag(:final name):
      return name == '*' || element.localName == name;
    case _Class(:final name):
      return element.classes.contains(name);
    case _Id(:final name):
      return element.id == name;
    case _Attribute():
      return _matchesAttribute(element, simple);
    case _Pseudo(:final name, :final argument):
      return _matchesPseudo(element, name, argument);
    case _Not(:final groups):
      return !groups.any(
        (steps) => _matchesChain(element, steps, steps.length - 1),
      );
    case _Has(:final groups):
      return groups.any((steps) => _selectSteps(element, steps).isNotEmpty);
  }
}

bool _matchesAttribute(Element element, _Attribute attr) {
  final actual = element.attributes[attr.name];
  if (actual == null) return false;
  final expected = attr.value;
  switch (attr.operator) {
    case null:
      return true;
    case '=':
      return actual == expected;
    case '!=':
      return actual != expected;
    case '^=':
      return expected != null && actual.startsWith(expected);
    case r'$=':
      return expected != null && actual.endsWith(expected);
    case '*=':
      return expected != null && actual.contains(expected);
    case '~=':
      return attr.regex?.hasMatch(actual) ?? false;
    case '|=':
      return expected != null &&
          (actual == expected || actual.startsWith('$expected-'));
    default:
      return false;
  }
}

bool _matchesPseudo(Element element, String name, String? argument) {
  switch (name) {
    case 'root':
      return element.parentNode == null;
    case 'empty':
      return element.nodes.isEmpty;
    case 'first-child':
      return _siblingIndex(element) == 0;
    case 'last-child':
      final siblings = element.parentNode?.children ?? const <Element>[];
      return siblings.isNotEmpty && siblings.last == element;
    case 'only-child':
      final siblings = element.parentNode?.children ?? const <Element>[];
      return siblings.length == 1;
    case 'first':
      return _siblingIndex(element) == 0;
    case 'last':
      final siblings = element.parentNode?.children ?? const <Element>[];
      return siblings.isNotEmpty && siblings.last == element;
    case 'eq':
      return _siblingIndex(element) == int.tryParse(argument ?? '');
    case 'lt':
      return _siblingIndex(element) < (int.tryParse(argument ?? '') ?? 0);
    case 'gt':
      return _siblingIndex(element) > (int.tryParse(argument ?? '') ?? 0);
    case 'nth-child':
      final index = _siblingIndex(element) + 1;
      return _matchesNth(index, argument ?? '');
    case 'contains':
      final needle = (argument ?? '').toLowerCase();
      return needle.isEmpty ||
          jsoupText(element).toLowerCase().contains(needle);
    case 'containsOwn':
      final needle = (argument ?? '').toLowerCase();
      return needle.isEmpty ||
          jsoupOwnText(element).toLowerCase().contains(needle);
    case 'matches':
      try {
        return RegExp(argument ?? '').hasMatch(jsoupText(element));
      } on Object {
        return false;
      }
    default:
      return false;
  }
}

int _siblingIndex(Element element) {
  final siblings = element.parentNode?.children ?? const <Element>[];
  final index = siblings.indexOf(element);
  return index < 0 ? 0 : index;
}

bool _matchesNth(int index, String expression) {
  final value = expression.trim().toLowerCase().replaceAll(' ', '');
  if (value == 'odd') return index.isOdd;
  if (value == 'even') return index.isEven;
  if (!value.contains('n')) {
    return index == int.tryParse(value);
  }
  final parts = value.split('n');
  final multiplier = parts[0].isEmpty
      ? 1
      : parts[0] == '-'
      ? -1
      : int.tryParse(parts[0]) ?? 1;
  final offset = parts.length > 1 && parts[1].isNotEmpty
      ? int.tryParse(parts[1]) ?? 0
      : 0;
  if (multiplier == 0) return index == offset;
  final delta = index - offset;
  return delta % multiplier == 0 && delta ~/ multiplier >= 0;
}

/// Jsoup `Element.text()`：收集后代文本并规范化空白。
String jsoupText(Element element) {
  final buffer = StringBuffer();
  void walk(Node node) {
    if (node is Text) {
      buffer.write(node.data);
      return;
    }
    if (node is Element) {
      for (final child in node.nodes) {
        walk(child);
      }
    }
  }

  walk(element);
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Jsoup `ownText()`：只收集直接文本子节点并规范化空白。
String jsoupOwnText(Element element) {
  final parts = <String>[];
  for (final node in element.nodes) {
    if (node is Text) {
      final text = node.data.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) parts.add(text);
    }
  }
  return parts.join(' ');
}

/// `textNodes()`：直接文本子节点，各自 trim 后非空的列表。
List<String> jsoupTextNodes(Element element) {
  final result = <String>[];
  for (final node in element.nodes) {
    if (node is Text) {
      final text = node.data.trim();
      if (text.isNotEmpty) result.add(text);
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// 解析

List<List<_Step>>? _parseSelector(String selector) {
  final groups = <List<_Step>>[];
  var index = 0;
  while (index < selector.length) {
    final parsed = _parseGroup(selector, index);
    if (parsed == null) return null;
    groups.add(parsed.steps);
    index = parsed.next;
    while (index < selector.length &&
        (selector[index] == ',' || _isSpace(selector[index]))) {
      if (selector[index] == ',') {
        index++;
        break;
      }
      index++;
    }
  }
  return groups.isEmpty ? null : groups;
}

class _Group {
  _Group(this.steps, this.next);
  final List<_Step> steps;
  final int next;
}

_Group? _parseGroup(String text, int start) {
  final steps = <_Step>[];
  var index = start;
  var combinator = _Combinator.descendant;
  var first = true;
  while (index < text.length) {
    while (index < text.length && _isSpace(text[index])) {
      index++;
    }
    if (index >= text.length || text[index] == ',') break;
    if (text[index] == '>' || text[index] == '+' || text[index] == '~') {
      combinator = switch (text[index]) {
        '>' => _Combinator.child,
        '+' => _Combinator.adjacent,
        _ => _Combinator.sibling,
      };
      index++;
      while (index < text.length && _isSpace(text[index])) {
        index++;
      }
      continue;
    }
    final compound = _Compound();
    final parsed = _parseCompound(text, index, compound);
    if (parsed == null) return null;
    index = parsed;
    if (compound.simples.isEmpty) return null;
    steps.add(_Step(first ? _Combinator.descendant : combinator, compound));
    first = false;
    combinator = _Combinator.descendant;
    var sawSpace = false;
    while (index < text.length && _isSpace(text[index])) {
      index++;
      sawSpace = true;
    }
    if (sawSpace) combinator = _Combinator.descendant;
  }
  return _Group(steps, index);
}

int? _parseCompound(String text, int start, _Compound compound) {
  var index = start;
  if (index < text.length && text[index] == '*') {
    compound.simples.add(const _Tag('*'));
    index++;
  } else if (index < text.length && _isNameStart(text[index])) {
    final name = _readName(text, index);
    compound.simples.add(_Tag(name.text.toLowerCase()));
    index = name.next;
  }
  while (index < text.length) {
    final char = text[index];
    if (char == '.') {
      final name = _readName(text, index + 1);
      if (name.text.isEmpty) return null;
      compound.simples.add(_Class(name.text));
      index = name.next;
    } else if (char == '#') {
      final name = _readName(text, index + 1);
      if (name.text.isEmpty) return null;
      compound.simples.add(_Id(name.text));
      index = name.next;
    } else if (char == '[') {
      final end = _findAttributeEnd(text, index + 1);
      if (end == null) return null;
      final attr = _parseAttribute(text.substring(index + 1, end));
      if (attr == null) return null;
      compound.simples.add(attr);
      index = end + 1;
    } else if (char == ':') {
      final name = _readName(text, index + 1);
      if (name.text.isEmpty) return null;
      var next = name.next;
      String? argument;
      if (next < text.length && text[next] == '(') {
        final end = _findBalancedParen(text, next + 1);
        if (end == null) return null;
        argument = text.substring(next + 1, end);
        next = end + 1;
      }
      final lower = name.text.toLowerCase();
      if (lower == 'not') {
        final groups = _parseSelector(argument ?? '');
        if (groups == null) return null;
        compound.simples.add(_Not(groups));
      } else if (lower == 'has') {
        final groups = _parseSelector(argument ?? '');
        if (groups == null) return null;
        compound.simples.add(_Has(groups));
      } else {
        compound.simples.add(_Pseudo(lower, argument));
      }
      index = next;
    } else {
      break;
    }
  }
  return index;
}

class _Name {
  _Name(this.text, this.next);
  final String text;
  final int next;
}

_Name _readName(String text, int start) {
  final buffer = StringBuffer();
  var index = start;
  while (index < text.length) {
    final char = text[index];
    if (char == r'\' && index + 1 < text.length) {
      buffer.write(text[index + 1]);
      index += 2;
      continue;
    }
    if (_isNameChar(char)) {
      buffer.write(char);
      index++;
      continue;
    }
    break;
  }
  return _Name(buffer.toString(), index);
}

_Attribute? _parseAttribute(String body) {
  var index = 0;
  while (index < body.length && _isSpace(body[index])) {
    index++;
  }
  final name = _readName(body, index);
  if (name.text.isEmpty) return null;
  index = name.next;
  while (index < body.length && _isSpace(body[index])) {
    index++;
  }
  if (index >= body.length) return _Attribute(name.text, null, null, null);
  final operators = <String>['~=', '^=', r'$=', '*=', '|=', '!=', '='];
  String? op;
  for (final candidate in operators) {
    if (body.startsWith(candidate, index)) {
      op = candidate;
      index += candidate.length;
      break;
    }
  }
  if (op == null) return null;
  while (index < body.length && _isSpace(body[index])) {
    index++;
  }
  String value;
  if (index < body.length && (body[index] == '"' || body[index] == "'")) {
    final quote = body[index];
    final end = body.indexOf(quote, index + 1);
    if (end < 0) return null;
    value = body.substring(index + 1, end);
    index = end + 1;
  } else {
    value = body.substring(index).trim();
  }
  RegExp? regex;
  if (op == '~=') {
    try {
      regex = RegExp(value);
    } on Object {
      return null;
    }
  }
  return _Attribute(name.text, op, value, regex);
}

int? _findAttributeEnd(String text, int start) {
  var index = start;
  String? quote;
  while (index < text.length) {
    final char = text[index];
    if (quote != null) {
      if (char == r'\') {
        index += 2;
        continue;
      }
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == ']') {
      return index;
    }
    index++;
  }
  return null;
}

int? _findBalancedParen(String text, int start) {
  var depth = 1;
  var index = start;
  String? quote;
  while (index < text.length) {
    final char = text[index];
    if (quote != null) {
      if (char == r'\') {
        index += 2;
        continue;
      }
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return index;
    }
    index++;
  }
  return null;
}

bool _isSpace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r' || char == '\f';

bool _isNameStart(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F ||
      code > 0x7F;
}

bool _isNameChar(String char) {
  final code = char.codeUnitAt(0);
  return _isNameStart(char) ||
      (code >= 0x30 && code <= 0x39) ||
      char == '-' ||
      char == '*';
}
