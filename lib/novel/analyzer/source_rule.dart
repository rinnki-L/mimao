/// legado `AnalyzeRule.SourceRule` 的 Dart 重译：一条规则的模式识别、`@put`
/// 提取、`@get` / `{{}}` 插值、`##match##replace` 正则替换。
///
/// 只保留与文本解析相关的语义；JS 由 [SourceRuleHost] 注入，规则层不直接
/// 依赖 QuickJS，便于纯 Dart 单测。
library;

import 'dart:convert';

/// 规则解析模式（对齐 Kotlin `AnalyzeRule.Mode`）。
enum RuleMode { defaultRule, xpath, json, js, regex, webJs }

/// 规则执行需要宿主提供的最小能力（由 `LegadoRuleAnalyzer` 实现）。
abstract interface class SourceRuleHost {
  /// 执行一段书源内嵌 JS，返回其值（Promise 已 await）。
  Future<Object?> evalJs(String snippet, {Object? result});

  /// 执行一条内嵌规则（`{{@.x}}` / `{{$.x}}` 这种），返回其值。
  Future<Object?> evalRule(String rule, {Object? result});

  /// 读取 `@put` 写入的变量（含书/源变量）。
  String getRuleVariable(String key);

  /// 写入变量。
  void putRuleVariable(String key, String value);
}

/// 一条切分后的规则。
class SourceRule {
  SourceRule(String ruleStr, [RuleMode mode = RuleMode.defaultRule])
    : _mode = mode {
    _parse(ruleStr);
  }

  RuleMode _mode;
  RuleMode get mode => _mode;

  /// 最终选择器 / 表达式（`##` 之前、插值后的文本）。
  String rule = '';

  /// `##match` 部分。
  String replaceRegex = '';

  /// `##match##replace` 部分。
  String replacement = '';

  /// 四段以上时只替换第一个匹配。
  bool replaceFirst = false;

  /// `@put:{...}` 里的键值。
  final Map<String, String> putMap = <String, String>{};

  final List<String> _params = <String>[];
  final List<int> _types = <int>[];

  static const int _getRuleType = -2;
  static const int _jsRuleType = -1;
  static const int _defaultRuleType = 0;

  static final RegExp _putPattern = RegExp(
    r'@put:(\{[^}]+?\})',
    caseSensitive: false,
  );
  static final RegExp _evalPattern = RegExp(
    r'@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}',
    caseSensitive: false,
  );
  static final RegExp _regexPattern = RegExp(r'\$\d{1,2}');

  void _parse(String ruleStr) {
    var text = ruleStr.trim();
    if (_mode == RuleMode.js || _mode == RuleMode.regex) {
      rule = text;
      return;
    }

    final lower = text.toLowerCase();
    if (lower.startsWith('@css:')) {
      _mode = RuleMode.defaultRule;
    } else if (text.startsWith('@@')) {
      _mode = RuleMode.defaultRule;
      text = text.substring(2);
    } else if (lower.startsWith('@xpath:')) {
      _mode = RuleMode.xpath;
      text = text.substring(7);
    } else if (lower.startsWith('@json:')) {
      _mode = RuleMode.json;
      text = text.substring(6);
    } else if (text.startsWith(r'$.') || text.startsWith(r'$[')) {
      _mode = RuleMode.json;
    } else if (text.startsWith('/')) {
      _mode = RuleMode.xpath;
    }

    text = _splitPutRule(text);

    final firstMatch = _evalPattern.firstMatch(text);
    if (firstMatch != null) {
      final before = text.substring(0, firstMatch.start);
      if (_mode != RuleMode.js &&
          _mode != RuleMode.regex &&
          (firstMatch.start == 0 || !before.contains('##'))) {
        _mode = RuleMode.regex;
      }
    }

    var index = 0;
    for (final match in _evalPattern.allMatches(text)) {
      if (match.start > index) {
        _splitRegex(text.substring(index, match.start));
      }
      final token = match.group(0)!;
      final lowerToken = token.toLowerCase();
      if (lowerToken.startsWith('@get:')) {
        _types.add(_getRuleType);
        _params.add(token.substring(6, token.length - 1));
      } else {
        _types.add(_jsRuleType);
        _params.add(token.substring(2, token.length - 2));
      }
      index = match.end;
    }
    if (text.length > index) {
      _splitRegex(text.substring(index));
    }
    // 没有参数时也要把整段当作 rule，供后续 ## 拆分。
    if (_params.isEmpty && _types.isEmpty && text.isNotEmpty) {
      _types.add(_defaultRuleType);
      _params.add(text);
    }
  }

  String _splitPutRule(String text) {
    var result = text;
    for (final match in _putPattern.allMatches(text).toList()) {
      result = result.replaceAll(match.group(0)!, '');
      final json = _lenientStringMap(match.group(1)!);
      if (json != null) putMap.addAll(json);
    }
    return result;
  }

  void _splitRegex(String segment) {
    final parts = segment.split('##');
    final head = parts.first;
    if (_regexPattern.hasMatch(head) &&
        _mode != RuleMode.js &&
        _mode != RuleMode.regex) {
      _mode = RuleMode.regex;
    }
    var start = 0;
    for (final match in _regexPattern.allMatches(segment)) {
      if (match.start > start) {
        _types.add(_defaultRuleType);
        _params.add(segment.substring(start, match.start));
      }
      _types.add(int.parse(match.group(0)!.substring(1)));
      _params.add(match.group(0)!);
      start = match.end;
    }
    if (segment.length > start) {
      _types.add(_defaultRuleType);
      _params.add(segment.substring(start));
    }
  }

  /// 用当前结果替换 `$n` / `@get` / `{{js}}`，并拆出 `##` 正则段。
  Future<void> makeUpRule(SourceRuleHost host, Object? result) async {
    if (_params.isNotEmpty) {
      final socket = StringBuffer();
      for (var i = 0; i < _params.length; i++) {
        final type = _types[i];
        final param = _params[i];
        if (type > _defaultRuleType) {
          final list = result is List ? result : null;
          if (list != null && list.length > type) {
            socket.write(list[type] ?? '');
          } else {
            socket.write(param);
          }
        } else if (type == _jsRuleType) {
          if (_looksLikeRule(param)) {
            final nested = SourceRule(param);
            final value = await host.evalRule(nested.rule, result: result);
            if (value != null) socket.write(value.toString());
          } else {
            final value = await host.evalJs(param, result: result);
            if (value != null) socket.write(_jsValueToString(value));
          }
        } else if (type == _getRuleType) {
          socket.write(host.getRuleVariable(param.trim()));
        } else {
          socket.write(param);
        }
      }
      rule = socket.toString();
    }

    if (_mode == RuleMode.js) return;

    final parts = rule.split('##');
    rule = parts.first.trim();
    if (parts.length > 1) replaceRegex = parts[1];
    if (parts.length > 2) replacement = parts[2];
    if (parts.length > 3) replaceFirst = true;
  }

  /// `{{@.x}}` / `{{$.x}}` 这类是内嵌规则，交给规则层而不是 JS。
  static bool _looksLikeRule(String text) =>
      text.startsWith('@') ||
      text.startsWith(r'$.') ||
      text.startsWith(r'$[') ||
      text.startsWith('//');

  /// 把内嵌规则包装成一句 JS：`java.getString(<rule JSON>)`，由 JS 宿主
  /// 同步调用规则层解析当前 result。避免在 Dart 里递归构造两条执行路径。
  /// （保留说明；当前实现直接走 [SourceRuleHost.evalRule]。）

  /// 对结果应用 `##` 正则替换（legado `replaceRegex` 语义）。
  String applyRegex(String input) {
    if (replaceRegex.isEmpty) return input;
    final regex = _compile(replaceRegex);
    if (replaceFirst) {
      if (regex == null) return replacement;
      final match = regex.firstMatch(input);
      if (match == null) return '';
      return match.group(0)!.replaceFirst(regex, _expand(replacement, match));
    }
    if (regex == null) return input.replaceAll(replaceRegex, replacement);
    return input.replaceAllMapped(
      regex,
      (match) => _expand(replacement, match),
    );
  }

  static RegExp? _compile(String pattern) {
    try {
      return RegExp(pattern, multiLine: true);
    } on Object {
      return null;
    }
  }

  /// Java `Pattern.replace` 风格的 `$1` / `$0` / `${name}` 展开。
  static String _expand(String replacement, Match match) {
    final out = StringBuffer();
    for (var i = 0; i < replacement.length; i++) {
      final char = replacement[i];
      if (char == r'\' && i + 1 < replacement.length) {
        out.write(replacement[++i]);
        continue;
      }
      if (char != r'$') {
        out.write(char);
        continue;
      }
      if (i + 1 < replacement.length && replacement[i + 1] == '{') {
        final end = replacement.indexOf('}', i + 2);
        if (end > 0) {
          final name = replacement.substring(i + 2, end);
          out.write(_group(match, name));
          i = end;
          continue;
        }
      }
      var cursor = i + 1;
      while (cursor < replacement.length &&
          cursor < i + 3 &&
          _isDigit(replacement.codeUnitAt(cursor))) {
        cursor++;
      }
      if (cursor > i + 1) {
        final index = int.parse(replacement.substring(i + 1, cursor));
        out.write(
          index < match.groupCount + 1 ? (match.group(index) ?? '') : '',
        );
        i = cursor - 1;
        continue;
      }
      out.write(char);
    }
    return out.toString();
  }

  static String _group(Match match, String name) {
    // Dart 不支持命名组回读；只有数字名可用。
    final index = int.tryParse(name);
    if (index == null || index > match.groupCount) return '';
    return match.group(index) ?? '';
  }

  static bool _isDigit(int char) => char >= 0x30 && char <= 0x39;

  /// JS 值转文本：整数值的 double 按整数输出（对齐 Kotlin `%.0f`）。
  static String _jsValueToString(Object value) {
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    if (value is bool) return value ? 'true' : 'false';
    return value.toString();
  }

  /// 宽松 JSON：书源里的 `@put` 偶尔写成单引号/无引号键。
  static Map<String, String>? _lenientStringMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return <String, String>{
          for (final entry in decoded.entries)
            '${entry.key}': '${entry.value ?? ''}',
        };
      }
    } on Object {
      // 落回宽松解析。
    }
    final normalized = text
        .replaceAll(RegExp(r"'"), '"')
        .replaceAll(RegExp(r',\s*}'), '}');
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map) {
        return <String, String>{
          for (final entry in decoded.entries)
            '${entry.key}': '${entry.value ?? ''}',
        };
      }
    } on Object {
      return null;
    }
    return null;
  }
}
