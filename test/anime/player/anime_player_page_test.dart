// closure-01：AnimePlayerPage 生命周期测试——剧集映射/initialIndex、切集写库、
// 暂停写库、错误重试。全程 FakePlaybackEngine，不初始化 media_kit、不联网。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/data/fixture_anime_data_source.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/anime/player/anime_player_page.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/anime/player/player_page.dart';

import '../anime_integration_env.dart';
import 'fake_playback_engine.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late AnimeIntegrationEnv env;
  late AnimeHistoryService history;

  setUp(() async {
    env = await AnimeIntegrationEnv.create();
    history = AnimeHistoryService(env.animeDb, env.library);
  });

  tearDown(() async {
    await env.close();
  });

  AnimeHistoryProgressRecorder buildRecorder() => AnimeHistoryProgressRecorder(
    history: history,
    entryId: FixtureAnimeDataSource.xinghai.id,
    sourceName: FixtureAnimeDataSource.xinghai.sourceName!,
    title: FixtureAnimeDataSource.xinghai.title,
  );

  List<Episode> buildEpisodes() => const <Episode>[
    Episode(number: 1, title: '启航', url: 'https://example.com/play/1'),
    Episode(number: 2, title: '星图', url: 'https://example.com/play/2'),
    Episode(number: 3, title: '失重', url: 'https://example.com/play/3'),
  ];

  testWidgets('显示视频槽/进度条/剧集列表，initialIndex 正确，open 收到对应地址', (tester) async {
    final engine = FakePlaybackEngine();
    await tester.pumpWidget(
      _app(
        AnimePlayerPage(
          title: '星海旅人',
          episodes: buildEpisodes(),
          initialIndex: 1,
          recorder: buildRecorder(),
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byKey(const Key('player-slider')), findsOneWidget);
    expect(find.text('剧集 2/3'), findsOneWidget);
    expect(engine.openedUrls, <String>['https://example.com/play/2']);
  });

  testWidgets('剧集列表数量/顺序与传入一致，chip 可点切集', (tester) async {
    final engine = FakePlaybackEngine();
    await tester.pumpWidget(
      _app(
        AnimePlayerPage(
          title: '星海旅人',
          episodes: buildEpisodes(),
          initialIndex: 0,
          recorder: buildRecorder(),
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      expect(find.byKey(Key('episode-$i')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('episode-2')));
    await tester.pumpAndSettle();
    expect(find.text('剧集 3/3'), findsOneWidget);
    expect(engine.openedUrls, <String>[
      'https://example.com/play/1',
      'https://example.com/play/3',
    ]);
  });

  testWidgets('暂停写权威行与投影，payload 键与文案正确', (tester) async {
    final engine = FakePlaybackEngine();
    await tester.pumpWidget(
      _app(
        AnimePlayerPage(
          title: '星海旅人',
          episodes: buildEpisodes(),
          initialIndex: 0,
          recorder: buildRecorder(),
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 让 fake 推一个"播放中 + 位置/时长"快照。
    engine.position = const Duration(seconds: 60);
    engine.duration = const Duration(seconds: 240);
    engine.playing = true;
    engine.emitSnapshot();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-play-pause')));
    await tester.pumpAndSettle();

    final ref = AnimeRef(id: 'xinghai', sourceName: '樱花动漫');
    final row = await env.animeDb.historyRow(ref);
    expect(row, isNotNull);
    expect(row!.episode, 1);
    expect(row.positionSec, 60);
    expect(row.durationSec, 240);
    final timeline = await env.library.timeline();
    expect(timeline, hasLength(1));
    expect(timeline.single.progressText, '第 1 话 · 25%');
  });

  testWidgets('切集前旧集进度先落库，不产生第二条投影', (tester) async {
    final engine = FakePlaybackEngine();
    await tester.pumpWidget(
      _app(
        AnimePlayerPage(
          title: '星海旅人',
          episodes: buildEpisodes(),
          initialIndex: 0,
          recorder: buildRecorder(),
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();

    engine.position = const Duration(seconds: 30);
    engine.duration = const Duration(seconds: 240);
    engine.playing = true;
    engine.emitSnapshot();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-next')));
    await tester.pumpAndSettle();

    final ref = AnimeRef(id: 'xinghai', sourceName: '樱花动漫');
    final row = await env.animeDb.historyRow(ref);
    expect(row!.episode, 1); // 切集前把旧集进度写入。
    expect(row.positionSec, 30);
    expect(await env.library.timeline(), hasLength(1));
    expect(engine.openedUrls.last, 'https://example.com/play/2');
  });

  testWidgets('播放失败显示错误态，重试重新 open', (tester) async {
    final engine = FakePlaybackEngine();
    await tester.pumpWidget(
      _app(
        AnimePlayerPage(
          title: '星海旅人',
          episodes: buildEpisodes(),
          initialIndex: 0,
          recorder: buildRecorder(),
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 起播后由后端推错误快照（open() 会清空初始 error，不能在构造时设）。
    engine.error = '地址无效';
    engine.emitSnapshot();
    await tester.pumpAndSettle();

    expect(find.text('播放失败'), findsOneWidget);
    expect(find.byKey(const Key('player-retry')), findsOneWidget);
    expect(engine.openedUrls, hasLength(1));

    await tester.tap(find.byKey(const Key('player-retry')));
    await tester.pumpAndSettle();
    expect(engine.openedUrls, hasLength(2));
  });

  testWidgets('dispose 不抛异常、不产生未捕获异步错误', (tester) async {
    final engine = FakePlaybackEngine();
    await tester.pumpWidget(
      _app(
        AnimePlayerPage(
          title: '星海旅人',
          episodes: buildEpisodes(),
          initialIndex: 0,
          recorder: buildRecorder(),
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(engine.disposed, isTrue);
  });
}
