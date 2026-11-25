// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 朗读：顺序队列推进 / 暂停继续 / 章末续章 / 睡眠定时 / 段落高亮与跟随。
//
// 全部注入 fake 引擎，不起真实语音：Windows 的 SAPI 宿主进程只在手测时跑。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_tts.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

const _source = NovelBookSource(
  key: 'src1',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

final _chapters = <NovelChapter>[
  const NovelChapter(
    id: 'c1',
    title: '第一章',
    index: 0,
    url: 'https://site.test/1',
  ),
  const NovelChapter(
    id: 'c2',
    title: '第二章',
    index: 1,
    url: 'https://site.test/2',
  ),
];

class _FixedStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

/// 两章正文；[paragraphsPerChapter] 控制分页测试的段落数。
class _TwoChapterEngine implements NovelOnlineEngine {
  _TwoChapterEngine({this.paragraphsPerChapter = 1});

  final int paragraphsPerChapter;

  @override
  void close() {}

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async =>
      const <NovelExploreKind>[];

  @override
  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async =>
      NovelDetail(ref: ref, title: '书', author: '作者', chapters: _chapters);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async {
    if (paragraphsPerChapter <= 1) {
      return NovelContent(
        chapterId: chapter.id,
        title: chapter.title,
        paragraphs: <String>['${chapter.title}正文'],
      );
    }
    return NovelContent(
      chapterId: chapter.id,
      title: chapter.title,
      paragraphs: <String>[
        for (var i = 0; i < paragraphsPerChapter; i++)
          '${chapter.title}第$i段：${List<String>.filled(120, '字').join()}',
      ],
    );
  }
}

class _FakeTts implements NovelTtsEngine {
  _FakeTts({this.gateAll = false});

  final bool gateAll;
  final List<String> spoken = <String>[];
  final List<double> rates = <double>[];
  final List<String> spokenVoices = <String>[];
  int stopCalls = 0;
  bool failNext = false;

  /// 闸门只在一次 speak 正等待时存在；否则 stop() 完成的错误没人接会污染
  /// 测试 Zone（真实引擎的 stop 只会让当前 Speak 抛错）。
  Completer<void>? _gate;

  /// 放行当前一次 speak（下一次 speak 会自己开新闸门）。
  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void _cancelGate() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) {
      gate.completeError(StateError('stopped'));
    }
  }

  @override
  bool get supportsFileOutput => false;

  @override
  bool get supportsFilePlayback => false;

  @override
  Future<void> configure() async {}

  @override
  Future<List<NovelTtsVoice>> voices() async => const <NovelTtsVoice>[
    NovelTtsVoice(id: 'Huihui', label: 'Huihui', locale: 'zh-CN'),
    NovelTtsVoice(id: 'Zira', label: 'Zira', locale: 'en-US'),
  ];

  @override
  Future<void> speak(
    String text, {
    required double rate,
    String voice = '',
    String? cacheKey,
  }) async {
    spoken.add(text);
    rates.add(rate);
    spokenVoices.add(voice);
    if (failNext) {
      failNext = false;
      throw StateError('合成失败');
    }
    if (gateAll) {
      final gate = _gate = Completer<void>();
      try {
        await gate.future;
      } finally {
        if (identical(_gate, gate)) _gate = null;
      }
    }
  }

  @override
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  }) async {
    throw UnsupportedError('测试不落盘');
  }

  @override
  Future<void> playFile(String path) async {
    throw UnsupportedError('测试不播放文件');
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _cancelGate();
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  String reason = '条件未满足',
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('$reason（超时 ${timeout.inSeconds}s）');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

NovelTtsPlayer _player(
  _FakeTts engine, {
  Future<List<String>?> Function()? loadNext,
  bool autoNext = true,
  int pauseMs = 0,
  void Function(NovelTtsPlaybackState)? onState,
  void Function(int)? onParagraph,
  void Function(Object)? onError,
}) {
  return NovelTtsPlayer(
    engine: engine,
    runtime: () => NovelTtsRuntime(
      rate: 1.2,
      voice: 'Huihui',
      paragraphPauseMs: pauseMs,
      autoNextChapter: autoNext,
    ),
    loadNextChapter: loadNext ?? () async => null,
    onStateChanged: onState,
    onParagraphChanged: onParagraph,
    onError: onError,
  );
}

void main() {
  group('朗读队列', () {
    test('按段推进，读完自然回到 idle', () async {
      final engine = _FakeTts();
      final states = <NovelTtsPlaybackState>[];
      final player = _player(engine, onState: states.add);
      await player.start(<String>['第一段', '第二段']);
      await player.finished;

      expect(engine.spoken, <String>['第一段', '第二段']);
      expect(engine.rates, <double>[1.2, 1.2]);
      expect(engine.spokenVoices, <String>['Huihui', 'Huihui']);
      expect(player.state, NovelTtsPlaybackState.idle);
      expect(states.first, NovelTtsPlaybackState.speaking);
      expect(states.last, NovelTtsPlaybackState.idle);
    });

    test('暂停后立刻停声，继续时从当前段重读', () async {
      final engine = _FakeTts(gateAll: true);
      final player = _player(engine);
      await player.start(<String>['甲', '乙']);
      await _waitUntil(() => engine.spoken.length == 1, reason: '第一段未开始');

      player.pause();
      expect(player.state, NovelTtsPlaybackState.paused);
      expect(player.isSpeaking, isFalse);
      expect(engine.stopCalls, 1);

      player.resume();
      await _waitUntil(() => engine.spoken.length == 2, reason: '继续后未重读');
      engine.release();
      await _waitUntil(() => engine.spoken.length == 3, reason: '未读第二段');
      engine.release();
      await player.finished;

      expect(engine.spoken, <String>['甲', '甲', '乙']);
      expect(player.state, NovelTtsPlaybackState.idle);
    });

    test('本章读完自动开下一章并从头继续', () async {
      final engine = _FakeTts();
      var nextLoaded = 0;
      final paragraphs = <int>[];
      final player = _player(
        engine,
        loadNext: () async {
          nextLoaded++;
          // 只有一次「下一章」；再次请求 = 书末。
          return nextLoaded == 1 ? <String>['下一章甲', '下一章乙'] : null;
        },
        onParagraph: paragraphs.add,
      );
      await player.start(<String>['本章']);
      await player.finished;

      expect(nextLoaded, 2); // 第二次问「还有下一章吗」= 书末
      expect(engine.spoken, <String>['本章', '下一章甲', '下一章乙']);
      expect(paragraphs, contains(0));
      expect(player.state, NovelTtsPlaybackState.idle);
    });

    test('关闭自动续章后读完本章就停', () async {
      final engine = _FakeTts();
      var nextLoaded = 0;
      final player = _player(
        engine,
        autoNext: false,
        loadNext: () async {
          nextLoaded++;
          return <String>['不该读'];
        },
      );
      await player.start(<String>['本章']);
      await player.finished;

      expect(nextLoaded, 0);
      expect(engine.spoken, <String>['本章']);
    });

    test('跳段打断当前句，从目标段继续', () async {
      final engine = _FakeTts(gateAll: true);
      final player = _player(engine);
      await player.start(<String>['一', '二', '三']);
      await _waitUntil(() => engine.spoken.length == 1, reason: '第一段未开始');

      player.seek(2);
      await _waitUntil(() => engine.spoken.length == 2, reason: '未跳到第三段');
      engine.release();
      await player.finished;

      expect(engine.spoken, <String>['一', '三']);
      expect(player.state, NovelTtsPlaybackState.idle);
    });

    test('后端报错会停读并回调错误', () async {
      final engine = _FakeTts()..failNext = true;
      Object? error;
      final player = _player(engine, onError: (value) => error = value);
      await player.start(<String>['会失败']);
      await _waitUntil(
        () => player.state == NovelTtsPlaybackState.idle,
        reason: '出错后未回 idle',
      );

      expect(error, isA<StateError>());
      expect(player.state, NovelTtsPlaybackState.idle);
    });
  });

  group('控制器朗读', () {
    Future<NovelReaderController> buildController(
      _FakeTts tts, {
      NovelReaderSettings settings = const NovelReaderSettings(),
    }) async {
      final controller = NovelReaderController(
        bookId: 'book-tts',
        title: '书',
        sourceKey: 'src1',
        bookUrl: 'https://site.test/book',
        chapterIndex: 0,
        chapters: _chapters,
        onlineEngine: _TwoChapterEngine(),
        sourceStore: _FixedStore(),
        settingsStore: MemoryNovelReaderSettingsStore(settings),
        ttsEngine: tts,
      );
      await controller.init();
      await controller.bootstrap();
      return controller;
    }

    test('章末自动续章：读完第一章接着读第二章', () async {
      final tts = _FakeTts();
      final controller = await buildController(
        tts,
        settings: const NovelReaderSettings(ttsParagraphPauseMs: 0),
      );
      addTearDown(controller.dispose);

      expect(await controller.startTts(), isTrue);
      await _waitUntil(
        () =>
            controller.chapter?.index == 1 &&
            controller.ttsState == NovelTtsPlaybackState.idle,
        reason: '没有自动续到第二章',
      );

      expect(tts.spoken, <String>['第一章正文', '第二章正文']);
      expect(controller.ttsSleepDeadline, isNull);
    });

    test('睡眠定时到点停读并回调提示', () async {
      final tts = _FakeTts(gateAll: true);
      final controller = await buildController(
        tts,
        settings: const NovelReaderSettings(ttsParagraphPauseMs: 0),
      );
      addTearDown(controller.dispose);
      var fired = 0;
      controller.onTtsSleepTimerFired = () => fired++;

      expect(await controller.startTts(), isTrue);
      await _waitUntil(() => tts.spoken.isNotEmpty, reason: '朗读未开始');
      controller.setTtsSleepTimer(const Duration(milliseconds: 60));
      expect(controller.ttsSleepDeadline, isNotNull);

      await _waitUntil(() => fired == 1, reason: '睡眠定时没有触发');
      expect(controller.ttsActive, isFalse);
      expect(controller.ttsSleepDeadline, isNull);
      expect(tts.stopCalls, greaterThanOrEqualTo(1));
    });

    test('暂停/继续复用同一队列；停止清掉定时', () async {
      final tts = _FakeTts(gateAll: true);
      final controller = await buildController(
        tts,
        settings: const NovelReaderSettings(ttsParagraphPauseMs: 0),
      );
      addTearDown(controller.dispose);

      expect(await controller.startTts(), isTrue);
      await _waitUntil(() => tts.spoken.isNotEmpty, reason: '朗读未开始');
      controller.pauseTts();
      expect(controller.ttsPaused, isTrue);

      controller.resumeTts();
      expect(controller.ttsSpeaking, isTrue);

      controller.setTtsSleepTimer(const Duration(minutes: 15));
      expect(controller.ttsSleepDeadline, isNotNull);
      await controller.stopTts();
      expect(controller.ttsActive, isFalse);
      expect(controller.ttsSleepDeadline, isNull);
    });

    test('朗读参数从设置读取（语速/音色/段间停顿）', () async {
      final tts = _FakeTts();
      final controller = await buildController(
        tts,
        settings: const NovelReaderSettings(
          ttsRate: 1.5,
          ttsVoice: 'Huihui',
          ttsParagraphPauseMs: 0,
        ),
      );
      addTearDown(controller.dispose);

      expect(await controller.startTts(), isTrue);
      await _waitUntil(() => !controller.ttsActive, reason: '朗读未结束');
      expect(tts.rates.every((rate) => rate == 1.5), isTrue);
      expect(tts.spokenVoices.every((voice) => voice == 'Huihui'), isTrue);
    });

    test('系统音色列表透传（中文音色排前）', () async {
      final tts = _FakeTts();
      final controller = await buildController(tts);
      addTearDown(controller.dispose);

      final voices = await controller.availableTtsVoices();
      expect(voices.map((voice) => voice.id), <String>['Huihui', 'Zira']);
    });
  });

  group('阅读页朗读界面', () {
    testWidgets('开始朗读后当前段高亮，手动翻页默认暂停', (tester) async {
      final tts = _FakeTts(gateAll: true);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelReaderPage(
            bookId: 'book-ui',
            title: '书',
            sourceKey: 'src1',
            bookUrl: 'https://site.test/book',
            chapterIndex: 0,
            chapters: _chapters,
            onlineEngine: _TwoChapterEngine(paragraphsPerChapter: 30),
            sourceStore: _FixedStore(),
            settingsStore: MemoryNovelReaderSettingsStore(
              const NovelReaderSettings(ttsParagraphPauseMs: 0),
            ),
            ttsEngine: tts,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('novel-reader-tts')));
      await tester.pump();
      expect(find.byKey(const Key('novel-tts-current-0')), findsOneWidget);

      // 默认策略「暂停」：手动翻页立刻停声，且不会把朗读位置带到新页。
      await tester.tapAt(const Offset(760, 300));
      await tester.pumpAndSettle();
      expect(tts.stopCalls, greaterThanOrEqualTo(1));
      // 默认「暂停」：不会把朗读位置带去新页，也不会继续读下一段。
      // （段落底色仍停在原段，只是被滚出了视口，所以这里不查 widget。）
      expect(tts.spoken.length, 1);
    });

    testWidgets('跟随策略：手动翻页把朗读位置移到新页首段', (tester) async {
      final tts = _FakeTts(gateAll: true);
      await tester.pumpWidget(
        MaterialApp(
          home: NovelReaderPage(
            bookId: 'book-follow',
            title: '书',
            sourceKey: 'src1',
            bookUrl: 'https://site.test/book',
            chapterIndex: 0,
            chapters: _chapters,
            onlineEngine: _TwoChapterEngine(paragraphsPerChapter: 80),
            sourceStore: _FixedStore(),
            settingsStore: MemoryNovelReaderSettingsStore(
              const NovelReaderSettings(
                pageMode: NovelPageMode.page,
                ttsParagraphPauseMs: 0,
                ttsTurnPagePolicy: NovelTtsTurnPolicy.follow,
              ),
            ),
            ttsEngine: tts,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('novel-reader-tts')));
      await tester.pump();
      expect(tts.spoken.length, 1);

      // 右半屏翻页，跟随策略会 seek 到新页第一段。
      await tester.tapAt(const Offset(760, 300));
      await tester.pumpAndSettle();
      expect(tts.spoken.length, greaterThanOrEqualTo(2));
      expect(tts.stopCalls, greaterThanOrEqualTo(1));
      // 新页也有一段被标记为「正在读」。
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'novel-tts-current-',
              ),
        ),
        findsOneWidget,
      );
    });
  });
}
