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
  final List<Future<void>> _pendingCookieWrites = <Future<void>>[];
  Map<String, String> _bookVariables = <String, String>{};
  String _sourceVariable = '';
  RuleJsContext? _currentContext;
  final List<String> logs = <String>[];

  // 整段重放副作用隔离：一段顶层脚本的多次重放视为同一"代"（epoch）。
  // 每个副作用调用（java.put/log/变量写入等）按调用序号去重：第 i 个副作用
  // 在第一次执行时真正落地并记入 _appliedSideEffects；重放时同序号的副作用
  // 被跳过，网络调用之后新出现的副作用才继续落地。这样既保留脚本语义，
  // 又不会把 java.put/log/变量写入重复执行。
  /// 已真正落地到外部世界的副作用高水位（跨同一次脚本的重放保留）。
  int _committedSideEffects = 0;

  /// 当前这一次重放内部的副作用调用序号（每次重放从 0 重新计数）。
  int _sideEffectCursor = 0;

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
    // 新的一段顶层脚本：重开时间/随机数的钉住窗口，让同一段脚本的多次
    // 网络预取重放拿到稳定的签名素材，但不同脚本之间互不影响。
    JSRef.freeRecursive(_engine.evaluate('__resetPins()'));
    _committedSideEffects = 0;
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
        // 每次重放内部副作用序号从 0 重数；已提交的高水位跨重放保留。
        _sideEffectCursor = 0;
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

  /// 加载书源 `jsLib`（全局函数库）。失败时记录日志并向上抛出，
  /// 由调用方（引擎）决定是否回滚已加载标记、下一轮重试（不阻断主流程）。
  Future<void> loadLibrary(String code) async {
    if (code.trim().isEmpty || _closed) return;
    await _ensureInitialized();
    try {
      JSRef.freeRecursive(_engine.evaluate(code, name: '<legado-js-lib>'));
    } on Object catch (error) {
      logs.add('jsLib 加载失败：$error');
      rethrow;
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
    // FlutterQjs.close() 不关 port，而 dispatch() 是 `await for (port)` 的
    // 无限循环；不关 port 每 dispose 一个宿主就泄漏一个常驻异步循环。
    _engine.port.close();
  }

  // ---------------------------------------------------------------------------
  // 绑定与结果

  void _applyBindings(RuleJsContext context) {
    final sourceInfo = _json(context.sourceInfo);
    final bookInfo = _json(context.bookInfo);
    final chapterInfo = _json(context.chapterInfo);
    // 额外变量（如 tocFormatJs 的 1 基 index / gInt）注入为全局，
    // 让 legado 的 formatJs 能读到 `index` / `gInt`。
    final extra = StringBuffer();
    for (final entry in context.variables.entries) {
      if (entry.key == 'gInt' || entry.key == 'index') {
        final value = int.tryParse(entry.value) ?? 0;
        extra.write('globalThis.${entry.key} = $value;');
      }
    }
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
        'globalThis.fromBookInfo = false;'
        '$extra',
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

  /// 预取失败（5xx 或 ERROR: 错误串）不写缓存，下次重放会再抓一次——
  /// 和 Kotlin 一样"失败不入缓存"，避免一次网络抖动把空/错正文钉死。
  bool _isFailed(NovelHttpResponse response) =>
      response.statusCode >= 500 || response.body.startsWith('ERROR:');

  Future<void> _prefetch(List<Map<String, Object?>> specs) async {
    // cookie.setCookie 是同步桥；先把排队的写入 flush 到 HTTP CookieJar，
    // 再发请求，否则脚本刚写的登录态丢失。
    await _flushCookieWrites();
    for (final spec in specs) {
      final kind = '${spec['kind'] ?? 'body'}';
      final url = '${spec['url'] ?? ''}';
      if (url.isEmpty) continue;
      final key = _cacheKey('${spec['method'] ?? 'GET'}', url, spec['body']);
      if (kind == 'response') {
        if (_responseCache.containsKey(key)) continue;
        final response = await _request(spec, wantResponse: true);
        if (_isFailed(response)) {
          logs.add('响应预取失败，不缓存：$url');
          continue;
        }
        _responseCache[key] = <String, Object?>{
          'body': response.body,
          'url': response.url,
          'code': response.statusCode,
        };
      } else {
        if (_bodyCache.containsKey(key)) continue;
        final response = await _request(spec, wantResponse: false);
        if (_isFailed(response)) {
          logs.add('正文预取失败，不缓存：$url');
          continue;
        }
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
            NovelHttpRequest(
              url: analyze.resolvedUrl,
              method: 'HEAD',
              useCookieJar: _source?.enabledCookieJar ?? true,
              sourceKey: _source?.key,
            ),
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
          useCookieJar: _source?.enabledCookieJar ?? true,
          sourceKey: _source?.key,
        ),
      );
    } on Object catch (error) {
      // 和 Kotlin AnalyzeUrl 一致：失败返回错误栈字符串，绝不返回空串——
      // 空串会被 JS 当正常正文，还会被缓存成"永久空正文"。
      final message = 'ERROR: $error';
      logs.add('请求失败 $method $url: $message');
      return NovelHttpResponse(url: url, statusCode: 500, body: message);
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

  /// 副作用只在"第一次到达该调用序号"时真正执行；同一脚本的重放里，
  /// 已提交过的序号直接跳过，避免 java.put/log/变量写入被重复执行。
  /// 返回 true 表示本次应真正落地，false 表示是重放的重复调用。
  bool _commitOnce() {
    final index = _sideEffectCursor++;
    if (index < _committedSideEffects) return false;
    if (index == _committedSideEffects) {
      _committedSideEffects = index + 1;
      return true;
    }
    // index > 水位：本轮新出现的副作用，推进水位并落地。
    _committedSideEffects = index + 1;
    return true;
  }

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
        // Kotlin post(urlStr, body, headers, timeout?)：args[1] 是 body，
        // args[2] 是 headers，args[3] 才是 timeout——别把 body 当 timeout。
        return _connect(
          '${_arg(args, 0)}',
          _arg(args, 2).toString(),
          _arg(args, 3)?.toString(),
          method: 'POST',
          body: _arg(args, 1)?.toString(),
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
        if (_commitOnce()) {
          context?.callbacks.putRuleVariable(
            '${_arg(args, 0)}',
            '${_arg(args, 1)}',
          );
        }
        return _arg(args, 1);
      case 'get':
        return context?.callbacks.getRuleVariable('${_arg(args, 0)}') ?? '';

      case 'source.getVariable':
        return _sourceVariable;
      case 'source.setVariable':
        if (_commitOnce()) _sourceVariable = '${_arg(args, 0)}';
        return _sourceVariable;
      case 'book.getVariable':
        final key = _arg(args, 0)?.toString();
        if (key == null || key.isEmpty) return jsonEncode(_bookVariables);
        return _bookVariables[key] ?? '';
      case 'book.putVariable':
        if (_commitOnce()) {
          _bookVariables['${_arg(args, 0)}'] = '${_arg(args, 1)}';
          context?.callbacks.putRuleVariable(
            '${_arg(args, 0)}',
            '${_arg(args, 1)}',
          );
        }
        return _arg(args, 1);
      case 'book.setReverseToc':
        return null;

      case 'cookie.get':
        return _cookieGet(_arg(args, 0)?.toString(), _arg(args, 1)?.toString());
      case 'cookie.set':
        if (_commitOnce()) {
          _cookieSet(_arg(args, 0)?.toString(), '${_arg(args, 1)}');
        }
        return null;
      case 'cookie.remove':
        if (_commitOnce()) _cookies.remove(_arg(args, 0)?.toString());
        return null;

      case 'cache.get':
        return _memory[_arg(args, 0)?.toString() ?? ''];
      case 'cache.put':
        if (_commitOnce()) {
          _memory[_arg(args, 0)?.toString() ?? ''] = _arg(args, 1);
        }
        return null;
      case 'cache.remove':
        if (_commitOnce()) _memory.remove(_arg(args, 0)?.toString() ?? '');
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
      case 'crypto.rsaEncryptBase64':
        return helpers.rsaEncryptBase64('${_arg(args, 0)}', '${_arg(args, 1)}');
      case 'crypto.rsaSignBase64':
        return helpers.rsaSignBase64(
          '${_arg(args, 0)}',
          '${_arg(args, 1)}',
          '${_arg(args, 2)}',
        );
      case 'crypto.rsaVerifyBase64':
        return helpers.rsaVerifyBase64(
          '${_arg(args, 0)}',
          '${_arg(args, 1)}',
          '${_arg(args, 2)}',
          '${_arg(args, 3)}',
        );
      case 'crypto.rsaDecryptBase64':
        return helpers.rsaDecryptText('${_arg(args, 0)}', '${_arg(args, 1)}');
      case 'crypto.rsaDecryptBytes':
        return helpers.rsaDecryptBytes('${_arg(args, 0)}', '${_arg(args, 1)}');

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
        return helpers.toSimplified('${_arg(args, 0)}');
      case 's2t':
        return helpers.toTraditional('${_arg(args, 0)}');
      case 'toNumChapter':
        return helpers.toNumChapter('${_arg(args, 0)}');
      case 'randomUUID':
        return helpers.randomUuid();
      case 'getWebViewUA':
        return _userAgent;
      case 'log':
        if (_commitOnce()) logs.add('${_arg(args, 0)}');
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
    // 空串当 miss：历史缓存里若有失败留下的空正文，重抓一次即可自愈
    // （真实空响应的代价只是多抓一次，比永久空正文好）。
    if (body != null && body.isNotEmpty) return body;
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
      if (body == null || body.isEmpty) {
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
    // 失败响应不入缓存；万一有旧的错误串残留，也当 miss 重抓。
    if (cached != null && !'${cached['body'] ?? ''}'.startsWith('ERROR:')) {
      return cached;
    }
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
    // 同步桥无法 await：把写入排到异步侧，并在网络预取前 flush，
    // 让同源 ajax 真的带上脚本刚写的 Cookie。
    final sink = _transport;
    if (sink is! NovelCookieSink) return;
    final cookieSink = sink as NovelCookieSink;
    final url = tag ?? _source?.url ?? '';
    final write = cookieSink.setCookie(_source?.key, url, value).catchError((
      Object _,
    ) {
      logs.add('Cookie 写入失败：$url');
    });
    _pendingCookieWrites.add(write);
  }

  Future<void> _flushCookieWrites() async {
    if (_pendingCookieWrites.isEmpty) return;
    final pending = List<Future<void>>.from(_pendingCookieWrites);
    _pendingCookieWrites.clear();
    await Future.wait(pending, eagerError: false);
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
