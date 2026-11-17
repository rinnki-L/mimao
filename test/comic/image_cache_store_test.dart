// 图片缓存仓储单测：写入/读取、按漫画与章节筛选、删除；不写 core 书架投影。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/image_cache_store.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicImageCacheStore cache;

  const ref = ComicRef(id: 'venera:1001', sourceName: '漫画源');

  setUp(() {
    env = ComicTestEnv.create();
    cache = ComicImageCacheStore(env.comicDb);
  });

  tearDown(() => env.close());

  test('put 写入元数据，find 读回路径与归属', () async {
    await cache.put(
      cacheKey: 'https://img/1.jpg',
      ref: ref,
      chapterId: 'ch1',
      filePath: '/cache/1.jpg',
      cachedAt: DateTime(2026, 11, 17, 10),
    );

    final row = await cache.find('https://img/1.jpg');
    expect(row, isNotNull);
    expect(row!.filePath, '/cache/1.jpg');
    expect(row.id, ref.id);
    expect(row.sourceName, ref.sourceName);
    expect(row.chapterId, 'ch1');
  });

  test('重复 put 同 key 覆盖更新（幂等）', () async {
    await cache.put(
      cacheKey: 'k',
      ref: ref,
      filePath: '/cache/old.jpg',
      cachedAt: DateTime(2026, 11, 1),
    );
    await cache.put(
      cacheKey: 'k',
      ref: ref,
      filePath: '/cache/new.jpg',
      cachedAt: DateTime(2026, 11, 17),
    );

    final rows = await cache.forComic(ref);
    expect(rows, hasLength(1));
    expect(rows.single.filePath, '/cache/new.jpg');
  });

  test('forComic 可按章节筛选，remove/clearComic 不影响其他漫画', () async {
    const other = ComicRef(id: 'venera:2002', sourceName: '漫画源');
    await cache.put(cacheKey: 'a', ref: ref, chapterId: 'ch1', filePath: 'a');
    await cache.put(cacheKey: 'b', ref: ref, chapterId: 'ch2', filePath: 'b');
    await cache.put(cacheKey: 'c', ref: other, chapterId: 'ch1', filePath: 'c');

    expect(await cache.forComic(ref, chapterId: 'ch1'), hasLength(1));
    expect((await cache.forComic(ref, chapterId: 'ch1')).single.filePath, 'a');
    expect(await cache.forComic(ref), hasLength(2));

    await cache.remove('a');
    expect(await cache.find('a'), isNull);
    expect(await cache.forComic(ref), hasLength(1));

    await cache.clearComic(ref);
    expect(await cache.forComic(ref), isEmpty);
    expect(await cache.forComic(other), hasLength(1));
  });

  test('图片缓存不产生 core 书架投影', () async {
    await cache.put(cacheKey: 'k', ref: ref, filePath: '/cache/k.jpg');
    expect(await env.library.timeline(), isEmpty);
  });
}
