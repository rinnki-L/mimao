// ignore_for_file: deprecated_member_use — 与 lib/music/lyric/lyric_view.dart 同款说明。
/// 歌词视图测试：三种模式、缺失翻译/音译的降级、当前行高亮、双击跳转、
/// 单击不误触、自动滚动与无歌词提示。全部使用固定时间轴，不涉及 I/O
/// 或无限动画。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/lyric/lyric_view.dart';

const ParsedLyric _lyric = ParsedLyric(
  lines: <LyricLine>[
    LyricLine(
      start: Duration.zero,
      end: Duration(seconds: 5),
      original: '第一行',
      translation: '第一行翻译',
      transliteration: 'da i chi gyou',
    ),
    LyricLine(
      start: Duration(seconds: 5),
      end: Duration(seconds: 10),
      original: '第二行',
      translation: '第二行翻译',
      transliteration: 'ni gyou',
    ),
  ],
);

Widget _wrap(Widget child, {double height = 400}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    ),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(height: height, width: 400, child: child),
    ),
  );
}

Widget _view({
  ParsedLyric? lyric = _lyric,
  Duration position = Duration.zero,
  LyricMode mode = LyricMode.original,
}) => LyricView(lyric: lyric, position: position, mode: mode);

Text _text(WidgetTester tester, String data) =>
    tester.widget<Text>(find.text(data));

Color _primary(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(LyricView))).colorScheme.primary;

void main() {
  testWidgets('original 模式只显示原文', (tester) async {
    await tester.pumpWidget(_wrap(_view()));
    await tester.pumpAndSettle();

    expect(find.text('第一行'), findsOneWidget);
    expect(find.text('第二行'), findsOneWidget);
    expect(find.text('第一行翻译'), findsNothing);
    expect(find.text('da i chi gyou'), findsNothing);
  });

  testWidgets('originalWithTranslation 显示翻译，不显示音译', (tester) async {
    await tester.pumpWidget(
      _wrap(_view(mode: LyricMode.originalWithTranslation)),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一行翻译'), findsOneWidget);
    expect(find.text('第二行翻译'), findsOneWidget);
    expect(find.text('da i chi gyou'), findsNothing);
    expect(_text(tester, '第一行翻译').style?.color, Colors.white70);
  });

  testWidgets('originalWithTransliteration 显示音译，不显示翻译', (tester) async {
    await tester.pumpWidget(
      _wrap(_view(mode: LyricMode.originalWithTransliteration)),
    );
    await tester.pumpAndSettle();

    expect(find.text('da i chi gyou'), findsOneWidget);
    expect(find.text('ni gyou'), findsOneWidget);
    expect(find.text('第一行翻译'), findsNothing);
    expect(_text(tester, 'da i chi gyou').style?.color, Colors.white70);
  });

  testWidgets('翻译缺失时只显示原文，不出现空壳', (tester) async {
    const withoutAux = ParsedLyric(
      lines: <LyricLine>[
        LyricLine(
          start: Duration.zero,
          end: Duration(seconds: 5),
          original: '只有原文',
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(_view(lyric: withoutAux, mode: LyricMode.originalWithTranslation)),
    );
    await tester.pumpAndSettle();

    expect(find.text('只有原文'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('当前行用主色加粗，其它行白色常规', (tester) async {
    await tester.pumpWidget(_wrap(_view(position: const Duration(seconds: 1))));
    await tester.pumpAndSettle();

    final current = _text(tester, '第一行');
    expect(current.style?.color, _primary(tester));
    expect(current.style?.fontWeight, FontWeight.bold);

    final other = _text(tester, '第二行');
    expect(other.style?.color, Colors.white);
    expect(other.style?.fontWeight, FontWeight.normal);
  });

  testWidgets('播放位置跨行后高亮切换到下一行', (tester) async {
    await tester.pumpWidget(_wrap(_view(position: const Duration(seconds: 1))));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_wrap(_view(position: const Duration(seconds: 6))));
    await tester.pumpAndSettle();

    expect(_text(tester, '第二行').style?.color, _primary(tester));
    expect(_text(tester, '第二行').style?.fontWeight, FontWeight.bold);
    expect(_text(tester, '第一行').style?.color, Colors.white);
    expect(_text(tester, '第一行').style?.fontWeight, FontWeight.normal);
  });

  testWidgets('双击歌词行回调对应的 LyricLine', (tester) async {
    final tapped = <LyricLine>[];
    await tester.pumpWidget(
      _wrap(
        LyricView(
          lyric: _lyric,
          position: Duration.zero,
          mode: LyricMode.original,
          onLineTap: tapped.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // flutter_test 没有 doubleTap，这里手动点两次：间隔 50ms，
    // 大于 kDoubleTapMinTime(40ms)、小于 kDoubleTapTimeout(300ms)。
    await tester.tap(find.text('第二行'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('第二行'));
    await tester.pump();

    expect(tapped, hasLength(1));
    expect(tapped.single.original, '第二行');
    expect(tapped.single.start, const Duration(seconds: 5));

    // 双击识别器为每次 tap 预留 40ms 最短间隔计时器，推掉它，
    // 避免测试结束时报 pending timer。
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('单击歌词行不触发跳转（避免误触）', (tester) async {
    final tapped = <LyricLine>[];
    await tester.pumpWidget(
      _wrap(
        LyricView(
          lyric: _lyric,
          position: Duration.zero,
          mode: LyricMode.original,
          onLineTap: tapped.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二行'));
    await tester.pump();
    expect(tapped, isEmpty);

    // 推过双击判定窗口（300ms），确认单击不会在窗口过期后补发回调，
    // 同时清掉手势识别器残留的计时器，避免测试结束时报 pending timer。
    await tester.pump(const Duration(milliseconds: 350));
    expect(tapped, isEmpty);
  });

  testWidgets('当前行随播放位置自动滚动到可视区', (tester) async {
    final lines = List<LyricLine>.generate(30, (i) {
      return LyricLine(
        start: Duration(seconds: i * 5),
        end: Duration(seconds: (i + 1) * 5),
        original: '第$i行',
      );
    });
    await tester.pumpWidget(
      _wrap(
        _view(
          lyric: ParsedLyric(lines: lines),
          position: const Duration(seconds: 100),
        ),
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('无歌词时显示温和提示', (tester) async {
    await tester.pumpWidget(_wrap(_view(lyric: null)));
    await tester.pumpAndSettle();
    expect(find.text('暂无歌词'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(_view(lyric: const ParsedLyric(lines: <LyricLine>[]))),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无歌词'), findsOneWidget);
  });
}
