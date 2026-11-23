// Cookie 隔离回归：enabledCookieJar:false 不读写 jar，按 sourceKey 分流。
//
// 请求级断言用假传输；拦截器行为用真实 Dio + 假 HttpClientAdapter 验证，离线。
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/engine/analyze_url.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class _FakeTransport implements NovelHttpTransport {
  NovelHttpRequest? request;

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest value) async {
    request = value;
    return NovelHttpResponse(url: value.url, statusCode: 200, body: 'ok');
  }

  @override
  void close() {}
}

Future<Object?> _noopRunner(String code, RuleJsContext context) async => null;

NovelBookSource _source({required bool enabledCookieJar}) => NovelBookSource(
  key: 'cookie-src',
  name: 'Cookie 测试源',
  url: 'https://example.com',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{
    'bookSourceUrl': 'https://example.com',
    'enabledCookieJar': enabledCookieJar,
  },
);

/// 假 dio 适配器：记录请求头，按序返回 set-cookie / 空响应。
class _RecordingAdapter implements HttpClientAdapter {
  final List<Map<String, String>> seenHeaders = <Map<String, String>>[];
  int _call = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seenHeaders.add(Map<String, String>.from(options.headers));
    final headers = <String, List<String>>{};
    if (_call++ == 0) {
      headers['set-cookie'] = <String>['sid=abc; Path=/'];
    }
    return ResponseBody.fromString(
      'ok',
      200,
      headers: <String, List<String>>{
        'content-type': <String>['text/html; charset=utf-8'],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('NovelHttpRequest 携带 useCookieJar 与 sourceKey', () {
    final disabled = NovelHttpRequest(
      url: 'https://example.com',
      useCookieJar: false,
      sourceKey: 'src-a',
    );
    expect(disabled.useCookieJar, isFalse);
    expect(disabled.sourceKey, 'src-a');
    final defaults = NovelHttpRequest(url: 'https://example.com');
    expect(defaults.useCookieJar, isTrue);
    expect(defaults.sourceKey, isNull);
  });

  test('AnalyzeUrl.fetch 传递 enabledCookieJar:false 与 source.key', () async {
    final transport = _FakeTransport();
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl: 'https://example.com/chapter',
      baseUrl: 'https://example.com',
      transport: transport,
      source: _source(enabledCookieJar: false),
      jsRunner: _noopRunner,
    );
    await analyze.fetch();

    final request = transport.request!;
    expect(request.useCookieJar, isFalse);
    expect(request.sourceKey, 'cookie-src');
  });

  test('AnalyzeUrl.fetch 默认启用 CookieJar', () async {
    final transport = _FakeTransport();
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl: 'https://example.com/chapter',
      baseUrl: 'https://example.com',
      transport: transport,
      source: _source(enabledCookieJar: true),
      jsRunner: _noopRunner,
    );
    await analyze.fetch();
    expect(transport.request!.useCookieJar, isTrue);
  });

  test('拦截器：useCookieJar:false 不读也不写 CookieJar', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(responseType: ResponseType.bytes));
    dio.httpClientAdapter = adapter;
    final client = DioNovelHttpTransport(dio: dio);

    // 第一次请求 opt out，即便响应带 set-cookie 也不入 jar。
    await client.send(
      NovelHttpRequest(url: 'https://example.com/a', useCookieJar: false),
    );
    // 第二次请求 opt out，不应看到 Cookie 头。
    await client.send(
      NovelHttpRequest(url: 'https://example.com/a', useCookieJar: false),
    );
    expect(adapter.seenHeaders[1].containsKey('Cookie'), isFalse);

    // 第三次请求 opt in，jar 仍是空的，不应看到 Cookie 头。
    await client.send(NovelHttpRequest(url: 'https://example.com/a'));
    expect(adapter.seenHeaders[2].containsKey('Cookie'), isFalse);
    client.close();
  });

  test('拦截器：按 sourceKey 隔离 CookieJar，同源不同源不串登录态', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(responseType: ResponseType.bytes));
    dio.httpClientAdapter = adapter;
    final client = DioNovelHttpTransport(dio: dio);

    // 源 A opt in 拿到 sid。
    await client.send(
      NovelHttpRequest(url: 'https://example.com/c', sourceKey: 'src-a'),
    );
    // 源 B 同域名 opt in，不应拿到源 A 的 sid。
    await client.send(
      NovelHttpRequest(url: 'https://example.com/c', sourceKey: 'src-b'),
    );
    // 源 A 再请求，应恢复自己的 sid。
    await client.send(
      NovelHttpRequest(url: 'https://example.com/c', sourceKey: 'src-a'),
    );

    expect(adapter.seenHeaders[1].containsKey('Cookie'), isFalse);
    expect(adapter.seenHeaders[2]['Cookie'], contains('sid=abc'));
    client.close();
  });
}
