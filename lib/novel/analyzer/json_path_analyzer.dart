/// legado `AnalyzeByJSonPath` 的 Dart 重译，底层用 `package:json_path`
/// （RFC 9535）。书源里的 Jayway 写法（`[?(@.x == 'y')]`）先做一次语法归一，
/// 其余 `$.a.b[*].c`、`$..x`、切片都交给库。
library;

import 'dart:convert';

import 'package:json_path/json_path.dart';

import 'rule_splitter.dart';

class JsonPathAnalyzer {
  JsonPathAnalyzer(Object json) : _json = _normalize(json);

  final Object? _json;

  static Object? _normalize(Object json) {
    if (json is String) {
      try {
        return jsonDecode(json);
      } on Object {
        return json;
      }
    }
    return json;
  }

  /// 取合并文本：多个结果用换行连接。
  String getString(String rule) {
    if (rule.isEmpty) return '';
    final splitter = RuleSplitter(rule, code: true);
    final rules = splitter.splitRule(const <String>['&&', '||']);
    if (rules.length == 1) {
      final inner = splitter.innerRule('{', '}', (expr) {
        if (!expr.startsWith(r'$.') && !expr.startsWith(r'$[')) {
          return null;
        }
        final value = getString(expr);
        return value.isEmpty ? null : value;
      });
      if (inner != rule) return inner;
      final values = _values(rule);
      return values.map(_stringify).join('\n');
    }
    final collected = <String>[];
    for (final part in rules) {
      final temp = getString(part);
      if (temp.isNotEmpty) {
        collected.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return collected.join('\n');
  }

  /// 取字符串列表。
  List<String> getStringList(String rule) {
    if (rule.isEmpty) return const <String>[];
    final splitter = RuleSplitter(rule, code: true);
    final rules = splitter.splitRule(const <String>['&&', '||', '%%']);
    if (rules.length == 1) {
      final inner = splitter.innerRule('{', '}', (expr) {
        if (!expr.startsWith(r'$.') && !expr.startsWith(r'$[')) {
          return null;
        }
        final value = getString(expr);
        return value.isEmpty ? null : value;
      });
      if (inner != rule) return <String>[inner];
      return <String>[
        for (final value in _values(rule))
          if (value is List) ...value.map(_stringify) else _stringify(value),
      ];
    }
    final results = <List<String>>[];
    for (final part in rules) {
      final temp = getStringList(part);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    if (splitter.elementsType == '%%') {
      return <String>[
        for (var i = 0; i < (results.isEmpty ? 0 : results.first.length); i++)
          for (final list in results)
            if (i < list.length) list[i],
      ];
    }
    return <String>[for (final list in results) ...list];
  }

  /// 取任意对象列表（bookList 规则可能直接给 JSON 数组）。
  List<Object?> getList(String rule) {
    if (rule.isEmpty) return const <Object?>[];
    final splitter = RuleSplitter(rule, code: true);
    final rules = splitter.splitRule(const <String>['&&', '||', '%%']);
    if (rules.length == 1) {
      return _values(rule).expand<Object?>((value) {
        return value is List ? value : <Object?>[value];
      }).toList();
    }
    final results = <List<Object?>>[];
    for (final part in rules) {
      final temp = getList(part);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    if (splitter.elementsType == '%%') {
      return <Object?>[
        for (var i = 0; i < (results.isEmpty ? 0 : results.first.length); i++)
          for (final list in results)
            if (i < list.length) list[i],
      ];
    }
    return <Object?>[for (final list in results) ...list];
  }

  /// 取第一个对象（getElement 用）。
  Object? getObject(String rule) {
    final values = _values(rule);
    return values.isEmpty ? null : values.first;
  }

  Iterable<Object?> _values(String rule) {
    final path = _normalizeJayway(rule);
    try {
      return JsonPath(path).readValues(_json).toList();
    } on Object {
      return const <Object?>[];
    }
  }

  /// Jayway `[?(expr)]` → RFC 9535 `[?expr]`；括号只删一层、保留内部括号。
  static String _normalizeJayway(String rule) {
    if (!rule.contains('?(')) return rule;
    final out = StringBuffer();
    var index = 0;
    while (index < rule.length) {
      final start = rule.indexOf('?(', index);
      if (start < 0) {
        out.write(rule.substring(index));
        break;
      }
      out.write(rule.substring(index, start));
      var depth = 0;
      var cursor = start + 1;
      var end = -1;
      while (cursor < rule.length) {
        final char = rule[cursor];
        if (char == '(') depth++;
        if (char == ')') {
          depth--;
          if (depth == 0) {
            end = cursor;
            break;
          }
        }
        cursor++;
      }
      if (end < 0) {
        out.write(rule.substring(start));
        break;
      }
      out
        ..write('?')
        ..write(rule.substring(start + 2, end));
      index = end + 1;
    }
    return out.toString();
  }

  static String _stringify(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    try {
      return jsonEncode(value);
    } on Object {
      return value.toString();
    }
  }
}
