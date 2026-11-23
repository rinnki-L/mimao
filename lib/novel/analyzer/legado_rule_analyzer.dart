/// legado `AnalyzeRule` 的 Dart 重译：把规则字符串拆成 `SourceRule`，按模式
/// 分发给 JSoup / XPath / JSONPath / Regex / JS；负责 `@get`、`@put`、`{{}}`
/// 插值、`##` 替换、相对 URL 补全与 HTML 实体反转义。
///
/// 规则层不直接依赖 QuickJS：JS 通过 [RuleJsRunner] 注入，同步回调通过
/// [RuleCallbacks] 暴露给 JS 宿主的 `java.getString(...)` 等 API。
library;

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:mimao/novel/analyzer/json_path_analyzer.dart';
import 'package:mimao/novel/analyzer/jsoup_analyzer.dart';
import 'package:mimao/novel/analyzer/jsoup_selector.dart' show jsoupText;
import 'package:mimao/novel/analyzer/regex_analyzer.dart';
import 'package:mimao/novel/analyzer/rule_analyzer.dart' as contract;
import 'package:mimao/novel/analyzer/rule_models.dart' show Rule;
import 'package:mimao/novel/analyzer/source_rule.dart';
import 'package:mimao/novel/analyzer/xpath_analyzer.dart';

/// JS 执行上下文：宿主在跑 `@js:` 片段时能看到当前结果/内容/URL/变量。
class RuleJsContext {
  RuleJsContext({
    required this.callbacks,
    this.result,
    this.baseUrl,
    this.bookName,
    this.chapterTitle,
    this.variables = const <String, String>{},
    this.sourceInfo = const <String, String>{},
  });

  /// 同步规则回调（`java.getString` / `java.setContent` 等）。
  final RuleCallbacks callbacks;

  /// 当前 `result` 变量。
  final Object? result;

  final String? baseUrl;
  final String? bookName;
  final String? chapterTitle;

  /// `@put` / `book.putVariable` 写入的变量。
  final Map<String, String> variables;

  /// 书源字段（`source.bookSourceUrl` / `getKey` 等）。
  final Map<String, String> sourceInfo;
}

/// JS 宿主的执行入口；生产实现是 QuickJS，测试可注入 fake。
typedef RuleJsRunner =
    Future<Object?> Function(String code, RuleJsContext context);

/// 暴露给 JS 宿主的同步规则能力。
abstract interface class RuleCallbacks {
  String getStringSync(String rule);

  List<String> getStringListSync(String rule);

  List<Object?> getElementsSync(String rule);

  Object? getElementSync(String rule);

  void setContent(Object? content);

  Object? getContent();
}

/// 规则执行器：一个实例绑定一段内容 + 上下文，可在同一段内容上连续取多个字段。
class LegadoRuleAnalyzer
    implements contract.RuleAnalyzer, SourceRuleHost, RuleCallbacks {
  LegadoRuleAnalyzer({
    Object? content,
    this.baseUrl,
    this.redirectUrl,
    this.bookName,
    this.chapterTitle,
    Map<String, String>? variables,
    Map<String, String>? sourceInfo,
    this.jsRunner,
  }) : _content = content,
       _variables = <String, String>{...?variables},
       _sourceInfo = <String, String>{...?sourceInfo},
       _isJson = _looksLikeJson(content);

  Object? _content;
  bool _isJson;

  String? baseUrl;
  Uri? redirectUrl;
  String? bookName;
  String? chapterTitle;

  /// 当前章节标题（`get('title')` 用）；与 [chapterTitle] 同步。
  final Map<String, String> _variables;
  final Map<String, String> _sourceInfo;
  final RuleJsRunner? jsRunner;

  @override
  Future<List<String>> parse(String content, Rule rule) async {
    setContent(content);
    return await getStringList(rule.expression) ?? const <String>[];
  }

  // ---------------------------------------------------------------------------
  // 内容与变量

  @override
  void setContent(Object? content) {
    _content = content;
    _isJson = _looksLikeJson(content);
  }

  Object? get content => _content;

  void setRedirectUrl(String? url) {
    if (url == null || url.isEmpty || url.startsWith('data:')) return;
    redirectUrl = Uri.tryParse(url);
  }

  @override
  Object? getContent() => _content;

  @override
  String getRuleVariable(String key) {
    if (key == 'bookName' && (bookName ?? '').isNotEmpty) return bookName!;
    if (key == 'title' && (chapterTitle ?? '').isNotEmpty) return chapterTitle!;
    return _variables[key] ?? '';
  }

  @override
  void putRuleVariable(String key, String value) => _variables[key] = value;

  Map<String, String> get variables =>
      Map<String, String>.unmodifiable(_variables);

  static bool _looksLikeJson(Object? content) {
    if (content == null || content is Element || content is Document) {
      return false;
    }
    final text = content.toString().trim();
    return text.startsWith('{') || text.startsWith('[');
  }

  // ---------------------------------------------------------------------------
  // 规则拆解

  static final RegExp _jsPattern = RegExp(
    r'<js>([\w\W]*?)</js>|@js:([\w\W]*)',
    caseSensitive: false,
  );
  static final RegExp _webJsPattern = RegExp(
    r'@webjs:([\w\W]{5,})',
    caseSensitive: false,
  );

  /// 把整条规则拆成 `SourceRule` 列表（`@js:` / `<js>` 段单独成条）。
  List<SourceRule> splitSourceRule(String? ruleStr, {bool allInOne = false}) {
    if (ruleStr == null || ruleStr.isEmpty) return const <SourceRule>[];
    var mode = RuleMode.defaultRule;
    var start = 0;
    if (allInOne && ruleStr.startsWith(':')) {
      mode = RuleMode.regex;
      start = 1;
    }
    final result = <SourceRule>[];
    for (final match in _jsPattern.allMatches(ruleStr)) {
      if (match.start > start) {
        final text = ruleStr.substring(start, match.start).trim();
        if (text.isNotEmpty) result.add(SourceRule(text, mode));
      }
      final script = (match.group(2) ?? '').isNotEmpty
          ? match.group(2)!
          : (match.group(1) ?? '');
      result.add(SourceRule(script, RuleMode.js));
      start = match.end;
    }
    for (final match in _webJsPattern.allMatches(ruleStr)) {
      if (match.start > start) {
        final text = ruleStr.substring(start, match.start).trim();
        if (text.isNotEmpty) result.add(SourceRule(text, mode));
      }
      result.add(SourceRule(match.group(1) ?? '', RuleMode.webJs));
      start = match.end;
    }
    if (ruleStr.length > start) {
      final text = ruleStr.substring(start).trim();
      if (text.isNotEmpty) result.add(SourceRule(text, mode));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // 取字符串

  /// 取文本（异步：可能执行网络 JS）。
  Future<String> getString(
    String? ruleStr, {
    Object? content,
    bool isUrl = false,
    bool unescape = true,
  }) async {
    if (ruleStr == null || ruleStr.isEmpty) return '';
    final rules = splitSourceRule(ruleStr);
    Object? result = content ?? _content;
    for (final sourceRule in rules) {
      for (final entry in sourceRule.putMap.entries) {
        putRuleVariable(entry.key, await getString(entry.value));
      }
      await sourceRule.makeUpRule(this, result);
      if (result == null) continue;
      if (result is Map && sourceRule.mode == RuleMode.defaultRule) {
        result = result[sourceRule.rule];
        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          result = sourceRule.applyRegex(result.toString());
        }
        continue;
      }
      if (sourceRule.rule.isNotEmpty || sourceRule.replaceRegex.isEmpty) {
        result = await _applyModeToString(sourceRule, result, isUrl);
      }
      if (result != null && sourceRule.replaceRegex.isNotEmpty) {
        result = sourceRule.applyRegex(result.toString());
      }
    }
    var text = result?.toString() ?? '';
    if (unescape && text.contains('&')) text = htmlUnescape(text);
    if (!isUrl) return text;
    if (text.trim().isEmpty) return baseUrl ?? '';
    return absoluteUrl(redirectUrl, text);
  }

  Future<Object?> _applyModeToString(
    SourceRule sourceRule,
    Object result,
    bool isUrl,
  ) async {
    switch (sourceRule.mode) {
      case RuleMode.js:
        return evalJs(sourceRule.rule, result: result);
      case RuleMode.json:
        return JsonPathAnalyzer(result).getString(sourceRule.rule);
      case RuleMode.xpath:
        return XPathAnalyzer(result).getString(sourceRule.rule);
      case RuleMode.defaultRule:
        final analyzer = JsoupAnalyzer(result);
        return isUrl
            ? analyzer.getString0(sourceRule.rule)
            : analyzer.getString(sourceRule.rule);
      case RuleMode.regex:
      case RuleMode.webJs:
        return sourceRule.rule;
    }
  }

  /// 取文本列表；空结果返回 null（对齐 Kotlin 的 `null` 语义）。
  Future<List<String>?> getStringList(
    String? ruleStr, {
    Object? content,
    bool isUrl = false,
  }) async {
    if (ruleStr == null || ruleStr.isEmpty) return null;
    final rules = splitSourceRule(ruleStr);
    Object? result = content ?? _content;
    for (final sourceRule in rules) {
      for (final entry in sourceRule.putMap.entries) {
        putRuleVariable(entry.key, await getString(entry.value));
      }
      await sourceRule.makeUpRule(this, result);
      if (result == null) continue;
      if (result is Map && sourceRule.mode == RuleMode.defaultRule) {
        result = result[sourceRule.rule];
        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          result = sourceRule.applyRegex(result.toString());
        }
        continue;
      }
      if (sourceRule.rule.isNotEmpty) {
        result = await _applyModeToList(sourceRule, result);
      }
      if (sourceRule.replaceRegex.isNotEmpty) {
        if (result is List) {
          result = <String>[
            for (final item in result) sourceRule.applyRegex(item.toString()),
          ];
        } else {
          result = sourceRule.applyRegex(result.toString());
        }
      }
    }
    if (result == null) return null;
    List<String> list;
    if (result is List) {
      list = <String>[for (final item in result) item.toString()];
    } else {
      list = result.toString().split('\n');
    }
    if (!isUrl) return list;
    final urls = <String>[];
    for (final url in list) {
      final absolute = absoluteUrl(redirectUrl, url);
      if (absolute.isNotEmpty && !urls.contains(absolute)) urls.add(absolute);
    }
    return urls;
  }

  Future<Object?> _applyModeToList(SourceRule sourceRule, Object result) async {
    switch (sourceRule.mode) {
      case RuleMode.js:
        return evalJs(sourceRule.rule, result: result);
      case RuleMode.json:
        return JsonPathAnalyzer(result).getStringList(sourceRule.rule);
      case RuleMode.xpath:
        return XPathAnalyzer(result).getStringList(sourceRule.rule);
      case RuleMode.defaultRule:
        return JsoupAnalyzer(result).getStringList(sourceRule.rule);
      case RuleMode.regex:
      case RuleMode.webJs:
        return sourceRule.rule;
    }
  }

  // ---------------------------------------------------------------------------
  // 取元素

  /// 取元素列表（书列表 / 目录列表）。
  Future<List<Object?>> getElements(String? ruleStr, {Object? content}) async {
    if (ruleStr == null || ruleStr.isEmpty) return const <Object?>[];
    final rules = splitSourceRule(ruleStr, allInOne: true);
    Object? result = content ?? _content;
    for (final sourceRule in rules) {
      for (final entry in sourceRule.putMap.entries) {
        putRuleVariable(entry.key, await getString(entry.value));
      }
      await sourceRule.makeUpRule(this, result);
      if (result == null) continue;
      switch (sourceRule.mode) {
        case RuleMode.js:
          result = evalJs(sourceRule.rule, result: result);
          break;
        case RuleMode.json:
          result = JsonPathAnalyzer(result).getList(sourceRule.rule);
          break;
        case RuleMode.xpath:
          result = XPathAnalyzer(result).getElements(sourceRule.rule);
          break;
        case RuleMode.regex:
          result = RegexAnalyzer.getElements(
            result.toString(),
            sourceRule.rule.split('&&'),
          );
          break;
        case RuleMode.defaultRule:
          result = JsoupAnalyzer(result).getElements(sourceRule.rule);
          break;
        case RuleMode.webJs:
          result = const <Object>[];
          break;
      }
    }
    if (result is List) return <Object?>[...result];
    return const <Object?>[];
  }

  /// 取单个元素（详情页 `init` 规则用）。
  Future<Object?> getElement(String? ruleStr, {Object? content}) async {
    if (ruleStr == null || ruleStr.isEmpty) return null;
    final rules = splitSourceRule(ruleStr, allInOne: true);
    Object? result = content ?? _content;
    for (final sourceRule in rules) {
      for (final entry in sourceRule.putMap.entries) {
        putRuleVariable(entry.key, await getString(entry.value));
      }
      await sourceRule.makeUpRule(this, result);
      if (result == null) return null;
      switch (sourceRule.mode) {
        case RuleMode.js:
          result = evalJs(sourceRule.rule, result: result);
          break;
        case RuleMode.json:
          result = JsonPathAnalyzer(result).getObject(sourceRule.rule);
          break;
        case RuleMode.xpath:
          final list = XPathAnalyzer(result).getElements(sourceRule.rule);
          result = list.isEmpty ? null : list.first;
          break;
        case RuleMode.regex:
          final groups = RegexAnalyzer.getElement(
            result.toString(),
            sourceRule.rule.split('&&'),
          );
          result = groups;
          break;
        case RuleMode.defaultRule:
          final list = JsoupAnalyzer(result).getElements(sourceRule.rule);
          result = list.isEmpty ? null : list.first;
          break;
        case RuleMode.webJs:
          result = null;
          break;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // 同步回调（JS 宿主用）

  @override
  String getStringSync(String rule) {
    try {
      final sourceRules = splitSourceRule(rule);
      Object? result = _content;
      for (final sourceRule in sourceRules) {
        if (sourceRule.mode == RuleMode.js) return '';
        for (final entry in sourceRule.putMap.entries) {
          putRuleVariable(entry.key, getStringSync(entry.value));
        }
        _makeUpRuleSync(sourceRule, result);
        if (result == null) continue;
        switch (sourceRule.mode) {
          case RuleMode.json:
            result = JsonPathAnalyzer(result).getString(sourceRule.rule);
            break;
          case RuleMode.xpath:
            result = XPathAnalyzer(result).getString(sourceRule.rule);
            break;
          case RuleMode.defaultRule:
            result = JsoupAnalyzer(result).getString(sourceRule.rule);
            break;
          default:
            result = sourceRule.rule;
        }
        if (sourceRule.replaceRegex.isNotEmpty) {
          result = sourceRule.applyRegex(result.toString());
        }
      }
      final text = result?.toString() ?? '';
      return text.contains('&') ? htmlUnescape(text) : text;
    } on Object {
      return '';
    }
  }

  @override
  List<String> getStringListSync(String rule) {
    try {
      final text = getStringSync(rule);
      return text.isEmpty ? const <String>[] : text.split('\n');
    } on Object {
      return const <String>[];
    }
  }

  @override
  List<Object?> getElementsSync(String rule) {
    try {
      final sourceRules = splitSourceRule(rule, allInOne: true);
      Object? result = _content;
      for (final sourceRule in sourceRules) {
        if (sourceRule.mode == RuleMode.js) return const <Object?>[];
        _makeUpRuleSync(sourceRule, result);
        if (result == null) continue;
        switch (sourceRule.mode) {
          case RuleMode.json:
            result = JsonPathAnalyzer(result).getList(sourceRule.rule);
            break;
          case RuleMode.xpath:
            result = XPathAnalyzer(result).getElements(sourceRule.rule);
            break;
          case RuleMode.defaultRule:
            result = JsoupAnalyzer(result).getElements(sourceRule.rule);
            break;
          default:
            result = const <Object>[];
        }
      }
      return result is List ? <Object?>[...result] : const <Object?>[];
    } on Object {
      return const <Object?>[];
    }
  }

  @override
  Object? getElementSync(String rule) {
    final list = getElementsSync(rule);
    return list.isEmpty ? null : list.first;
  }

  void _makeUpRuleSync(SourceRule sourceRule, Object? result) {
    // 同步路径不做 JS 插值；没有 {{}} 的规则占绝大多数，JS 回调里再走
    // 规则级 `java.getString` 时也会命中同一约束，失败时退化为空串。
    if (sourceRule.rule.isEmpty) return;
    final parts = sourceRule.rule.split('##');
    sourceRule.rule = parts.first.trim();
    if (parts.length > 1) sourceRule.replaceRegex = parts[1];
    if (parts.length > 2) sourceRule.replacement = parts[2];
    if (parts.length > 3) sourceRule.replaceFirst = true;
  }

  // ---------------------------------------------------------------------------
  // JS

  @override
  Future<Object?> evalJs(String snippet, {Object? result}) async {
    final runner = jsRunner;
    if (runner == null) return null;
    return runner(
      snippet,
      RuleJsContext(
        callbacks: this,
        result: result ?? _content,
        baseUrl: baseUrl,
        bookName: bookName,
        chapterTitle: chapterTitle,
        variables: Map<String, String>.from(_variables),
        sourceInfo: _sourceInfo,
      ),
    );
  }

  /// 内嵌规则（`{{@.x}}`）：在当前内容上取文本。
  @override
  Future<Object?> evalRule(String rule, {Object? result}) async {
    final content = _content;
    if (content == null) return null;
    if (rule.startsWith(r'$.') || rule.startsWith(r'$[') || _isJson) {
      return JsonPathAnalyzer(content).getObject(rule);
    }
    return JsoupAnalyzer(content).getElements(rule).firstOrNull;
  }

  /// 直接跑 JS 并转成字符串（URL 解析等场景）。
  Future<String?> evalJsString(String snippet, {Object? result}) async {
    final value = await evalJs(snippet, result: result);
    if (value == null) return null;
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  // ---------------------------------------------------------------------------

  String absoluteUrl(Uri? redirect, String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return trimmed;
    final base = redirect ?? Uri.tryParse(baseUrl ?? '');
    if (base == null) return trimmed;
    try {
      return base.resolve(trimmed).toString();
    } on Object {
      return trimmed;
    }
  }

  static final Map<String, String> _entities = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': '\u00A0',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'ldquo': '“',
    'rdquo': '”',
    'lsquo': '‘',
    'rsquo': '’',
    'middot': '·',
    'bull': '•',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'times': '×',
    'divide': '÷',
    'deg': '°',
    'plusmn': '±',
    'laquo': '«',
    'raquo': '»',
    'ensp': '\u2002',
    'emsp': '\u2003',
    'thinsp': '\u2009',
    'zwj': '\u200D',
    'zwnj': '\u200C',
  };

  /// HTML4 实体反转义（`&amp;` / `&#123;` / `&#x1F;`）。
  static String htmlUnescape(String text) {
    return text.replaceAllMapped(
      RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);'),
      (match) {
        final body = match.group(1)!;
        if (body.startsWith('#x') || body.startsWith('#X')) {
          final code = int.tryParse(body.substring(2), radix: 16);
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        if (body.startsWith('#')) {
          final code = int.tryParse(body.substring(1));
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        return _entities[body.toLowerCase()] ?? match.group(0)!;
      },
    );
  }

  /// 把任意规则结果转成可读文本（JS 列表结果等）。
  static String valueToString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Element) return jsoupText(value);
    if (value is num || value is bool) return value.toString();
    try {
      return jsonEncode(value);
    } on Object {
      return value.toString();
    }
  }
}
