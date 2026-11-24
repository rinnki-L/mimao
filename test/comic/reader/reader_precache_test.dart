// 预取器与图片尺寸缓存单测：并发上限、窗口替换丢旧任务、只预热窗口前 N 张、
// 编码头尺寸解析。全部用可控内存 loader，不碰网络。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_image_size.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_precache.dart';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AF+kLQIAAAAAElFTkSuQmCC',
);

/// 可控 loader：每个 URL 调一次，测试手动完成；记录并发与启动顺序。
class _ControlledLoader {
  final List<String> started = <String>[];
  final Map<String, Completer<Uint8List>> _pending =
      <String, Completer<Uint8List>>{};
  int active = 0;
  int maxActive = 0;

  Future<Uint8List> call(ImageRequest request) {
    started.add(request.url);
    active++;
    if (active > maxActive) maxActive = active;
    final completer = Completer<Uint8List>();
    _pending[request.url] = completer;
    return completer.future.whenComplete(() => active--);
  }

  void complete(String url, [Uint8List? bytes]) {
    _pending.remove(url)!.complete(bytes ?? _png);
  }

  void fail(String url) {
    _pending.remove(url)!.completeError(StateError('boom: $url'));
  }
}

ReaderImageCache _cache(_ControlledLoader loader) => ReaderImageCache(
  loader: (_) async => throw StateError('旧 loader 不应被调用'),
  requestLoader: loader.call,
  disk: MemoryByteStore(),
);

ImageRequest _request(String url) => ImageRequest(url: url);

void main() {
  group('ReaderImagePreloader', () {
    test('并发有界，全部取完后 flush 返回', () async {
      final loader = _ControlledLoader();
      final preloader = ReaderImagePreloader(
        cache: _cache(loader),
        maxConcurrent: 2,
        decodeAhead: 0,
      );

      preloader.update(<ImageRequest>[
        _request('a'),
        _request('b'),
        _request('c'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(loader.started, <String>['a', 'b']);
      expect(loader.maxActive, 2);

      loader.complete('a');
      await Future<void>.delayed(Duration.zero);
      expect(loader.started, <String>['a', 'b', 'c']);

      final done = preloader.flush();
      loader.complete('b');
      loader.complete('c');
      await done;
      expect(loader.maxActive, 2);
      expect(preloader.pendingCount, 0);
      preloader.dispose();
    });

    test('窗口替换：旧窗口未开始的任务不再发出', () async {
      final loader = _ControlledLoader();
      final preloader = ReaderImagePreloader(
        cache: _cache(loader),
        maxConcurrent: 1,
        decodeAhead: 0,
      );

      preloader.update(<ImageRequest>[_request('a'), _request('b')]);
      await Future<void>.delayed(Duration.zero);
      expect(loader.started, <String>['a']);

      preloader.update(<ImageRequest>[_request('c')]);
      loader.complete('a');
      await Future<void>.delayed(Duration.zero);

      expect(loader.started, <String>['a', 'c']);
      loader.complete('c');
      await preloader.flush();
      preloader.dispose();
    });

    test('只对窗口内前 decodeAhead 张回调 onBytes', () async {
      final loader = _ControlledLoader();
      final decoded = <String>[];
      final preloader = ReaderImagePreloader(
        cache: _cache(loader),
        maxConcurrent: 2,
        decodeAhead: 1,
        onBytes: (request, bytes) => decoded.add(request.url),
      );

      preloader.update(<ImageRequest>[_request('a'), _request('b')]);
      await Future<void>.delayed(Duration.zero);
      loader.complete('a');
      loader.complete('b');
      await preloader.flush();

      expect(decoded, <String>['a']);
      preloader.dispose();
    });

    test('失败不影响后续任务', () async {
      final loader = _ControlledLoader();
      final preloader = ReaderImagePreloader(
        cache: _cache(loader),
        maxConcurrent: 1,
        decodeAhead: 0,
      );

      preloader.update(<ImageRequest>[_request('a'), _request('b')]);
      await Future<void>.delayed(Duration.zero);
      loader.fail('a');
      await Future<void>.delayed(Duration.zero);
      expect(loader.started, <String>['a', 'b']);
      loader.complete('b');
      await preloader.flush();
      preloader.dispose();
    });

    test('内存已有的图不重复排队', () async {
      final loader = _ControlledLoader();
      final cache = _cache(loader);
      final loading = cache.load('a');
      await Future<void>.delayed(Duration.zero);
      loader.complete('a');
      await loading;

      final preloader = ReaderImagePreloader(cache: cache, decodeAhead: 0);
      preloader.update(<ImageRequest>[_request('a')]);
      expect(preloader.pendingCount, 0);
      preloader.dispose();
    });
  });

  group('ReaderImageSizeCache', () {
    test('量出的尺寸按请求身份缓存', () async {
      final cache = ReaderImageSizeCache(
        measure: (_) async => const Size(800, 1200),
      );
      final request = _request('a');
      expect(cache.peek(request), isNull);

      final size = await cache.measure(request, _png);
      expect(size, const Size(800, 1200));
      expect(cache.peek(request), const Size(800, 1200));
      expect(cache.contains(request), isTrue);
    });

    test('不同请求头视为不同地址', () async {
      final cache = ReaderImageSizeCache(
        measure: (_) async => const Size(800, 1200),
      );
      await cache.measure(
        const ImageRequest(url: 'a', referer: 'https://x/'),
        _png,
      );
      expect(cache.contains(const ImageRequest(url: 'a')), isFalse);
      expect(
        cache.contains(const ImageRequest(url: 'a', referer: 'https://x/')),
        isTrue,
      );
    });

    test('无法识别的字节返回 null 且不抛错', () async {
      final cache = ReaderImageSizeCache(
        measure: (_) async => throw const FormatException('bad image'),
      );
      expect(
        await cache.measure(
          _request('bad'),
          Uint8List.fromList(<int>[1, 2, 3]),
        ),
        isNull,
      );
      expect(cache.contains(_request('bad')), isFalse);
    });

    testWidgets('默认识别器能从 PNG 编码头读出真实尺寸', (tester) async {
      final cache = ReaderImageSizeCache();
      final size = await tester.runAsync(
        () => cache.measure(_request('real'), _png),
      );
      expect(size, const Size(1, 1));
    });
  });
}
