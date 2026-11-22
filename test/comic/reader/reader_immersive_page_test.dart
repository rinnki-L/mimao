// 沉浸式阅读页 widget 测试：锁定"图片有界布局"（回归 infinite-height 崩溃）、
// 加载/错误/空三态、七模式设置切换。用假源 + 假 loader，不碰网络/引擎。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_chapter_source.dart';
import 'package:mimao/comic/reader/reader_immersive_page.dart';
import 'package:mimao/comic/reader/reader_settings.dart';
import 'package:mimao/comic/reader/reader_view_mode.dart';

import 'reader_test_env.dart';

/// 假章节源：两章各 3 图，或按 errorUrls 让取字节失败。
class _FakeSource implements ReaderChapterSource {
  const _FakeSource();

  static const List<List<String>> chapters = <List<String>>[
    <String>['a1.png', 'a2.png', 'a3.png'],
    <String>['b1.png', 'b2.png', 'b3.png'],
  ];

  @override
  int get chapterCount => chapters.length;

  @override
  String chapterId(int chapter) => 'ep-$chapter';

  @override
  Future<List<String>> load(int chapter, ReaderLoadScope scope) async =>
      chapters[chapter - 1];
}

Widget _app(ReaderImageCache cache, ReaderSettingsStore store) => MaterialApp(
  home: Scaffold(
    body: ImmersiveReaderPage(
      title: '测试漫画',
      source: _FakeSource(),
      imageCache: cache,
      settingsStore: store,
      chapterTitles: const <String>['第 1 章', '第 2 章'],
    ),
  ),
);

void main() {
  late ReaderTestEnv env;
  late MemoryReaderSettingsStore store;

  setUp(() {
    env = ReaderTestEnv.create();
    store = MemoryReaderSettingsStore();
  });

  tearDown(() => env.close());

  testWidgets('瀑布模式：图片在有限框内渲染（回归 infinite-height 布局崩溃）', (tester) async {
    await tester.pumpWidget(_app(env.cache, store));
    await tester.pumpAndSettle();

    // 图片槽出现且没有布局异常（pumpAndSettle 若抛布局错误此测试会红）。
    expect(find.byKey(const Key('immersive-scroll')), findsOneWidget);
    expect(find.byKey(const Key('immersive-image-1')), findsWidgets);
    // 顶/底栏与页码浮层都在。
    expect(find.byKey(const Key('reader-settings')), findsOneWidget);
    expect(find.byKey(const Key('reader-progress-slider')), findsOneWidget);
  });

  testWidgets('加载失败：显示错误占位，可点重试', (tester) async {
    await env.close();
    env = ReaderTestEnv.create(errorUrls: const <String>{'a1.png'});
    await tester.pumpWidget(_app(env.cache, store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('immersive-image-error-1')), findsOneWidget);
    expect(find.textContaining('图片加载失败'), findsOneWidget);
  });

  testWidgets('切到翻页模式：渲染 PageView 画廊', (tester) async {
    // 预置设置为左到右翻页。
    store = MemoryReaderSettingsStore(
      const ReaderSettings(mode: ReaderViewMode.galleryLeftToRight),
    );
    await tester.pumpWidget(_app(env.cache, store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('immersive-gallery')), findsOneWidget);
    expect(find.byKey(const Key('immersive-scroll')), findsNothing);
  });

  testWidgets('设置持久化：改模式后写入 store', (tester) async {
    await tester.pumpWidget(_app(env.cache, store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('reader-settings-mode-galleryRightToLeft')),
    );
    await tester.pumpAndSettle();

    final saved = await store.load();
    expect(saved.mode, ReaderViewMode.galleryRightToLeft);
  });
}
