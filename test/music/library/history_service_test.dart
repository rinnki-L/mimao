// 验收 A4：历史服务的持久化点（位置/时长/playCount/latest/recent）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/music/models/music_models.dart';

import 'music_test_env.dart';

void main() {
  late MusicTestEnv env;

  setUp(() {
    env = MusicTestEnv.create();
  });

  tearDown(() => env.close());

  test('A4 saveProgress 写位置/时长；同曲重复写只有一行且 playCount 递增', () async {
    final song = testSong();
    await env.history.saveProgress(
      song,
      const Duration(milliseconds: 30000),
      const Duration(milliseconds: 223000),
    );
    await env.history.saveProgress(
      song,
      const Duration(milliseconds: 90000),
      const Duration(milliseconds: 223000),
    );

    final rows = await env.musicDb
        .select(env.musicDb.musicHistoryEntries)
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.positionMs, 90000);
    expect(rows.single.durationMs, 223000);
    expect(rows.single.playCount, 2);

    final latest = await env.history.latest(song.id);
    expect(latest, isNotNull);
    expect(latest!.position, const Duration(milliseconds: 90000));
    expect(latest.song.id, song.id);
    expect(latest.song.artists.single.name, '周杰伦');
  });

  test('A4 latest 返回最新一条；recent 按 openedAt 倒序并遵守 limit', () async {
    await env.history.saveProgressRef(
      const MusicRef(id: 'a'),
      positionMs: 1000,
      durationMs: 2000,
      title: 'A',
      song: testSong(id: 'a', title: 'A'),
      at: DateTime(2026, 11, 1),
    );
    await env.history.saveProgressRef(
      const MusicRef(id: 'b'),
      positionMs: 2000,
      durationMs: 4000,
      title: 'B',
      song: testSong(id: 'b', title: 'B'),
      at: DateTime(2026, 11, 3),
    );
    await env.history.saveProgressRef(
      const MusicRef(id: 'c'),
      positionMs: 3000,
      durationMs: 6000,
      title: 'C',
      song: testSong(id: 'c', title: 'C'),
      at: DateTime(2026, 11, 2),
    );

    expect((await env.history.latest('a'))!.openedAt, DateTime(2026, 11, 1));

    final recent = await env.history.recent();
    expect(recent.map((item) => item.song.id).toList(), <String>[
      'b',
      'c',
      'a',
    ]);
    expect((await env.history.recent(limit: 1)).single.song.id, 'b');
  });

  test('A4 open：没有历史行时不建行、不写投影；有行时校正投影', () async {
    final song = testSong();

    await env.history.open(song);
    expect(await env.musicDb.historyRow(musicRefOf(song)), isNull);
    expect(await env.library.timeline(), isEmpty);

    await env.history.saveProgress(
      song,
      const Duration(milliseconds: 120000),
      const Duration(milliseconds: 300000),
    );
    // 模拟投影落后：把 core 行压回 80000ms。
    await env.library.upsert(
      id: song.id,
      type: MediaType.music,
      sourceName: kugouSourceName,
      title: song.title,
      payload: '{"positionMs":80000,"durationMs":300000}',
      progressText: '已听 27%',
      lastOpenedAt: DateTime(2026, 11, 1),
    );

    await env.history.open(song);

    final view = (await env.library.timeline()).single;
    expect(view.progressText, '已听 40%');
    final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    expect(raw.payload, contains('"positionMs":120000'));
  });

  test('A4 负进度被拒绝（不落库）', () async {
    await expectLater(
      env.history.saveProgress(
        testSong(),
        const Duration(milliseconds: -1),
        const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    expect(
      await env.musicDb.select(env.musicDb.musicHistoryEntries).get(),
      isEmpty,
    );
  });
}
