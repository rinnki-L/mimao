// 收藏（collect）单测：内部库增删查 + core 投影 starred 同步 + 复合主键。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/core/contract.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicCollectService collect;

  const ref = ComicRef(id: 'venera:1001', sourceName: '漫画源');

  setUp(() {
    env = ComicTestEnv.create();
    collect = ComicCollectService(env.comicDb, env.library);
  });

  tearDown(() => env.close());

  test('收藏写入内部库，并投影为一行 starred=true', () async {
    await collect.collect(
      ref,
      title: '葬送的芙莉莲',
      coverUrl: 'https://example.test/frieren.jpg',
      collectedAt: DateTime(2026, 11, 17, 12),
    );

    expect(await collect.isCollected(ref), isTrue);
    final entry = await collect.find(ref);
    expect(entry, isNotNull);
    expect(entry!.title, '葬送的芙莉莲');
    expect(entry.coverUrl, 'https://example.test/frieren.jpg');

    final starred = await env.library.timeline(starredOnly: true);
    expect(starred, hasLength(1));
    expect(starred.single.id, ref.id);
    expect(starred.single.sourceName, ref.sourceName);
    expect(starred.single.type, MediaType.comic);
    expect(starred.single.title, '葬送的芙莉莲');
    expect(starred.single.starred, isTrue);
    expect(starred.single.progressText, '尚未阅读');
  });

  test('重复收藏幂等：内部仍一行，元数据刷新且投影跟着更新', () async {
    await collect.collect(ref, title: '旧标题', collectedAt: DateTime(2026, 1, 1));
    await collect.collect(
      ref,
      title: '新标题',
      collectedAt: DateTime(2026, 11, 17),
    );

    final all = await collect.all();
    expect(all, hasLength(1));
    expect(all.single.title, '新标题');
    expect((await env.library.timeline()).single.title, '新标题');
  });

  test('取消收藏：内部行删除，投影 starred 校正为 false', () async {
    await collect.collect(ref, title: '葬送的芙莉莲');

    await collect.remove(ref);

    expect(await collect.isCollected(ref), isFalse);
    expect(await collect.all(), isEmpty);
    expect(await env.library.timeline(starredOnly: true), isEmpty);

    // core 没有 delete API，投影行保留为"未收藏"的索引行；starred 必须一致。
    final rows = await env.library.timeline();
    expect(rows, hasLength(1));
    expect(rows.single.starred, isFalse);
  });

  test('收藏不清掉已有阅读进度（历史权威优先于收藏元数据）', () async {
    final history = ComicHistoryService(env.comicDb, env.library);
    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      chapterId: 'ch1',
      page: 10,
      pageCount: 20,
      openedAt: DateTime(2026, 11, 16),
    );

    await collect.collect(
      ref,
      title: '葬送的芙莉莲',
      collectedAt: DateTime(2026, 11, 17),
    );

    final view = (await env.library.timeline()).single;
    expect(view.starred, isTrue);
    expect(view.progressText, 'ch1 · 第 10 页 · 50%');
    expect(view.lastOpenedAt, DateTime(2026, 11, 16));
  });

  test('复合主键：同 id 不同源是两条收藏、两行投影', () async {
    const sourceA = ComicRef(id: 'same-id', sourceName: '源A');
    const sourceB = ComicRef(id: 'same-id', sourceName: '源B');

    await collect.collect(sourceA, title: 'A 版');
    await collect.collect(sourceB, title: 'B 版');

    final all = await collect.all();
    expect(all, hasLength(2));
    expect(
      all.map((entry) => entry.ref.sourceName),
      containsAll(<String>['源A', '源B']),
    );

    final rows = await env.library.timeline();
    expect(rows, hasLength(2));
    expect(
      rows.map((row) => row.sourceName),
      containsAll(<String>['源A', '源B']),
    );
    expect(rows.every((row) => row.starred), isTrue);
  });
}
