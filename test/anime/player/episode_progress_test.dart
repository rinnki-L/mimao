// 收敛后的播放器进度写入口单测。
//
// B 线不再自带权威 store：AnimeHistoryProgressRecorder 把 EpisodeProgress
// 适配到 AnimeHistoryService.saveProgress，后者在同一个函数内写内部权威行
// （AnimeDb.anime_history）并经 syncAnimeProjection 写 core 投影。
// 这里验证单一权威、字段/文案/payload 一致、幂等、复合主键、打开校正、固定时间。
// 全程内存库，不联网、不写用户目录。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';

import '../anime_test_env.dart';

const String entryId = 'anime:demo:hardcoded';
const String sourceName = '演示源（硬编码）';
const AnimeRef ref = AnimeRef(id: entryId, sourceName: sourceName);

final DateTime fixedNow = DateTime(2026, 11, 17, 10, 30);

void main() {
  late AnimeTestEnv env;
  late AnimeHistoryService history;
  late AnimeHistoryProgressRecorder recorder;

  setUp(() {
    env = AnimeTestEnv.create();
    history = AnimeHistoryService(env.animeDb, env.library);
    recorder = AnimeHistoryProgressRecorder(
      history: history,
      entryId: entryId,
      sourceName: sourceName,
      title: '硬编码视频源验证',
      now: () => fixedNow,
    );
  });

  tearDown(() => env.close());

  Future<dynamic> authoritative() => env.animeDb.historyRow(ref);

  Future<MediaEntryRow> singleRow() async {
    final rows = await env.appDb.select(env.appDb.mediaEntries).get();
    expect(rows, hasLength(1), reason: '同一 {id, sourceName} 应只有一条投影');
    return rows.single;
  }

  Map<String, dynamic> payloadOf(MediaEntryRow row) =>
      jsonDecode(row.payload) as Map<String, dynamic>;

  test('recorder 写内部权威行 + core 投影：字段、文案、payload 键完全一致', () async {
    await recorder.persist(
      const EpisodeProgress(
        episode: 5,
        episodeTitle: '第 5 话',
        position: Duration(seconds: 600),
        total: Duration(seconds: 1440),
      ),
    );

    // 内部权威行：字段与 EpisodeProgress 一致，时间取注入的 now。
    final row = await authoritative();
    expect(row, isNotNull);
    expect(row.episode, 5);
    expect(row.positionSec, 600);
    expect(row.durationSec, 1440);
    expect(row.openedAt, fixedNow);

    // core 投影：payload 键恰好三个——不允许多出旧 payload 键或 epTitle。
    final projection = await singleRow();
    final payload = payloadOf(projection);
    expect(
      payload.keys,
      unorderedEquals(<String>['episode', 'positionSec', 'durationSec']),
    );
    expect(payload['episode'], 5);
    expect(payload['positionSec'], 600);
    expect(payload['durationSec'], 1440);
    expect(projection.mediaType, MediaType.anime);
    expect(projection.sourceName, sourceName);
    expect(projection.title, '硬编码视频源验证');
    expect(projection.progressText, '第 5 话 · 42%');
    expect(projection.lastOpenedAt, fixedNow);
  });

  test('重复写同一进度幂等：内部行、投影行、payload 字符串都不变', () async {
    const progress = EpisodeProgress(
      episode: 3,
      episodeTitle: '第 3 话',
      position: Duration(seconds: 42),
      total: Duration(seconds: 120),
    );

    await recorder.persist(progress);
    final firstProjection = await singleRow();
    final firstInternal = await authoritative();

    await recorder.persist(progress);
    final secondProjection = await singleRow();
    final secondInternal = await authoritative();

    expect(secondProjection.payload, firstProjection.payload);
    expect(secondProjection.progressText, firstProjection.progressText);
    expect(secondProjection.lastOpenedAt, firstProjection.lastOpenedAt);
    expect(secondInternal.openedAt, firstInternal.openedAt);
    expect(secondInternal.episode, firstInternal.episode);
    expect(
      await env.animeDb.select(env.animeDb.animeHistoryEntries).get(),
      hasLength(1),
    );
  });

  test('同 id 不同源各写一行：内部权威与投影互不覆盖', () async {
    final recorderA = AnimeHistoryProgressRecorder(
      history: history,
      entryId: 'same',
      sourceName: '源A',
      title: 'A 版',
      now: () => fixedNow,
    );
    final recorderB = AnimeHistoryProgressRecorder(
      history: history,
      entryId: 'same',
      sourceName: '源B',
      title: 'B 版',
      now: () => fixedNow,
    );

    await recorderA.persist(
      const EpisodeProgress(
        episode: 5,
        episodeTitle: '第 5 话',
        position: Duration.zero,
        total: Duration.zero,
      ),
    );
    await recorderB.persist(
      const EpisodeProgress(
        episode: 2,
        episodeTitle: '第 2 话',
        position: Duration.zero,
        total: Duration.zero,
      ),
    );

    final internalRows = await env.animeDb
        .select(env.animeDb.animeHistoryEntries)
        .get();
    expect(internalRows, hasLength(2));
    expect(
      internalRows.map((r) => r.sourceName),
      containsAll(<String>['源A', '源B']),
    );

    final projectionRows = await env.appDb.select(env.appDb.mediaEntries).get();
    expect(projectionRows, hasLength(2));
    expect(
      projectionRows.map((r) => r.sourceName),
      containsAll(<String>['源A', '源B']),
    );

    final a = await env.animeDb.historyRow(
      const AnimeRef(id: 'same', sourceName: '源A'),
    );
    final b = await env.animeDb.historyRow(
      const AnimeRef(id: 'same', sourceName: '源B'),
    );
    expect(a!.episode, 5);
    expect(b!.episode, 2);
  });

  test('文案统一：durationSec==0 报话数，>0 报统一百分比且无重复空格', () async {
    await recorder.persist(
      const EpisodeProgress(
        episode: 4,
        episodeTitle: '第 4 话',
        position: Duration(seconds: 30),
        total: Duration.zero,
      ),
    );
    expect((await singleRow()).progressText, '看到第 4 话');

    await recorder.persist(
      const EpisodeProgress(
        episode: 4,
        episodeTitle: '第 4 话',
        position: Duration(seconds: 30),
        total: Duration(seconds: 100),
      ),
    );
    final text = (await singleRow()).progressText;
    expect(text, '第 4 话 · 30%');
    expect(text, isNot(contains('  ')));
  });

  test('打开校正：内部 ep5、投影被改成 ep4 后 open 把投影校正回 ep5', () async {
    await recorder.persist(
      const EpisodeProgress(
        episode: 5,
        episodeTitle: '第 5 话',
        position: Duration(seconds: 600),
        total: Duration(seconds: 1440),
      ),
    );

    // 模拟最后一笔投影没落盘：把投影压回 ep4，内部权威保持 ep5。
    await env.library.upsert(
      id: entryId,
      type: MediaType.anime,
      sourceName: sourceName,
      title: '硬编码视频源验证',
      payload: jsonEncode(<String, Object?>{'episode': 4}),
      progressText: '看到第 4 话',
      lastOpenedAt: fixedNow.subtract(const Duration(hours: 1)),
    );
    expect((await singleRow()).progressText, '看到第 4 话');

    await history.open(ref);

    final corrected = await singleRow();
    expect(corrected.progressText, '第 5 话 · 42%');
    expect(payloadOf(corrected)['episode'], 5);
    expect(payloadOf(corrected)['positionSec'], 600);
    expect(corrected.lastOpenedAt, fixedNow);
  });

  test('注入固定 now：openedAt 与投影 lastOpenedAt 都取注入值', () async {
    final injectedTime = DateTime(2030, 1, 2, 3, 4, 5);
    final clockRecorder = AnimeHistoryProgressRecorder(
      history: history,
      entryId: entryId,
      sourceName: sourceName,
      title: '硬编码视频源验证',
      now: () => injectedTime,
    );

    await clockRecorder.persist(
      const EpisodeProgress(
        episode: 1,
        episodeTitle: '第 1 话',
        position: Duration(seconds: 10),
        total: Duration(seconds: 100),
      ),
    );

    expect((await authoritative()).openedAt, injectedTime);
    expect((await singleRow()).lastOpenedAt, injectedTime);
  });
}
