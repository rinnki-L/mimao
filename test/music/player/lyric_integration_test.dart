// ignore_for_file: deprecated_member_use — 与模块页面测试同款说明。
/// 歌词接线集成测试：fake loadLyric 闭包 + fake engine/playbackApi。
///
/// 验证三件事：解析结果会渲染到播放页右侧；歌词显示模式从本地设置读取并
/// 决定翻译/音译小字；关闭歌词开关时不渲染歌词区。不联网、不 sleep。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/player_store.dart';

import 'player_fakes.dart';

/// 歌词加载闭包替身：记录请求歌曲，可返回固定结果/抛错/挂起。
class _FakeLyricLoader {
  final List<MusicSong> requestedSongs = <MusicSong>[];

  ParsedLyric? result;

  Object? failure;

  Completer<ParsedLyric?>? pending;

  Future<ParsedLyric?> call(MusicSong song) {
    requestedSongs.add(song);
    final error = failure;
    if (error != null) throw error; // 同步抛：验证页面静默吞掉
    final blocker = pending;
    if (blocker != null) return blocker.future;
    return Future<ParsedLyric?>.value(result);
  }
}

ParsedLyric _lyric() => const ParsedLyric(
  lines: <LyricLine>[
    LyricLine(
      start: Duration.zero,
      end: Duration(seconds: 10),
      original: '第一句歌词',
      translation: '第一句翻译',
      transliteration: 'Dai ichi',
    ),
  ],
);

void main() {
  late FakeMusicEngine engine;
  late FakePlaybackApi api;
  late _FakeLyricLoader loader;
  MusicPlayerStore? store;

  setUp(() {
    engine = FakeMusicEngine();
    api = FakePlaybackApi();
    loader = _FakeLyricLoader()..result = _lyric();
  });

  tearDown(() => store?.dispose());

  Future<void> pumpPlayerPage(
    WidgetTester tester, {
    LyricMode mode = LyricMode.original,
    bool lyricEnabled = true,
  }) async {
    final player = store = MusicPlayerStore(
      playbackApi: api,
      engineFactory: () => engine,
      settings: FakeMusicSettings(lyricEnabled: lyricEnabled, lyricMode: mode),
    );
    await player.playSong(fakeSong());
    await tester.pumpWidget(
      MaterialApp(
        home: MusicPlayerPage(player: player, loadLyric: loader.call),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('歌词解析结果渲染到播放页，且按需取词一次', (tester) async {
    await pumpPlayerPage(tester);

    expect(find.text('第一句歌词'), findsOneWidget);
    expect(loader.requestedSongs, hasLength(1));
    expect(loader.requestedSongs.single.hash, fakeSong().hash);
    // 原文模式不显示翻译小字。
    expect(find.text('第一句翻译'), findsNothing);
  });

  for (final (mode, visible, hidden) in <(LyricMode, String, String)>[
    (LyricMode.originalWithTranslation, '第一句翻译', 'Dai ichi'),
    (LyricMode.originalWithTransliteration, 'Dai ichi', '第一句翻译'),
  ]) {
    testWidgets('歌词模式 ${mode.name} 显示对应小字', (tester) async {
      await pumpPlayerPage(tester, mode: mode);

      expect(find.text('第一句歌词'), findsOneWidget);
      expect(find.text(visible), findsOneWidget);
      expect(find.text(hidden), findsNothing);
    });
  }

  testWidgets('关闭歌词开关时不渲染歌词区', (tester) async {
    await pumpPlayerPage(tester, lyricEnabled: false);

    expect(find.text('第一句歌词'), findsNothing);
    expect(find.text('暂无歌词'), findsNothing);
  });

  testWidgets('双击歌词行跳转到该行起始时间', (tester) async {
    await pumpPlayerPage(tester);

    // flutter_test 没有 doubleTap，手动点两次（间隔 50ms 落在双击窗口内）。
    await tester.tap(find.text('第一句歌词'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('第一句歌词'));
    await tester.pumpAndSettle();

    expect(engine.seeks, <Duration>[Duration.zero]);
  });
}
