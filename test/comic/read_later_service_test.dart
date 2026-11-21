// 稍后阅读（read later）单测：内部库增删查、幂等刷新、复合主键、时间倒序，
// 以及刻意不写 core 投影的双账边界。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/read_later_service.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicReadLaterService service;

  setUp(() {
    env = ComicTestEnv.create();
    service = ComicReadLaterService(env.comicDb);
  });

  tearDown(() => env.close());

  test('add 写入一行，find/contains 命中，all 返回完整元数据', () async {
    const ref = ComicRef(id: 'venera:1001', sourceName: '漫画源');
    final addedAt = DateTime(2026, 11, 22, 9);

    await service.add(
      ref,
      title: '葬送的芙莉莲',
      coverUrl: 'https://example.test/frieren.jpg',
      detailUrl: 'https://example.test/detail/1001',
      payload: '{"rule":"v1"}',
      addedAt: addedAt,
    );

    expect(await service.contains(ref), isTrue);
    final found = await service.find(ref);
    expect(found, isNotNull);
    expect(found!.ref, ref);
    expect(found.title, '葬送的芙莉莲');
    expect(found.coverUrl, 'https://example.test/frieren.jpg');
    expect(found.detailUrl, 'https://example.test/detail/1001');
    expect(found.payload, '{"rule":"v1"}');
    expect(found.addedAt, addedAt);

    final all = await service.all();
    expect(all, hasLength(1));
    expect(all.single.ref, ref);
    expect(all.single.title, '葬送的芙莉莲');
    expect(all.single.coverUrl, 'https://example.test/frieren.jpg');
    expect(all.single.detailUrl, 'https://example.test/detail/1001');
    expect(all.single.payload, '{"rule":"v1"}');
    expect(all.single.addedAt, addedAt);
  });

  test('同 {id, sourceName} 重复 add 幂等：仍一行，元数据刷新且顺序跟随更新后的 addedAt', () async {
    const ref = ComicRef(id: 'a', sourceName: '源');
    const other = ComicRef(id: 'b', sourceName: '源');

    await service.add(
      ref,
      title: '旧标题',
      detailUrl: 'old',
      payload: '{"v":1}',
      addedAt: DateTime(2026, 11, 20),
    );
    await service.add(other, title: 'B', addedAt: DateTime(2026, 11, 21));
    // 重加前 all 应为 [other, ref]；把 ref 刷新到最新时间后应变成 [ref, other]。
    expect((await service.all()).map((e) => e.ref.id), ['b', 'a']);

    await service.add(
      ref,
      title: '新标题',
      detailUrl: 'new',
      payload: '{"v":2}',
      addedAt: DateTime(2026, 11, 22),
    );

    final all = await service.all();
    // ref 仍只有一行（总数仍为 2），元数据已刷新。
    expect(all, hasLength(2));
    final refreshed = all.singleWhere((e) => e.ref == ref);
    expect(refreshed.title, '新标题');
    expect(refreshed.detailUrl, 'new');
    expect(refreshed.payload, '{"v":2}');
    expect(refreshed.addedAt, DateTime(2026, 11, 22));
    // 更新后的 addedAt 决定倒序位置：ref 升到最前。
    expect(all.map((e) => e.ref.id), ['a', 'b']);
  });

  test('同 id 不同 sourceName 是两条独立记录', () async {
    const sourceA = ComicRef(id: 'same-id', sourceName: '源A');
    const sourceB = ComicRef(id: 'same-id', sourceName: '源B');

    await service.add(
      sourceA,
      title: 'A 版',
      addedAt: DateTime(2026, 11, 22, 9),
    );
    await service.add(
      sourceB,
      title: 'B 版',
      addedAt: DateTime(2026, 11, 22, 10),
    );

    final all = await service.all();
    expect(all, hasLength(2));
    expect(all.map((e) => e.ref.sourceName), ['源B', '源A']);
    expect(await service.contains(sourceA), isTrue);
    expect(await service.contains(sourceB), isTrue);
    expect((await service.find(sourceA))!.title, 'A 版');
    expect((await service.find(sourceB))!.title, 'B 版');
  });

  test('remove 幂等且只删匹配的 {id, sourceName}', () async {
    const sourceA = ComicRef(id: 'same-id', sourceName: '源A');
    const sourceB = ComicRef(id: 'same-id', sourceName: '源B');

    await service.add(sourceA, title: 'A 版');
    await service.add(sourceB, title: 'B 版');

    await service.remove(sourceA);
    expect(await service.contains(sourceA), isFalse);
    expect(await service.find(sourceA), isNull);
    expect(await service.contains(sourceB), isTrue);

    // 再删一次不报错，也不误伤另一条。
    await service.remove(sourceA);
    final all = await service.all();
    expect(all, hasLength(1));
    expect(all.single.ref, sourceB);
  });

  test('set(true) 加入并返回 true、set(false) 移除并返回 false，重复 true 仍一行', () async {
    const ref = ComicRef(id: 's', sourceName: '源');

    expect(
      await service.set(
        ref,
        included: true,
        title: '标题',
        coverUrl: 'cov',
        detailUrl: 'd',
        now: DateTime(2026, 11, 22),
      ),
      isTrue,
    );
    expect(await service.contains(ref), isTrue);
    final added = (await service.find(ref))!;
    expect(added.title, '标题');
    expect(added.coverUrl, 'cov');
    expect(added.detailUrl, 'd');
    expect(added.addedAt, DateTime(2026, 11, 22));
    expect(added.payload, '{}');

    // 再 set(true) 只刷新，不新增行。
    expect(
      await service.set(
        ref,
        included: true,
        title: '标题2',
        now: DateTime(2026, 11, 23),
      ),
      isTrue,
    );
    expect(await service.all(), hasLength(1));
    expect((await service.find(ref))!.title, '标题2');

    // set(false) 移除并返回 false。
    expect(await service.set(ref, included: false, title: '标题2'), isFalse);
    expect(await service.contains(ref), isFalse);
    expect(await service.all(), isEmpty);
  });

  test('all 按 addedAt 倒序（显式时间戳）', () async {
    const a = ComicRef(id: 'a', sourceName: '源');
    const b = ComicRef(id: 'b', sourceName: '源');
    const c = ComicRef(id: 'c', sourceName: '源');

    await service.add(a, title: 'A', addedAt: DateTime(2026, 11, 20, 10));
    await service.add(c, title: 'C', addedAt: DateTime(2026, 11, 22, 10));
    await service.add(b, title: 'B', addedAt: DateTime(2026, 11, 21, 10));

    final all = await service.all();
    expect(all.map((e) => e.ref.id), ['c', 'b', 'a']);
    expect(all.map((e) => e.addedAt), [
      DateTime(2026, 11, 22, 10),
      DateTime(2026, 11, 21, 10),
      DateTime(2026, 11, 20, 10),
    ]);
  });

  test('稍后阅读不写 core 投影：时间线与 media_entries 均无该 ref', () async {
    const ref = ComicRef(id: 'later-only', sourceName: '漫画源');

    await service.add(ref, title: '只稍后阅读', addedAt: DateTime(2026, 11, 22));

    expect(await service.contains(ref), isTrue);
    // core 书架时间线没有任何条目。
    expect(await env.library.timeline(), isEmpty);
    // core 投影表也没有该 ref 对应的行。
    final rows = await env.appDb.select(env.appDb.mediaEntries).get();
    expect(rows, isEmpty);
    expect(
      rows.where((r) => r.id == ref.id && r.sourceName == ref.sourceName),
      isEmpty,
    );
  });
}
