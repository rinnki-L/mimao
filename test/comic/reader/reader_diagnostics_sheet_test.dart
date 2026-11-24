// 诊断面板 UI：开始/停止、复制、清除、预览；无采集时给引导文案。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_diagnostics.dart';
import 'package:mimao/comic/reader/reader_diagnostics_sheet.dart';

ReaderDiagnostics _diagnostics() => ReaderDiagnostics(
  nowMicros: () => 0,
  attachTimings: (_) {},
  detachTimings: (_) {},
);

Widget _app(ReaderDiagnostics diagnostics) => MaterialApp(
  home: Scaffold(body: ReaderDiagnosticsSheet(diagnostics: diagnostics)),
);

void main() {
  testWidgets('无采集时显示引导文案，开始按钮可用', (tester) async {
    final diagnostics = _diagnostics();
    addTearDown(diagnostics.dispose);
    await tester.pumpWidget(_app(diagnostics));

    expect(find.textContaining('还没有采集结果'), findsOneWidget);
    expect(find.byKey(const Key('reader-diagnostics-copy')), findsNothing);

    await tester.tap(find.byKey(const Key('reader-diagnostics-toggle')));
    await tester.pump();
    expect(diagnostics.isRecording, isTrue);
    expect(find.text('停止采集'), findsOneWidget);
  });

  testWidgets('停止后出现复制/保存/预览', (tester) async {
    final diagnostics = _diagnostics();
    addTearDown(diagnostics.dispose);
    await tester.pumpWidget(_app(diagnostics));

    await tester.tap(find.byKey(const Key('reader-diagnostics-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reader-diagnostics-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-diagnostics-copy')), findsOneWidget);
    expect(find.byKey(const Key('reader-diagnostics-save')), findsOneWidget);
    expect(find.byKey(const Key('reader-diagnostics-preview')), findsOneWidget);
    expect(find.textContaining('"schema": 3'), findsOneWidget);
  });

  testWidgets('清除后回到引导文案', (tester) async {
    final diagnostics = _diagnostics();
    addTearDown(diagnostics.dispose);
    await tester.pumpWidget(_app(diagnostics));

    await tester.tap(find.byKey(const Key('reader-diagnostics-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reader-diagnostics-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-diagnostics-clear')));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有采集结果'), findsOneWidget);
    expect(diagnostics.hasCapture, isFalse);
  });

  testWidgets('关闭按钮在面板里可点（不抛异常）', (tester) async {
    final diagnostics = _diagnostics();
    addTearDown(diagnostics.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) =>
                      ReaderDiagnosticsSheet(diagnostics: diagnostics),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('阅读诊断'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-diagnostics-close')));
    await tester.pumpAndSettle();
    expect(find.text('阅读诊断'), findsNothing, reason: '关闭后弹层消失');
  });
}
