/// legado 书源 JS 宿主：QuickJS runtime + `__native` 桥 + 网络预取重放。
///
/// 书源 JS 是 Rhino 同步语义（`java.ajax(...)` 直接拿字符串）。QuickJS 不能
/// 同步等 Dart Future，这里用「哨兵 + 重放」：JS 调网络时返回
/// `{__mimaofetch:[...]}`，JS 侧抛 `__MIMAO_FETCH__`；Dart 预取后重跑整段脚本。
/// 对规则作者透明，同步语义不变。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mimao/novel/analyzer/jsoup_analyzer.dart';
import 'package:mimao/novel/analyzer/jsoup_selector.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/engine/analyze_url.dart';
import 'package:mimao/novel/engine/lenient_json.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/js/js_helpers.dart' as helpers;
import 'package:mimao/novel/js/js_preamble.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// JS 执行失败（语法错/未捕获异常）。
class LegadoJsException implements Exception {
  const LegadoJsException(this.message);

  final String message;

  @override
  String toString() => 'LegadoJsException: $message';
}

/// 书源 JS 宿主。一个源复用一个实例（全局变量/上下文跨规则共享，和 Rhino 一致）。
class LegadoJsHost {
  LegadoJsHost({
    required NovelHttpTransport transport,
    NovelBookSource? source,
    String? userAgent,
  }) : _transport = transport,
       _source = source,
       _userAgent = userAgent ?? novelDefaultUserAgent;

  final NovelHttpTransport _transport;
  final NovelBookSource? _source;
  final String _userAgent;
  final FlutterQjs _engine = FlutterQjs(
    memoryLimit: 64 * 1024 * 1024,
    timeout: 20000,
  );

  JSInvokable? _setGlobal;
  Future<void>? _dispatcher;
  bool _closed = false;

  final Map<String, String> _bodyCache = <String, String>{};
  final Map<String, Map<String, Object?>> _responseCache =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, String>> _cookies =
      <String, Map<String, String>>{};
  final Map<String, Object?> _memory = <String, Object?>{};
  Map<String, String> _bookVariables = <String, String>{};
  String _sourceVariable = '';
  RuleJsContext? _currentContext;
  final List<String> logs = <String>[];

  Future<void> _ensureInitialized() async {
    if (_dispatcher != null) return;
    _dispatcher = _engine.dispatch();
    _setGlobal = _engine.evaluate(legadoInitGlobalSetter) as JSInvokable;
    _setGlobal!(<dynamic>[
      '__native',
      (dynamic name, dynamic args) => _dispatch(name, args),
    ]);
    JSRef.freeRecursive(_engine.evaluate(legadoInitJs, name: '<legado-init>'));
  }

  Future<Object?> call(String code, RuleJsContext context) =>
      evaluate(code, context);

  /// 执行一段书源 JS，并自动完成 `java.ajax` 等网络预取重放。
  Future<Object?> evaluate(String code, RuleJsContext context) async {
    if (_closed) return null;
    await _ensureInitialized();
    final previous = _currentContext;
    _currentContext = context;
    _bookVariables = <String, String>{...context.variables};
    try {
      final script = jsonEncode(code);
      final wrapper =
          '(function(){ var __v = eval($script); '
          'if (__v === undefined) return null; '
          'if (__v !== null && typeof __v === "object") { '
          '  try { return {__mimaovalue: JSON.stringify(__v)}; } '
          '  catch (e) { return String(__v); } '
          '} return __v; })()';
      for (var attempt = 0; attempt < 30; attempt++) {
        _applyBindings(context);
        try {
          final value = _engine.evaluate(wrapper, name: '<legado-js>');
          final result = value is Future ? await value : value;
          JSRef.freeRecursive(result);
          return _unwrap(result);
        } on JSError catch (error) {
          final specs = _fetchSpecs(error.message);
          if (specs == null || specs.isEmpty) {
            throw LegadoJsException(error.message);
          }
          await _prefetch(specs);
        }
      }
      throw const LegadoJsException('JS 网络预取次数过多');
    } on LegadoJsException {
      rethrow;
    } on Object catch (error) {
      throw LegadoJsException('$error');
    } finally {
      _currentContext = previous;
    }
  }

  /// 加载书源 `jsLib`（全局函数库）。只执行一次，失败记录不抛出。
  Future<void> loadLibrary(String code) async {
    if (code.trim().isEmpty || _closed) return;
    await _ensureInitialized();
    try {
      JSRef.freeRecursive(_engine.evaluate(code, name: '<legado-js-lib>'));
    } on Object catch (error) {
      logs.add('jsLib 加载失败：$error');
    }
  }

  /// URL 规则等场景的字符串结果。
  Future<String?> evalString(String code, RuleJsContext context) async {
    final value = await evaluate(code, context);
    if (value == null) return null;
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _setGlobal?.free();
    _setGlobal = null;
    _engine.close();
  }

  // ---------------------------------------------------------------------------
  // 绑定与结果

  void _applyBindings(RuleJsContext context) {
    final sourceInfo = _json(context.sourceInfo);
    final bookInfo = _json(context.bookInfo);
    final chapterInfo = _json(context.chapterInfo);
    final chapter = <String, Object?>{
      'title': context.chapterInfo['title'] ?? context.chapterTitle ?? '',
      'index': int.tryParse(context.chapterInfo['index'] ?? '') ?? 0,
      'url': context.chapterInfo['url'] ?? '',
    };
    final content = _literal(context.callbacks.getContent());
    JSRef.freeRecursive(
      _engine.evaluate(
        'globalThis.__sourceInfo = $sourceInfo;'
        'globalThis.__bookInfo = $bookInfo;'
        'globalThis.__chapterInfo = $chapterInfo;'
        'globalThis.__baseUrlInternal = ${jsonEncode(context.baseUrl ?? '')};'
        'globalThis.baseUrl = globalThis.__baseUrlInternal;'
        'globalThis.result = ${_literal(context.result)};'
        'globalThis.title = ${jsonEncode(context.chapterTitle ?? '')};'
        'globalThis.chapter = ${_jsonObject(chapter)};'
        'globalThis.key = ${jsonEncode(context.key ?? '')};'
        'globalThis.page = ${context.page ?? 0};'
        'globalThis.src = $content;'
        'globalThis.nextChapterUrl = "";'
        'globalThis.fromBookInfo = false;',
        name: '<legado-bindings>',
      ),
    );
  }

  Object? _unwrap(Object? value) {
    if (value is Map) {
      final map = Map<dynamic, dynamic>.from(value);
      final json = map['__mimaovalue'];
      if (json is String) {
        try {
          return jsonDecode(json);
        } on Object {
          return json;
        }
      }
      return Map<String, Object?>.from(map);
    }
    if (value is List) return List<Object?>.from(value);
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return value;
  }

  String _literal(Object? value) {
    if (value == null) return 'null';
    if (value is String) return jsonEncode(value);
    if (value is num || value is bool) return value.toString();
    if (value is Element) return jsonEncode(value.outerHtml);
    if (value is Document) {
      return jsonEncode(value.documentElement?.outerHtml ?? '');
    }
    if (value is List) {
      return '[${value.map(_literal).join(',')}]';
    }
    if (value is Map) {
      return _jsonObject(<String, Object?>{
        for (final entry in value.entries) '${entry.key}': _plain(entry.value),
      });
    }
    return jsonEncode(value.toString());
  }

  Object? _plain(Object? value) {
    if (value is Element) return value.outerHtml;
    if (value is Document) return value.documentElement?.outerHtml ?? '';
    if (value is List) return <Object?>[for (final item in value) _plain(item)];
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': _plain(entry.value),
      };
    }
    return value;
  }

  String _json(Map<String, String> map) => _jsonObject(map);

  String _jsonObject(Map<String, Object?> map) {
    try {
      return jsonEncode(map);
    } on Object {
      return '{}';
    }
  }

  // ---------------------------------------------------------------------------
  // 网络预取

  List<Map<String, Object?>>? _fetchSpecs(String message) {
    const marker = '__MIMAO_FETCH__';
    final index = message.indexOf(marker);
    if (index < 0) return null;
    final text = message.substring(index + marker.length).trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return <Map<String, Object?>>[
          for (final item in decoded)
            if (item is Map) Map<String, Object?>.from(item),
        ];
      }
      if (decoded is Map) {
        return <Map<String, Object?>>[Map<String, Object?>.from(decoded)];
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<void> _prefetch(List<Map<String, Object?>> specs) async {
    for (final spec in specs) {
      final kind = '${spec['kind'] ?? 'body'}';
      final url = '${spec['url'] ?? ''}';
      if (url.isEmpty) continue;
      final key = _cacheKey('${spec['method'] ?? 'GET'}', url, spec['body']);
      if (kind == 'response') {
        if (_responseCache.containsKey(key)) continue;
        final response = await _request(spec, wantResponse: true);
        _responseCache[key] = <String, Object?>{
          'body': response.body,
          'url': response.url,
          'code': response.statusCode,
        };
      } else {
        if (_bodyCache.containsKey(key)) continue;
        final response = await _request(spec, wantResponse: false);
        _bodyCache[key] = response.body;
      }
    }
  }

  Future<NovelHttpResponse> _request(
    Map<String, Object?> spec, {
    required bool wantResponse,
  }) async {
    final url = '${spec['url'] ?? ''}';
    final method = '${spec['method'] ?? 'GET'}'.toUpperCase();
    final headers = <String, String>{
      for (final entry in _mapOf(spec['headers']).entries)
        entry.key: '${entry.value ?? ''}',
    };
    try {
      if (method == 'GET' || method == 'HEAD') {
        final analyze = await AnalyzeUrl.resolve(
          ruleUrl: url,
          baseUrl: _source?.url ?? url,
          transport: _transport,
          source: _source,
          jsRunner: evaluate,
          variables: _currentContext?.variables,
          sourceInfo: _currentContext?.sourceInfo,
          key: _currentContext?.key,
          page: _currentContext?.page,
          headerOverride: headers,
        );
        if (method == 'HEAD') {
          return await _transport.send(
            NovelHttpRequest(url: analyze.resolvedUrl, method: 'HEAD'),
          );
        }
        return await analyze.fetch();
      }
      final analyze = await AnalyzeUrl.resolve(
        ruleUrl: url,
        baseUrl: _source?.url ?? url,
        transport: _transport,
        source: _source,
        jsRunner: evaluate,
        variables: _currentContext?.variables,
        sourceInfo: _currentContext?.sourceInfo,
        key: _currentContext?.key,
        page: _currentContext?.page,
      );
      return await _transport.send(
        NovelHttpRequest(
          url: analyze.resolvedUrl,
          method: method,
          headers: <String, String>{...analyze.headers, ...headers},
          body: spec['body']?.toString(),
        ),
      );
    } on Object catch (error) {
      if (!wantResponse) {
        return NovelHttpResponse(url: url, statusCode: 500, body: '');
      }
      return NovelHttpResponse(
        url: url,
        statusCode: 500,
        body: 'ERROR: $error',
      );
    }
  }

  String _cacheKey(String method, String url, Object? body) =>
      '$method\u0000$url\u0000${body ?? ''}';

  Map<String, Object?> _mapOf(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String && value.trim().startsWith('{')) {
      return lenientJsonObject(value) ?? const <String, Object?>{};
    }
    return const <String, Object?>{};
  }

  // ---------------------------------------------------------------------------
  // 同步分派（JS → Dart）

  Object? _dispatch(String name, dynamic rawArgs) {
    final args = rawArgs is List ? rawArgs : const <dynamic>[];
    final context = _currentContext;
    switch (name) {
      case 'ajax':
        return _ajax('${_arg(args, 0)}');
      case 'ajaxAll':
        return _ajaxAll(args.isEmpty ? const <Object?>[] : _listOf(args[0]));
      case 'connect':
        return _connect(
          '${_arg(args, 0)}',
          _arg(args, 1)?.toString() ?? '',
          _arg(args, 2)?.toString(),
        );
      case 'post':
        return _connect(
          '${_arg(args, 0)}',
          _arg(args, 2).toString(),
          _arg(args, 1)?.toString(),
          method: 'POST',
        );
      case 'head':
        return _connect(
          '${_arg(args, 0)}',
          _arg(args, 1)?.toString() ?? '',
          _arg(args, 2)?.toString(),
          method: 'HEAD',
        );
      case 'webView':
        return _ajax('${_arg(args, 0)}');
      case 'importScript':
      case 'cacheFile':
        return _ajax('${_arg(args, 0)}');

      case 'getString':
        final content = _arg(args, 1);
        return _withContent(
          context,
          content,
          (callbacks) => callbacks.getStringSync('${_arg(args, 0)}'),
        );
      case 'getStringList':
        return _withContent(
          context,
          _arg(args, 1),
          (callbacks) => callbacks.getStringListSync('${_arg(args, 0)}'),
        );
      case 'getElements':
        return _withContent(context, _arg(args, 1), (callbacks) {
          final elements = callbacks.getElementsSync('${_arg(args, 0)}');
          return <Object?>[
            for (final element in elements)
              if (element is Element) element.outerHtml else '$element',
          ];
        });
      case 'getElement':
        return _withContent(context, _arg(args, 1), (callbacks) {
          final element = callbacks.getElementSync('${_arg(args, 0)}');
          return element is Element ? element.outerHtml : '$element';
        });
      case 'setContent':
        context?.callbacks.setContent(_coerceContent(_arg(args, 0)));
        return null;
      case 'put':
        context?.callbacks.putRuleVariable(
          '${_arg(args, 0)}',
          '${_arg(args, 1)}',
        );
        return _arg(args, 1);
      case 'get':
        return context?.callbacks.getRuleVariable('${_arg(args, 0)}') ?? '';

      case 'source.getVariable':
        return _sourceVariable;
      case 'source.setVariable':
        _sourceVariable = '${_arg(args, 0)}';
        return _sourceVariable;
      case 'book.getVariable':
        final key = _arg(args, 0)?.toString();
        if (key == null || key.isEmpty) return jsonEncode(_bookVariables);
        return _bookVariables[key] ?? '';
      case 'book.putVariable':
        _bookVariables['${_arg(args, 0)}'] = '${_arg(args, 1)}';
        context?.callbacks.putRuleVariable(
          '${_arg(args, 0)}',
          '${_arg(args, 1)}',
        );
        return _arg(args, 1);
      case 'book.setReverseToc':
        return null;

      case 'cookie.get':
        return _cookieGet(_arg(args, 0)?.toString(), _arg(args, 1)?.toString());
      case 'cookie.set':
        _cookieSet(_arg(args, 0)?.toString(), '${_arg(args, 1)}');
        return null;
      case 'cookie.remove':
        _cookies.remove(_arg(args, 0)?.toString());
        return null;

      case 'cache.get':
        return _memory[_arg(args, 0)?.toString() ?? ''];
      case 'cache.put':
        _memory[_arg(args, 0)?.toString() ?? ''] = _arg(args, 1);
        return null;
      case 'cache.remove':
        _memory.remove(_arg(args, 0)?.toString() ?? '');
        return null;

      case 'md5Encode':
        return helpers.md5Hex('${_arg(args, 0)}');
      case 'md5Encode16':
        return helpers.md5Hex16('${_arg(args, 0)}');
      case 'base64Encode':
        return helpers.base64EncodeText('${_arg(args, 0)}');
      case 'base64Decode':
        return helpers.base64DecodeText(
          '${_arg(args, 0)}',
          charset: _arg(args, 1)?.toString(),
        );
      case 'base64DecodeToByteArray':
        return helpers.base64ToBytes('${_arg(args, 0)}');
      case 'hexEncodeToString':
        return helpers.hexEncode('${_arg(args, 0)}');
      case 'hexDecodeToString':
        return helpers.hexDecode('${_arg(args, 0)}');
      case 'encodeURI':
        return helpers.encodeUriComponentText(
          '${_arg(args, 0)}',
          _arg(args, 1)?.toString(),
        );
      case 'strToBytes':
        final encoding = _arg(args, 1)?.toString();
        return encoding == null || encoding.isEmpty
            ? utf8.encode('${_arg(args, 0)}')
            : utf8.encode('${_arg(args, 0)}');
      case 'bytesToStr':
        final value = _arg(args, 0);
        final bytes = value is List
            ? <int>[for (final item in value) item is num ? item.toInt() : 0]
            : <int>[];
        return utf8.decode(bytes, allowMalformed: true);
      case 'digestHex':
        return helpers.digestHex('${_arg(args, 0)}', '${_arg(args, 1)}');
      case 'digestBase64Str':
        return helpers.digestBase64('${_arg(args, 0)}', '${_arg(args, 1)}');
      case 'hmacHex':
        return helpers.hmacHex(
          '${_arg(args, 0)}',
          '${_arg(args, 1)}',
          '${_arg(args, 2)}',
        );
      case 'hmacBase64':
        return helpers.hmacBase64(
          '${_arg(args, 0)}',
          '${_arg(args, 1)}',
          '${_arg(args, 2)}',
        );
      case 'crypto.decrypt':
        return helpers.symmetricDecryptText(
          '${_arg(args, 0)}',
          _arg(args, 1),
          _arg(args, 2),
          _arg(args, 3),
        );
      case 'crypto.decryptBytes':
        return helpers.symmetric(
          false,
          '${_arg(args, 0)}',
          _arg(args, 1),
          _arg(args, 2),
          _arg(args, 3),
        );
      case 'crypto.encryptBytes':
        return helpers.symmetric(
          true,
          '${_arg(args, 0)}',
          _arg(args, 1),
          _arg(args, 2),
          _arg(args, 3),
        );
      case 'crypto.encryptBase64':
        return helpers.symmetricEncryptBase64(
          '${_arg(args, 0)}',
          _arg(args, 1),
          _arg(args, 2),
          _arg(args, 3),
        );
      case 'crypto.encryptHex':
        return helpers.symmetricEncryptHex(
          '${_arg(args, 0)}',
          _arg(args, 1),
          _arg(args, 2),
          _arg(args, 3),
        );

      case 'timeFormat':
        final time = _intArg(args, 0);
        return helpers.formatTime(DateTime.fromMillisecondsSinceEpoch(time));
      case 'timeFormatUTC':
        final time = _intArg(args, 0);
        return helpers.formatTimeUtc(
          DateTime.fromMillisecondsSinceEpoch(time),
          '${_arg(args, 1)}',
          _intArg(args, 2),
        );
      case 't2s':
        return '${_arg(args, 0)}';
      case 's2t':
        return '${_arg(args, 0)}';
      case 'toNumChapter':
        return helpers.toNumChapter('${_arg(args, 0)}');
      case 'randomUUID':
        return helpers.randomUuid();
      case 'getWebViewUA':
        return _userAgent;
      case 'log':
        logs.add('${_arg(args, 0)}');
        return null;

      case 'dom.text':
        final parsed = html_parser.parseFragment('${_arg(args, 0)}');
        final root = parsed.nodes.whereType<Element>().firstOrNull;
        return root == null ? '' : jsoupText(root);
      case 'dom.ownText':
        final parsed = html_parser.parseFragment('${_arg(args, 0)}');
        final root = parsed.nodes.whereType<Element>().firstOrNull;
        return root == null ? '' : jsoupOwnText(root);
      case 'dom.html':
        final parsed = html_parser.parseFragment('${_arg(args, 0)}');
        return parsed.nodes
            .map((node) => node is Element ? node.outerHtml : node.text ?? '')
            .join();
      case 'dom.attr':
        final parsed = html_parser.parseFragment('${_arg(args, 0)}');
        final root = parsed.nodes.whereType<Element>().firstOrNull;
        return root?.attributes['${_arg(args, 1)}'] ?? '';
      case 'dom.select':
        final analyzer = JsoupAnalyzer(_coerceContent(_arg(args, 0)) ?? '');
        return <String>[
          for (final element in analyzer.getElements('${_arg(args, 1)}'))
            element.outerHtml,
        ];

      default:
        logs.add('unsupported java method: $name');
        return null;
    }
  }

  Object? _ajax(String url) {
    if (url.isEmpty) return '';
    final key = _cacheKey('GET', url, null);
    final body = _bodyCache[key];
    if (body != null) return body;
    return <String, Object?>{
      '__mimaofetch': <Map<String, Object?>>[
        <String, Object?>{'kind': 'body', 'url': url, 'method': 'GET'},
      ],
    };
  }

  Object? _ajaxAll(List<Object?> urls) {
    final specs = <Map<String, Object?>>[];
    final result = <Object?>[];
    for (final url in urls) {
      final value = '$url';
      final key = _cacheKey('GET', value, null);
      final body = _bodyCache[key];
      if (body == null) {
        specs.add(<String, Object?>{
          'kind': 'body',
          'url': value,
          'method': 'GET',
        });
      } else {
        result.add(<String, Object?>{'body': body, 'url': value, 'code': 200});
      }
    }
    if (specs.isNotEmpty) {
      return <String, Object?>{'__mimaofetch': specs};
    }
    return result;
  }

  Object? _connect(
    String url,
    String headers,
    String? timeout, {
    String method = 'GET',
    String? body,
  }) {
    if (url.isEmpty) {
      return <String, Object?>{'body': '', 'url': url, 'code': 0};
    }
    final headerMap = lenientJsonObject(headers) ?? const <String, Object?>{};
    final key = _cacheKey(method, url, body);
    final cached = _responseCache[key];
    if (cached != null) return cached;
    return <String, Object?>{
      '__mimaofetch': <Map<String, Object?>>[
        <String, Object?>{
          'kind': 'response',
          'url': url,
          'method': method,
          'headers': headerMap,
          'body': body,
        },
      ],
    };
  }

  Object _withContent(
    RuleJsContext? context,
    Object? content,
    Object Function(RuleCallbacks callbacks) action,
  ) {
    final callbacks = context?.callbacks;
    if (callbacks == null) return '';
    if (content == null) return action(callbacks);
    final previous = callbacks.getContent();
    callbacks.setContent(_coerceContent(content));
    try {
      return action(callbacks);
    } finally {
      callbacks.setContent(previous);
    }
  }

  Object? _coerceContent(Object? content) {
    if (content is Map && content.containsKey('__html')) {
      return '${content['__html']}';
    }
    return content;
  }

  String _cookieGet(String? tag, String? key) {
    final values =
        _cookies[tag ?? _source?.url ?? ''] ?? const <String, String>{};
    if (key != null && key.isNotEmpty) return values[key] ?? '';
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  void _cookieSet(String? tag, String value) {
    final target = _cookies.putIfAbsent(
      tag ?? _source?.url ?? '',
      () => <String, String>{},
    );
    for (final pair in value.split(';')) {
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      target[pair.substring(0, index).trim()] = pair
          .substring(index + 1)
          .trim();
    }
  }

  Object? _arg(List<dynamic> args, int index) =>
      index < args.length ? args[index] : null;

  int _intArg(List<dynamic> args, int index) {
    final value = _arg(args, index);
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  List<Object?> _listOf(Object? value) {
    if (value is List) return List<Object?>.from(value);
    return const <Object?>[];
  }
}
