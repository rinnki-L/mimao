// 磁盘缓存与默认本地加载器的测试：用系统临时目录，测完即删，不碰网络。
//
// 这组测试同时抬高 reader_cache.dart 的行覆盖率——DiskByteStore 与
// defaultImageByteLoader 的本地分支都在 CI 覆盖率门的分母里。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mimao_reader_cache_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('DiskByteStore：write→read 原样往返，length 正确', () async {
    final store = DiskByteStore(tempDir, maxEntries: 5);
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    await store.write('k1', bytes);

    expect(store.length, 1);
    expect(await store.read('k1'), bytes);
  });

  test('DiskByteStore：未命中返回 null，remove 删除', () async {
    final store = DiskByteStore(tempDir);
    expect(await store.read('missing'), isNull);

    await store.write('k2', Uint8List.fromList(<int>[9]));
    await store.remove('k2');
    expect(await store.read('k2'), isNull);
    expect(store.length, 0);
    // 删除不存在的键不抛异常。
    await store.remove('k2');
  });

  test('DiskByteStore：读到的文件是目录时按未命中处理', () async {
    final store = DiskByteStore(tempDir);
    // 用缓存键建一个目录，read 会 readAsBytes 失败 → 返回 null。
    final dirKeyFile = File(
      '${tempDir.path}${Platform.pathSeparator}${cacheKey('dir.png')}',
    );
    await dirKeyFile.create();
    await dirKeyFile.delete();
    await Directory(dirKeyFile.path).create();
    expect(await store.read('dir.png'), isNull);
  });

  test('DiskByteStore：超过 maxEntries 时淘汰最旧文件', () async {
    final store = DiskByteStore(tempDir, maxEntries: 2);
    await store.write('a', Uint8List.fromList(<int>[1]));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.write('b', Uint8List.fromList(<int>[2]));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.write('c', Uint8List.fromList(<int>[3]));

    expect(store.length, 2);
    expect(await store.read('a'), isNull, reason: '最早的 a 被淘汰');
    expect(await store.read('c'), isNotNull);
  });

  test('defaultImageByteLoader：读取本地文件路径', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}img.png');
    final bytes = Uint8List.fromList(<int>[7, 8, 9]);
    await file.writeAsBytes(bytes);

    expect(await defaultImageByteLoader(file.path), bytes);
  });

  test('defaultImageByteLoader：读取 file:// URI', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}img2.png');
    final bytes = Uint8List.fromList(<int>[4, 5, 6]);
    await file.writeAsBytes(bytes);

    expect(await defaultImageByteLoader(file.uri.toString()), bytes);
  });

  test('ReaderImageCache 走真实 DiskByteStore：跨实例命中磁盘', () async {
    final loaderCalls = <String>[];
    ReaderImageCache build() => ReaderImageCache(
      loader: (url) async {
        loaderCalls.add(url);
        return Uint8List.fromList(url.codeUnits);
      },
      disk: DiskByteStore(tempDir, maxEntries: 10),
    );

    final first = build();
    await first.load('persisted.png');
    expect(loaderCalls, <String>['persisted.png']);

    // 新实例内存为空，但磁盘有 → 不重新调 loader。
    final second = build();
    final bytes = await second.load('persisted.png');
    expect(String.fromCharCodes(bytes), 'persisted.png');
    expect(loaderCalls, <String>['persisted.png']);
    expect(second.hits, 1);
  });
}
