// 朗读音频缓存（L2）：键稳定性 / 命中 / 丢文件自愈 / 容量 LRU / 清理。

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/reader/novel_tts.dart';
import 'package:mimao/novel/reader/novel_tts_cache.dart';

void main() {
  late Directory dir;
  late NovelDb db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mimao_tts_cache_test_');
    db = NovelDb.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } on Object {
      // Windows 偶尔占用文件；测试临时目录清不掉不影响结果。
    }
  });

  NovelTtsCache cacheWith({int maxBytes = 1024 * 1024}) {
    var now = DateTime(2026, 1, 1);
    return NovelTtsCache(
      db: db,
      directory: () async => dir,
      maxBytes: maxBytes,
      clock: () => now = now.add(const Duration(seconds: 1)),
    );
  }

  File writeFile(String name, int bytes) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(List<int>.filled(bytes, 0));
    return file;
  }

  test('缓存键包含书/章节/段落/音色/语速，语速固定两位小数', () {
    final a = novelTtsCacheKey(
      bookId: 'b1',
      chapterKey: 'c1',
      paragraph: 3,
      voice: 'Huihui',
      rate: 1.0,
    );
    final b = novelTtsCacheKey(
      bookId: 'b1',
      chapterKey: 'c1',
      paragraph: 3,
      voice: 'Huihui',
      rate: 1,
    );
    expect(a, b);
    expect(a, contains('|3|Huihui|1.00'));

    expect(
      novelTtsCacheKey(
        bookId: 'b1',
        chapterKey: 'c1',
        paragraph: 3,
        voice: 'Huihui',
        rate: 1.5,
      ),
      isNot(a),
    );
    expect(
      novelTtsCacheKey(
        bookId: 'b1',
        chapterKey: 'c1',
        paragraph: 4,
        voice: 'Huihui',
        rate: 1.0,
      ),
      isNot(a),
    );
    expect(
      novelTtsCacheKey(
        bookId: 'b1',
        chapterKey: 'c1',
        paragraph: 3,
        voice: '',
        rate: 1.0,
      ),
      contains('|auto|1.00'),
    );
  });

  test('登记后能命中并刷新 LRU；文件丢了自愈删除索引', () async {
    final cache = cacheWith();
    final path = writeFile('a.wav', 100).path;
    const key = 'book|c1|0|auto|1.00';
    await cache.put(cacheKey: key, path: path);

    expect(await cache.find(key), path);
    var stats = await cache.stats();
    expect(stats.count, 1);
    expect(stats.bytes, 100);

    // 文件被用户/清理工具删掉：find 返回 null，索引也要删掉。
    await File(path).delete();
    expect(await cache.find(key), isNull);
    stats = await cache.stats();
    expect(stats.count, 0);
  });

  test('超过容量按最久未用淘汰，并删掉对应文件', () async {
    final cache = cacheWith(maxBytes: 250);
    final files = <String>[];
    for (var i = 0; i < 3; i++) {
      final path = writeFile('$i.wav', 100).path;
      files.add(path);
      await cache.put(cacheKey: 'k$i', path: path);
    }

    final stats = await cache.stats();
    expect(stats.count, 2);
    expect(stats.bytes, 200);
    expect(File(files[0]).existsSync(), isFalse, reason: '最旧的一段应被淘汰');
    expect(await cache.find('k0'), isNull);
    expect(await cache.find('k1'), files[1]);
    expect(await cache.find('k2'), files[2]);
  });

  test('清理会删索引与文件', () async {
    final cache = cacheWith();
    final a = writeFile('a.wav', 60).path;
    final b = writeFile('b.wav', 60).path;
    await cache.put(cacheKey: 'ka', path: a);
    await cache.put(cacheKey: 'kb', path: b);

    expect(await cache.clear(), 2);
    expect(await cache.stats(), isA<NovelTtsCacheStats>());
    expect((await cache.stats()).count, 0);
    expect(File(a).existsSync(), isFalse);
    expect(File(b).existsSync(), isFalse);
  });

  test('缓存装饰器：首次合成落盘，第二次直接播文件', () async {
    final cache = cacheWith();
    final inner = _CachingEngine();
    final engine = CachedNovelTtsEngine(inner: inner, cache: cache);

    await engine.speak('第一段', rate: 1.0, cacheKey: 'k1');
    expect(inner.synths, 1);
    expect(inner.played, hasLength(1));
    expect(File(inner.played.single).existsSync(), isTrue);
    expect((await cache.stats()).count, 1);

    // 同一键命中：不再合成，只播放。
    await engine.speak('第一段', rate: 1.0, cacheKey: 'k1');
    expect(inner.synths, 1);
    expect(inner.played, hasLength(2));

    // 换音色 = 新键，重新合成。
    await engine.speak('第一段', rate: 1.0, voice: 'Zira', cacheKey: 'k2');
    expect(inner.synths, 2);
  });

  test('合成失败时不挡朗读：回退直接 speak', () async {
    final cache = cacheWith();
    final inner = _CachingEngine(failSynthesis: true);
    final engine = CachedNovelTtsEngine(inner: inner, cache: cache);

    await engine.speak('会失败', rate: 1.0, cacheKey: 'kfail');
    expect(inner.synths, 1);
    expect(inner.fallbackSpoken, <String>['会失败']);
    expect((await cache.stats()).count, 0);
  });
}

class _CachingEngine implements NovelTtsEngine {
  _CachingEngine({this.failSynthesis = false});

  final bool failSynthesis;
  int synths = 0;
  final List<String> played = <String>[];
  final List<String> fallbackSpoken = <String>[];

  @override
  bool get supportsFileOutput => true;

  @override
  bool get supportsFilePlayback => true;

  @override
  Future<void> configure() async {}

  @override
  Future<List<NovelTtsVoice>> voices() async => const <NovelTtsVoice>[];

  @override
  Future<void> speak(
    String text, {
    required double rate,
    String voice = '',
    String? cacheKey,
  }) async {
    fallbackSpoken.add(text);
  }

  @override
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  }) async {
    synths++;
    if (failSynthesis) throw StateError('合成失败');
    await File(path).writeAsBytes(List<int>.filled(32, 0));
  }

  @override
  Future<void> playFile(String path) async => played.add(path);

  @override
  Future<void> stop() async {}
}
