/// legado `AnalyzeUrl` 的 Dart 重译：展开书源 URL 规则（`@js:` / `<js>` /
/// `{{改写}}` / `<1,2,3>` 翻页占位）、解析 `,{...}` 选项、编码 query/form、
/// 发请求并应用 `bodyJs`。
///
/// 不支持的 URL 选项：`webView`（按普通 HTTP 抓并留诊断位）、`dnsIp`、`proxy`、
/// `type`（音频/图片源的专用处理）。这些是少数源的增强项，不影响文本源主路径。
library;

import 'dart:async';
import 'dart:convert';

import 'package:charset/charset.dart';

import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/analyzer/rule_splitter.dart';
import 'package:mimao/novel/engine/lenient_json.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// URL 规则展开后的请求描述 + 抓取入口。
class AnalyzeUrl {
  AnalyzeUrl._({
    required this.ruleUrl,
    required this.url,
    required this.method,
    required this.headers,
    required this.transport,
    required this.source,
    required this.jsRunner,
    required this.sourceInfo,
    required this.variables,
    required this.key,
    required this.page,
    required this.baseUrl,
  });

  /// 原始规则串（日志/错误展示用）。
  final String ruleUrl;

  /// 展开后的最终 URL。
  final String url;
  String method;
  final Map<String, String> headers;
  final NovelHttpTransport transport;
  final NovelBookSource? source;
  final RuleJsRunner? jsRunner;
  final Map<String, String> sourceInfo;
  final Map<String, String> variables;
  final String? key;
  final int? page;
  final String baseUrl;

  String? charset;
  String? body;
  int retry = 0;
  bool useWebView = false;
  String? bodyJs;
  String? type;

  /// 展开 URL 规则（可能执行 JS，异步）。
  static Future<AnalyzeUrl> resolve({
    required String ruleUrl,
    required String baseUrl,
    required NovelHttpTransport transport,
    NovelBookSource? source,
    RuleJsRunner? jsRunner,
    Map<String, String>? variables,
    Map<String, String>? sourceInfo,
    String? key,
    int? page,
    Map<String, String>? headerOverride,
  }) async {
    final result = AnalyzeUrl._(
      ruleUrl: ruleUrl,
      url: '',
      method: 'GET',
      headers: <String, String>{
        if (source != null)
          ...?lenientJsonObject(
            source.headerRaw,
          )?.map((k, v) => MapEntry(k.toString(), v.toString())),
        ...?headerOverride,
      },
      transport: transport,
      source: source,
      jsRunner: jsRunner,
      sourceInfo: sourceInfo ?? _defaultSourceInfo(source),
      variables: variables ?? const <String, String>{},
      key: key,
      page: page,
      baseUrl: baseUrl,
    );
    await result._init(ruleUrl);
    return result;
  }

  static Map<String, String> _defaultSourceInfo(NovelBookSource? source) {
    if (source == null) return const <String, String>{};
    return <String, String>{
      'bookSourceUrl': source.url,
      'bookSourceName': source.name,
      'bookSourceComment': '${source.raw['bookSourceComment'] ?? ''}',
      'bookSourceGroup': '${source.raw['bookSourceGroup'] ?? ''}',
      'bookSourceType': '${source.type}',
      'key': source.key,
    };
  }

  Future<void> _init(String ruleUrl) async {
    var text = await _analyzeJs(ruleUrl);
    text = await _replaceKeyPageJs(text);
    final optionMatch = RegExp(r'\s*,\s*(?=\{)').firstMatch(text);
    final rawUrl = optionMatch == null
        ? text
        : text.substring(0, optionMatch.start);
    var resolved = _absolute(baseUrl, rawUrl.trim());
    if (optionMatch != null) {
      final optionText = text.substring(optionMatch.end);
      final option = lenientJsonObject(optionText);
      if (option != null) _applyOptions(option);
      if (_jsOption != null) {
        final value = await _evalUrlJs(_jsOption!, result: resolved);
        if (value != null && value.trim().isNotEmpty) resolved = value.trim();
      }
    }
    if (resolved.startsWith('data:')) {
      _dataUri = resolved;
    }
    _url = _normalizeUrl(resolved);
    if (method == 'GET') _url = _encodeQuery(_url, charset);
    if (method == 'POST') {
      final contentType = _headerValue(headers, 'content-type');
      final rawBody = body;
      if (rawBody != null &&
          !_looksJson(rawBody) &&
          !_looksXml(rawBody) &&
          contentType.isEmpty) {
        _encodedForm = _encodeForm(rawBody, charset);
      }
    }
  }

  String _url = '';
  String? _dataUri;
  String? _encodedForm;
  String? _jsOption;

  /// 最终 URL（GET 已编码 query）。
  String get resolvedUrl => _url;

  /// 实际发给 HTTP 的 URL（POST 不含 query）。
  String get requestUrl {
    if (method != 'POST') return _url;
    final index = _url.indexOf('?');
    return index < 0 ? _url : _url.substring(0, index);
  }

  /// 发起请求；[jsStr] / [sourceRegex] 只在 webView 模式下有意义，当前忽略。
  Future<NovelHttpResponse> fetch({
    String? jsStr,
    String? sourceRegex,
    bool useWebViewOption = true,
  }) async {
    final dataUri = _dataUri;
    if (dataUri != null) {
      return NovelHttpResponse(
        url: dataUri,
        statusCode: 200,
        body: _decodeDataUri(dataUri),
      );
    }
    final request = NovelHttpRequest(
      url: method == 'POST' ? requestUrl : _url,
      method: method,
      headers: headers,
      body: method == 'POST' ? _encodedForm ?? body : null,
      charset: charset,
      retry: retry,
      useCookieJar: source?.enabledCookieJar ?? true,
      sourceKey: source?.key,
    );
    final response = await transport.send(request);
    var finalBody = response.body;
    if (bodyJs != null) {
      final value = await _evalUrlJs(bodyJs!, result: finalBody);
      if (value != null) finalBody = value;
    }
    return NovelHttpResponse(
      url: response.url,
      statusCode: response.statusCode,
      body: finalBody,
      headers: response.headers,
      charset: response.charset,
      usedWebViewFallback: useWebView && useWebViewOption,
    );
  }

  void _applyOptions(Map<String, Object?> option) {
    final methodValue = '${option['method'] ?? ''}'.trim().toUpperCase();
    if (methodValue.isNotEmpty) {
      method = methodValue == 'POST' || methodValue == 'HEAD'
          ? methodValue
          : 'GET';
    }
    final charsetValue = '${option['charset'] ?? ''}'.trim();
    if (charsetValue.isNotEmpty) charset = charsetValue.toLowerCase();
    final headerValue = option['headers'];
    if (headerValue is Map) {
      for (final entry in headerValue.entries) {
        headers['${entry.key}'] = '${entry.value ?? ''}';
      }
    } else if (headerValue is String) {
      final parsed = lenientJsonObject(headerValue);
      if (parsed != null) {
        for (final entry in parsed.entries) {
          headers[entry.key] = '${entry.value ?? ''}';
        }
      }
    }
    final bodyValue = option['body'];
    if (bodyValue != null) {
      if (bodyValue is String) {
        body = bodyValue;
      } else {
        try {
          body = jsonEncode(bodyValue);
        } on Object {
          body = bodyValue.toString();
        }
      }
    }
    final retryValue = option['retry'];
    if (retryValue is num) {
      retry = retryValue.toInt();
    } else if (retryValue is String) {
      retry = int.tryParse(retryValue) ?? 0;
    }
    final webView = option['webView'];
    useWebView = webView == true || '$webView'.toLowerCase() == 'true';
    final bodyJsValue = option['bodyJs'];
    if (bodyJsValue is String && bodyJsValue.trim().isNotEmpty) {
      bodyJs = bodyJsValue.trim();
    }
    final jsValue = option['js'];
    if (jsValue is String && jsValue.trim().isNotEmpty) {
      _jsOption = jsValue.trim();
    }
    final typeValue = option['type'];
    if (typeValue is String && typeValue.trim().isNotEmpty) {
      type = typeValue.trim();
    }
  }

  /// 展开 `<js>...</js>` / `@js:`：把上一段 URL 作为 `result` 传入。
  Future<String> _analyzeJs(String rule) async {
    var current = rule;
    var start = 0;
    var output = StringBuffer();
    final pattern = RegExp(
      r'<js>([\w\W]*?)</js>|@js:([\w\W]*)',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(rule)) {
      if (match.start > start) {
        final text = rule.substring(start, match.start).trim();
        if (text.isNotEmpty) output.write(text.replaceAll('@result', current));
      }
      var script = (match.group(2) ?? '').isNotEmpty
          ? match.group(2)!
          : (match.group(1) ?? '');
      // `@js:([\w\W]*)` 贪婪吃到串尾，书源常把 `##手机地址：` 这类尾注写在
      // 后面；不先拆掉，整段进 eval 会让 QuickJS 报 private name 语法错，
      // 搜索/详情整条失败（LESSON §八，规则层已在 SourceRule 同款收口）。
      script = script.split('##').first.trim();
      final value = await _evalUrlJs(script, result: current);
      current = value ?? '';
      output.write(current);
      start = match.end;
    }
    if (rule.length > start) {
      final text = rule.substring(start).trim();
      if (text.isNotEmpty) output.write(text.replaceAll('@result', current));
    }
    return output.toString();
  }

  /// `{{key}}` / `{{page}}` / JS 表达式；`<1,2,3>` 选页。
  Future<String> _replaceKeyPageJs(String rule) async {
    var result = rule;
    if (result.contains('{{') && result.contains('}}')) {
      final splitter = RuleSplitter(result);
      final replaced = splitter.innerRule('{{', '}}', (_) => '');
      if (replaced != rule) {
        // 逐段处理，避免把 JS 里的 `}}` 当结束标记。
        final buffer = StringBuffer();
        var index = 0;
        while (index < result.length) {
          final start = result.indexOf('{{', index);
          if (start < 0) {
            buffer.write(result.substring(index));
            break;
          }
          buffer.write(result.substring(index, start));
          final end = _findDoubleBraceEnd(result, start + 2);
          if (end < 0) {
            buffer.write(result.substring(start));
            break;
          }
          final expression = result.substring(start + 2, end);
          final value = await _evalUrlJs(expression);
          buffer.write(value ?? '');
          index = end + 2;
        }
        result = buffer.toString();
      }
    }
    return _replacePage(result);
  }

  String _replacePage(String rule) {
    final pageValue = page;
    if (pageValue == null) return rule;
    return rule.replaceAllMapped(RegExp(r'<(.*?)>'), (match) {
      final pages = match.group(1)!.split(',');
      final selected = pageValue <= pages.length
          ? pages[pageValue - 1]
          : pages.last;
      return selected.trim();
    });
  }

  static int _findDoubleBraceEnd(String text, int start) {
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
        index++;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        index++;
        continue;
      }
      if (text.startsWith('{{', index)) {
        depth++;
        index += 2;
        continue;
      }
      if (text.startsWith('}}', index)) {
        depth--;
        if (depth == 0) return index;
        index += 2;
        continue;
      }
      index++;
    }
    return -1;
  }

  Future<String?> _evalUrlJs(String script, {Object? result}) async {
    final runner = jsRunner;
    if (runner == null) return null;
    final analyzer = LegadoRuleAnalyzer(
      content: '',
      baseUrl: baseUrl,
      jsRunner: runner,
      key: key,
      page: page,
      variables: variables,
      sourceInfo: sourceInfo,
    );
    return analyzer.evalJsString(script, result: result);
  }

  static String _absolute(String base, String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return trimmed;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return trimmed;
    try {
      return baseUri.resolve(trimmed).toString();
    } on Object {
      return trimmed;
    }
  }

  static String _normalizeUrl(String url) {
    final index = url.indexOf('#');
    if (index > 0 && url.startsWith('http')) return url.substring(0, index);
    return url;
  }

  static String _encodeQuery(String url, String? charset) {
    final index = url.indexOf('?');
    if (index < 0) return url;
    final query = url.substring(index + 1);
    if (query.isEmpty) return url;
    if (_isEncodedQuery(query)) return url;
    final encoding = _encodingFor(charset);
    final buffer = StringBuffer();
    for (final char in query.split('')) {
      final code = char.codeUnitAt(0);
      if (_querySafe(code)) {
        buffer.write(char);
      } else {
        for (final byte in encoding.encode(char)) {
          buffer
            ..write('%')
            ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
        }
      }
    }
    return '${url.substring(0, index)}?$buffer';
  }

  static bool _isEncodedQuery(String query) {
    for (var i = 0; i < query.length; i++) {
      final code = query.codeUnitAt(i);
      if (code > 0x7F) return false;
      if (code == 0x25 /* % */ ) {
        if (i + 2 >= query.length) return false;
        if (!_isHex(query.codeUnitAt(i + 1)) ||
            !_isHex(query.codeUnitAt(i + 2))) {
          return false;
        }
        i += 2;
      } else if (code == 0x20) {
        return false;
      }
    }
    return true;
  }

  static bool _isHex(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x46) ||
      (code >= 0x61 && code <= 0x66);

  static bool _querySafe(int code) {
    if ((code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        (code >= 0x30 && code <= 0x39)) {
      return true;
    }
    return '_.-~!\$&()*+,/:;=?@[]^`{|}\\'.codeUnits.contains(code);
  }

  static String _encodeForm(String body, String? charset) {
    final encoding = _encodingFor(charset);
    final checkEncoded = charset == null || charset.isEmpty;
    final buffer = StringBuffer();
    for (final pair in body.split('&')) {
      if (buffer.isNotEmpty) buffer.write('&');
      final eq = pair.indexOf('=');
      final key = eq < 0 ? pair : pair.substring(0, eq);
      final value = eq < 0 ? null : pair.substring(eq + 1);
      buffer.write(_encodeFormValue(key, encoding, checkEncoded));
      if (value != null) {
        buffer
          ..write('=')
          ..write(_encodeFormValue(value, encoding, checkEncoded));
      }
    }
    return buffer.toString();
  }

  static String _encodeFormValue(
    String value,
    Encoding encoding,
    bool checkEncoded,
  ) {
    if (checkEncoded && _isEncodedQuery(value)) return value;
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      final code = char.codeUnitAt(0);
      if ((code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A) ||
          (code >= 0x30 && code <= 0x39) ||
          char == '*' ||
          char == '-' ||
          char == '.' ||
          char == '_') {
        buffer.write(char);
      } else if (char == ' ') {
        buffer.write('+');
      } else {
        for (final byte in encoding.encode(char)) {
          buffer
            ..write('%')
            ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
        }
      }
    }
    return buffer.toString();
  }

  static Encoding _encodingFor(String? charset) {
    if (charset == null || charset.isEmpty || charset == 'utf-8') {
      return utf8;
    }
    if (charset == 'escape') return utf8;
    return Charset.getByName(charset) ?? utf8;
  }

  static String _decodeDataUri(String uri) {
    final comma = uri.indexOf(',');
    if (comma < 0) return '';
    final header = uri.substring(0, comma);
    final data = uri.substring(comma + 1);
    if (header.contains('base64')) {
      try {
        return const Utf8Decoder(
          allowMalformed: true,
        ).convert(base64Decode(data));
      } on Object {
        return '';
      }
    }
    return Uri.decodeComponent(data);
  }

  static bool _looksJson(String body) {
    final text = body.trimLeft();
    return text.startsWith('{') || text.startsWith('[');
  }

  static bool _looksXml(String body) => body.trimLeft().startsWith('<');

  static String _headerValue(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return '';
  }
}
