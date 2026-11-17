// 历史（history）单测：观看记录持久化、文案、打开校正入口、复合主键。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/history_service.dart';

import 'anime_test_env.dart';

void main() {
  late AnimeTestEnv env;
  late AnimeHistoryService history;

  const ref = AnimeRef(id: 'kazumi:1001', sourceName: '樱花动漫');

  setUp(() {
    env = AnimeTestEnv.create();
    history = AnimeHistoryService(env.animeDb, env.library);
  });

  tearDown(() => env.close());

  test('saveProgress：先写内部库，同函数内投影 progressText 与时间', () async {
    final saved = await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      coverUrl: 'https://example.test/frieren.jpg',
      episode: 5,
      openedAt: DateTime(2026, 11, 17, 20, 30),
    );

    expect(saved.episode, 5);
    final latest = await history.latest(ref);
    expect(latest, isNotNull);
    expect(latest!.episode, 5);
    expect(latest.title, '葬送的芙莉莲');

    final view = (await env.library.timeline()).single;
    expect(view.progressText, '看到第 5 话');
    expect(view.lastOpenedAt, DateTime(2026, 11, 17, 20, 30));
    expect(view.coverUrl, 'https://example.test/frieren.jpg');
  });

  test('有时长/位置时投影文案带百分比（百分比四舍五入）', () async {
    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      episode: 5,
      positionSec: 600,
      durationSec: 1440,
    );

    expect((await env.library.timeline()).single.progressText, '第 5 话 · 42%');
  });

  test('open 只在内部库有历史时校正投影（无记录不凭空造条目）', () async {
    await history.open(ref);
    expect(await env.library.timeline(), isEmpty);

    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      episode: 2,
      openedAt: DateTime(2026, 11, 1),
    );
    await history.open(ref);
    expect((await env.library.timeline()).single.progressText, '看到第 2 话');
  });

  test('复合主键：同 id 不同源各一行历史、投影也各一行', () async {
    const sourceA = AnimeRef(id: 'same-id', sourceName: '源A');
    const sourceB = AnimeRef(id: 'same-id', sourceName: '源B');

    await history.saveProgress(
      sourceA,
      title: 'A 版',
      episode: 5,
      openedAt: DateTime(2026, 11, 17),
    );
    await history.saveProgress(
      sourceB,
      title: 'B 版',
      episode: 2,
      openedAt: DateTime(2026, 11, 16),
    );

    final recent = await history.recent();
    expect(recent, hasLength(2));
    expect(recent.first.ref.sourceName, '源A');
    expect(recent.first.title, 'A 版');
    expect(recent.last.title, 'B 版');

    final rows = await env.library.timeline();
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.title), containsAll(<String>['A 版', 'B 版']));
  });
}
