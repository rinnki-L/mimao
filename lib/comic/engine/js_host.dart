/// JS 宿主抽象 + flutter_qjs 实现 + 源脚本执行池。
///
/// [JsHost] 是"执行一段 JS 源脚本并调用其方法"的最小接口。真实实现
/// [QuickJsHost] 用 flutter_qjs（CyrilPeng fork）建 QuickJS runtime，注入
/// [comicInitJs] 与 `sendMessage` 桥；测试可用内存 fake 或（有 native 库时）
/// 直接用 [QuickJsHost] 跑真脚本。
library;

import 'dart:async';

import 'package:flutter_qjs/flutter_qjs.dart';

import '../request/challenge.dart';
import 'init_js.dart';
import 'js_bridge.dart';

/// 执行源脚本的最小宿主接口。
abstract interface class JsHost {
  /// 注入桥并执行源脚本文本。脚本里应定义 `class ... extends ComicSource`
  /// 并把实例挂到 `globalThis.source`；仓库社区源通常如此。
  Future<void> loadScript(String script);

  /// 执行一段 JS 表达式并返回 Dart 值（`source.search.load(...)` 等）。
  /// 支持返回 Promise —— 宿主会 await。
  Future<Object?> evaluate(String expression);

  /// 释放 native 资源。
  void close();
}

/// 基于 flutter_qjs 的真实宿主。
class QuickJsHost implements JsHost {
  QuickJsHost({ComicJsBridge? bridge})
    : _bridge = bridge ?? ComicJsBridge(),
      _engine = FlutterQjs(memoryLimit: 128 * 1024 * 1024);

  final ComicJsBridge _bridge;
  final FlutterQjs _engine;
  JSInvokable? _setGlobal;
  Future<void>? _dispatcher;
  bool _closed = false;

  /// 确保 runtime 已初始化：注册 `sendMessage`、注入 init.js。
  Future<void> ensureInitialized() async {
    if (_dispatcher != null) return;
    _dispatcher = _engine.dispatch();
    _setGlobal = _engine.evaluate(comicInitGlobalSetter) as JSInvokable;
    _setGlobal!(<dynamic>[
      'sendMessage',
      (dynamic message) {
        if (message is! Map) return null;
        final map = Map<dynamic, dynamic>.from(message);
        final (value, needsAsync) = _bridge.dispatchSync(map);
        // 只有 http/delay 返回 Future（QuickJS 会包装成 Promise）；
        // html/convert/cookie 等必须同步返回，否则源脚本的 DOM 查询会拿到 Promise。
        return needsAsync ? _bridge.dispatch(map) : value;
      },
    ]);
    _engine.evaluate(comicInitJs, name: '<comic-init>');
  }

  /// 找到脚本里 `class Xxx extends ComicSource` 的类名（Venera 同款规则），
  /// 供上层把实例挂到 `source` / `ComicSource.sources[key]`。
  static String? findSourceClassName(String script) => RegExp(
    r'^\s*class\s+([a-zA-Z_$][a-zA-Z0-9_$]*)\s+extends\s+ComicSource\b',
    multiLine: true,
  ).firstMatch(script.replaceFirst('\uFEFF', ''))?.group(1);

  @override
  Future<void> loadScript(String script) async {
    await ensureInitialized();
    // 脚本的顶层值是类定义/实例（含 JS 函数句柄）；释放 Dart 侧包装引用，
    // JS 侧实例仍由 globalThis/ComicSource.sources 持有，不影响调用。
    final result = _engine.evaluate(script, name: '<comic-source>');
    JSRef.freeRecursive(result);
  }

  @override
  Future<Object?> evaluate(String expression) async {
    await ensureInitialized();
    // QuickJS 的 evaluate 遇到 Promise 会返回 Future；普通值直接返回。
    final result = _engine.evaluate(expression, name: '<comic-call>');
    if (result is Future) return await result;
    return result;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _setGlobal?.free();
    _setGlobal = null;
    _engine.close();
  }
}

/// 源脚本执行池：隔离每个源的 QuickJS runtime，避免一个源的全局污染另一个。
///
/// 采用"懒创建 + 显式回收"策略：每个 key 一个 [JsHost]；[execute] 负责注入
/// 脚本（仅一次）并调用方法；[dispose] 关掉宿主。并发调用同一 key 时复用
/// 宿主，但 QuickJS 单线程语义下由调用方串行化（上层按源串行搜索即可）。
class SourceExecutionPool {
  SourceExecutionPool({
    JsHost Function()? hostFactory,
    this.timeout = const Duration(seconds: 30),
  }) : _hostFactory = hostFactory ?? (() => QuickJsHost());

  final JsHost Function() _hostFactory;

  /// 单次执行超时；超时收敛为 [SourceExecutionResult.error]，不抛给上层。
  final Duration timeout;
  final Map<String, _PooledSource> _sources = <String, _PooledSource>{};

  /// 注册期 `init()` 的失败原因（按源 key）。init 不阻塞注册，异步部分
  /// 失败时先记在这里，由上层（搜索/源管理）取走作为诊断，不静默吞掉。
  final Map<String, String> _initErrors = <String, String>{};

  /// 取走某源注册期 init 的失败原因（取走即清）；没有失败返回 null。
  String? takeInitError(String key) => _initErrors.remove(key);

  /// 注册（或覆盖）一个源脚本。
  ///
  /// 像 Venera 一样从脚本里找出 `class Xxx extends ComicSource`，实例化后挂到
  /// `source` 与 `ComicSource.sources[key]`，上层即可用 `source.search.load(...)`
  /// 等表达式调用。类名找不到时原样加载脚本（脚本自己挂 `source` 也支持）。
  ///
  /// 实例化后按 Venera 的顺序做两件事：先拍下 `source.settings` 的默认值快照
  /// （`loadSetting` 无用户存储值时回落到它），再调用可选 `init()`。顺序不能
  /// 反——个别源（如 copy_manga）会在 init 里改写 settings 定义，默认值必须
  /// 以注册期定义为准。
  ///
  /// `init()` **不 await**：app 启动期在 `runApp` 前注册全部源，等异步 init
  /// 的网络请求会把入口卡住；同步部分照常先执行，异步失败记入 [_initErrors]。
  Future<void> register(String key, String script) async {
    final previous = _sources.remove(key);
    previous?.host.close();
    _initErrors.remove(key);
    final host = _hostFactory();
    try {
      await host.loadScript(script);
      final className = QuickJsHost.findSourceClassName(script);
      Object? registered;
      if (className != null) {
        registered = await host.evaluate(
          'source = new $className(); source.key = ${_jsString(key)}; '
          'ComicSource.sources[${_jsString(key)}] = source;',
        );
      }
      // 默认值快照不改变脚本文本；脚本自挂 source 的路径同样适用。
      await host.evaluate(_captureSettingDefaultsExpression);
      _runInitThenRelease(host, key, registered);
    } catch (_) {
      // 脚本注入/实例化失败（语法错等）：关掉宿主再抛出，交给调用方容错。
      host.close();
      rethrow;
    }
    _sources[key] = _PooledSource(host: host, script: script);
  }

  /// 调 init 并在其**开始执行后**释放注册表达式的 Dart 侧包装。
  ///
  /// 不能在调用前释放：注册结果递归包含了实例方法的 JSRef，提前
  /// `freeRecursive` 会让 init() 抛 "JSValue released"。init 返回 Promise 时
  /// 等它 settle（成功或失败）再释放，避免异步 continuation 用到已释放句柄。
  void _runInitThenRelease(JsHost host, String key, Object? registered) {
    final Future<Object?> started;
    try {
      started = host.evaluate(_sourceInitExpression);
    } on Object catch (error) {
      _initErrors[key] = error.toString();
      JSRef.freeRecursive(registered);
      return;
    }
    unawaited(
      started
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace _) {
              _initErrors[key] = error.toString();
            },
          )
          .whenComplete(() {
            try {
              JSRef.freeRecursive(registered);
            } on Object {
              // 宿主已 close 时释放可能失败；进程内资源已随 runtime 回收。
            }
          }),
    );
  }

  /// 是否已注册。
  bool contains(String key) => _sources.containsKey(key);

  /// 当前已注册的全部源 key（对账用，如执行池与 store 的同步）。
  Iterable<String> get keys => _sources.keys;

  /// 在指定源的 runtime 里执行表达式。
  ///
  /// 源未注册、脚本抛错、Promise reject 都收敛为 [SourceExecutionResult]，
  /// 不向上抛——上层逐源容错。
  ///
  /// [timeout] 可覆盖池默认值。Cloudflare WebView 等用户操作的时间由
  /// [ComicChallengeGate] 排除在计时之外，所以这里不需要为挑战放大超时。
  Future<SourceExecutionResult> execute(
    String key,
    String expression, {
    Duration? timeout,
  }) async {
    final pooled = _sources[key];
    if (pooled == null) {
      return SourceExecutionResult.error('源未注册：$key');
    }
    try {
      final value = await _withIdleTimeout(
        pooled.host.evaluate(expression),
        timeout ?? this.timeout,
      );
      return SourceExecutionResult(value: value);
    } catch (error) {
      return SourceExecutionResult.error(error.toString());
    }
  }

  /// 带「空闲计时」的超时：挑战验证页打开期间（[ComicChallengeGate.active]）
  /// 暂停累计，用户操作多久都不算超时；其余时间照常按 [limit] 计时。
  Future<T> _withIdleTimeout<T>(Future<T> future, Duration limit) {
    final completer = Completer<T>();
    var waited = Duration.zero;
    const tick = Duration(milliseconds: 250);
    late final Timer timer;
    void finish(void Function() complete) {
      if (completer.isCompleted) return;
      timer.cancel();
      complete();
    }

    timer = Timer.periodic(tick, (_) {
      if (completer.isCompleted) {
        timer.cancel();
        return;
      }
      if (ComicChallengeGate.active) return;
      waited += tick;
      if (waited >= limit) {
        timer.cancel();
        completer.completeError(TimeoutException('源执行超时（timeout $limit）'));
      }
    });
    future.then(
      (value) => finish(() => completer.complete(value)),
      onError: (Object error, StackTrace stack) =>
          finish(() => completer.completeError(error, stack)),
    );
    return completer.future;
  }

  /// 释放一个源；返回是否确实释放了。
  bool dispose(String key) {
    final pooled = _sources.remove(key);
    if (pooled == null) return false;
    pooled.host.close();
    return true;
  }

  /// 释放全部源。
  void disposeAll() {
    for (final key in _sources.keys.toList()) {
      dispose(key);
    }
  }
}

/// 一次源脚本执行的结果（成功值或错误诊断）。
class SourceExecutionResult {
  const SourceExecutionResult({this.value, this.error});

  final Object? value;
  final String? error;

  bool get isOk => error == null;

  factory SourceExecutionResult.error(String message) =>
      SourceExecutionResult(error: message);

  @override
  String toString() =>
      isOk ? 'SourceExecutionResult(ok)' : 'SourceExecutionResult($error)';
}

class _PooledSource {
  const _PooledSource({required this.host, required this.script});

  final JsHost host;
  final String script;
}

/// 把 `source.settings` 的 `default` 拍成 `__sourceSettingDefaults` 快照。
/// 只取对象定义（`{title, type, default}`）里的 `default`，没有默认值的
/// setting 不写入——`loadSetting` 会返回 null，与旧行为一致。
const String _captureSettingDefaultsExpression = '''
(() => {
  const defaults = {};
  const settings = (typeof source !== 'undefined' && source) ? source.settings : null;
  if (settings && typeof settings === 'object') {
    for (const key of Object.keys(settings)) {
      const definition = settings[key];
      if (definition && typeof definition === 'object' &&
          Object.prototype.hasOwnProperty.call(definition, 'default')) {
        defaults[key] = definition.default;
      }
    }
  }
  __sourceSettingDefaults = defaults;
})()
''';

/// 调用源脚本的可选 `init()`；同步返回值忽略，返回 Promise 时等它完成。
/// 与 Venera `initializeRuntime()` 的表达式一致（含 init 不存在的兼容）。
const String _sourceInitExpression = '''
(() => {
  if (typeof source === 'undefined' || !source || typeof source.init !== 'function') {
    return undefined;
  }
  const result = source.init();
  return result && typeof result.then === 'function'
      ? result.then(() => undefined)
      : undefined;
})()
''';

/// 把 Dart 字符串序列化成安全的 JS 字符串字面量。
String _jsString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
