// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读设置面板：字号、背景、字体、动画速度、四个页签与重置。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
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

  testWidgets('菜单页签：动画风格、九宫格面板、长按/双击都能改', (tester) async {
    var last = const NovelReaderSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value) => last = value,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('novel-settings-tab-menu')));
    await tester.pumpAndSettle();

    // 动画风格下拉：默认 slide，改成视差。
    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-page-anim-style')),
    );
    await tester.tap(find.byKey(const Key('novel-settings-page-anim-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视差').last);
    await tester.pumpAndSettle();
    expect(last.pageAnimStyle, NovelPageAnimStyle.parallax);

    // 长按下拉：默认选文，改成菜单。
    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-long-press')),
    );
    await tester.tap(find.byKey(const Key('novel-settings-long-press')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('菜单').last);
    await tester.pumpAndSettle();
    expect(last.longPressAction, NovelLongPressAction.menu);

    // 双击下拉：默认无动作，改成下一页。
    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-double-tap')),
    );
    await tester.tap(find.byKey(const Key('novel-settings-double-tap')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一页').last);
    await tester.pumpAndSettle();
    expect(last.doubleTapAction, NovelDoubleTapAction.nextPage);
  });

  testWidgets('九宫格配置面板：点格子换动作，未实现动作显灰且不可选', (tester) async {
    var last = const NovelReaderSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value) => last = value,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-tab-menu')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-click-zones')),
    );
    await tester.tap(find.byKey(const Key('novel-settings-click-zones')));
    await tester.pumpAndSettle();

    // 面板里 9 个格子都在。
    for (final zone in NovelClickZone.values) {
      expect(find.byKey(Key('novel-click-zone-${zone.name}')), findsOneWidget);
    }

    // 左上格：无动作 → 目录。
    await tester.tap(
      find.byKey(Key('novel-click-zone-${NovelClickZone.topLeft.name}')),
    );
    await tester.pumpAndSettle();
    // 未实现动作显灰：菜单项存在但禁用，文案带「需先完成」。
    final bookmark = tester.widget<PopupMenuItem<NovelClickAction>>(
      find.byKey(const Key('novel-click-action-addBookmark')),
    );
    expect(bookmark.enabled, isFalse);
    expect((bookmark.child! as Text).data, contains('需先完成'));

    await tester.tap(find.byKey(const Key('novel-click-action-catalog')));
    await tester.pumpAndSettle();
    expect(
      last.clickZones[NovelClickZone.topLeft.index],
      NovelClickAction.catalog,
    );

    // 恢复默认。
    await tester.tap(find.byKey(const Key('novel-click-zones-reset')));
    await tester.pumpAndSettle();
    expect(last.clickZones, novelDefaultClickZones);
  });
}
