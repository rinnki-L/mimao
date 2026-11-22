// 图片请求加载器 + 缓存新契约（loadRequest / cacheIdentity）的单测。
//
// 网络部分用回环地址上的真实 [HttpServer]：既断言实际发出的请求头，
// 又能精确控制返回码与请求次数；退避一律注入 0 延迟，测试不等待真实秒数。
// 本地文件分支用系统临时目录，测完即删。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_image_loader.dart';
import 'package:mimao/comic/reader/reader_models.dart';

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    unawaited(handler(request));
  });
  return server;
}

String _baseUrl(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

Future<void> _respond(HttpRequest request, int status, List<int> bytes) async {
  request.response.statusCode = status;
  request.response.add(bytes);
  await request.response.close();
}

Map<String, String> _headersOf(HttpRequest request) {
  final headers = <String, String>{};
  request.headers.forEach((name, values) {
    headers[name] = values.join(',');
  });
  return headers;
}

void main() {
  test('注入 Referer / 自定义头 / 默认桌面 UA，200 返回字节', () async {
    final received = <String, String>{};
    var hits = 0;
    final server = await _serve((request) async {
      hits++;
      received.addAll(_headersOf(request));
      await _respond(request, 200, <int>[1, 2, 3]);
    });
    addTearDown(() => server.close(force: true));

    final loader = defaultImageRequestLoader(backoff: (_) => Duration.zero);
    final bytes = await loader(
      ImageRequest(
        url: '${_baseUrl(server)}/img.png',
        referer: 'https://ref.example/page',
        headers: const <String, String>{'X-Token': 'abc'},
      ),
    );

    expect(bytes, <int>[1, 2, 3]);
    expect(hits, 1);
    expect(received['x-token'], 'abc');
    expect(received['referer'], 'https://ref.example/page');
    expect(received['user-agent'], contains('Chrome/'));
  });

  test('请求头里自带 UA 时不覆盖', () async {
    final received = <String, String>{};
    final server = await _serve((request) async {
      received.addAll(_headersOf(request));
      await _respond(request, 200, <int>[7]);
    });
    addTearDown(() => server.close(force: true));

    final loader = defaultImageRequestLoader(backoff: (_) => Duration.zero);
    await loader(
      ImageRequest(
        url: '${_baseUrl(server)}/ua.png',
        headers: const <String, String>{'User-Agent': 'Custom-UA/1.0'},
      ),
    );

    expect(received['user-agent'], 'Custom-UA/1.0');
    // 未显式给 Referer 时按同源推导。
    expect(received['referer'], '${_baseUrl(server)}/');
  });

  test('4xx（非 408/429）立即失败，不重试', () async {
    var hits = 0;
    final server = await _serve((request) async {
      hits++;
      await _respond(request, 404, <int>[]);
    });
    addTearDown(() => server.close(force: true));

    final loader = defaultImageRequestLoader(maxRetries: 3);
    await expectLater(
      loader(ImageRequest(url: '${_baseUrl(server)}/missing.png')),
      throwsA(
        isA<ImageLoadException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.isRetryable, 'isRetryable', isFalse),
      ),
    );
    expect(hits, 1, reason: '4xx 不应重试');
  });

  test('5xx 重试后成功，退避按 1/2 递增', () async {
    var hits = 0;
    final backoffAttempts = <int>[];
    final server = await _serve((request) async {
      hits++;
      await _respond(request, hits <= 2 ? 500 : 200, <int>[9]);
    });
    addTearDown(() => server.close(force: true));

    final loader = defaultImageRequestLoader(
      maxRetries: 2,
      backoff: (attempt) {
        backoffAttempts.add(attempt);
        return Duration.zero;
      },
    );
    final bytes = await loader(ImageRequest(url: '${_baseUrl(server)}/flaky'));

    expect(bytes, <int>[9]);
    expect(hits, 3);
    expect(backoffAttempts, <int>[1, 2]);
  });

  test('429 视为可重试：重试一次后成功', () async {
    var hits = 0;
    final server = await _serve((request) async {
      hits++;
      await _respond(request, hits == 1 ? 429 : 200, <int>[5]);
    });
    addTearDown(() => server.close(force: true));

    final loader = defaultImageRequestLoader(backoff: (_) => Duration.zero);
    final bytes = await loader(ImageRequest(url: '${_baseUrl(server)}/limit'));

    expect(bytes, <int>[5]);
    expect(hits, 2);
  });

  test('5xx 重试耗尽后抛可重试异常', () async {
    var hits = 0;
    final server = await _serve((request) async {
      hits++;
      await _respond(request, 503, <int>[]);
    });
    addTearDown(() => server.close(force: true));

    final loader = defaultImageRequestLoader(
      maxRetries: 1,
      backoff: (_) => Duration.zero,
    );
    await expectLater(
      loader(ImageRequest(url: '${_baseUrl(server)}/down')),
      throwsA(
        isA<ImageLoadException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.isRetryable, 'isRetryable', isTrue),
      ),
    );
    expect(hits, 2, reason: '1 + maxRetries(1) = 2 次');
  });

  test('本地文件路径 / file:// 直接读文件，不走网络', () async {
    final tempDir = await Directory.systemTemp.createTemp('mimao_img_loader_');
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}local.png');
    final bytes = Uint8List.fromList(<int>[4, 5, 6]);
    await file.writeAsBytes(bytes);

    final loader = defaultImageRequestLoader(backoff: (_) => Duration.zero);
    expect(await loader(ImageRequest(url: file.path)), bytes);
    expect(await loader(ImageRequest(url: file.uri.toString())), bytes);
  });

  test('本地文件缺失：不可重试的 ImageLoadException', () async {
    final tempDir = await Directory.systemTemp.createTemp('mimao_img_miss_');
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });
    final missing = '${tempDir.path}${Platform.pathSeparator}nope.png';

    final loader = defaultImageRequestLoader(backoff: (_) => Duration.zero);
    await expectLater(
      loader(ImageRequest(url: missing)),
      throwsA(
        isA<ImageLoadException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.isRetryable, 'isRetryable', isFalse),
      ),
    );
  });

  test('loadRequest 命中内存后不再取字节，hits/misses 正确', () async {
    var requestCalls = 0;
    final cache = ReaderImageCache(
      loader: (url) async => throw StateError('不应走旧 loader'),
      requestLoader: (request) async {
        requestCalls++;
        return Uint8List.fromList(<int>[1, 2]);
      },
      disk: MemoryByteStore(),
    );
    final request = ImageRequest(
      url: 'https://img.example/a.png',
      headers: const <String, String>{'Referer': 'https://img.example/'},
    );

    await cache.loadRequest(request);
    final second = await cache.loadRequest(request);

    expect(second, <int>[1, 2]);
    expect(requestCalls, 1);
    expect(cache.misses, 1);
    expect(cache.hits, 1);
  });

  test('cacheIdentity：带头与不带头是不同 key，落两份缓存', () async {
    var requestCalls = 0;
    final disk = MemoryByteStore();
    final cache = ReaderImageCache(
      loader: (url) async => throw StateError('不应走旧 loader'),
      requestLoader: (request) async {
        requestCalls++;
        return Uint8List.fromList(<int>[request.url.length]);
      },
      disk: disk,
    );

    const plain = ImageRequest(url: 'https://img.example/same.png');
    const withHeaders = ImageRequest(
      url: 'https://img.example/same.png',
      referer: 'https://site.example/',
    );

    await cache.loadRequest(plain);
    await cache.loadRequest(withHeaders);

    expect(requestCalls, 2, reason: '不同 cacheIdentity 不能共用缓存');
    expect(disk.length, 2);
    expect(cache.memoryLength, 2);
  });

  test('旧 load(url) 与新 loadRequest(纯地址) 共用同一缓存键', () async {
    var requestCalls = 0;
    final cache = ReaderImageCache(
      loader: (url) async => throw StateError('不应走旧 loader'),
      requestLoader: (request) async {
        requestCalls++;
        return Uint8List.fromList(<int>[8]);
      },
      disk: MemoryByteStore(),
    );
    const url = 'https://img.example/shared.png';

    await cache.loadRequest(const ImageRequest(url: url));
    await cache.load(url);

    expect(requestCalls, 1);
    expect(cache.hits, 1);
    expect(cache.isInMemory(url), isTrue);
  });

  test('未注入 requestLoader 时降级为旧 loader（丢弃请求头）', () async {
    final calledUrls = <String>[];
    final cache = ReaderImageCache(
      loader: (url) async {
        calledUrls.add(url);
        return Uint8List.fromList(<int>[3]);
      },
      disk: MemoryByteStore(),
    );

    final bytes = await cache.loadRequest(
      const ImageRequest(
        url: 'https://img.example/legacy.png',
        referer: 'https://site.example/',
      ),
    );

    expect(bytes, <int>[3]);
    expect(calledUrls, <String>['https://img.example/legacy.png']);
  });
}
