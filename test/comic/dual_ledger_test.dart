// 双记账专项：权威内部库 vs core 投影的写入点、打开校正点、payload 隔离。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/core/contract.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicHistoryService history;
  late ComicCollectService collect;

  const ref = ComicRef(id: 'venera:1001', sourceName: '漫画源');

  setUp(() {
    env = ComicTestEnv.create();
    history = ComicHistoryService(env.comicDb, env.library);
    collect = ComicCollectService(env.comicDb, env.library);
  });

  tearDown(() => env.close());

  test('内部读到第 10 页、投影停第 8 页：打开动作后投影校正为第 10 页', () async {
    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      chapterId: 'ch1',
      page: 10,
      pageCount: 20,
      openedAt: DateTime(2026, 11, 17, 10),
    );

    // 模拟杀进程前最后一笔投影没落盘：把投影压回第 8 页。
    await env.library.upsert(
      id: ref.id,
      type: MediaType.comic,
      sourceName: ref.sourceName,
      title: '葬送的芙莉莲',
      payload: jsonEncode(<String, Object?>{'page': 8}),
      progressText: 'ch1 · 第 8 页 · 40%',
      lastOpenedAt: DateTime(2026, 11, 17, 9),
    );
    expect(
      (await env.library.timeline()).single.progressText,
      'ch1 · 第 8 页 · 40%',
    );

    // 从统一时间线点进条目 = 用投影公共列构造 ref → 模块打开动作。
    final staleView = (await env.library.timeline()).single;
    await history.open(
      ComicRef(id: staleView.id, sourceName: staleView.sourceName),
    );

    final corrected = (await env.library.timeline()).single;
    expect(corrected.progressText, 'ch1 · 第 10 页 · 50%');
    expect(corrected.lastOpenedAt, DateTime(2026, 11, 17, 10));

    final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    final payload = jsonDecode(raw.payload) as Map<String, Object?>;
    expect(payload['page'], 10);
    expect(payload['pageCount'], 20);
    expect(payload['chapterId'], 'ch1');
  });

  test('校正按复合主键定位：同 id 不同源互不串写', () async {
    const sourceA = ComicRef(id: 'same-id', sourceName: '源A');
    const sourceB = ComicRef(id: 'same-id', sourceName: '源B');

    await history.saveProgress(
      sourceA,
      title: 'A 版',
      page: 10,
      pageCount: 20,
      openedAt: DateTime(2026, 11, 17, 10),
    );
    await history.saveProgress(
      sourceB,
      title: 'B 版',
      page: 2,
      pageCount: 20,
      openedAt: DateTime(2026, 11, 16, 10),
    );

    // 只把 A 源的投影压回第 1 页；B 源保持权威值。
    await env.library.upsert(
      id: 'same-id',
      type: MediaType.comic,
      sourceName: '源A',
      title: 'A 版',
      payload: '{}',
      progressText: '看到第 1 页',
      lastOpenedAt: DateTime(2026, 11, 15),
    );

    await history.open(sourceA);

    final rows = await env.library.timeline();
    expect(rows, hasLength(2));
    final a = rows.firstWhere((row) => row.sourceName == '源A');
    final b = rows.firstWhere((row) => row.sourceName == '源B');
    expect(a.progressText, '第 10 页 · 50%');
    expect(b.progressText, '第 2 页 · 10%');
  });

  test('core 投影不解析 payload：坏 JSON 原样保存，视图公共列不受影响', () async {
    const junkPayload = '这不是 JSON <<< {"page":99} >>>';
    await env.library.upsert(
      id: ref.id,
      type: MediaType.comic,
      sourceName: ref.sourceName,
      title: '葬送的芙莉莲',
      payload: junkPayload,
      progressText: '看到第 3 页',
      starred: true,
      lastOpenedAt: DateTime(2026, 11, 17, 8),
    );

    final view = (await env.library.timeline()).single;
    expect(view.title, '葬送的芙莉莲');
    expect(view.progressText, '看到第 3 页');
    expect(view.starred, isTrue);

    final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    expect(raw.payload, junkPayload);
  });

  test('模块私有 payload 不泄漏：投影 payload 只有进度摘要', () async {
    await collect.collect(
      ref,
      title: '葬送的芙莉莲',
      payload: jsonEncode(<String, Object?>{'privateRule': 'source-rule-v1'}),
      collectedAt: DateTime(2026, 11, 17, 9),
    );

    final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    expect(raw.payload, isNot(contains('source-rule-v1')));
    final decoded = jsonDecode(raw.payload) as Map<String, Object?>;
    expect(
      decoded.keys,
      containsAll(<String>['chapterId', 'page', 'pageCount']),
    );
  });

  test('持久化点成对落账：收藏、进度、取消收藏后两库状态一致', () async {
    await collect.collect(
      ref,
      title: '葬送的芙莉莲',
      collectedAt: DateTime(2026, 11, 17, 9),
    );
    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      page: 10,
      pageCount: 20,
      openedAt: DateTime(2026, 11, 17, 10),
    );

    final collectedView = (await env.library.timeline()).single;
    expect(collectedView.starred, isTrue);
    expect(collectedView.progressText, '第 10 页 · 50%');

    await collect.remove(ref);

    expect(await collect.isCollected(ref), isFalse);
    expect((await history.latest(ref))!.page, 10);
    final afterRemove = (await env.library.timeline()).single;
    expect(afterRemove.starred, isFalse);
    expect(afterRemove.progressText, '第 10 页 · 50%');
  });
}
