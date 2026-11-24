// 沉浸式阅读器集成行为：历史位置恢复、翻页模式一屏多图、键盘翻页。
// 假章节源 + 假字节 loader，不碰网络；图片是 1×1 PNG，尺寸测量走真实编码头。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_chapter_source.dart';
import 'package:mimao/comic/reader/reader_immersive_page.dart';
import 'package:mimao/comic/reader/reader_settings.dart';
import 'package:mimao/comic/reader/reader_view_mode.dart';

import 'reader_test_env.dart';

/// 三章、每章五图；URL 带章号，便于断言"只加载目标章"。
class _Source implements ReaderChapterSource {
  static final List<List<String>> chapters = <List<String>>[
    for (var c = 1; c <= 3; c++)
      <String>[for (var i = 1; i <= 5; i++) 'c$c-p$i.png'],
  ];

  @override
  int get chapterCount => chapters.length;

  @override
  String chapterId(int chapter) => 'ep-$chapter';

  @override
  Future<List<String>> load(int chapter, ReaderLoadScope scope) async =>
      chapters[chapter - 1];
}

Widget _app({
  required ReaderImageCache cache,
  required ReaderSettingsStore store,
  int initialChapter = 1,
  int initialPage = 1,
}) => MaterialApp(
  home: Scaffold(
    body: ImmersiveReaderPage(
      title: '测试漫画',
      source: _Source(),
      imageCache: cache,
      settingsStore: store,
      initialChapter: initialChapter,
      initialPage: initialPage,
      chapterTitles: const <String>['第 1 章', '第 2 章', '第 3 章'],
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

  testWidgets('历史恢复：从第 2 章第 4 页打开，页码不被首帧冲回第 1 页', (tester) async {
    await tester.pumpWidget(
      _app(cache: env.cache, store: store, initialChapter: 2, initialPage: 4),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第 2 章'), findsWidgets);
    expect(find.textContaining('4/5'), findsWidgets);
    // 起始章之外的第 1 章不应被加载（向前补章只在接近顶部时触发）。
    expect(env.loaded.where((url) => url.startsWith('c1-')), isEmpty);
  });

  testWidgets('翻页模式每屏 2 图 + 键盘右箭头按屏推进', (tester) async {
    store = MemoryReaderSettingsStore(
      const ReaderSettings(
        mode: ReaderViewMode.galleryLeftToRight,
        imagesPerPage: 2,
        singleImageOnFirstPage: false,
      ),
    );
    await tester.pumpWidget(_app(cache: env.cache, store: store));
    await tester.pumpAndSettle();

    expect(find.textContaining('1/3'), findsWidgets);
    expect(find.byKey(const Key('immersive-image-1')), findsOneWidget);
    expect(find.byKey(const Key('immersive-image-2')), findsOneWidget);
    // 第一屏两张图都要有实际尺寸（不是 0 高占位）。
    expect(
      tester.getSize(find.byKey(const Key('immersive-image-1'))).height,
      greaterThan(0),
    );
    expect(
      tester.getSize(find.byKey(const Key('immersive-image-2'))).height,
      greaterThan(0),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.textContaining('2/3'), findsWidgets);
    expect(env.loaded, contains('c1-p3.png'));
    expect(env.loaded, contains('c1-p4.png'));
  });

  testWidgets('桌面右键弹出阅读操作菜单', (tester) async {
    await tester.pumpWidget(_app(cache: env.cache, store: store));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('immersive-scroll'))),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读设置'), findsOneWidget);
    expect(find.text('保存当前图片'), findsOneWidget);
    expect(find.text('章节目录'), findsOneWidget);
  });
}
