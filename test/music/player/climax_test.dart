// ignore_for_file: deprecated_member_use — 与模块页面测试同款说明。
/// 歌曲高潮测试（L4）：fake loadClimax 闭包 + fake engine/playbackApi。
///
/// 覆盖成功显示并 seek、失败/无数据隐藏、hash 非 32 位不请求、换歌丢弃
/// 旧结果、UIImpl/mini player/工厂透传；不真实 sleep、不联网。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/player/pages/music_mini_player.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/player_store.dart';
import 'package:mimao/music/player/player_ui_impl.dart';

import 'player_fakes.dart';

/// 高潮区间闭包替身：记录请求 hash，按 hash 决定返回结果/抛错/挂起。
class _FakeClimaxLoader {
  final List<String> requestedHashes = <String>[];
  final Map<String, List<MusicSongClimaxSegment>> results =
      <String, List<MusicSongClimaxSegment>>{};
  final Set<String> failures = <String>{};
  final Map<String, Completer<List<MusicSongClimaxSegment>>> pending =
      <String, Completer<List<MusicSongClimaxSegment>>>{};

  Future<List<MusicSongClimaxSegment>> call(String hash) {
    requestedHashes.add(hash);
    if (failures.contains(hash)) {
      throw Exception('高潮查询失败'); // 同步抛：验证静默吞掉
    }
    final pendingCompleter = pending[hash];
    if (pendingCompleter != null) return pendingCompleter.future;
    return Future<List<MusicSongClimaxSegment>>.value(
      results[hash] ?? const <MusicSongClimaxSegment>[],
    );
  }
}

void main() {
  late FakeMusicEngine engine;
  late FakePlaybackApi api;
  late MusicPlayerStore store;
  late _FakeClimaxLoader loader;

  const segmentA = MusicSongClimaxSegment(
    startMs: 65000,
    endMs: 95000,
    hash: 'a',
  );

  setUp(() {
    engine = FakeMusicEngine();
    api = FakePlaybackApi();
    store = MusicPlayerStore(playbackApi: api, engineFactory: () => engine);
    loader = _FakeClimaxLoader();
  });

  tearDown(() => store.dispose());

  Future<void> pumpPlayerPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicPlayerPage(player: store, loadClimax: loader.call),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('成功：显示「高潮 mm:ss–mm:ss」chip，点击 seek 到起点', (tester) async {
    loader.results[fakeSong().hash] = <MusicSongClimaxSegment>[segmentA];
    await store.playSong(fakeSong());
    await pumpPlayerPage(tester);

    expect(find.textContaining('高潮'), findsOneWidget);
    expect(find.text('高潮 1:05–1:35'), findsOneWidget);
    expect(loader.requestedHashes, <String>[fakeSong().hash]);

    await tester.tap(find.text('高潮 1:05–1:35'));
    await tester.pumpAndSettle();
    expect(engine.seeks, contains(const Duration(milliseconds: 65000)));
  });

  testWidgets('失败：静默隐藏、不重试、不影响播放状态', (tester) async {
    loader.failures.add(fakeSong().hash);
    await store.playSong(fakeSong());
    await pumpPlayerPage(tester);

    expect(find.textContaining('高潮'), findsNothing);
    expect(loader.requestedHashes, hasLength(1));
    expect(store.error, isNull);
    expect(engine.playCalls, 1);
  });

  testWidgets('无数据：空列表不显示 chip', (tester) async {
    await store.playSong(fakeSong());
    await pumpPlayerPage(tester);
    expect(find.textContaining('高潮'), findsNothing);
  });

  testWidgets('hash 非 32 位：不发起请求', (tester) async {
    await store.playSong(fakeSong(hash: 'not-a-32-char-hash'));
    await pumpPlayerPage(tester);

    expect(loader.requestedHashes, isEmpty);
    expect(find.textContaining('高潮'), findsNothing);
  });

  testWidgets('换歌：丢弃旧结果，只显示新歌 chip，各请求一次', (tester) async {
    const songB = MusicSongClimaxSegment(
      startMs: 120000,
      endMs: 150000,
      hash: 'b',
    );
    final songA = fakeSong(id: '1');
    final hashA = songA.hash;
    // 与默认 fakeSong 同款 32 位十六进制，只换首字母（高潮端点长度约束）。
    const hashB = 'bbcdef0123456789abcdef0123456789';
    loader.pending[hashA] =
        Completer<List<MusicSongClimaxSegment>>(); // A 的请求挂起
    loader.results[hashB] = <MusicSongClimaxSegment>[songB];

    await store.playSong(songA);
    await pumpPlayerPage(tester);
    expect(find.textContaining('高潮'), findsNothing, reason: 'A 尚未返回');
    expect(loader.requestedHashes, <String>[hashA]);

    // 换到 B：旧请求作废，B 的结果正常显示。
    await store.playSong(fakeSong(id: '2', hash: hashB));
    await tester.pumpAndSettle();
    expect(find.text('高潮 2:00–2:30'), findsOneWidget);
    expect(loader.requestedHashes, <String>[hashA, hashB]);

    // A 的慢请求此刻才回来：按歌曲 key 比对后丢弃，不渲染。
    loader.pending[hashA]!.complete(<MusicSongClimaxSegment>[segmentA]);
    await tester.pumpAndSettle();
    expect(find.text('高潮 1:05–1:35'), findsNothing);
    expect(find.text('高潮 2:00–2:30'), findsOneWidget);
  });

  testWidgets('loadClimax 为 null：整段隐藏且不发请求', (tester) async {
    await store.playSong(fakeSong());
    await tester.pumpWidget(MaterialApp(home: MusicPlayerPage(player: store)));
    await tester.pumpAndSettle();
    expect(find.textContaining('高潮'), findsNothing);
    expect(loader.requestedHashes, isEmpty);
  });

  testWidgets('MusicPlayerUiImpl 透传 loadClimax 到播放页', (tester) async {
    loader.results[fakeSong().hash] = <MusicSongClimaxSegment>[segmentA];
    await store.playSong(fakeSong());
    final playerUi = MusicPlayerUiImpl(store, loadClimax: loader.call);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => playerUi.buildPlayerPage(context)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('高潮 1:05–1:35'), findsOneWidget);
  });

  testWidgets('mini player 打开的播放页同样透传 loadClimax', (tester) async {
    loader.results[fakeSong().hash] = <MusicSongClimaxSegment>[segmentA];
    await store.playSong(fakeSong());
    final playerUi = MusicPlayerUiImpl(store, loadClimax: loader.call);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => playerUi.buildMiniPlayer(context)!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MusicMiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(MusicPlayerPage), findsOneWidget);
    expect(find.text('高潮 1:05–1:35'), findsOneWidget);
  });

  testWidgets('createMusicPlayerUi 透传 listenReport 与 loadClimax', (
    tester,
  ) async {
    loader.results[fakeSong().hash] = <MusicSongClimaxSegment>[segmentA];
    final report = FakeListenReportApi();
    final playerUi = createMusicPlayerUi(
      api,
      () => engine,
      null,
      listenReport: report,
      loadClimax: loader.call,
    );

    await playerUi.playSong(fakeSong());
    expect(report.events, hasLength(1), reason: '工厂把上报缝装进 store');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => playerUi.buildPlayerPage(context)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('高潮 1:05–1:35'), findsOneWidget);
  });
}
