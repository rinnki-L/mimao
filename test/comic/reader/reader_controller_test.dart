// 阅读器控制器逻辑单测（验收：构造校验、懒加载、空章跳过、跨章翻页、失败重试、
// 防抖持久化、切章边界、翻页方向、模式/设置、章加载三态、预取）。
//
// 用 FakeChapterSource + RecordingRecorder 断言状态与持久化点，不碰数据库与引擎。
// 重试/可变失败行为用本文件内的 [_MutableFailingSource] 子类，不改共享夹具。

// fake_async 是 flutter_test 的传递依赖，直接拿来验 1 秒防抖，不进 pubspec.yaml。
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_controller.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_progress.dart';
import 'package:mimao/comic/reader/reader_settings.dart';

import 'reader_test_env.dart';

/// 默认两章、每章三页的源。
FakeChapterSource sampleSource() => FakeChapterSource(sampleChapters());

/// 手动装配：env（缓存）+ source + recorder → controller，并完成 open()。
Future<(ReaderTestEnv, ReaderController, RecordingRecorder)> buildController({
  FakeChapterSource? source,
  ReaderSettingsStore? settingsStore,
  ReaderSettings settings = const ReaderSettings(),
  int initialChapter = 0,
  Set<String> errorUrls = const <String>{},
}) async {
  final env = ReaderTestEnv.create(errorUrls: errorUrls);
  final recorder = RecordingRecorder();
  final controller = ReaderController(
    source: source ?? sampleSource(),
    imageCache: env.cache,
    settingsStore: settingsStore,
    recorder: recorder,
    initialChapter: initialChapter,
    settings: settings,
  );
  await controller.open();
  return (env, controller, recorder);
}

/// 失败章可变的源：构造后改 [failingNow] 即可让下一轮 loadImages 成功，
/// 用于重试断言。照抄 FakeChapterSource.loadImages 的语义，但失败集合可变。
class _MutableFailingSource extends FakeChapterSource {
  _MutableFailingSource(super.chapters, {Set<int> failing = const <int>{}})
    : failingNow = <int>{...failing};

  /// 当前失败章集合，测试可随时改写。
  late Set<int> failingNow;

  @override
  Future<List<ReaderImage>> loadImages(int index) async {
    loadCalls.add(index);
    if (failingNow.contains(index)) {
      throw StateError('章节加载失败：$index');
    }
    return chapters[index].images;
  }
}

/// 只含指定图片列表的单章源（便捷构造空章/有图章）。
ComicChapter _chapter(
  String title,
  List<ReaderImage> images, {
  String id = '',
}) => ComicChapter(title: title, chapterId: id, images: images);

List<ReaderImage> _pages(String prefix, int count) =>
    List<ReaderImage>.generate(
      count,
      (i) => ReaderImage('$prefix-${i + 1}.png'),
      growable: false,
    );

void main() {
  tearDown(() async {});

  test('构造校验：空章列表抛 ArgumentError，越界初始章抛 RangeError', () async {
    final env = ReaderTestEnv.create();
    addTearDown(env.close);
    expect(
      () => ReaderController(
        source: FakeChapterSource(const <ComicChapter>[]),
        imageCache: env.cache,
      ),
      throwsArgumentError,
    );
    expect(
      () => ReaderController(
        source: sampleSource(),
        imageCache: env.cache,
        initialChapter: 2,
      ),
      throwsRangeError,
    );
  });

  test('open() 懒加载：只拉初始章，标题/稳定 id 可读，不写进度', () async {
    final env = ReaderTestEnv.create();
    final source = sampleSource();
    final recorder = RecordingRecorder();
    final controller = ReaderController(
      source: source,
      imageCache: env.cache,
      recorder: recorder,
    );
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(source.loadCalls, <int>[0], reason: '只加载初始章，不预载后续章');
    expect(controller.chapterLoading, isFalse);
    expect(controller.pageCount, 3);
    expect(controller.chapterTitle, '第 1 章');
    expect(controller.chapterId, 'ep-1');
    expect(controller.pageNumber, 1);
    expect(recorder.events, isEmpty, reason: 'open 不是翻页，不写进度');
  });

  test('open() 从 store 装载阅读偏好，覆盖构造入参', () async {
    final store = InMemoryReaderSettingsStore(
      const ReaderSettings(mode: ReaderMode.continuousTtb, preloadCount: 1),
    );
    final (env, controller, _) = await buildController(
      settingsStore: store,
      settings: const ReaderSettings(mode: ReaderMode.pagedLtr),
    );
    addTearDown(controller.dispose);
    addTearDown(env.close);
    expect(controller.settings.mode, ReaderMode.continuousTtb);
    expect(controller.settings.preloadCount, 1);
  });

  test('切章懒加载：nextChapter 只拉目标章；回切复用缓存不重拉', () async {
    final env = ReaderTestEnv.create();
    final source = sampleSource();
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(source.loadCalls, <int>[0]);
    await controller.nextChapter();
    expect(source.loadCalls, <int>[0, 1]);
    expect(controller.chapterIndex, 1);
    await controller.previousChapter();
    expect(source.loadCalls, <int>[0, 1], reason: '已加载章从缓存复用');
    expect(controller.chapterIndex, 0);
  });

  test('切章索引边界：越界抛 RangeError 且不改状态；上一章/下一章到边界停住', () async {
    final (env, controller, recorder) = await buildController();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await expectLater(controller.goToChapter(-1), throwsRangeError);
    await expectLater(controller.goToChapter(2), throwsRangeError);
    expect(controller.chapterIndex, 0);

    await controller.previousChapter();
    expect(controller.chapterIndex, 0);

    await controller.nextChapter();
    expect(controller.chapterIndex, 1);
    expect(controller.pageIndex, 0, reason: '切章应重置到第 1 页');
    expect(recorder.events.last.chapter, 2);
    expect(recorder.events.last.page, 1);
    expect(recorder.events.last.chapterId, 'ep-2');

    await controller.nextChapter();
    expect(controller.chapterIndex, 1);
  });

  test('goToChapter 指定页：越界页码钳制到章内', () async {
    final (env, controller, _) = await buildController();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await controller.goToChapter(1, page: 99);
    expect(controller.pageIndex, 2);
    expect(controller.chapterIndex, 1);
  });

  test('空章跳过：open() 从空章向后落到第一个非空章', () async {
    final env = ReaderTestEnv.create();
    final source = FakeChapterSource(<ComicChapter>[
      _chapter('空章', const <ReaderImage>[]),
      _chapter('有图1', _pages('p2', 2)),
      _chapter('有图2', _pages('p3', 2)),
    ]);
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(controller.chapterIndex, 1, reason: '跳过开头空章');
    expect(source.loadCalls, <int>[0, 1], reason: '遇到第一个非空章即停');
    expect(controller.pageCount, 2);
    expect(controller.isChapterEmpty, isFalse);
  });

  test('空章跳过：向后到尾再向前回退，落在前面的非空章', () async {
    final env = ReaderTestEnv.create();
    final source = FakeChapterSource(<ComicChapter>[
      _chapter('有图', _pages('p1', 2)),
      _chapter('空章1', const <ReaderImage>[]),
      _chapter('空章2', const <ReaderImage>[]),
    ]);
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await controller.goToChapter(1);
    expect(controller.chapterIndex, 0, reason: '后面全空，回退到前面的非空章');
    expect(source.loadCalls, contains(1));
    expect(source.loadCalls, contains(2));
    expect(controller.isChapterEmpty, isFalse);
  });

  test('空章跳过：全空时停在目标章并显示空态', () async {
    final env = ReaderTestEnv.create();
    final source = FakeChapterSource(<ComicChapter>[
      _chapter('空1', const <ReaderImage>[]),
      _chapter('空2', const <ReaderImage>[]),
    ]);
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(controller.chapterIndex, 0);
    expect(controller.isChapterEmpty, isTrue);
    expect(controller.chapterError, isNull);
    expect(controller.pageCount, 0);
  });

  test('翻页方向：下一页 +1 / 上一页 -1，边界返回 false 且记录', () async {
    final (env, controller, recorder) = await buildController();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(await controller.nextPage(), isTrue);
    expect(controller.pageNumber, 2);
    expect(await controller.nextPage(), isTrue);
    expect(await controller.nextPage(), isFalse, reason: '章尾不再前进');
    expect(controller.pageNumber, 3);

    expect(await controller.previousPage(), isTrue);
    expect(controller.pageNumber, 2);
    expect(await controller.previousPage(), isTrue);
    expect(await controller.previousPage(), isFalse, reason: '章首不再后退');
    expect(controller.pageNumber, 1);

    // 每次成功翻页都是持久化点。
    expect(recorder.events.length, 4);
    expect(recorder.events.map((e) => e.page), <int>[2, 3, 2, 1]);
  });

  test('wrapChapter：章尾跨到下一章第 0 页；章首跨到上一章末页', () async {
    final (env, controller, recorder) = await buildController();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await controller.goToPage(2); // 第 1 章章尾
    expect(await controller.nextPage(wrapChapter: true), isTrue);
    expect(controller.chapterIndex, 1);
    expect(controller.pageIndex, 0, reason: '跨章落在下一章第 1 页');
    expect(recorder.events.last.chapter, 2);

    expect(await controller.previousPage(wrapChapter: true), isTrue);
    expect(controller.chapterIndex, 0);
    expect(controller.pageIndex, 2, reason: '跨回上一章末页');
    expect(recorder.events.last.page, 3);
  });

  test('wrapChapter：默认不跨章，无相邻章时返回 false', () async {
    final (env, controller, _) = await buildController();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await controller.goToPage(2);
    expect(await controller.nextPage(), isFalse, reason: '默认不跨章');
    expect(controller.chapterIndex, 0);
    await controller.goToChapter(1);
    await controller.goToPage(2);
    expect(
      await controller.nextPage(wrapChapter: true),
      isFalse,
      reason: '已是最后一章',
    );
    await controller.goToChapter(0);
    await controller.goToPage(0);
    expect(
      await controller.previousPage(wrapChapter: true),
      isFalse,
      reason: '第一章前无可跨章',
    );
  });

  test('wrapChapter 空章链：跨入空章后自动落到下一个非空章', () async {
    final env = ReaderTestEnv.create();
    final source = FakeChapterSource(<ComicChapter>[
      _chapter('有图1', _pages('p1', 2)),
      _chapter('空章1', const <ReaderImage>[]),
      _chapter('空章2', const <ReaderImage>[]),
      _chapter('有图2', _pages('p4', 2)),
    ]);
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await controller.goToPage(1); // 第 0 章章尾
    expect(await controller.nextPage(wrapChapter: true), isTrue);
    expect(controller.chapterIndex, 3, reason: '跨过两个空章落到下一个非空章');
    expect(controller.pageIndex, 0);
    expect(controller.isChapterEmpty, isFalse);

    // 反向：从有图2 章首跨回，越过中间空章落到有图1 末页。
    await controller.goToPage(0);
    expect(await controller.previousPage(wrapChapter: true), isTrue);
    expect(controller.chapterIndex, 0, reason: '向前越过空章落到有图章');
    expect(controller.pageIndex, 1, reason: '落在上一非空章末页');
  });

  test('goToPage：跳页钳制并持久化；setVisibleIndex 只更新状态（防抖另测）', () async {
    final (env, controller, recorder) = await buildController();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await controller.goToPage(2);
    expect(controller.pageNumber, 3);
    await controller.goToPage(99);
    expect(controller.pageNumber, 3, reason: '越界钳制');

    controller.setVisibleIndex(0);
    expect(controller.pageNumber, 1);
    controller.setVisibleIndex(99);
    expect(controller.pageNumber, 3, reason: '越界钳制到章末');
    controller.setVisibleIndex(1);
    expect(controller.pageNumber, 2);

    // 滚动回报不走持久化点，退出时由 persistNow 兜底。
    expect(recorder.events.last.page, 3, reason: 'goToPage 已持久化');
    await controller.persistNow();
    expect(recorder.events.last.page, 2, reason: 'persistNow 补写滚动位置');
  });

  test('防抖持久化：setVisibleIndex 连续回报，静止 1 秒只落一次库', () async {
    fakeAsync((async) {
      final env = ReaderTestEnv.create();
      final recorder = RecordingRecorder();
      final controller = ReaderController(
        source: sampleSource(),
        imageCache: env.cache,
        recorder: recorder,
      );
      // open 内部是异步的，fakeAsync 下用 flushMicrotasks 推进。
      controller.open();
      async.flushMicrotasks();

      controller.setVisibleIndex(1);
      async.elapse(const Duration(milliseconds: 300));
      controller.setVisibleIndex(2);
      async.elapse(const Duration(milliseconds: 300));
      controller.setVisibleIndex(0);
      expect(recorder.events, isEmpty, reason: '滚动期间不立即落库');

      async.elapse(const Duration(seconds: 1));
      expect(recorder.events.length, 1, reason: '静止 1 秒后只落一次');
      expect(recorder.events.single.page, 1, reason: '落的是最终可见位置');

      controller.dispose();
      async.flushMicrotasks();
      env.close();
    });
  });

  test('防抖 flush：persistNow 取消挂起计时器并立即落，不再重复写', () async {
    fakeAsync((async) {
      final env = ReaderTestEnv.create();
      final recorder = RecordingRecorder();
      final controller = ReaderController(
        source: sampleSource(),
        imageCache: env.cache,
        recorder: recorder,
      );
      controller.open();
      async.flushMicrotasks();

      controller.setVisibleIndex(2);
      controller.persistNow();
      async.flushMicrotasks();
      expect(recorder.events.length, 1);
      expect(recorder.events.single.page, 3);

      async.elapse(const Duration(seconds: 2));
      expect(recorder.events.length, 1, reason: '计时器已取消，不再重复写');

      controller.dispose();
      env.close();
    });
  });

  test('dispose 兜底：挂起的滚动落库在 dispose 时补写一次', () async {
    fakeAsync((async) {
      final env = ReaderTestEnv.create();
      final recorder = RecordingRecorder();
      final controller = ReaderController(
        source: sampleSource(),
        imageCache: env.cache,
        recorder: recorder,
      );
      controller.open();
      async.flushMicrotasks();

      controller.setVisibleIndex(2);
      expect(recorder.events, isEmpty);
      controller.dispose();
      async.flushMicrotasks();
      expect(recorder.events.length, 1, reason: 'dispose 时补写挂起进度');
      expect(recorder.events.single.page, 3);
      env.close();
    });
  });

  test('模式与设置切换：updateSettings 即时生效并写 store，不触发进度持久化', () async {
    final store = InMemoryReaderSettingsStore();
    final (env, controller, recorder) = await buildController(
      settingsStore: store,
    );
    addTearDown(controller.dispose);
    addTearDown(env.close);

    final before = recorder.events.length;
    controller.toggleMode();
    expect(controller.settings.mode, ReaderMode.continuousTtb);
    await Future<void>.delayed(Duration.zero);
    expect(store.value.mode, ReaderMode.continuousTtb);

    controller.updateSettings(
      const ReaderSettings(mode: ReaderMode.pagedRtl, preloadCount: 8),
    );
    expect(controller.settings.mode, ReaderMode.pagedRtl);
    expect(controller.settings.preloadCount, 8);
    await Future<void>.delayed(Duration.zero);
    expect(store.value.preloadCount, 8);
    expect(recorder.events.length, before, reason: '改设置不是进度');
  });

  test('缩放：zoomIn/zoomOut 步进 0.25 且有界；非法值抛 ArgumentError', () async {
    final (env, controller, _) = await buildController();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(controller.zoom, 1.0);
    controller.zoomIn();
    expect(controller.zoom, 1.25);
    controller.zoomOut();
    expect(controller.zoom, 1.0);
    expect(() => controller.setZoom(0.5), throwsArgumentError);
    expect(() => controller.setZoom(9.0), throwsArgumentError);
    expect(controller.zoom, 1.0, reason: '非法缩放不改状态');
  });

  test('预取：preloadAround 按设置张数预取当前页前后，命中后不再调 loader', () async {
    final env = ReaderTestEnv.create(maxMemoryEntries: 3, maxDiskEntries: 3);
    final source = sampleSource();
    final controller = ReaderController(
      source: source,
      imageCache: env.cache,
      settings: const ReaderSettings(preloadCount: 1),
    );
    await controller.open();
    await controller.nextPage(); // 到第 2 页
    await controller.preloadAround(); // 显式等待预取完成（内部为 fire-and-forget）
    expect(env.cache.memoryLength, 3);
    expect(env.cache.misses, 3);

    final loadedBefore = env.loaded.length;
    await controller.loadCurrentImage();
    expect(env.loaded.length, loadedBefore, reason: '命中内存不再调 loader');
    controller.dispose();
    await env.close();
  });

  test('空章：isChapterEmpty 为真，翻页/跳页为空操作', () async {
    final env = ReaderTestEnv.create();
    final source = FakeChapterSource(<ComicChapter>[
      const ComicChapter(title: '空章', images: <ReaderImage>[]),
    ]);
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(controller.isChapterEmpty, isTrue);
    expect(controller.pageCount, 0);
    expect(controller.hasNextPage, isFalse);
    expect(await controller.nextPage(), isFalse);
    expect(await controller.previousPage(), isFalse);
    await expectLater(controller.loadCurrentImage(), throwsStateError);
    await controller.goToPage(1); // 空章跳页是空操作
    expect(controller.chapterLoading, isFalse);
  });

  test('章加载失败：chapterError 置位、状态不崩、不切章', () async {
    final env = ReaderTestEnv.create();
    final source = FakeChapterSource(sampleChapters(), failing: <int>{0});
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(controller.chapterError, isNotNull);
    expect(controller.pageCount, 0);
    expect(controller.chapterLoading, isFalse);
    expect(controller.chapterIndex, 0, reason: '失败不切章');
    expect(source.loadCalls, <int>[0]);
  });

  test('章失败重试：清掉失败章记录后重拉，成功恢复且不再报错', () async {
    final env = ReaderTestEnv.create();
    final source = _MutableFailingSource(sampleChapters(), failing: <int>{0});
    final controller = ReaderController(source: source, imageCache: env.cache);
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    expect(controller.chapterError, isNotNull);
    expect(source.loadCalls, <int>[0]);

    // 模拟用户重试：放开失败标记并再调同章下标。
    source.failingNow = <int>{};
    await controller.goToChapter(0);
    expect(source.loadCalls, <int>[0, 0], reason: '失败章不入缓存，重试重新加载');
    expect(controller.chapterError, isNull);
    expect(controller.pageCount, 3);
    expect(controller.isChapterEmpty, isFalse);

    // 加载成功后再切回，命中缓存不重拉。
    await controller.goToChapter(1);
    await controller.goToChapter(0);
    expect(source.loadCalls, <int>[0, 0, 1], reason: '已成功章复用缓存');
  });

  test('持久化失败：errorMessage 置位但翻页状态不被破坏', () async {
    final env = ReaderTestEnv.create();
    final controller = ReaderController(
      source: sampleSource(),
      recorder: _ThrowingRecorder(),
      imageCache: env.cache,
    );
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);

    await controller.nextPage();
    expect(controller.pageNumber, 2, reason: '写失败不应回滚翻页');
    expect(controller.errorMessage, contains('进度保存失败'));
    await controller.persistNow();
    expect(controller.errorMessage, contains('进度保存失败'));
  });

  test('预取失败被吞进 errorMessage，不向外抛', () async {
    final env = ReaderTestEnv.create(errorUrls: <String>{'p1-1.png'});
    final controller = ReaderController(
      source: sampleSource(),
      imageCache: env.cache,
    );
    await controller.open();
    addTearDown(controller.dispose);
    addTearDown(env.close);
    expect(controller.errorMessage, contains('预取失败'));
  });
}

class _ThrowingRecorder implements ProgressRecorder {
  @override
  Future<void> persist(ReadingProgress progress) async {
    throw StateError('boom');
  }
}
