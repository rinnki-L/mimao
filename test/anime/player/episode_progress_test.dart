// 进度写入 core 统一书架投影的单测。
//
// 验收点：切集后进度更新 / 重复 upsert 幂等 / payload 原样往返
// （payload 含 episode、positionSec），另验证"内部库为权威"的双记账落位。

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

import 'fake_playback_engine.dart';

const List<Episode> episodes = <Episode>[
  Episode(number: 1, title: '第 1 话', url: 'https://example.test/1.m3u8'),
  Episode(number: 2, title: '第 2 话', url: 'https://example.test/2.m3u8'),
];

void main() {
  late AppDb db;
  late InMemoryAnimeProgressStore store;
  late LibraryProgressRecorder recorder;

  setUp(() {
    db = AppDb.forTesting(NativeDatabase.memory());
    store = InMemoryAnimeProgressStore();
    recorder = LibraryProgressRecorder(
      library: LibraryRepository(db),
      store: store,
      entryId: 'anime:demo:hardcoded',
      sourceName: '演示源（硬编码）',
      title: '硬编码视频源验证',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<MediaEntryRow> singleRow() async {
    final rows = await db.select(db.mediaEntries).get();
    expect(rows, hasLength(1), reason: '同一 entryId 应只有一条投影');
    return rows.single;
  }

  Map<String, dynamic> payloadOf(MediaEntryRow row) =>
      jsonDecode(row.payload) as Map<String, dynamic>;

  test('切集后进度更新：先落旧集，再更新到新集（仍是同一行投影）', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: episodes,
      progressRecorder: recorder,
    );
    addTearDown(controller.dispose);

    await controller.start();
    await pumpEventQueue();
    engine.position = const Duration(seconds: 95);
    engine.emitSnapshot();
    await pumpEventQueue();

    // 切集 → 持久化点：旧集（第 1 话）的 95 秒落库。
    await controller.loadEpisode(1);
    await pumpEventQueue();

    var row = await singleRow();
    expect(row.mediaType, MediaType.anime);
    expect(row.sourceName, '演示源（硬编码）');
    expect(payloadOf(row)['episode'], 1);
    expect(payloadOf(row)['positionSec'], 95);
    expect(row.progressText, '第 1 话 · 40%');

    // 新集播到 30 秒后暂停 → 同一条投影更新为第 2 话。
    engine.position = const Duration(seconds: 30);
    engine.emitSnapshot();
    await pumpEventQueue();
    await controller.pause();
    await pumpEventQueue();

    row = await singleRow();
    expect(payloadOf(row)['episode'], 2);
    expect(payloadOf(row)['positionSec'], 30);
    expect(row.progressText, '第 2 话 · 13%');
    expect(await db.select(db.mediaEntries).get(), hasLength(1));
  });

  test('重复 upsert 幂等：同一进度写两次仍是一行且 payload 不变', () async {
    const progress = EpisodeProgress(
      episode: 3,
      episodeTitle: '第 3 话',
      position: Duration(seconds: 42),
      total: Duration(seconds: 120),
    );

    await recorder.persist(progress);
    final first = await singleRow();
    await recorder.persist(progress);
    final second = await singleRow();

    expect(second.id, first.id);
    expect(second.payload, first.payload);
    expect(second.progressText, first.progressText);
    expect(second.mediaType, first.mediaType);
  });

  test('payload 原样往返：episode / positionSec 等字段可解码且与写入一致', () async {
    await recorder.persist(
      const EpisodeProgress(
        episode: 7,
        episodeTitle: '第 7 话',
        position: Duration(seconds: 321),
        total: Duration(seconds: 1440),
      ),
    );

    final row = await singleRow();
    final decoded = AnimeEpisodeProgress.decode(row.payload);
    expect(decoded.episode, 7);
    expect(decoded.positionSec, 321);
    expect(decoded.durationSec, 1440);
    expect(decoded.episodeTitle, '第 7 话');
    expect(decoded.toPayload(), payloadOf(row));
    expect(payloadOf(row).containsKey('episode'), isTrue);
    expect(payloadOf(row).containsKey('positionSec'), isTrue);
  });

  test('双记账：模块内部库存权威值，core 投影只是索引', () async {
    await recorder.persist(
      const EpisodeProgress(
        episode: 5,
        episodeTitle: '第 5 话',
        position: Duration(seconds: 66),
        total: Duration(seconds: 600),
      ),
    );

    final authoritative = await store.read('anime:demo:hardcoded');
    expect(authoritative, isNotNull);
    expect(authoritative!.episode, 5);
    expect(authoritative.positionSec, 66);
    expect(authoritative.durationSec, 600);
    expect(authoritative.episodeTitle, '第 5 话');

    final row = await singleRow();
    expect(payloadOf(row)['episode'], authoritative.episode);
    expect(payloadOf(row)['positionSec'], authoritative.positionSec);
  });

  test('JSON 文件存储可跨实例读回（权威侧落盘）', () async {
    final dir = await Directory.systemTemp.createTemp('mimao_progress_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}progress.json');

    await JsonFileAnimeProgressStore(file).write(
      'a:1',
      const AnimeEpisodeProgress(
        episode: 2,
        positionSec: 33,
        durationSec: 100,
        episodeTitle: '第 2 话',
      ),
    );

    final reopened = JsonFileAnimeProgressStore(file);
    final record = await reopened.read('a:1');
    expect(record, isNotNull);
    expect(record!.episode, 2);
    expect(record.positionSec, 33);
    expect(record.durationSec, 100);
    expect(await reopened.read('missing'), isNull);
  });
}
