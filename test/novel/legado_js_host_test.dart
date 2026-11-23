// 书源 JS 宿主单测：真 QuickJS + 假传输，覆盖 Rhino 兼容 API 与网络重放。
//
// native 就绪探测与 CI 严格门统一走 js_native_guard.dart：无 native 库默认 skip，
// CI 置 MIMAO_REQUIRE_NATIVE_JS=1 后拿不到库直接 fail，杜绝假绿。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/js/legado_js_host.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

import 'js_native_guard.dart';

class _FakeTransport implements NovelHttpTransport {
  final List<String> requested = <String>[];

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    requested.add(request.url);
    if (request.url.contains('/api')) {
      return NovelHttpResponse(
        url: request.url,
        statusCode: 200,
        body: '{"code":0,"data":{"name":"远端书名"}}',
      );
    }
    return NovelHttpResponse(
      url: request.url,
      statusCode: 200,
      body: '<html><h1>远端标题</h1><a href="/x">链接</a></html>',
    );
  }

  @override
  void close() {}
}

NovelBookSource _source() => NovelBookSource(
  key: 'k1',
  name: '测试源',
  url: 'https://example.com',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{'bookSourceUrl': 'https://example.com'},
);

void main() {
  if (!hasNativeQuickJs()) {
    if (requireNativeQuickJs) {
      test('CI 缺少 QuickJS native 库——JS 宿主测试必须真跑，不允许 skip', () {
        fail(missingNativeMessage);
      });
      return;
    }
    test('skip：缺少 native QuickJS 库（本地运行无需先编译）', () {}, skip: skipReason());
    return;
  }

  late _FakeTransport transport;
  late LegadoJsHost host;
  late LegadoRuleAnalyzer analyzer;
  late RuleJsContext context;

  setUp(() {
    transport = _FakeTransport();
    host = LegadoJsHost(transport: transport, source: _source());
    analyzer = LegadoRuleAnalyzer(
      content: '<div class="book"><span class="name">本地书名</span></div>',
      baseUrl: 'https://example.com',
      key: '关键词',
      page: 2,
      jsRunner: host.evaluate,
      sourceInfo: <String, String>{
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': '测试源',
      },
      bookInfo: <String, String>{
        'name': '书',
        'author': '作者',
        'bookUrl': 'https://example.com/book/1',
      },
    );
    context = RuleJsContext(
      callbacks: analyzer,
      result: 'https://example.com',
      baseUrl: 'https://example.com',
      bookName: '书',
      chapterTitle: '第一章',
      key: '关键词',
      page: 2,
      sourceInfo: <String, String>{
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': '测试源',
      },
      bookInfo: <String, String>{
        'name': '书',
        'author': '作者',
        'bookUrl': 'https://example.com/book/1',
      },
    );
  });

  tearDown(() => host.dispose());

  test('基础表达式与 result/key/page/source/book', () async {
    expect(await host.evaluate('1+1', context), 2);
    expect(await host.evaluate('key', context), '关键词');
    expect(await host.evaluate('page', context), 2);
    expect(
      await host.evaluate('source.getKey()', context),
      'https://example.com',
    );
    expect(await host.evaluate('book.name', context), '书');
    expect(await host.evaluate('title', context), '第一章');
    expect(await host.evaluate('result', context), 'https://example.com');
  });

  test('md5 / base64 / hex / encodeURI', () async {
    expect(
      await host.evaluate('java.md5Encode("abc")', context),
      '900150983cd24fb0d6963f7d28e17f72',
    );
    expect(await host.evaluate('java.base64Encode("中文")', context), '5Lit5paH');
    expect(await host.evaluate('java.base64Decode("5Lit5paH")', context), '中文');
    expect(
      await host.evaluate('java.hexEncodeToString("中")', context),
      'e4b8ad',
    );
    expect(await host.evaluate('java.encodeURI("a b")', context), 'a+b');
  });

  test('规则回调：getString / setContent / put-get', () async {
    expect(
      await host.evaluate('java.getString("class.name@text")', context),
      '本地书名',
    );
    expect(
      await host.evaluate('java.put("k","v"); java.get("k")', context),
      'v',
    );
    expect(
      await host.evaluate(
        'java.getStringList("class.name@text").length',
        context,
      ),
      1,
    );
    expect(
      await host.evaluate(
        'java.setContent("<b>新内容</b>"); java.getString("b@text")',
        context,
      ),
      '新内容',
    );
  });

  test('java.ajax 预取重放 + setContent', () async {
    expect(transport.requested, isEmpty);
    final value = await host.evaluate(
      'java.setContent(java.ajax("https://example.com/page")); '
      'java.getString("h1@text")',
      context,
    );
    expect(value, '远端标题');
    expect(transport.requested, contains('https://example.com/page'));
  });

  test('java.ajax 返回 JSON 时按字符串处理', () async {
    expect(
      await host.evaluate('java.ajax("https://example.com/api")', context),
      '{"code":0,"data":{"name":"远端书名"}}',
    );
  });

  test('java.connect 返回响应对象', () async {
    final value = await host.evaluate(
      'java.connect("https://example.com/page").body',
      context,
    );
    expect(value, contains('远端标题'));
  });

  test('cookie / cache 内存读写', () async {
    expect(
      await host.evaluate(
        'cookie.setCookie("t","a=1; b=2"); cookie.getKey("t","b")',
        context,
      ),
      '2',
    );
    expect(
      await host.evaluate(
        'cache.putMemory("m","v"); cache.getFromMemory("m")',
        context,
      ),
      'v',
    );
  });

  test('时间格式化与中文数字', () async {
    expect(
      await host.evaluate('java.timeFormat(0)', context),
      contains('1970'),
    );
    expect(
      await host.evaluate('java.toNumChapter("第一百二十三章")', context),
      '第123章',
    );
  });
}
