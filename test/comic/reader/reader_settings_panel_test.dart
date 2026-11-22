// 阅读设置面板 widget 测试：模式选择、开关、滑块回调与渲染。
//
// 面板是纯展示层，测试只注入设置快照并收集 onChanged 抛出的新快照，
// 不读盘、不依赖阅读引擎与 native QuickJS。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_settings.dart';
import 'package:mimao/comic/reader/reader_settings_panel.dart';
import 'package:mimao/comic/reader/reader_view_mode.dart';
import 'package:mimao/core/theme.dart';

void main() {
  late List<ReaderSettings> changes;

  setUp(() => changes = <ReaderSettings>[]);

  Future<void> pumpPanel(
    WidgetTester tester, {
    ReaderSettings initial = const ReaderSettings(),
    VoidCallback? onClose,
  }) async {
    // 面板内容长，放大测试画布让 ListView 一次建出全部条目，便于断言。
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMimaoTheme(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: ReaderSettingsPanel(
            initial: initial,
            onChanged: changes.add,
            onClose: onClose,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('初始渲染：标题、关闭按钮、七种模式与各开关都在', (tester) async {
    await pumpPanel(tester);

    expect(find.byKey(const Key('reader-settings-title')), findsOneWidget);
    expect(find.text('阅读设置'), findsOneWidget);
    expect(find.byKey(const Key('reader-settings-close')), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    for (final mode in ReaderViewMode.values) {
      expect(find.text(mode.label), findsOneWidget);
    }
    expect(
      find.byKey(const Key('reader-settings-images-per-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-first-page-single')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-tap-to-turn')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-reverse-tap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-double-tap-zoom')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-long-press-zoom')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-page-animation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-show-page-number')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-limit-image-width')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-dim-brightness-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-preload-count-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-scroll-speed-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reader-settings-auto-interval-slider')),
      findsOneWidget,
    );
  });

  testWidgets('点模式 chip：onChanged 携带新模式，其它字段不变', (tester) async {
    const initial = ReaderSettings(imagesPerPage: 3, scrollSpeed: 1.5);
    await pumpPanel(tester, initial: initial);

    await tester.tap(
      find.byKey(const Key('reader-settings-mode-galleryRightToLeft')),
    );
    await tester.pumpAndSettle();

    expect(changes, hasLength(1));
    expect(changes.single.mode, ReaderViewMode.galleryRightToLeft);
    expect(changes.single.imagesPerPage, 3);
    expect(changes.single.scrollSpeed, 1.5);

    // 再点另一模式，面板内部状态已切换，回调携带最新选择。
    await tester.tap(
      find.byKey(const Key('reader-settings-mode-continuousTopToBottom')),
    );
    await tester.pumpAndSettle();
    expect(changes, hasLength(2));
    expect(changes.last.mode, ReaderViewMode.continuousTopToBottom);
    expect(changes.last.imagesPerPage, 3);
  });

  testWidgets('每屏图数分段按钮：切换后回调携带新值', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();

    expect(changes, hasLength(1));
    expect(changes.single.imagesPerPage, 4);
  });

  testWidgets('切开关：onChanged 携带新值，其余字段保持原样', (tester) async {
    const initial = ReaderSettings(
      tapToTurnPages: true,
      showPageNumber: true,
      dimBrightness: 60,
    );
    await pumpPanel(tester, initial: initial);

    await tester.tap(find.byKey(const Key('reader-settings-tap-to-turn')));
    await tester.pumpAndSettle();

    expect(changes, hasLength(1));
    expect(changes.single.tapToTurnPages, isFalse);
    expect(changes.single.showPageNumber, isTrue);
    expect(changes.single.dimBrightness, 60);
    expect(changes.single.mode, initial.mode);
    expect(
      changes.single.toJson(),
      initial.copyWith(tapToTurnPages: false).toJson(),
    );
  });

  testWidgets('阅读亮度滑块：按初始值渲染，拖动后回调新值且其余字段不变', (tester) async {
    const initial = ReaderSettings(dimBrightness: 80, preloadCount: 5);
    await pumpPanel(tester, initial: initial);

    final slider = find.byKey(
      const Key('reader-settings-dim-brightness-slider'),
    );
    expect(tester.widget<Slider>(slider).value, 80);
    expect(find.text('80'), findsWidgets);

    // 从滑块中心向左拖 → 值变小；具体落点不追求精确，只验证回调与区间。
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(changes, isNotEmpty);
    final next = changes.last;
    expect(next.dimBrightness, lessThan(80));
    expect(next.dimBrightness, inInclusiveRange(20, 100));
    expect(next.preloadCount, 5);
    expect(next.mode, initial.mode);
    expect(
      tester
          .widget<Slider>(
            find.byKey(const Key('reader-settings-dim-brightness-slider')),
          )
          .value,
      next.dimBrightness.toDouble(),
    );
  });

  testWidgets('滑块按 initial 渲染预加载/速度/间隔的当前值', (tester) async {
    const initial = ReaderSettings(
      preloadCount: 8,
      scrollSpeed: 2.0,
      autoReadingInterval: 12,
    );
    await pumpPanel(tester, initial: initial);

    final preload = tester.widget<Slider>(
      find.byKey(const Key('reader-settings-preload-count-slider')),
    );
    final speed = tester.widget<Slider>(
      find.byKey(const Key('reader-settings-scroll-speed-slider')),
    );
    final interval = tester.widget<Slider>(
      find.byKey(const Key('reader-settings-auto-interval-slider')),
    );
    expect(preload.value, 8);
    expect(speed.value, 2.0);
    expect(interval.value, 12);
    expect(find.text('8 张'), findsOneWidget);
    expect(find.text('2.0x'), findsOneWidget);
    expect(find.text('12 秒'), findsOneWidget);
  });

  testWidgets('关闭按钮触发 onClose', (tester) async {
    var closed = false;
    await pumpPanel(tester, onClose: () => closed = true);

    await tester.tap(find.byKey(const Key('reader-settings-close')));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}
