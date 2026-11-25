// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读设置面板：字号、背景、字体、动画速度、四个页签与重置。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_menu_actions.dart';
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
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                last = value,
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

    // 菜单页签：显示页脚开关（菜单外观与三处按钮编辑器在它上面，先滚到可见）。
    await tester.tap(find.byKey(const Key('novel-settings-tab-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-show-footer')),
    );
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
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                last = value,
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
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                last = value,
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

  testWidgets('设置搜索：跨页签过滤、命中高亮、点结果跳到对应页签', (tester) async {
    var last = const NovelReaderSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                last = value,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('novel-settings-search')),
      '背景',
    );
    await tester.pumpAndSettle();

    // 跨页签命中：结果列表里既有「背景」也有「背景图」。
    expect(
      find.byKey(const Key('novel-settings-search-results')),
      findsOneWidget,
    );
    expect(find.text('背景'), findsWidgets);
    expect(find.text('背景图'), findsOneWidget);
    // 命中片段用主色加粗高亮（Text.rich）。
    final highlighted = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const Key('novel-settings-search-hit-背景')),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(highlighted.textSpan, isNotNull);

    // 点「字号」这条会跳到全局页签并清空搜索。
    await tester.enterText(
      find.byKey(const Key('novel-settings-search')),
      '字号',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-search-hit-字号')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-settings-font-plus')), findsOneWidget);
    expect(
      find.byKey(const Key('novel-settings-search-results')),
      findsNothing,
    );
    expect(last, isA<NovelReaderSettings>());
  });

  testWidgets('设置搜索：没有匹配时给空态说明', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value, {scope = NovelSettingsScope.global}) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('novel-settings-search')),
      '不存在的设置项',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-settings-search-empty')),
      findsOneWidget,
    );
    expect(find.textContaining('没有匹配'), findsOneWidget);
    // 空态要说明下一步，而不只是「无结果」。
    expect(find.textContaining('清空搜索框'), findsOneWidget);

    // 清空后回到当前页签。
    await tester.tap(find.byKey(const Key('novel-settings-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-settings-font-plus')), findsOneWidget);
  });

  testWidgets('每书设置：默认改全局，切换后只改这本', (tester) async {
    final scopes = <NovelSettingsScope>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                scopes.add(scope),
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认是「改全局」。
    expect(find.text('改全局'), findsOneWidget);
    await tester.tap(find.byKey(const Key('novel-settings-font-plus')));
    await tester.pump();
    expect(scopes, <NovelSettingsScope>[NovelSettingsScope.global]);

    // 切到「只改这本」后再改，scope 变 book。
    await tester.tap(find.byKey(const Key('novel-settings-scope')));
    await tester.pump();
    expect(find.text('只改这本'), findsOneWidget);
    await tester.tap(find.byKey(const Key('novel-settings-font-plus')));
    await tester.pump();
    expect(scopes.last, NovelSettingsScope.book);
  });

  testWidgets('每书设置：有覆盖时提示可一键跟随全局', (tester) async {
    var cleared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            hasBookOverride: true,
            onClearBookOverride: () => cleared = true,
            onChanged: (value, {scope = NovelSettingsScope.global}) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('这本书有独立设置'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('novel-settings-clear-book-override')),
    );
    await tester.pump();
    expect(cleared, isTrue);
  });

  testWidgets('菜单外观：每行个数/行数/圆角/图标文字/紧凑标题栏都能改', (tester) async {
    var last = const NovelReaderSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                last = value,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-tab-menu')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-menu-icon-text')),
    );
    await tester.tap(find.byKey(const Key('novel-settings-menu-icon-text')));
    await tester.pump();
    expect(last.menuShowIconText, isTrue);

    await tester.tap(find.byKey(const Key('novel-settings-title-bar-compact')));
    await tester.pump();
    expect(last.titleBarCompact, isTrue);

    // 滑杆：把每行个数拖到最大，值应被写进设置。
    final slider = find.byKey(const Key('novel-settings-menu-items-per-row'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(
      last.menuIconItemsPerRow,
      NovelReaderSettings.maxMenuIconItemsPerRow,
    );
  });

  testWidgets('菜单编辑器：加动作、调顺序、禁用、移除、恢复默认', (tester) async {
    var last = const NovelReaderSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelReaderSettingsSheet(
            initial: const NovelReaderSettings(),
            info: const NovelReaderBookInfo(),
            onChanged: (value, {scope = NovelSettingsScope.global}) =>
                last = value,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-tab-menu')));
    await tester.pumpAndSettle();

    // 浮动行默认空，空态说明「为什么空 + 下一步」。
    await tester.ensureVisible(
      find.byKey(const Key('novel-settings-menu-empty-floatingBar')),
    );
    expect(
      find.byKey(const Key('novel-settings-menu-empty-floatingBar')),
      findsOneWidget,
    );

    // 往浮动行加「上一章」。
    final addKey = find.byKey(
      const Key('novel-settings-menu-add-floatingBar-previousChapter'),
    );
    await tester.ensureVisible(addKey);
    await tester.tap(addKey);
    await tester.pumpAndSettle();
    expect(last.floatingBarMenu.map((item) => item.id), <String>[
      novelMenuActionPreviousChapter,
    ]);

    // 再加一个「下一章」，然后把它上移到前面。
    await tester.tap(
      find.byKey(const Key('novel-settings-menu-add-floatingBar-nextChapter')),
    );
    await tester.pumpAndSettle();
    expect(last.floatingBarMenu.length, 2);

    final upKey = find.byKey(
      const Key('novel-settings-menu-up-floatingBar-nextChapter'),
    );
    await tester.ensureVisible(upKey);
    await tester.pumpAndSettle();
    await tester.tap(upKey);
    await tester.pumpAndSettle();
    expect(last.floatingBarMenu.map((item) => item.id), <String>[
      novelMenuActionNextChapter,
      novelMenuActionPreviousChapter,
    ]);

    // 禁用其中一项：配置里仍保留，但 enabled=false。
    final toggleKey = find.byKey(
      const Key('novel-settings-menu-toggle-floatingBar-nextChapter'),
    );
    await tester.ensureVisible(toggleKey);
    await tester.pumpAndSettle();
    await tester.tap(toggleKey);
    await tester.pumpAndSettle();
    expect(last.floatingBarMenu.first.enabled, isFalse);

    // 移除一项。
    final removeKey = find.byKey(
      const Key('novel-settings-menu-remove-floatingBar-nextChapter'),
    );
    await tester.ensureVisible(removeKey);
    await tester.pumpAndSettle();
    await tester.tap(removeKey);
    await tester.pumpAndSettle();
    expect(last.floatingBarMenu.map((item) => item.id), <String>[
      novelMenuActionPreviousChapter,
    ]);

    // 恢复默认：浮动行清空。
    final resetKey = find.byKey(
      const Key('novel-settings-menu-reset-floatingBar'),
    );
    await tester.ensureVisible(resetKey);
    await tester.pumpAndSettle();
    await tester.tap(resetKey);
    await tester.pumpAndSettle();
    expect(last.floatingBarMenu, isEmpty);
  });
}
