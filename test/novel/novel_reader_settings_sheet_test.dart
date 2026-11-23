// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读设置面板：字号、背景、字体、动画速度、四个页签与重置。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_reader_settings_sheet.dart';

void main() {
  testWidgets('设置面板：常用项与页签都能改，重置回默认', (tester) async {
    var last = const NovelReaderSettings();
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(
              bookTitle: '目标书',
              author: '作者',
              sourceName: '测试源',
              chapterTitle: '第一章',
              chapterIndex: 1,
              chapterCount: 12,
              page: 2,
              pageCount: 4,
              percent: 12.5,
            ),
            onChanged: (value) => last = value,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('阅读界面'), findsOneWidget);

    // 字号 +1。
    await tester.tap(find.byKey(const Key('novel-settings-font-plus')));
    await tester.pump();
    expect(last.fontSize, 21);

    // 选纯黑背景。
    await tester.tap(find.byKey(const Key('novel-settings-background-0')));
    await tester.pump();
    expect(last.backgroundIndex, 0);
    expect(last.customBackgroundArgb, isNull);

    // 护眼开关。
    await tester.tap(find.byKey(const Key('novel-settings-eye-protection')));
    await tester.pump();
    expect(last.eyeProtection, isTrue);

    // Tt 字体。
    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-font-family')),
    );
    await tester.tap(find.byKey(const Key('novel-settings-font-family')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('宋体'));
    await tester.pumpAndSettle();
    expect(last.fontFamily, 'SimSun');

    // 翻页动画速度。
    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-animation-speed')),
    );
    await tester.tap(find.byKey(const Key('novel-settings-animation-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('极速'));
    await tester.pumpAndSettle();
    expect(last.pageAnimationMs, 120);

    // 菜单页签：显示页脚开关。
    await tester.tap(find.byKey(const Key('novel-settings-tab-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-show-footer')));
    await tester.pump();
    expect(last.showFooter, isFalse);

    // 信息页签：页脚槽位。
    await tester.tap(find.byKey(const Key('novel-settings-tab-info')));
    await tester.pumpAndSettle();
    expect(find.text('页脚左槽'), findsOneWidget);
    expect(find.text('目标书'), findsOneWidget);

    // 更多页签：行距滑杆与恢复默认。
    await tester.tap(find.byKey(const Key('novel-settings-tab-more')));
    await tester.pumpAndSettle();
    expect(find.text('行距'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('novel-settings-reset')));
    await tester.tap(find.byKey(const Key('novel-settings-reset')));
    await tester.pump();
    expect(last.fontSize, 20);
    expect(last.fontFamily, '');
    expect(last.backgroundIndex, novelReaderDefaultBackground);
    expect(last.eyeProtection, isFalse);
    expect(closed, isFalse);
  });
}
