// 双记账专项：权威内部库 vs core 投影的写入点、打开校正点、payload 隔离。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/collect_service.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/core/contract.dart';

import 'anime_test_env.dart';

void main() {
  late AnimeTestEnv env;
  late AnimeHistoryService history;
  late AnimeCollectService collect;

  const ref = AnimeRef(id: 'kazumi:1001', sourceName: '樱花动漫');

  setUp(() {
    env = AnimeTestEnv.create();
    history = AnimeHistoryService(env.animeDb, env.library);
    collect = AnimeCollectService(env.animeDb, env.library);
  });

  tearDown(() => env.close());

  test('内部库记 ep5、投影停 ep4：打开动作后投影被校正为 ep5', () async {
    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      episode: 5,
      positionSec: 600,
      durationSec: 1440,
      openedAt: DateTime(2026, 11, 17, 10),
    );

    // 模拟杀进程前最后一笔投影没落盘：把投影压回 ep4。
    await env.library.upsert(
      id: ref.id,
      type: MediaType.anime,
      sourceName: ref.sourceName,
      title: '葬送的芙莉莲',
      payload: jsonEncode(<String, Object?>{'episode': 4}),
      progressText: '看到第 4 话',
      lastOpenedAt: DateTime(2026, 11, 17, 9),
    );
    expect((await env.library.timeline()).single.progressText, '看到第 4 话');

    // 从统一时间线点进条目 = 用投影公共列构造 ref → 模块打开动作。
    final staleView = (await env.library.timeline()).single;
    await history.open(
      AnimeRef(id: staleView.id, sourceName: staleView.sourceName),
    );

    final corrected = (await env.library.timeline()).single;
    expect(corrected.progressText, '第 5 话 · 42%');
    expect(corrected.lastOpenedAt, DateTime(2026, 11, 17, 10));

    final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    final payload = jsonDecode(raw.payload) as Map<String, Object?>;
    expect(payload['episode'], 5);
    expect(payload['positionSec'], 600);
  });

  test('校正按复合主键定位：同 id 不同源互不串写', () async {
    const sourceA = AnimeRef(id: 'same-id', sourceName: '源A');
    const sourceB = AnimeRef(id: 'same-id', sourceName: '源B');

    await history.saveProgress(
      sourceA,
      title: 'A 版',
      episode: 5,
      openedAt: DateTime(2026, 11, 17, 10),
    );
    await history.saveProgress(
      sourceB,
      title: 'B 版',
      episode: 2,
      openedAt: DateTime(2026, 11, 16, 10),
    );

    // 只把 A 源的投影压回 ep1；B 源保持权威值。
    await env.library.upsert(
      id: 'same-id',
      type: MediaType.anime,
      sourceName: '源A',
      title: 'A 版',
      payload: '{}',
      progressText: '看到第 1 话',
      lastOpenedAt: DateTime(2026, 11, 15),
    );

    await history.open(sourceA);

    final rows = await env.library.timeline();
    expect(rows, hasLength(2));
    final a = rows.firstWhere((row) => row.sourceName == '源A');
    final b = rows.firstWhere((row) => row.sourceName == '源B');
    expect(a.progressText, '看到第 5 话');
    expect(b.progressText, '看到第 2 话');
  });

  test('core 投影不解析 payload：坏 JSON 原样保存，视图公共列不受影响', () async {
    const junkPayload = '这不是 JSON <<< {"episode":99} >>>';
    await env.library.upsert(
      id: ref.id,
      type: MediaType.anime,
      sourceName: ref.sourceName,
      title: '葬送的芙莉莲',
      payload: junkPayload,
      progressText: '看到第 3 话',
      starred: true,
      lastOpenedAt: DateTime(2026, 11, 17, 8),
    );

    final view = (await env.library.timeline()).single;
    expect(view.title, '葬送的芙莉莲');
    expect(view.progressText, '看到第 3 话');
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
      containsAll(<String>['episode', 'positionSec', 'durationSec']),
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
      episode: 5,
      openedAt: DateTime(2026, 11, 17, 10),
    );

    final collectedView = (await env.library.timeline()).single;
    expect(collectedView.starred, isTrue);
    expect(collectedView.progressText, '看到第 5 话');

    await collect.remove(ref);

    expect(await collect.isCollected(ref), isFalse);
    expect((await history.latest(ref))!.episode, 5);
    final afterRemove = (await env.library.timeline()).single;
    expect(afterRemove.starred, isFalse);
    expect(afterRemove.progressText, '看到第 5 话');
  });
}
