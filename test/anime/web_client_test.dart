import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/request/web_client.dart';

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
    test('默认 UA、Referer、Cookie 与自定义头', () {
      const options = AnimeFetchOptions(
        userAgent: 'mimao-UA',
        referer: 'https://site.test/list',
        cookies: <String, String>{'sid': 'abc', 'theme': 'dark'},
        headers: <String, String>{'X-Test': 'yes'},
      );

      final headers = options.toHeaders(defaultUserAgent: 'fallback-UA');

      expect(headers['User-Agent'], 'mimao-UA');
      expect(headers['Referer'], 'https://site.test/list');
      expect(headers['Cookie'], 'sid=abc; theme=dark');
      expect(headers['X-Test'], 'yes');
    });

    test('未给 UA 时用客户端默认；空 Referer 不发送', () {
      const options = AnimeFetchOptions(referer: '   ');

      final headers = options.toHeaders(
        defaultUserAgent: defaultAnimeUserAgent,
      );

      expect(headers['User-Agent'], defaultAnimeUserAgent);
      expect(headers.containsKey('Referer'), isFalse);
      expect(headers.containsKey('Cookie'), isFalse);
    });
  });

  group('AnimeWebClient', () {
    test('fetch 返回状态码/正文/最终 URL，并带上 UA/Cookie', () async {
      final adapter = _RecordingAdapter(
        headers: <String, List<String>>{
          'set-cookie': <String>['sid=1; Path=/'],
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final client = AnimeWebClient(
        dio: dio,
        timeout: const Duration(seconds: 5),
      );

      final response = await client.fetch(
        'https://site.test/rules.json',
        options: const AnimeFetchOptions(
          userAgent: 'mimao-UA',
          cookies: <String, String>{'sid': 'abc'},
        ),
      );

      expect(response.statusCode, 200);
      expect(response.body, '<html>ok</html>');
      expect(response.isSuccessful, isTrue);
      expect(response.url, 'https://site.test/rules.json');
      expect(response.setCookies, <String>['sid=1; Path=/']);
      expect(adapter.seenOptions?.method, 'GET');
      expect(adapter.seenOptions?.headers['User-Agent'], 'mimao-UA');
      expect(adapter.seenOptions?.headers['Cookie'], 'sid=abc');
    });

    test('POST 表单带上 form-urlencoded Content-Type', () async {
      final adapter = _RecordingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;

      await AnimeWebClient(dio: dio).fetch(
        'https://site.test/search',
        options: const AnimeFetchOptions(
          method: 'POST',
          formData: <String, String>{'q': '芙莉莲'},
        ),
      );

      expect(
        adapter.seenOptions?.contentType,
        Headers.formUrlEncodedContentType,
      );
    });

    test('4xx 不抛异常：交给导入器读状态码', () async {
      final dio = Dio()
        ..httpClientAdapter = _RecordingAdapter(
          body: 'forbidden',
          statusCode: 403,
        );

      final response = await AnimeWebClient(
        dio: dio,
      ).fetch('https://site.test/x');

      expect(response.statusCode, 403);
      expect(response.isSuccessful, isFalse);
      expect(response.body, 'forbidden');
    });

    test('非绝对 URL 直接参数错误', () async {
      final client = AnimeWebClient();

      await expectLater(client.fetch('/relative'), throwsArgumentError);
      await expectLater(client.fetch('   '), throwsArgumentError);
    });
  });
}
