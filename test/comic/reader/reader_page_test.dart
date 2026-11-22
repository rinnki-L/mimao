// 阅读器 widget 测试：六模式视图 / 三区手势 / 章级三态 / 键盘 / 哨兵切章。
//
// 注入 ReaderController（页面不会自动 open），测试手动 await controller.open()
// 再 pump；假 loader 返回可解码的 1x1 PNG，不碰网络/媒体引擎。
// 注意：CircularProgressIndicator 是无限动画、photo_view 翻页有动画——
// 这些地方用 tester.pump(时长) 而不是 pumpAndSettle。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_controller.dart';
import 'package:mimao/comic/reader/reader_page.dart';
import 'package:mimao/comic/reader/reader_models.dart';

import 'reader_test_env.dart';

/// 可变假章源：既能挂起（Completer）也能失败（failing），失败集合可改，
/// 供"章加载失败 → 改源 → 重试"用例在同一控制器下复用。
class MutableChapterSource implements ReaderChapterSource {
  MutableChapterSource(this.chapters);

  List<ComicChapter> chapters;
  final Set<int> failing = <int>{};
  final Map<int, Completer<List<ReaderImage>>> _pending =
      <int, Completer<List<ReaderImage>>>{};

  void hang(int index) => _pending[index] = Completer<List<ReaderImage>>();
  void resolve(int index, List<ReaderImage> images) =>
      _pending.remove(index)?.complete(images);

  @override
  int get chapterCount => chapters.length;

  @override
  String chapterTitle(int index) => chapters[index].title;

  @override
  String chapterId(int index) => chapters[index].chapterId;

  @override
  Future<List<ReaderImage>> loadImages(int index) {
    final pending = _pending[index];
    if (pending != null) return pending.future;
    if (failing.contains(index)) {
      return Future.error(StateError('章节加载失败：$index'));
    }
    return Future.value(chapters[index].images);
  }
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late ReaderTestEnv env;

  setUp(() => env = ReaderTestEnv.create());
  tearDown(() => env.close());

  Future<ReaderController> pumpReader(
    WidgetTester tester, {
    required ReaderChapterSource source,
    ReaderSettings settings = const ReaderSettings(),
    ReaderImageCache? cache,
  }) async {
    final controller = ReaderController(
      source: source,
      imageCache: cache ?? env.cache,
      settings: settings,
    );
    await controller.open();
    await tester.pumpWidget(
      _app(
        ComicReaderPage(
          title: '尖帽子的魔法工坊',
          source: source,
          imageCache: cache ?? env.cache,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return controller;
  }

  Future<void> settle(WidgetTester tester) async {
    // photo_view 的缩放动画 / 无限转圈不能 pumpAndSettle，固定推进若干帧即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('1 渲染：paged 模式显示图片、页码文本与上下工具栏', (tester) async {
    await pumpReader(tester, source: FakeChapterSource(sampleChapters()));

    expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    expect(find.byKey(const Key('reader-page-label')), findsOneWidget);
    expect(find.byKey(const Key('reader-top-bar')), findsOneWidget);
    expect(find.byKey(const Key('reader-bottom-bar')), findsOneWidget);
    expect(find.text('P1/3'), findsWidgets);
  });

  testWidgets('2 三区单击：右区 +1、左区 -1、中间隐藏/恢复工具栏', (tester) async {
    final controller = await pumpReader(
      tester,
      source: FakeChapterSource(sampleChapters()),
    );
    final view = find.byKey(const Key('reader-paged-view'));
    final rect = tester.getRect(view);

    // 默认工具栏可见：先点中间隐藏，之后单击才翻页。
    await tester.tapAt(rect.center);
    await settle(tester);
    expect(find.byKey(const Key('reader-page-info')), findsOneWidget);
    expect(
      tester
          .widget<AnimatedPositioned>(find.byKey(const Key('reader-top-bar')))
          .top,
      lessThan(0),
    );

    // 右 1/3 → 下一页。
    await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
    await settle(tester);
    expect(controller.pageNumber, 2);

    // 左 1/3 → 上一页。
    await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
    await settle(tester);
    expect(controller.pageNumber, 1);

    // 中间 → 工具栏恢复，常驻页码消失。
    await tester.tapAt(rect.center);
    await settle(tester);
    expect(find.byKey(const Key('reader-page-info')), findsNothing);
    expect(
      tester
          .widget<AnimatedPositioned>(find.byKey(const Key('reader-top-bar')))
          .top,
      0,
    );

    // 再点中间 → 工具栏再次隐藏。
    await tester.tapAt(rect.center);
    await settle(tester);
    expect(find.byKey(const Key('reader-page-info')), findsOneWidget);
  });

  testWidgets('3 拖拽翻页：drag 分页视图后页码前进', (tester) async {
    final controller = await pumpReader(
      tester,
      source: FakeChapterSource(sampleChapters()),
    );
    final view = find.byKey(const Key('reader-paged-view'));

    await tester.drag(view, const Offset(-600, 0));
    await settle(tester);
    expect(controller.pageNumber, 2);
  });

  testWidgets('4 模式循环：点模式按钮切到连续模式后出现列表、分页视图消失', (tester) async {
    final controller = await pumpReader(
      tester,
      source: FakeChapterSource(sampleChapters()),
    );
    expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-mode-button')));
    await settle(tester);
    expect(controller.settings.mode, ReaderMode.pagedRtl);

    await tester.tap(find.byKey(const Key('reader-mode-button')));
    await settle(tester);
    expect(controller.settings.mode, ReaderMode.pagedTtb);

    await tester.tap(find.byKey(const Key('reader-mode-button')));
    await settle(tester);
    expect(controller.settings.mode, ReaderMode.continuousTtb);
    expect(find.byKey(const Key('reader-continuous-list')), findsOneWidget);
    expect(find.byKey(const Key('reader-paged-view')), findsNothing);

    // 连续模式首次布局会触发 setVisibleIndex 的 1s 落库防抖；推进时间消化。
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('5 章加载中：source 挂起时显示章节转圈', (tester) async {
    final source = MutableChapterSource(sampleChapters())..hang(0);
    final controller = ReaderController(source: source, imageCache: env.cache);
    final pending = controller.open(); // 故意不 await：停在图未加载态
    await tester.pumpWidget(
      _app(
        ComicReaderPage(
          title: '加载中',
          source: source,
          imageCache: env.cache,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('reader-chapter-loading')), findsOneWidget);
    expect(find.text('正在加载章节'), findsOneWidget);

    source.resolve(0, sampleChapters().first.images);
    await pending;
    await settle(tester);
  });

  testWidgets('6 章加载失败：显示错误态，改源后点重试恢复', (tester) async {
    final source = MutableChapterSource(sampleChapters())..failing.add(0);
    final controller = await pumpReader(tester, source: source);
    expect(controller.chapterError, isNotNull);
    expect(find.byKey(const Key('reader-chapter-error')), findsOneWidget);
    expect(find.textContaining('章节加载失败'), findsOneWidget);

    source.failing.remove(0);
    await tester.tap(find.byKey(const Key('reader-chapter-retry')));
    await settle(tester);
    expect(controller.chapterError, isNull);
    expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
  });

  testWidgets('7 空章：显示空态（无下一章时不显示跳转按钮）', (tester) async {
    // 单章且为空：控制器的落点解析没有可跳的章，停在空章显示空态。
    await pumpReader(
      tester,
      source: FakeChapterSource(<ComicChapter>[
        const ComicChapter(title: '空章', images: <ReaderImage>[]),
      ]),
    );

    expect(find.byKey(const Key('reader-empty-chapter')), findsOneWidget);
    expect(find.text('本章暂无图片'), findsOneWidget);
    expect(find.textContaining('没有可读的图片'), findsOneWidget);
  });

  testWidgets('8 图片失败：显示占位，点重试仍失败不崩', (tester) async {
    await env.close();
    env = ReaderTestEnv.create(errorUrls: <String>{'p1-1.png'});

    // 连续模式无 photo_view 包装，失败占位可直接点击重试。
    await pumpReader(
      tester,
      source: FakeChapterSource(sampleChapters()),
      cache: env.cache,
      settings: const ReaderSettings(mode: ReaderMode.continuousTtb),
    );
    expect(find.byKey(const Key('reader-image-error-0')), findsOneWidget);
    expect(find.text('图片加载失败'), findsOneWidget);
    expect(find.text('点此重试'), findsOneWidget);

    // 顶部工具栏会挡住列表首项，先点中间把它收起；再按实际位置点占位。
    await tester.tapAt(const Offset(400, 300));
    await settle(tester);
    final errorRect = tester.getRect(
      find.byKey(const Key('reader-image-error-0')),
    );
    await tester.tapAt(Offset(errorRect.center.dx, errorRect.center.dy + 40));
    await settle(tester);
    expect(find.byKey(const Key('reader-image-error-0')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // 消化连续模式滚动防抖
  });

  testWidgets('9 键盘：右方向键页码 +1，Esc 弹栈', (tester) async {
    // 先测方向键（独立 pumpReader）。
    final controller = await pumpReader(
      tester,
      source: FakeChapterSource(sampleChapters()),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(controller.pageNumber, 2);

    // 再用 Navigator.push 推一层阅读页，验证 Esc 会 pop 回主页。
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => navKey.currentState!.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ComicReaderPage(
                    title: '键盘退出',
                    source: FakeChapterSource(sampleChapters()),
                    imageCache: env.cache,
                    controller: controller,
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await settle(tester);
    expect(find.byType(ComicReaderPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    // 路由 pop 是异步的，推进到动画结束。
    await tester.pumpAndSettle();
    expect(find.byType(ComicReaderPage), findsNothing);
  });

  testWidgets('10 哨兵切章：拖入尾哨兵切到下一章第 1 页', (tester) async {
    final controller = await pumpReader(
      tester,
      source: FakeChapterSource(sampleChapters()),
    );
    expect(controller.chapterNumber, 1);

    // 先翻到最后一页（End 键经页面层同步 PageView 位置）。
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settle(tester);
    expect(controller.pageNumber, 3);

    final view = find.byKey(const Key('reader-paged-view'));
    // 向左拖过整屏，滑入尾哨兵（PageView 有页吸附，需要足够位移）。
    await tester.drag(view, const Offset(-1800, 0));
    await settle(tester);
    // 切章是异步的，再推进确保落地。
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.chapterNumber, 2);
    expect(controller.pageNumber, 1);
  });
}
