// 图片缓存策略单测：内存 LRU + 磁盘持久化 + 容量限制 + 失败重试。
//
// 用 MemoryByteStore 模拟磁盘（可注入、容量可控），假 loader 计数取字节次数；
// 不碰真实文件系统与网络。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_models.dart';

void main() {
  int loadCount = 0;
  final disk = MemoryByteStore(maxEntries: 3);

  ReaderImageCache buildCache({int maxMemoryEntries = 2}) => ReaderImageCache(
    loader: (ReaderImage image) async {
      loadCount++;
      return Uint8List.fromList(image.url.codeUnits);
    },
    disk: disk,
    maxMemoryEntries: maxMemoryEntries,
  );

  setUp(() async {
    loadCount = 0;
    await disk.clear();
  });

  test('内存命中不重复取字节，hits/misses 计数正确', () async {
    final cache = buildCache();
    await cache.load(ReaderImage.plain('a.png'));
    await cache.load(ReaderImage.plain('a.png'));
    expect(loadCount, 1);
    expect(cache.misses, 1);
    expect(cache.hits, 1);
  });

  test('内存淘汰后磁盘命中：不重新取字节，回填内存', () async {
    final cache = buildCache(maxMemoryEntries: 1);
    await cache.load(ReaderImage.plain('a.png'));
    await cache.load(ReaderImage.plain('b.png')); // a 被内存淘汰，但磁盘还在
    expect(cache.isInMemory('a.png'), isFalse);

    final hitsBefore = cache.hits;
    final bytes = await cache.load(ReaderImage.plain('a.png'));
    expect(String.fromCharCodes(bytes), 'a.png');
    expect(loadCount, 2, reason: '磁盘命中不应再调 loader');
    expect(cache.hits, hitsBefore + 1);
    expect(cache.isInMemory('a.png'), isTrue);
  });

  test('磁盘也未命中才取字节，并回填两级缓存', () async {
    final cache = buildCache();
    await cache.load(ReaderImage.plain('new.png'));
    expect(loadCount, 1);
    expect(disk.length, 1);
    expect(cache.isInMemory('new.png'), isTrue);
  });

  test('容量限制：磁盘 LRU 淘汰最旧项', () async {
    final cache = buildCache(maxMemoryEntries: 10);
    for (final u in <String>['a.png', 'b.png', 'c.png', 'd.png']) {
      await cache.load(ReaderImage.plain(u));
    }
    expect(disk.length, 3, reason: '磁盘容量上限为 3');
    expect(await disk.read(cacheKey('a.png')), isNull, reason: '最早的 a 被淘汰');
    expect(await disk.read(cacheKey('d.png')), isNotNull);
  });

  test('cacheKey 稳定且不同 URL 不冲突', () {
    expect(cacheKey('a.png'), cacheKey('a.png'));
    expect(cacheKey('a.png') != cacheKey('b.png'), isTrue);
  });

  test('空字节被拒，不写入缓存', () async {
    final cache = ReaderImageCache(
      loader: (ReaderImage image) async => Uint8List(0),
      disk: MemoryByteStore(),
    );
    await expectLater(
      cache.load(ReaderImage.plain('empty.png')),
      throwsStateError,
    );
    expect(cache.memoryLength, 0);
    expect(cache.misses, 1);
  });

  test('瞬时失败重试：两次 StateError 后成功，loader 共调 3 次', () async {
    var attempts = 0;
    final store = MemoryByteStore();
    final cache = ReaderImageCache(
      loader: (ReaderImage image) async {
        attempts++;
        if (attempts < 3) throw StateError('网络抖动');
        return Uint8List.fromList(image.url.codeUnits);
      },
      disk: store,
      retryDelay: const Duration(milliseconds: 1),
    );
    final bytes = await cache.load(ReaderImage.plain('flaky.png'));
    expect(String.fromCharCodes(bytes), 'flaky.png');
    expect(attempts, 3);
    expect(store.length, 1, reason: '重试成功后照常回填磁盘');
  });

  test('确定性失败（4xx）不重试，直接抛出', () async {
    var attempts = 0;
    final cache = ReaderImageCache(
      loader: (ReaderImage image) async {
        attempts++;
        throw const HttpException('HTTP 403');
      },
      disk: MemoryByteStore(),
      retryDelay: const Duration(milliseconds: 1),
    );
    await expectLater(
      cache.load(ReaderImage.plain('forbidden.png')),
      throwsA(isA<HttpException>()),
    );
    expect(attempts, 1, reason: '403 重试无意义');
  });

  test('重试上限：始终瞬时失败时 loader 共调 maxRetries+1 次', () async {
    var attempts = 0;
    final cache = ReaderImageCache(
      loader: (ReaderImage image) async {
        attempts++;
        throw StateError('一直挂');
      },
      disk: MemoryByteStore(),
      maxRetries: 2,
      retryDelay: const Duration(milliseconds: 1),
    );
    await expectLater(
      cache.load(ReaderImage.plain('dead.png')),
      throwsStateError,
    );
    expect(attempts, 3);
  });

  test('loader 收到 ReaderImage 本体，headers 直通', () async {
    ReaderImage? received;
    final cache = ReaderImageCache(
      loader: (ReaderImage image) async {
        received = image;
        return Uint8List.fromList(image.url.codeUnits);
      },
      disk: MemoryByteStore(),
    );
    const withHeaders = ReaderImage(
      'h.png',
      headers: <String, String>{'Referer': 'https://x.test/'},
    );
    await cache.load(withHeaders);
    expect(received, withHeaders);
  });

  test('同图并发请求合并：两个 load 共享一次 loader 调用', () async {
    final cache = buildCache();
    final first = cache.load(ReaderImage.plain('dup.png'));
    final second = cache.load(ReaderImage.plain('dup.png'));
    final bytes = await first;
    expect(String.fromCharCodes(await second), String.fromCharCodes(bytes));
    expect(loadCount, 1, reason: 'in-flight 去重');
  });

  test('MemoryByteStore.remove 删除指定键', () async {
    await disk.write('del.png', Uint8List.fromList(<int>[1]));
    await disk.remove('del.png');
    expect(await disk.read('del.png'), isNull);
  });
}
