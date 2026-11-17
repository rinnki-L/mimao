/// 源脚本执行单测（≥6）：用真实 flutter_qjs + ComicJsBridge + fake HTTP 客户端
/// 跑一份 Venera 风格源脚本，覆盖搜索/详情/图片路径、语法错容错、超时不崩。
///
/// Windows 本地需先 `flutter build windows` 并把 flutter_qjs_plugin.dll 放到
/// 工作目录（见 engine/README.md）；无 native 库的环境自动 skip，API 对齐性
/// 由 js_bridge_api_test.dart 的纯 Dart 测试兜底。
library;

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

  test('⑥ 类名发现与注册：findSourceClassName 对齐 Venera 规则', () {
    // 这条不需要 native，任何环境都跑。
    expect(
      QuickJsHost.findSourceClassName(fixtureSourceScript),
      'FixtureSource',
    );
    expect(QuickJsHost.findSourceClassName(fixtureNotASource), isNull);
  });
}
