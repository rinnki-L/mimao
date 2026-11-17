// 图片缓存策略单测：内存 LRU + 磁盘持久化 + 容量限制。
//
// 用 MemoryByteStore 模拟磁盘（可注入、容量可控），假 loader 计数取字节次数；
// 不碰真实文件系统与网络。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';

void main() {
  int loadCount = 0;
  final disk = MemoryByteStore(maxEntries: 3);

  ReaderImageCache buildCache({int maxMemoryEntries = 2}) => ReaderImageCache(
    loader: (url) async {
      loadCount++;
      return Uint8List.fromList(url.codeUnits);
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
    await cache.load('a.png');
    await cache.load('a.png');
    expect(loadCount, 1);
    expect(cache.misses, 1);
    expect(cache.hits, 1);
  });

  test('内存淘汰后磁盘命中：不重新取字节，回填内存', () async {
    final cache = buildCache(maxMemoryEntries: 1);
    await cache.load('a.png');
    await cache.load('b.png'); // a 被内存淘汰，但磁盘还在
    expect(cache.isInMemory('a.png'), isFalse);

    final hitsBefore = cache.hits;
    final bytes = await cache.load('a.png');
    expect(String.fromCharCodes(bytes), 'a.png');
    expect(loadCount, 2, reason: '磁盘命中不应再调 loader');
    expect(cache.hits, hitsBefore + 1);
    expect(cache.isInMemory('a.png'), isTrue);
  });

  test('磁盘也未命中才取字节，并回填两级缓存', () async {
    final cache = buildCache();
    await cache.load('new.png');
    expect(loadCount, 1);
    expect(disk.length, 1);
    expect(cache.isInMemory('new.png'), isTrue);
  });

  test('容量限制：磁盘 LRU 淘汰最旧项', () async {
    final cache = buildCache(maxMemoryEntries: 10);
    for (final u in <String>['a.png', 'b.png', 'c.png', 'd.png']) {
      await cache.load(u);
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
      loader: (url) async => Uint8List(0),
      disk: MemoryByteStore(),
    );
    await expectLater(cache.load('empty.png'), throwsStateError);
    expect(cache.memoryLength, 0);
    expect(cache.misses, 1);
  });

  test('MemoryByteStore.remove 删除指定键', () async {
    await disk.write('del.png', Uint8List.fromList(<int>[1]));
    await disk.remove('del.png');
    expect(await disk.read('del.png'), isNull);
  });
}
