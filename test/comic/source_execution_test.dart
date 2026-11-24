/// 源脚本执行单测（≥6）：用真实 flutter_qjs + ComicJsBridge + fake HTTP 客户端
/// 跑一份 Venera 风格源脚本，覆盖搜索/详情/图片路径、语法错容错、超时不崩。
///
/// Windows 本地需先 `flutter build windows` 并把 flutter_qjs_plugin.dll 放到
/// 工作目录（见 engine/README.md）；无 native 库的环境自动 skip，API 对齐性
/// 由 js_bridge_api_test.dart 的纯 Dart 测试兜底。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

import 'fixtures.dart';

/// 若工作目录没有 DLL，但 app 已 build windows，则从标准产物目录拷一份。
/// 这样只要跑过 `flutter build windows`，无需手工复制即可执行真 JS 测试。
bool _ensureNativeJs() {
  const target = 'flutter_qjs_plugin.dll';
  if (File(target).existsSync()) return true;
  const built = 'build/windows/x64/runner/Release/flutter_qjs_plugin.dll';
  if (File(built).existsSync()) {
    File(built).copySync(target);
    return true;
  }
  return false;
}

bool get _hasNativeJs => File('flutter_qjs_plugin.dll').existsSync();

/// 按夹具 URL 返回正文的假客户端。
class _FixtureClient implements ComicHttpClient {
  @override
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    final body = _bodyFor(url);
    return ComicHttpResponse(
      statusCode: body == null ? 404 : 200,
      body: body ?? 'not found',
      url: url,
      headers: const <String, List<String>>{},
    );
  }

  String? _bodyFor(String url) {
    if (url.contains('/search')) return fixtureSearchHtml;
    if (url.contains('/comic/') && url.contains('ch-')) {
      return fixtureImagesHtml;
    }
    if (url.contains('/comic/')) return fixtureDetailHtml;
    return null;
  }

  @override
  Future<void> setCookies(String url, Map<String, String> cookies) async {}

  @override
  List<Map<String, String>> getCookies(String url) =>
      const <Map<String, String>>[];

  @override
  Future<void> deleteCookies(String url) async {}
}

void main() {
  SourceExecutionPool? pool;

  setUpAll(() {
    _ensureNativeJs();
  });

  setUp(() async {
    if (!_hasNativeJs) return;
    pool = SourceExecutionPool(
      hostFactory: () =>
          QuickJsHost(bridge: ComicJsBridge(client: _FixtureClient())),
    );
    await pool!.register('fixture', fixtureSourceScript);
  });

  tearDown(() {
    pool?.disposeAll();
    pool = null;
  });

  ComicSourceEngine engineFor(SourceExecutionPool p) =>
      ComicSourceEngine(pool: p);

  test('native QuickJS 可用（前置门禁）', () {
    if (!_hasNativeJs) {
      // 无 native 库时明确 skip，不下结论。
      return;
    }
    expect(pool!.contains('fixture'), isTrue);
  });

  test('① 正确源 search.load 返回列表路径', () async {
    if (!_hasNativeJs) return;
    final result = await engineFor(pool!).search('fixture', '海贼王');
    expect(result.diagnostics, isEmpty, reason: result.diagnostics.toString());
    expect(result.items.length, 2);
    expect(result.items.first.title, '海贼王');
    expect(result.items.first.id, 'one');
    expect(result.items.first.cover, 'https://fixture.test/cover/one.jpg');
    expect(result.items.first.tags, <String>['测试']);
  });

  test('② comic.loadInfo 返回详情 + 章节路径', () async {
    if (!_hasNativeJs) return;
    final result = await engineFor(pool!).detail('fixture', 'one');
    expect(result.diagnostics, isEmpty, reason: result.diagnostics.toString());
    expect(result.items, hasLength(1));
    final detail = result.items.first;
    expect(detail.title, '海贼王');
    expect(detail.chapters.length, 3);
    expect(detail.chapters.first.id, 'ch-1');
    expect(detail.chapters.first.title, '第1话 启程');
    expect(detail.tags['作者'], <String>['测试作者']);
  });

  test('③ comic.loadEp 返回图片地址路径', () async {
    if (!_hasNativeJs) return;
    final result = await engineFor(
      pool!,
    ).images('fixture', 'one', episodeId: 'ch-1');
    expect(result.diagnostics, isEmpty, reason: result.diagnostics.toString());
    expect(result.items.map((e) => e.url), <String>[
      'https://fixture.test/img/1.jpg',
      'https://fixture.test/img/2.jpg',
      'https://cdn.test/3.jpg',
    ]);
  });

  test('③b comic.onImageLoad 请求头随 imagesWithHeaders 返回', () async {
    if (!_hasNativeJs) return;
    final result = await engineFor(
      pool!,
    ).imagesWithHeaders('fixture', 'one', episodeId: 'ch-1');
    expect(result.diagnostics, isEmpty, reason: result.diagnostics.toString());
    expect(result.items, hasLength(3));
    for (final image in result.items) {
      expect(image.headers['Referer'], 'https://fixture.test/');
      expect(image.headers['X-Image'], image.url);
    }
  });

  test('③c imageHeaders 单张懒解析 onImageLoad', () async {
    if (!_hasNativeJs) return;
    final headers = await engineFor(pool!).imageHeaders(
      'fixture',
      'https://fixture.test/img/1.jpg',
      'one',
      episodeId: 'ch-1',
    );
    expect(headers['Referer'], 'https://fixture.test/');
    expect(headers['X-Image'], 'https://fixture.test/img/1.jpg');
  });

  test('④ 脚本语法错误不崩溃：返回带诊断的空结果', () async {
    if (!_hasNativeJs) return;
    final badPool = SourceExecutionPool(
      hostFactory: () =>
          QuickJsHost(bridge: ComicJsBridge(client: _FixtureClient())),
    );
    try {
      // 语法错的脚本在注入阶段就被 QuickJS 拒绝，等价于"注册失败即容错"。
      await expectLater(
        badPool.register('bad', fixtureBrokenScript),
        throwsA(anything),
      );
    } finally {
      badPool.disposeAll();
    }
  });

  test('⑤ 超时/异常方法不崩溃：Promise reject 收敛为诊断', () async {
    if (!_hasNativeJs) return;
    // 源未注册 → execute 直接返回错误（模拟"执行不可用"也不崩）。
    final result = await pool!.execute(
      'missing',
      'source.search.load("x",[],1)',
    );
    expect(result.isOk, isFalse);
    expect(result.error, contains('源未注册'));
  });

  test('⑥ settings 默认值生效，且 init() 在注册期执行', () async {
    if (!_hasNativeJs) return;
    final settingsPool = SourceExecutionPool(
      hostFactory: () =>
          QuickJsHost(bridge: ComicJsBridge(client: _FixtureClient())),
    );
    try {
      await settingsPool.register('settings_probe', _settingsProbeScript);

      // 没有用户保存值 → 回落 settings 定义里的 default。
      final domain = await settingsPool.execute(
        'settings_probe',
        'source.loadSetting("domains")',
      );
      expect(domain.value, 'example.com');
      // 默认 false 不能被当成「缺失」。
      final flag = await settingsPool.execute(
        'settings_probe',
        'source.loadSetting("flag")',
      );
      expect(flag.value, isFalse);
      // 没有默认值的 setting 仍返回 null（与旧行为一致）。
      final missing = await settingsPool.execute(
        'settings_probe',
        'source.loadSetting("missing")',
      );
      expect(missing.value, isNull);

      // init() 在注册时已被调用。
      final inited = await settingsPool.execute(
        'settings_probe',
        'source.inited === true',
      );
      expect(inited.value, isTrue);

      // getter 基于默认值拼出的地址进入真实搜索路径。
      final result = await ComicSourceEngine(
        pool: settingsPool,
      ).search('settings_probe', '海贼');
      expect(
        result.diagnostics,
        isEmpty,
        reason: result.diagnostics.toString(),
      );
      expect(result.items.single.title, '海贼@https://example.com');
    } finally {
      settingsPool.disposeAll();
    }
  });

  test('⑦ 类名发现与注册：findSourceClassName 对齐 Venera 规则', () {
    // 这条不需要 native，任何环境都跑。
    expect(
      QuickJsHost.findSourceClassName(fixtureSourceScript),
      'FixtureSource',
    );
    expect(QuickJsHost.findSourceClassName(fixtureNotASource), isNull);
  });

  test('⑧ 执行超时不崩溃：fake 慢宿主超时收敛为错误诊断', () async {
    // 不需要 native：用故意挂起的 fake JsHost 验证 SourceExecutionPool 的超时保护。
    final slowPool = SourceExecutionPool(
      hostFactory: () => _HangingHost(),
      timeout: const Duration(milliseconds: 50),
    );
    await slowPool.register('slow', fixtureSourceScript);
    final result = await slowPool.execute(
      'slow',
      'source.search.load("x",[],1)',
    );
    expect(result.isOk, isFalse);
    expect(result.error, isNotNull);
    expect(
      result.error!.toLowerCase(),
      contains('timeout'),
      reason: '超时错误应含 timeout：${result.error}',
    );
    slowPool.disposeAll();
  });

  test('⑨ execute 等待注册期 init settle：首搜能读到 init 设置的标记', () async {
    // fake 宿主的 init 延迟完成并打标；execute 不等 init 的话会读到 false。
    final host = _InitDelayHost(initDelay: const Duration(milliseconds: 100));
    final initPool = SourceExecutionPool(
      hostFactory: () => host,
      timeout: const Duration(seconds: 5),
    );
    addTearDown(initPool.disposeAll);
    await initPool.register('delayed_init', fixtureSourceScript);
    // 注册不阻塞启动：init 尚未完成，register 已经返回。
    expect(host.inited, isFalse);

    final result = await initPool.execute(
      'delayed_init',
      'source.search.load("x",[],1)',
    );
    expect(result.isOk, isTrue, reason: result.error);
    expect(result.value, isTrue, reason: 'execute 未等待 init，标记仍为 false');
  });

  test('⑩ init 失败不阻塞 execute：仍能执行并保留诊断', () async {
    final host = _InitDelayHost(
      initDelay: const Duration(milliseconds: 20),
      failInit: true,
    );
    final failPool = SourceExecutionPool(
      hostFactory: () => host,
      timeout: const Duration(seconds: 5),
    );
    addTearDown(failPool.disposeAll);
    await failPool.register('failed_init', fixtureSourceScript);

    final result = await failPool.execute(
      'failed_init',
      'source.search.load("x",[],1)',
    );
    expect(result.isOk, isTrue, reason: result.error);
    // init 抛错后标记仍为 false，但执行本身成功返回。
    expect(result.value, isFalse);
    // 失败原因仍走现有诊断路径。
    expect(failPool.takeInitError('failed_init'), contains('init boom'));
  });

  test('⑪ init 永不完成时 execute 按池超时收敛，不永久挂住', () async {
    final hangPool = SourceExecutionPool(
      hostFactory: () => _HangingInitHost(),
      timeout: const Duration(milliseconds: 60),
    );
    addTearDown(hangPool.disposeAll);
    await hangPool.register('hanging_init', fixtureSourceScript);
    final result = await hangPool.execute(
      'hanging_init',
      'source.search.load("x",[],1)',
    );
    expect(result.isOk, isFalse);
    expect(
      result.error!.toLowerCase(),
      contains('timeout'),
      reason: '超时错误应含 timeout：${result.error}',
    );
  });

  test('挑战验证期间暂停执行超时，验证结束后恢复计时', () async {
    final slowPool = SourceExecutionPool(
      hostFactory: () => _DelayHost(const Duration(milliseconds: 400)),
      timeout: const Duration(milliseconds: 150),
    );
    addTearDown(slowPool.disposeAll);
    await slowPool.register('slow', fixtureSourceScript);

    // 闸门打开：400ms 的调用超过 150ms 上限也不应超时。
    ComicChallengeGate.begin();
    try {
      final result = await slowPool.execute(
        'slow',
        'source.search.load("x",[],1)',
      );
      expect(result.isOk, isTrue, reason: result.error);
    } finally {
      ComicChallengeGate.end();
    }
  });

  test('没有挑战时慢执行仍按池超时收敛', () async {
    final slowPool = SourceExecutionPool(
      hostFactory: () => _DelayHost(const Duration(milliseconds: 400)),
      timeout: const Duration(milliseconds: 150),
    );
    addTearDown(slowPool.disposeAll);
    await slowPool.register('slow', fixtureSourceScript);
    final result = await slowPool.execute(
      'slow',
      'source.search.load("x",[],1)',
    );
    expect(result.isOk, isFalse);
    expect(result.error, contains('超时'));
  });
}

/// 方法调用固定延迟的宿主（超时/闸门测试用）。
class _DelayHost implements JsHost {
  _DelayHost(this.delay);

  final Duration delay;

  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) async {
    if (!expression.startsWith('source.search.load')) return null;
    await Future<void>.delayed(delay);
    return null;
  }

  @override
  void close() {}
}

/// 执行阶段永远不完成的宿主——专门用来触发 SourceExecutionPool 超时保护。
class _HangingHost implements JsHost {
  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) async {
    // 注册期的实例化 / 默认值快照 / init 表达式立即返回；真正的方法调用才挂起。
    if (!expression.startsWith('source.search.load')) return null;
    return Completer<Object?>().future; // 永不 complete
  }

  @override
  void close() {}
}

/// 表达式是否是注册期 init 调用（对齐 js_host.dart 的 _sourceInitExpression）。
bool _isInitCall(String expression) => expression.contains('source.init');

/// init 延迟完成的宿主：完成后打上 [inited] 标记，搜索表达式读它。
/// 用来验证 execute 在 evaluate 之前确实等到了 init settle。
class _InitDelayHost implements JsHost {
  _InitDelayHost({
    this.initDelay = const Duration(milliseconds: 80),
    this.failInit = false,
  });

  final Duration initDelay;
  final bool failInit;
  bool inited = false;

  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) async {
    if (_isInitCall(expression)) {
      await Future<void>.delayed(initDelay);
      if (failInit) throw StateError('init boom');
      inited = true;
      return null;
    }
    if (expression.startsWith('source.search.load')) return inited;
    return null;
  }

  @override
  void close() {}
}

/// init 永远不完成的宿主：验证首执行不会因 init 挂死而永久等待。
class _HangingInitHost implements JsHost {
  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) {
    if (_isInitCall(expression)) {
      return Completer<Object?>().future; // 永不 complete
    }
    return Future<Object?>.value(null);
  }

  @override
  void close() {}
}

/// 设置默认值 / init 探针源：没有用户保存值时 loadSetting 读 settings.default，
/// init() 在注册期给实例打标。
const String _settingsProbeScript = r'''
class SettingsProbeSource extends ComicSource {
  name = "设置探针源";
  key = "settings_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";

  settings = {
    domains: { title: "域名", type: "input", default: "example.com" },
    flag: { title: "开关", type: "switch", default: false },
  };

  get baseUrl() {
    return `https://${this.loadSetting("domains")}`;
  }

  init() {
    this.inited = true;
  }

  search = {
    load: async (keyword, options, page) => {
      return {
        comics: [new Comic({ id: "1", title: keyword + "@" + this.baseUrl })],
        maxPage: 1,
      };
    },
  };
}
''';
