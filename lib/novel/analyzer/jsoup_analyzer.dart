/// legado `AnalyzeByJSoup` 的 Dart 重译：在 `package:html` DOM 上执行
/// JSoup 方言规则，并把结果收敛成字符串列表 / Element 列表。
///
/// 规则语法（书源实际使用）：
/// - 选择器链：`li > a@href`、`class.info@p.1@text`、`text.下一章@href`；
/// - legado 索引：`tag.li.1`、`tag.li!0`、`tag.li.0:-1`、`tag.li[-1,3:-2:-10,2]`；
/// - 取文本：`@text` `@textNodes` `@ownText` `@html` `@all` `@任意属性`；
/// - 组合：`&&`（拼接）、`||`（首个非空）、`%%`（交错合并）。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'jsoup_selector.dart';
import 'rule_splitter.dart';

/// JSoup 规则解析器。一个实例对应一段内容（可复用 select）。
class JsoupAnalyzer {
  JsoupAnalyzer(Object doc) : element = _parse(doc);

  final Element element;

  static Element _parse(Object doc) {
    if (doc is Element) return doc;
    if (doc is Document) {
      final root = doc.documentElement;
      if (root != null) return root;
    }
    final parsed = html_parser.parse(doc.toString());
    final root = parsed.documentElement;
    if (root != null) return root;
    final fragment = html_parser.parseFragment(doc.toString());
    return fragment.nodes.whereType<Element>().firstOrNull ??
        html_parser.parse('<div></div>').documentElement!;
  }

  /// 取文本列表（`@` 链最后一项是取法）。
  List<String> getStringList(String ruleStr) {
    if (ruleStr.isEmpty) return const <String>[];
    final sourceRule = _SourceRule(ruleStr);
    if (sourceRule.elementsRule.isEmpty) {
      return <String>[element.outerHtml];
    }
    final splitter = RuleSplitter(sourceRule.elementsRule);
    final rules = splitter.splitRule(const <String>['&&', '||', '%%']);
    final results = <List<String>>[];
    for (final part in rules) {
      final temp = sourceRule.isCss ? _cssPart(part) : _getResultList(part);
      if (temp != null && temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return _combine(results, splitter.elementsType);
  }

  /// 取合并文本；单个结果原样，多个用换行连接。
  String? getString(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    final list = getStringList(ruleStr);
    if (list.isEmpty) return null;
    return list.join('\n');
  }

  /// 取第一个结果（空则空串）。
  String getString0(String ruleStr) {
    final list = getStringList(ruleStr);
    return list.isEmpty ? '' : list.first;
  }

  /// 取 Element 列表（供 `bookList` / `chapterList` 使用）。
  List<Element> getElements(String ruleStr) {
    if (ruleStr.isEmpty) return const <Element>[];
    final sourceRule = _SourceRule(ruleStr);
    final splitter = RuleSplitter(sourceRule.elementsRule);
    final rules = splitter.splitRule(const <String>['&&', '||', '%%']);
    final results = <List<Element>>[];
    if (sourceRule.isCss) {
      for (final part in rules) {
        final selected = _select(element, part);
        results.add(selected);
        if (selected.isNotEmpty && splitter.elementsType == '||') break;
      }
    } else {
      for (final part in rules) {
        final trimmed = _trimRule(part);
        final chain = RuleSplitter(trimmed).splitRule(const <String>['@']);
        final List<Element> found;
        if (chain.length > 1) {
          var current = <Element>[element];
          for (final step in chain) {
            final next = <Element>[];
            for (final node in current) {
              next.addAll(_ElementsSingle().apply(node, step));
            }
            current = next;
          }
          found = current;
        } else {
          found = _ElementsSingle().apply(element, trimmed);
        }
        results.add(found);
        if (found.isNotEmpty && splitter.elementsType == '||') break;
      }
    }
    return _combine(results, splitter.elementsType);
  }

  List<String> _cssPart(String part) {
    final at = part.lastIndexOf('@');
    if (at < 0) return const <String>[];
    final selector = part.substring(0, at);
    final attr = part.substring(at + 1);
    return _resultLast(_select(element, selector), attr);
  }

  List<String>? _getResultList(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    var elements = <Element>[element];
    final trimmed = _trimRule(ruleStr);
    final rules = RuleSplitter(trimmed).splitRule(const <String>['@']);
    if (rules.isEmpty) return null;
    for (var i = 0; i < rules.length - 1; i++) {
      final next = <Element>[];
      for (final node in elements) {
        next.addAll(_ElementsSingle().apply(node, rules[i]));
      }
      elements = next;
      if (elements.isEmpty) return null;
    }
    return _resultLast(elements, rules.last);
  }

  List<String> _resultLast(List<Element> elements, String lastRule) {
    final result = <String>[];
    switch (lastRule) {
      case 'text':
        for (final element in elements) {
          final text = jsoupText(element);
          if (text.isNotEmpty) result.add(text);
        }
        return result;
      case 'textNodes':
        for (final element in elements) {
          final nodes = jsoupTextNodes(element);
          if (nodes.isNotEmpty) result.add(nodes.join('\n'));
        }
        return result;
      case 'ownText':
        for (final element in elements) {
          final text = jsoupOwnText(element);
          if (text.isNotEmpty) result.add(text);
        }
        return result;
      case 'html':
        for (final element in elements) {
          final html = _outerHtmlWithoutScripts(element);
          if (html.isNotEmpty) result.add(html);
        }
        return result;
      case 'all':
        return <String>[for (final element in elements) element.outerHtml];
      default:
        for (final element in elements) {
          final value = element.attributes[lastRule] ?? '';
          if (value.trim().isEmpty || result.contains(value)) continue;
          result.add(value);
        }
        return result;
    }
  }

  static String _outerHtmlWithoutScripts(Element element) {
    final document = html_parser.parse(element.outerHtml);
    final root = document.documentElement;
    if (root == null) return '';
    final clone = root.querySelectorAll('body').firstOrNull;
    final target = clone ?? root;
    for (final tag in const <String>['script', 'style']) {
      target.querySelectorAll(tag).forEach((node) => node.remove());
    }
    return clone == null
        ? target.outerHtml
        : target.nodes
              .map((node) => node is Element ? node.outerHtml : node.text ?? '')
              .join();
  }

  static String _trimRule(String rule) {
    var index = 0;
    while (index < rule.length) {
      final char = rule.codeUnitAt(index);
      if (char == 0x40 /* @ */ || char <= 0x20) {
        index++;
        continue;
      }
      break;
    }
    return rule.substring(index);
  }

  static List<Element> _select(Element root, String selector) {
    final trimmed = selector.trim();
    if (trimmed.isEmpty) return const <Element>[];
    final jsoup = jsoupSelect(root, trimmed);
    if (jsoup != null) return jsoup;
    try {
      return root.querySelectorAll(trimmed);
    } on Object {
      return const <Element>[];
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

  static Iterable<Element> _descendants(Element root) {
    final out = <Element>[];
    void walk(Element element) {
      for (final child in element.children) {
        out.add(child);
        walk(child);
      }
    }

    walk(root);
    return out;
  }
}

class _SourceRule {
  _SourceRule(String ruleStr) {
    var text = ruleStr;
    final lower = ruleStr.toLowerCase();
    if (lower.startsWith('@css:')) {
      isCss = true;
      text = ruleStr.substring(5).trim();
    } else if (text.startsWith('@@')) {
      text = text.substring(2);
    }
    elementsRule = text;
  }

  var isCss = false;
  var elementsRule = '';
}

/// legado `ElementsSingle`：对当前元素执行一段「选择器 + 索引」规则。
class _ElementsSingle {
  String _split = ' ';
  String _beforeRule = '';
  final List<int> _indexDefault = <int>[];
  final List<Object> _indexes = <Object>[];

  List<Element> apply(Element temp, String rule) {
    _findIndexSet(rule);
    var elements = _beforeRule.isEmpty
        ? temp.children
        : switch (_beforeRule.split('.').first) {
            'children' => temp.children,
            'class' => JsoupAnalyzer._descendants(
              temp,
            ).where((e) => e.classes.contains(_afterDot(_beforeRule))).toList(),
            'tag' => JsoupAnalyzer._descendants(
              temp,
            ).where((e) => e.localName == _afterDot(_beforeRule)).toList(),
            'id' => JsoupAnalyzer._descendants(
              temp,
            ).where((e) => e.id == _afterDot(_beforeRule)).toList(),
            'text' =>
              JsoupAnalyzer._descendants(temp)
                  .where(
                    (e) => jsoupOwnText(e).toLowerCase().contains(
                      _afterDot(_beforeRule).toLowerCase(),
                    ),
                  )
                  .toList(),
            _ => JsoupAnalyzer._select(temp, _beforeRule),
          };
    final length = elements.length;
    final last = _indexDefault.isNotEmpty
        ? _indexDefault.length - 1
        : _indexes.length - 1;
    final selected = <int>{};
    if (_indexes.isEmpty) {
      for (var i = last; i >= 0; i--) {
        final int index = _indexDefault[i];
        if (index >= 0 && index < length) selected.add(index);
        if (index < 0 && length >= -index) selected.add(index + length);
      }
    } else {
      for (var i = last; i >= 0; i--) {
        final item = _indexes[i];
        if (item is _Range) {
          _addRange(selected, item, length);
        } else if (item is int) {
          if (item >= 0 && item < length) selected.add(item);
          if (item < 0 && length >= -item) selected.add(item + length);
        }
      }
    }
    if (_split == '!') {
      elements = <Element>[
        for (var i = 0; i < elements.length; i++)
          if (!selected.contains(i)) elements[i],
      ];
    } else if (_split == '.') {
      elements = <Element>[
        for (final index in selected)
          if (index >= 0 && index < elements.length) elements[index],
      ];
    }
    return elements;
  }

  static void _addRange(Set<int> selected, _Range range, int length) {
    var start = range.start ?? 0;
    if (start < 0) start += length;
    var end = range.end ?? (length - 1);
    if (end < 0) end += length;
    if ((start < 0 && end < 0) || (start >= length && end >= length)) return;
    if (start >= length) {
      start = length - 1;
    } else if (start < 0) {
      start = 0;
    }
    if (end >= length) {
      end = length - 1;
    } else if (end < 0) {
      end = 0;
    }
    if (start == end || (range.step >= length && range.step > 0)) {
      selected.add(start);
      return;
    }
    var step = range.step;
    if (step < 0 && -step >= length) step = 1;
    if (step == 0) step = 1;
    if (end > start) {
      for (var i = start; i <= end; i += step) {
        selected.add(i);
      }
    } else {
      for (var i = start; i >= end; i += step) {
        selected.add(i);
      }
    }
  }

  static String _afterDot(String beforeRule) {
    final parts = beforeRule.split('.');
    return parts.length > 1 ? parts[1] : '';
  }

  void _findIndexSet(String rule) {
    final text = rule.trim();
    var length = text.length;
    int? current;
    var negative = false;
    final rangeParts = <int?>[];
    var digits = '';
    final head = text.isNotEmpty && text.endsWith(']');
    if (head) {
      length--;
      var index = length - 1;
      while (index >= 0) {
        final char = text[index];
        if (char == ' ') {
          index--;
          continue;
        }
        if (_isDigit(char)) {
          digits = char + digits;
        } else if (char == '-') {
          negative = true;
        } else {
          current = digits.isEmpty
              ? null
              : negative
              ? -int.parse(digits)
              : int.parse(digits);
          if (char == ':') {
            rangeParts.add(current);
          } else {
            if (rangeParts.isEmpty) {
              if (current == null) break;
              _indexes.add(current);
            } else {
              _indexes.add(
                _Range(
                  current,
                  rangeParts.last,
                  rangeParts.length == 2 ? rangeParts.first : null,
                ),
              );
              rangeParts.clear();
            }
            if (char == '!') {
              _split = '!';
              do {
                index--;
              } while (index > 0 && text[index] == ' ');
              if (index >= 0 && text[index] == '[') {
                _beforeRule = text.substring(0, index);
                return;
              }
            }
            if (char == '[') {
              _beforeRule = text.substring(0, index);
              return;
            }
            if (char != ',') break;
          }
          digits = '';
          negative = false;
        }
        index--;
      }
      _split = ' ';
      _beforeRule = text;
      return;
    }

    var index = length - 1;
    while (index >= 0) {
      final char = text[index];
      if (char == ' ') {
        index--;
        continue;
      }
      if (_isDigit(char)) {
        digits = char + digits;
      } else if (char == '-') {
        negative = true;
      } else {
        if (char == '!' || char == '.' || char == ':') {
          if (digits.isEmpty && !negative) break;
          _indexDefault.add(negative ? -int.parse(digits) : int.parse(digits));
          if (char != ':') {
            _split = char;
            _beforeRule = text.substring(0, index);
            return;
          }
        } else {
          break;
        }
        digits = '';
        negative = false;
      }
      index--;
    }
    _split = ' ';
    _beforeRule = text;
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}

class _Range {
  const _Range(this.start, this.end, this._step);

  final int? start;
  final int? end;
  final int? _step;

  int get step => _step ?? 1;
}
