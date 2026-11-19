// 验收 B6–B11：双记账投影（唯一写入口、payload 形状、打开点校正、文案规则）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_projection.dart';

import 'music_test_env.dart';

void main() {
  late MusicTestEnv env;

  const ref = MusicRef(id: '7301');

  setUp(() {
    env = MusicTestEnv.create();
  });

  tearDown(() => env.close());

  Future<Map<String, Object?>> readPayload() async {
    final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    return jsonDecode(raw.payload) as Map<String, Object?>;
  }

  test(
    'B6 收藏后投影：mediaType=music、sourceName=kugou、starred、payload 摘要',
    () async {
      await env.collect.collect(testSong());

      final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
      expect(raw.id, '7301');
      expect(raw.mediaType, MediaType.music);
      expect(raw.sourceName, 'kugou');
      expect(raw.title, '稻香');
      expect(raw.starred, isTrue);
      expect(raw.progressText, musicUnplayedText);
      expect(await readPayload(), <String, Object?>{
        'positionMs': 0,
        'durationMs': 0,
      });
    },
  );

  test('B7 先收藏再写进度：starred 保持、标题/封面不被覆盖、createdAt 不重置', () async {
    final collectedAt = DateTime(2026, 11, 1, 10);
    await env.collect.collectRef(
      ref,
      title: '稻香',
      coverUrl: 'https://example.com/cover.jpg',
      song: testSong(),
      collectedAt: collectedAt,
    );
    final before = await env.appDb.select(env.appDb.mediaEntries).getSingle();

    await env.history.saveProgress(
      testSong(),
      const Duration(milliseconds: 60000),
      const Duration(milliseconds: 223000),
    );

    final after = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    expect(after.starred, isTrue);
    expect(after.title, '稻香');
    expect(after.coverUrl, 'https://example.com/cover.jpg');
    expect(after.createdAt, collectedAt);
    expect(after.createdAt, before.createdAt);
    expect(after.lastOpenedAt, isNot(before.lastOpenedAt));
    expect(after.progressText, '已听 27%');
    expect((await readPayload())['positionMs'], 60000);
  });

  test('B8 先写进度再收藏：starred 变 true，历史进度保留', () async {
    await env.history.saveProgress(
      testSong(),
      const Duration(milliseconds: 120000),
      const Duration(milliseconds: 300000),
    );
    expect((await env.library.timeline()).single.starred, isFalse);

    await env.collect.collect(testSong());

    final view = (await env.library.timeline()).single;
    expect(view.starred, isTrue);
    expect(view.progressText, '已听 40%');
  });

  test('B9 open 校正投影（内部 120000 → 投影从 80000 校正）', () async {
    await env.history.saveProgress(
      testSong(),
      const Duration(milliseconds: 120000),
      const Duration(milliseconds: 300000),
    );
    await env.library.upsert(
      id: ref.id,
      type: MediaType.music,
      sourceName: kugouSourceName,
      title: '稻香',
      payload: jsonEncode(<String, Object?>{'positionMs': 80000}),
      progressText: '已听 27%',
      lastOpenedAt: DateTime(2026, 11, 1),
    );

    await env.history.open(testSong());

    final view = (await env.library.timeline()).single;
    expect(view.progressText, '已听 40%');
    expect((await readPayload())['positionMs'], 120000);
  });

  test('B10 progressText：60%、0/0 听过、只有收藏尚未播放、超 100% 夹取', () async {
    expect(musicProgressText(positionMs: 180000, durationMs: 300000), '已听 60%');
    expect(musicProgressText(positionMs: 0, durationMs: 0), '听过');
    expect(musicProgressText(positionMs: 5000, durationMs: 0), '听过');
    expect(
      musicProgressText(positionMs: 500000, durationMs: 100000),
      '已听 100%',
    );

    await env.collect.collect(testSong());
    expect((await env.library.timeline()).single.progressText, '尚未播放');
  });

  test('B11 无收藏无历史且无 fallback → 不产生投影行；有 fallback 才写', () async {
    await syncMusicProjection(db: env.musicDb, library: env.library, ref: ref);
    expect(await env.appDb.select(env.appDb.mediaEntries).get(), isEmpty);

    await syncMusicProjection(
      db: env.musicDb,
      library: env.library,
      ref: ref,
      fallbackTitle: '旧标题',
      fallbackCoverUrl: 'https://example.com/old.jpg',
    );
    final view = (await env.library.timeline()).single;
    expect(view.title, '旧标题');
    expect(view.starred, isFalse);
    expect(view.progressText, '尚未播放');
  });

  test('B11 payload 是纯摘要：内部歌曲 JSON 不泄漏进 core', () async {
    await env.collect.collect(testSong());
    final payload = (await readPayload());
    expect(payload.keys, <String>['positionMs', 'durationMs']);
    expect(payload.values, everyElement(isA<int>()));
    expect(
      (await env.appDb.select(env.appDb.mediaEntries).getSingle()).payload,
      isNot(contains('ABCDEF0123456789')),
    );
  });
}
