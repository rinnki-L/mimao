/// 网络层 mock 测试：用 dio 假 adapter 断言 UA / Referer / Cookie 请求头，
/// 以及 cookie_jar 写入后的 Cookie 自动携带、响应字节体与状态码。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({
    this.body = '<html>ok</html>',
    this.statusCode = 200,
    this.headers = const <String, List<String>>{},
  });

  final String body;
  final int statusCode;
  final Map<String, List<String>> headers;
  RequestOptions? seenOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seenOptions = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('请求头拼装', () {
    test('默认 UA、Referer、自定义头', () {
      const options = ComicFetchOptions(
        userAgent: 'mimao-comic-UA',
        referer: 'https://site.test/list',
        headers: <String, String>{'X-Test': 'yes'},
      );
      final headers = options.toHeaders(defaultUserAgent: 'fallback-UA');
      expect(headers['User-Agent'], 'mimao-comic-UA');
      expect(headers['Referer'], 'https://site.test/list');
      expect(headers['X-Test'], 'yes');
    });

    test('未给 UA 用默认；空 Referer 不发送', () {
      const options = ComicFetchOptions(referer: '   ');
      final headers = options.toHeaders(
        defaultUserAgent: defaultComicUserAgent,
      );
      expect(headers['User-Agent'], defaultComicUserAgent);
      expect(headers.containsKey('Referer'), isFalse);
    });
  });

  group('ComicWebClient', () {
    test('fetch 返回状态/正文/最终 URL，带 UA 与 Referer', () async {
      final adapter = _RecordingAdapter(
        headers: <String, List<String>>{
          'set-cookie': <String>['sid=1; Path=/'],
        },
      );
      final client = ComicWebClient(
        dio: Dio()..httpClientAdapter = adapter,
        timeout: const Duration(seconds: 5),
      );

      final response = await client.fetch(
        'https://site.test/comic/1',
        options: const ComicFetchOptions(
          userAgent: 'mimao-comic-UA',
          referer: 'https://site.test/',
        ),
      );

      expect(response.statusCode, 200);
      expect(response.body, '<html>ok</html>');
      expect(response.url, 'https://site.test/comic/1');
      expect(response.setCookies, <String>['sid=1; Path=/']);
      expect(adapter.seenOptions?.method, 'GET');
      expect(adapter.seenOptions?.headers['User-Agent'], 'mimao-comic-UA');
      expect(adapter.seenOptions?.headers['Referer'], 'https://site.test/');
      expect(adapter.seenOptions?.responseType, ResponseType.bytes);
    });

    test('setCookies 后 fetch 自动携带 Cookie 头', () async {
      final adapter = _RecordingAdapter();
      final client = ComicWebClient(dio: Dio()..httpClientAdapter = adapter);

      await client.setCookies('https://site.test', <String, String>{
        'sid': 'abc',
      });
      await client.fetch('https://site.test/comic/2');

      expect(adapter.seenOptions?.headers['Cookie'], contains('sid=abc'));
    });

    test('setCookies / fetch 后 getCookies 同步可见（真实 ComicWebClient）', () async {
      final adapter = _RecordingAdapter(
        headers: <String, List<String>>{
          'set-cookie': <String>['token=xyz; Path=/'],
        },
      );
      final client = ComicWebClient(dio: Dio()..httpClientAdapter = adapter);

      await client.setCookies('https://site.test', <String, String>{
        'sid': 'abc',
      });
      // setCookies 同步可见，且只对该主机可见。
      expect(
        client.getCookies('https://site.test'),
        contains(
          predicate(
            (Map<String, String> c) =>
                c['name'] == 'sid' && c['value'] == 'abc',
          ),
        ),
      );
      expect(client.getCookies('https://other.test'), isEmpty);

      // fetch 响应里的 Set-Cookie 也要落入同步缓存。
      await client.fetch('https://site.test/comic/3');
      expect(
        client.getCookies('https://site.test'),
        contains(
          predicate(
            (Map<String, String> c) =>
                c['name'] == 'token' && c['value'] == 'xyz',
          ),
        ),
      );

      // 同名同域覆盖，不产生重复项。
      await client.setCookies('https://site.test', <String, String>{
        'sid': 'def',
      });
      final sids = client
          .getCookies('https://site.test')
          .where((c) => c['name'] == 'sid')
          .toList();
      expect(sids, hasLength(1));
      expect(sids.single['value'], 'def');

      // deleteCookies 后同步缓存也清空。
      await client.deleteCookies('https://site.test');
      expect(client.getCookies('https://site.test'), isEmpty);
    });

    test('POST data 以字节体发送；4xx 不抛异常', () async {
      final adapter = _RecordingAdapter(body: 'forbidden', statusCode: 403);
      final client = ComicWebClient(dio: Dio()..httpClientAdapter = adapter);

      final response = await client.fetch(
        'https://site.test/search',
        options: const ComicFetchOptions(
          method: 'POST',
          data: 'q=abc',
          headers: <String, String>{
            'content-type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      expect(response.statusCode, 403);
      expect(response.isSuccessful, isFalse);
      expect(response.body, 'forbidden');
      expect(adapter.seenOptions?.method, 'POST');
      expect(adapter.seenOptions?.data, 'q=abc');
    });

    test('bodyBytes 与 UTF-8 解码一致', () async {
      final client = ComicWebClient(
        dio: Dio()..httpClientAdapter = _RecordingAdapter(body: '你好 mimao'),
      );
      final response = await client.fetch('https://site.test/utf8');
      expect(response.body, '你好 mimao');
      expect(utf8.decode(response.bodyBytes), '你好 mimao');
    });

    test('非绝对 URL 参数错误', () async {
      final client = ComicWebClient();
      await expectLater(client.fetch('/relative'), throwsArgumentError);
    });
  });
}
