// AnalyzeUrl 单测：{{}}/<> 展开、选项、POST 编码、bodyJs 与相对 URL。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/engine/analyze_url.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class _FakeTransport implements NovelHttpTransport {
  _FakeTransport(this.body);

  final String body;
  NovelHttpRequest? request;
  bool closed = false;

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest value) async {
    request = value;
    return NovelHttpResponse(
      url: value.url,
      statusCode: 200,
      body: body,
      charset: value.charset,
    );
  }

  @override
  void close() => closed = true;
}

Future<Object?> _runner(String code, RuleJsContext context) async {
  final trimmed = code.trim();
  if (trimmed == 'key') return context.key;
  if (trimmed == 'page') return context.page;
  if (trimmed == '1+1') return 2;
  if (trimmed.contains('baseUrl')) return '${context.baseUrl}/s';
  return null;
}

NovelBookSource _source({String header = ''}) => NovelBookSource(
  key: 'k1',
  name: '测试源',
  url: 'https://example.com',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{
    'bookSourceUrl': 'https://example.com',
    if (header.isNotEmpty) 'header': header,
  },
);

void main() {
  test('{{key}}/{{page}} 插值与 query 编码', () async {
    final transport = _FakeTransport('<html>ok</html>');
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl: 'https://example.com/search?q={{key}}&p={{page}}',
      baseUrl: 'https://example.com',
      transport: transport,
      source: _source(),
      jsRunner: _runner,
      key: '张三',
      page: 2,
    );
    expect(
      analyze.resolvedUrl,
      'https://example.com/search?q=%E5%BC%A0%E4%B8%89&p=2',
    );
  });

  test('<1,2,3> 页占位选当前页，越界取末页', () async {
    final transport = _FakeTransport('ok');
    final p2 = await AnalyzeUrl.resolve(
      ruleUrl: 'https://example.com/list_<1,2,3>.html',
      baseUrl: 'https://example.com',
      transport: transport,
      page: 2,
    );
    expect(p2.resolvedUrl, 'https://example.com/list_2.html');
    final p9 = await AnalyzeUrl.resolve(
      ruleUrl: 'https://example.com/list_<1,2,3>.html',
      baseUrl: 'https://example.com',
      transport: transport,
      page: 9,
    );
    expect(p9.resolvedUrl, 'https://example.com/list_3.html');
  });

  test('POST 选项：method/body/charset/headers', () async {
    final transport = _FakeTransport('{"code":0}');
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl:
          'https://example.com/api,{ "method":"POST", '
          '"charset":"gbk", "body":"kw=中文&page=1", '
          '"headers":{"X-Test":"1"} }',
      baseUrl: 'https://example.com',
      transport: transport,
    );
    expect(analyze.method, 'POST');
    expect(analyze.requestUrl, 'https://example.com/api');
    expect(analyze.headers['X-Test'], '1');
    expect(analyze.charset, 'gbk');
    final response = await analyze.fetch();
    expect(response.statusCode, 200);
    // GBK 的“中文”是 D6D0 CEC4；URLEncoder 空格用 +。
    expect(transport.request?.body, 'kw=%D6%D0%CE%C4&page=1');
  });

  test('@js: 改写 URL', () async {
    final transport = _FakeTransport('ok');
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl: '@js:baseUrl + "/s"',
      baseUrl: 'https://example.com',
      transport: transport,
      jsRunner: _runner,
    );
    expect(analyze.resolvedUrl, 'https://example.com/s');
  });

  test('@js: 尾部 ##说明 不进 JS（避免 private name 语法错）', () async {
    final transport = _FakeTransport('ok');
    final scripts = <String>[];
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl: '@js:baseUrl + "/s"##手机地址：https://m.example.com',
      baseUrl: 'https://example.com',
      transport: transport,
      jsRunner: (code, context) async {
        scripts.add(code);
        return _runner(code, context);
      },
    );
    expect(analyze.resolvedUrl, 'https://example.com/s');
    expect(scripts, hasLength(1));
    expect(scripts.single, 'baseUrl + "/s"');
    expect(scripts.single, isNot(contains('##')));
  });

  test('bodyJs 二次处理响应体', () async {
    final transport = _FakeTransport('raw');
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl:
          'https://example.com/api,{"method":"GET","bodyJs":"result + \'-done\'"}',
      baseUrl: 'https://example.com',
      transport: transport,
      jsRunner: (code, context) async {
        if (code.contains('-done')) return '${context.result}-done';
        return null;
      },
    );
    final response = await analyze.fetch();
    expect(response.body, 'raw-done');
  });

  test('源请求头 + 相对 URL', () async {
    final transport = _FakeTransport('ok');
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl: '/search?q=1',
      baseUrl: 'https://example.com',
      transport: transport,
      source: _source(header: '{"User-Agent":"UA","Referer":"https://ref"}'),
    );
    expect(analyze.resolvedUrl, 'https://example.com/search?q=1');
    expect(analyze.headers['User-Agent'], 'UA');
    expect(analyze.headers['Referer'], 'https://ref');
  });
}
