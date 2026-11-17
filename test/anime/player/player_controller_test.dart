// 播放控制器单测（验收点：播放/暂停状态切换、切集索引边界、倍速值合法）。
//
// 全程使用 FakePlaybackEngine：不触碰 media_kit / libmpv / 网络，
// 也不依赖真实视频解码。切集持久化点一条走真实 AnimeHistoryProgressRecorder
// 落到内存 AnimeDb；其余控制器行为测试用只记录调用的假 recorder。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/player_controller.dart';

import '../anime_test_env.dart';
import 'fake_playback_engine.dart';

const List<Episode> episodes = <Episode>[
  Episode(number: 1, title: '第 1 话', url: 'https://example.test/1.m3u8'),
  Episode(number: 2, title: '第 2 话', url: 'https://example.test/2.m3u8'),
  Episode(number: 3, title: '第 3 话', url: 'https://example.test/3.mp4'),
];

/// 只记录调用的进度接收器（仅用于控制器行为测试，不碰数据库）。
class RecordingProgressRecorder implements ProgressRecorder {
  final List<EpisodeProgress> events = <EpisodeProgress>[];

  @override
  Future<void> persist(EpisodeProgress progress) async {
    events.add(progress);
  }
}

/// 总是抛异常的 recorder（验证持久化失败被 controller 吞进 error 态）。
class ThrowingProgressRecorder implements ProgressRecorder {
  @override
  Future<void> persist(EpisodeProgress progress) async {
    throw StateError('boom');
  }
}

void main() {
  test('播放/暂停状态切换：状态与后端调用一致', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    expect(controller.status, PlayerStatus.idle);

    await controller.start();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing);
    expect(controller.isPlaying, isTrue);
    expect(engine.openedUrls, <String>[episodes.first.url]);

    await controller.togglePlay();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.paused);
    expect(engine.pauseCount, 1);
    expect(engine.playing, isFalse);

    await controller.togglePlay();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing);
    expect(engine.playCount, 1);
    expect(engine.playing, isTrue);
  });

  test('切集索引边界：越界抛 RangeError 且不改状态，合法切集换源', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    await expectLater(controller.loadEpisode(-1), throwsRangeError);
    await expectLater(
      controller.loadEpisode(episodes.length),
      throwsRangeError,
    );
    expect(controller.index, 0);
    expect(engine.openedUrls, hasLength(1));

    await controller.loadEpisode(2);
    await pumpEventQueue();
    expect(controller.index, 2);
    expect(engine.openedUrls.last, episodes[2].url);
    expect(controller.status, PlayerStatus.playing);
    expect(controller.hasNext, isFalse);
    expect(controller.hasPrevious, isTrue);
  });

  test('倍速值合法：预设生效，越界/非有限值被拒且状态不变', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    await controller.setSpeed(1.5);
    expect(controller.speed, 1.5);
    expect(engine.lastSpeed, 1.5);

    for (final illegal in <double>[
      0,
      0.25,
      3.5,
      10,
      double.nan,
      double.infinity,
    ]) {
      await expectLater(controller.setSpeed(illegal), throwsArgumentError);
      expect(controller.speed, 1.5, reason: '非法倍速 $illegal 不得改动状态');
    }

    // 所有 UI 预设都合法。
    for (final preset in PlayerController.speedPresets) {
      await controller.setSpeed(preset);
      expect(controller.speed, preset);
    }
  });

  test('跳转钳制在 [0, duration]，并透传后端', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();
    expect(controller.duration, const Duration(seconds: 240));

    await controller.seek(const Duration(seconds: -5));
    expect(controller.position, Duration.zero);
    expect(engine.seeks.last, Duration.zero);

    await controller.seek(const Duration(seconds: 999));
    expect(controller.position, const Duration(seconds: 240));
    expect(engine.seeks.last, const Duration(seconds: 240));
  });

  test('切集是持久化点：真实 recorder 先落旧集，再更新到新集（同一权威行）', () async {
    final env = AnimeTestEnv.create();
    addTearDown(env.close);
    const ref = AnimeRef(id: 'anime:demo:hardcoded', sourceName: '演示源（硬编码）');
    final history = AnimeHistoryService(env.animeDb, env.library);
    final recorder = AnimeHistoryProgressRecorder(
      history: history,
      entryId: ref.id,
      sourceName: ref.sourceName,
      title: '硬编码视频源验证',
    );

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

    // 切集 → 持久化点：旧集（第 1 话）95 秒写入 AnimeDb 与 core 投影。
    await controller.loadEpisode(1);
    await pumpEventQueue();

    var authoritative = await env.animeDb.historyRow(ref);
    expect(authoritative, isNotNull);
    expect(authoritative!.episode, 1);
    expect(authoritative.positionSec, 95);
    expect(
      (await env.appDb.select(env.appDb.mediaEntries).get()),
      hasLength(1),
    );

    // 新集播到 30 秒后暂停 → 同一权威行/投影更新到第 2 话 30 秒。
    engine.position = const Duration(seconds: 30);
    engine.emitSnapshot();
    await pumpEventQueue();
    await controller.pause();
    await pumpEventQueue();

    authoritative = await env.animeDb.historyRow(ref);
    expect(authoritative!.episode, 2);
    expect(authoritative.positionSec, 30);
    expect(
      await env.animeDb.select(env.animeDb.animeHistoryEntries).get(),
      hasLength(1),
    );
    expect(await env.appDb.select(env.appDb.mediaEntries).get(), hasLength(1));
  });

  test('进度回调上报 position/total（seconds 语义）', () async {
    final engine = FakePlaybackEngine();
    final reports = <String>[];
    final controller = PlayerController(
      engine: engine,
      episodes: episodes,
      onProgress: (position, total) =>
          reports.add('${position.inSeconds}/${total.inSeconds}'),
    );
    addTearDown(controller.dispose);

    await controller.start();
    await pumpEventQueue();
    engine.position = const Duration(seconds: 95);
    engine.emitSnapshot();
    await pumpEventQueue();

    expect(reports.last, '95/240');
  });

  test('播完是持久化点：按总时长记录', () async {
    final engine = FakePlaybackEngine();
    final recorder = RecordingProgressRecorder();
    final controller = PlayerController(
      engine: engine,
      episodes: episodes,
      progressRecorder: recorder,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    engine.complete();
    await pumpEventQueue();

    expect(controller.status, PlayerStatus.completed);
    expect(recorder.events, hasLength(1));
    expect(recorder.events.single.episode, 1);
    expect(recorder.events.single.position, const Duration(seconds: 240));
  });

  test('持久化失败：暂停记录 errorMessage，播放状态不被破坏，dispose 无未捕获异常', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: episodes,
      progressRecorder: ThrowingProgressRecorder(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    engine.position = const Duration(seconds: 30);
    engine.emitSnapshot();
    await pumpEventQueue();

    await controller.pause();
    await pumpEventQueue();

    expect(controller.errorMessage, contains('进度保存失败'));
    expect(controller.status, PlayerStatus.paused, reason: '持久化失败不应破坏播放状态');
    // dispose 内部再触发一次持久化，同样抛异常但必须被吞进 error 态。
    // flutter_test 会把任何未捕获的异步异常判为失败，因此这里正常结束即通过。
    controller.dispose();
    await pumpEventQueue();
  });
}
