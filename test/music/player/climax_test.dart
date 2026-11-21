// ignore_for_file: deprecated_member_use — 与模块页面测试同款说明。
/// 歌曲高潮测试（L4）：fake loadClimax 闭包 + fake engine/playbackApi。
///
/// 高潮 chip 已删除，区间改为内化进波浪进度条（`WavySliderTheme.climaxSpans`），
/// 页面只在有时段时给进度条挂 `Semantics(label: '含高潮区间')` 供断言。覆盖
/// 成功标注、失败/无数据不标注、hash 非 32 位不请求、换歌丢弃旧结果、
/// UIImpl/mini player/工厂透传；不真实 sleep、不联网。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/player/pages/music_mini_player.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/playback_engine.dart';
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

/// 进度条上的「含高潮区间」语义标签（仅当页面的 climaxSpans 非空时存在）。
Finder _climaxMarker() => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == '含高潮区间',
  description: '含高潮区间的进度条语义标签',
);

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

  /// 给引擎一个非零时长：高潮区间要按时长归一化才画得出来。playing 保持
  /// false，避免唱片旋转动画干扰测试。
  Future<void> emitDuration(WidgetTester tester) async {
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration.zero,
        duration: Duration(seconds: 200),
        playing: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPlayerPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicPlayerPage(player: store, loadClimax: loader.call),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('成功：高潮区间内化进进度条，不再渲染 chip', (tester) async {
    loader.results[fakeSong().hash] = <MusicSongClimaxSegment>[segmentA];
    await store.playSong(fakeSong());
    await pumpPlayerPage(tester);
    await emitDuration(tester);

    expect(loader.requestedHashes, <String>[fakeSong().hash]);
    // 旧的高潮 chip 整段移除。
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('高潮 1:05–1:35'), findsNothing);
    // 区间被交给进度条：出现语义标注钩子。
    expect(_climaxMarker(), findsOneWidget, reason: '高潮区间应由进度条内部标注');
  });

  testWidgets('失败：静默不标注、不重试、不影响播放状态', (tester) async {
    loader.failures.add(fakeSong().hash);
    await store.playSong(fakeSong());
    await pumpPlayerPage(tester);
    await emitDuration(tester);

    expect(find.byType(ActionChip), findsNothing);
    expect(find.textContaining('高潮'), findsNothing);
    expect(_climaxMarker(), findsNothing);
    expect(loader.requestedHashes, hasLength(1));
    expect(store.error, isNull);
    expect(engine.playCalls, 1);
  });

  testWidgets('无数据：空列表不标注进进度条', (tester) async {
    await store.playSong(fakeSong());
    await pumpPlayerPage(tester);
    await emitDuration(tester);
    expect(find.textContaining('高潮'), findsNothing);
    expect(_climaxMarker(), findsNothing);
  });

  testWidgets('hash 非 32 位：不发起请求', (tester) async {
    await store.playSong(fakeSong(hash: 'not-a-32-char-hash'));
    await pumpPlayerPage(tester);
    await emitDuration(tester);

    expect(loader.requestedHashes, isEmpty);
    expect(find.textContaining('高潮'), findsNothing);
    expect(_climaxMarker(), findsNothing);
  });

  testWidgets('换歌：丢弃旧结果，只标注新歌区间，各请求一次', (tester) async {
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
    await emitDuration(tester);
    expect(find.textContaining('高潮'), findsNothing, reason: 'A 尚未返回');
    expect(_climaxMarker(), findsNothing);
    expect(loader.requestedHashes, <String>[hashA]);

    // 换到 B：旧请求作废，B 的结果正常标注。
    await store.playSong(fakeSong(id: '2', hash: hashB));
    await tester.pumpAndSettle();
    await emitDuration(tester);
    expect(_climaxMarker(), findsOneWidget);
    expect(loader.requestedHashes, <String>[hashA, hashB]);

    // A 的慢请求此刻才回来：按歌曲 key 比对后丢弃，不额外标注。
    loader.pending[hashA]!.complete(<MusicSongClimaxSegment>[segmentA]);
    await tester.pumpAndSettle();
    expect(_climaxMarker(), findsOneWidget, reason: '仍只标注 B 的区间');
    expect(find.text('高潮 1:05–1:35'), findsNothing);
    expect(find.text('高潮 2:00–2:30'), findsNothing);
  });

  testWidgets('loadClimax 为 null：不标注且不发请求', (tester) async {
    await store.playSong(fakeSong());
    await tester.pumpWidget(MaterialApp(home: MusicPlayerPage(player: store)));
    await tester.pumpAndSettle();
    await emitDuration(tester);
    expect(find.textContaining('高潮'), findsNothing);
    expect(_climaxMarker(), findsNothing);
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
    await emitDuration(tester);
    expect(_climaxMarker(), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
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
    await emitDuration(tester);
    expect(find.byType(MusicPlayerPage), findsOneWidget);
    expect(_climaxMarker(), findsOneWidget);
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
    await emitDuration(tester);
    expect(_climaxMarker(), findsOneWidget);
  });
}
