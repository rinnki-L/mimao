// HTTP 传输层：GBK 解码、meta charset、Cookie 回传。用本地 HttpServer，离线。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';

void main() {
  late HttpServer server;
  late String base;
  final gbkBytes = <int>[0xD6, 0xD0, 0xCE, 0xC4]; // 中文（GBK）

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/gbk') {
        response.headers.contentType = ContentType(
          'text',
          'html',
          charset: 'gbk',
        );
        response.add(gbkBytes);
      } else if (request.uri.path == '/meta') {
        response.headers.set('content-type', 'text/html');
        response.add(utf8.encode('<meta charset="gbk">'));
        response.add(gbkBytes);
      } else if (request.uri.path == '/cookie') {
        if (request.cookies.any((cookie) => cookie.name == 'sid')) {
          response.headers.contentType = ContentType.text;
          response.write('ok');
        } else {
          response.headers.add('set-cookie', 'sid=abc; Path=/');
          response.headers.contentType = ContentType.text;
          response.write('set');
        }
      } else {
        response.headers.contentType = ContentType.html;
        response.add(utf8.encode('<html>utf8 中文</html>'));
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('按 Content-Type charset 解 GBK', () async {
    final client = DioNovelHttpTransport();
    final response = await client.send(NovelHttpRequest(url: '$base/gbk'));
    expect(response.body, '中文');
    expect(response.charset, 'gbk');
    client.close();
  });

  test('按 meta charset 解 GBK（响应头未声明）', () async {
    final client = DioNovelHttpTransport();
    final response = await client.send(NovelHttpRequest(url: '$base/meta'));
    expect(response.body, contains('中文'));
    client.close();
  });

  test('无声明时 UTF-8 优先', () async {
    final client = DioNovelHttpTransport();
    final response = await client.send(NovelHttpRequest(url: '$base/utf8'));
    expect(response.body, contains('中文'));
    client.close();
  });

  test('Cookie 自动保存并回传', () async {
    final client = DioNovelHttpTransport();
    final first = await client.send(NovelHttpRequest(url: '$base/cookie'));
    expect(first.body, 'set');
    final second = await client.send(NovelHttpRequest(url: '$base/cookie'));
    expect(second.body, 'ok');
    client.close();
  });
}
