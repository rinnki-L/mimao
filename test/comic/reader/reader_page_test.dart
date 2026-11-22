// 阅读器 widget 测试（验收：图片列表渲染、切章 UI 更新、加载失败占位）。
//
// 用 fake loader 返回可解码的 1x1 PNG 字节（成功）或抛异常（失败），
// 不碰真实网络、不初始化 media_kit、不依赖 A′ 源引擎。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_page.dart';
import 'package:mimao/comic/reader/reader_models.dart';

import 'reader_test_env.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late ReaderTestEnv env;

  setUp(() {
    env = ReaderTestEnv.create();
  });

  tearDown(() => env.close());

  Future<void> pumpReader(
    WidgetTester tester, {
    Set<String> errorUrls = const <String>{},
    ReaderMode mode = ReaderMode.pagedLtr,
  }) async {
    if (errorUrls.isNotEmpty) {
      await env.close();
      env = ReaderTestEnv.create(errorUrls: errorUrls);
    }
    await tester.pumpWidget(
      _app(
        ComicReaderPage(
          title: '尖帽子的魔法工坊',
          chapters: sampleChapters(),
          imageCache: env.cache,
          initialMode: mode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('图片列表渲染：翻页模式显示当前页图片与章节信息', (tester) async {
    await pumpReader(tester);

    expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    expect(find.byKey(const Key('reader-info')), findsOneWidget);
    expect(find.textContaining('第 1 章 · 1/3'), findsOneWidget);
  });

  testWidgets('切章 UI 更新：点下一章后标题与页码刷新到新章第 1 页', (tester) async {
    await pumpReader(tester);
    expect(find.textContaining('第 1 章 · 1/3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-next-chapter')));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 2 章 · 1/3'), findsOneWidget);
    // 第 1 章的图不再是当前渲染项（当前页变成第 2 章第 1 页）。
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    expect(find.byKey(const Key('reader-next-chapter')), findsOneWidget);
  });

  testWidgets('翻页 UI 更新：点下一页后页码前进', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.byKey(const Key('reader-next-page')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 章 · 2/3'), findsOneWidget);
  });

  testWidgets('模式切换 UI：切到连续滚动后显示 ListView', (tester) async {
    await pumpReader(tester);
    expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-toggle-mode')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-continuous-list')), findsOneWidget);
    expect(find.byKey(const Key('reader-paged-view')), findsNothing);
  });

  testWidgets('加载失败占位：loader 抛错时显示失败占位，可点重试', (tester) async {
    await pumpReader(tester, errorUrls: <String>{'p1-1.png'});

    expect(find.byKey(const Key('reader-image-error-0')), findsOneWidget);
    expect(find.text('图片加载失败'), findsOneWidget);

    // 点占位触发重试；loader 仍抛错，占位保持（不崩溃）。
    await tester.tap(find.text('图片加载失败'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-image-error-0')), findsOneWidget);
  });

  testWidgets('加载态：图片字节未返回时显示转圈占位', (tester) async {
    // 第一张图永不返回 → 稳定停留在 loading 占位。
    await env.close();
    env = ReaderTestEnv.create(pendingUrls: <String>{'p1-1.png'});
    await tester.pumpWidget(
      _app(
        ComicReaderPage(
          title: '尖帽子的魔法工坊',
          chapters: sampleChapters(),
          imageCache: env.cache,
        ),
      ),
    );
    // 加载转圈是无限动画，不能用 pumpAndSettle；固定 pump 几帧即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('reader-image-loading')), findsOneWidget);
    expect(find.byKey(const Key('reader-image-0')), findsNothing);
  });

  testWidgets('左右滑动切换页面（左右翻页手势）', (tester) async {
    await pumpReader(tester);
    final view = find.byKey(const Key('reader-paged-view'));
    final center = tester.getCenter(view);

    // 向左拖 → 下一页。
    await tester.drag(view, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 章 · 2/3'), findsOneWidget);

    // 向右拖 → 上一页。
    await tester.drag(view, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 章 · 1/3'), findsOneWidget);
    expect(center.dx, greaterThan(0));
  });

  testWidgets('缩放按钮改变 info 条上的倍率', (tester) async {
    await pumpReader(tester);
    expect(find.textContaining('1.00x'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-zoom-in')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.25x'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-zoom-out')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.00x'), findsOneWidget);
  });

  testWidgets('空章显示占位，不渲染图片列表', (tester) async {
    await tester.pumpWidget(
      _app(
        ComicReaderPage(
          title: '空章测试',
          chapters: const <ComicChapter>[
            ComicChapter(title: '空章', images: <ReaderImage>[]),
          ],
          imageCache: env.cache,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-empty-chapter')), findsOneWidget);
    expect(find.text('本章暂无图片'), findsOneWidget);
  });
}
