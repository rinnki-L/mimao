/// js_bridge API 对齐性的"真刀"验证：跑一份**真实社区源脚本**
/// （bilimanga.js，来自 weihanlong267-spec/Venera-Next-sources），
/// 用假 HTTP 客户端喂 HTML，断言它能解析出搜索列表与详情。
///
/// 与自写夹具不同，这份源是社区维护、我们一字未改的规则数据：它用到
/// loadSetting / new Map / String.replace / Comic / ComicDetails / Network.get /
/// HtmlDocument.querySelectorAll 等真实 Venera API，能跑通即证明 API 对齐。
/// Windows 有 native 库时执行真 QuickJS（自举见 source_execution_test），
/// 其它环境 skip（纯 Dart 分派对齐由 js_bridge_api_test.dart 覆盖）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

import 'fixtures.dart';

bool get _hasNativeJs => _NativeHelper.ensure();

class _NativeHelper {
  static bool ensure() {
    const target = 'flutter_qjs_plugin.dll';
    if (File(target).existsSync()) return true;
    const built = 'build/windows/x64/runner/Release/flutter_qjs_plugin.dll';
    if (File(built).existsSync()) {
      File(built).copySync(target);
      return true;
    }
    return false;
  }
}

/// 按 bilimanga 的选择器结构返回页面。
class _BiliClient implements ComicHttpClient {
  static const searchPage = '''
    <div class="comic-list">
      <li><a href="/comic/12345.html"><img src="/cover/1.jpg"/>
        <div class="title">间谍过家家</div><div class="author">远藤达哉</div>
        <div class="update">最新话：第10话</div></a></li>
      <li><a href="/comic/67890.html"><img data-src="/cover/2.jpg"/>
        <h3 class="title">葬送的芙莉莲</h3><div class="book-author">山田钟人</div></a></li>
    </div>
  ''';

  static const detailPage = '''
    <h1 class="book-title">间谍过家家</h1>
    <img class="book-cover" src="/cover/1.jpg"/>
    <div class="book-author">远藤达哉</div>
    <div class="book-intro">间谍与家庭</div>
    <div id="chapter-list">
      <a href="/comic/12345/1.html">第1话</a>
      <a href="/comic/12345/2.html">第2话</a>
    </div>
  ''';

  static const epPage = '''
    <div class="chapter-content">
      <img data-src="/img/1.jpg"/><img data-original="/img/2.jpg"/>
    </div>
  ''';

  @override
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    final body =
        url.contains('/comic/') &&
            url.contains('.html') &&
            !url.endsWith('.html')
        ? epPage
        : url.contains('/comic/')
        ? detailPage
        : url.contains('/search/')
        ? searchPage
        : '';
    return ComicHttpResponse(statusCode: 200, body: body, url: url);
  }

  @override
  Future<void> setCookies(String url, Map<String, String> cookies) async {}

  @override
  List<Map<String, String>> getCookies(String url) => const [];

  @override
  Future<void> deleteCookies(String url) async {}
}

void main() {
  SourceExecutionPool? pool;

  setUpAll(() {
    _hasNativeJs;
  });

  setUp(() async {
    if (!_hasNativeJs) return;
    // loadSetting("domains") 需返回值；真实源用它拼 baseUrl。
    final bridge = ComicJsBridge(client: _BiliClient())
      ..loadSetting = (key, settingKey) => 'https://www.bilimanga.net';
    pool = SourceExecutionPool(hostFactory: () => QuickJsHost(bridge: bridge));
    await pool!.register('bilimanga', realBilimangaSource);
  });

  tearDown(() {
    pool?.disposeAll();
    pool = null;
  });

  test('真实社区源 bilimanga.js：search.load 解析出列表', () async {
    if (!_hasNativeJs) return;
    final result = await ComicSourceEngine(
      pool: pool!,
    ).search('bilimanga', '间谍');
    expect(result.diagnostics, isEmpty, reason: result.diagnostics.toString());
    expect(result.items.length, 2);
    expect(result.items.first.title, '间谍过家家');
    expect(result.items.first.id, '12345');
    expect(result.items.first.subtitle, '远藤达哉');
    expect(result.items.first.cover, 'https://www.bilimanga.net/cover/1.jpg');
  });

  test('真实社区源 bilimanga.js：comic.loadInfo 解析出详情（含 new Map 章节）', () async {
    if (!_hasNativeJs) return;
    final result = await ComicSourceEngine(
      pool: pool!,
    ).detail('bilimanga', '12345');
    expect(result.diagnostics, isEmpty, reason: result.diagnostics.toString());
    expect(result.items, hasLength(1));
    final detail = result.items.first;
    expect(detail.title, '间谍过家家');
    expect(detail.chapters.length, 2);
    expect(detail.chapters.first.title, '第1话');
    expect(detail.tags['作者'], <String>['远藤达哉']);
  });
}
