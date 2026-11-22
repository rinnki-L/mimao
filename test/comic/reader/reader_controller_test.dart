// 阅读器控制器逻辑单测（验收：切章索引边界、翻页方向、模式切换、缓存命中/淘汰）。
//
// 用 RecordingRecorder 断言持久化点，不碰数据库；缓存命中/淘汰通过预取 +
// ReaderImageCache 的 hits/evictions 计数断言。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_controller.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_progress.dart';

import 'reader_test_env.dart';

void main() {
  late ReaderTestEnv env;
  late RecordingRecorder recorder;
  late ReaderController controller;

  List<ComicChapter> chapters() => sampleChapters();

  setUp(() {
    env = ReaderTestEnv.create(maxMemoryEntries: 3, maxDiskEntries: 3);
    recorder = RecordingRecorder();
    controller = ReaderController(
      chapters: chapters(),
      recorder: recorder,
      imageCache: env.cache,
    );
  });

  tearDown(() {
    controller.dispose();
    env.close();
  });

  test('构造校验：空章列表抛异常，越界初始章/页抛 RangeError', () {
    expect(
      () => ReaderController(
        chapters: const <ComicChapter>[],
        imageCache: env.cache,
      ),
      throwsArgumentError,
    );
    expect(
      () => ReaderController(
        chapters: chapters(),
        imageCache: env.cache,
        initialChapter: 2,
      ),
      throwsRangeError,
    );
    expect(
      () => ReaderController(
        chapters: chapters(),
        imageCache: env.cache,
        initialPage: 3,
      ),
      throwsRangeError,
    );
  });

  test('切章索引边界：越界抛 RangeError 且不改状态；上一章/下一章到边界停住', () async {
    await expectLater(controller.goToChapter(-1), throwsRangeError);
    await expectLater(controller.goToChapter(2), throwsRangeError);
    expect(controller.chapterIndex, 0);

    // 第一章没有上一章。
    await controller.previousChapter();
    expect(controller.chapterIndex, 0);

    await controller.nextChapter();
    expect(controller.chapterIndex, 1);
    expect(controller.pageIndex, 0, reason: '切章应重置到第 1 页');
    expect(recorder.events.last.chapter, 2);
    expect(recorder.events.last.page, 1);

    // 最后一章没有下一章。
    await controller.nextChapter();
    expect(controller.chapterIndex, 1);
  });

  test('翻页方向：下一页 +1 / 上一页 -1，边界返回 false 且记录', () async {
    expect(controller.pageNumber, 1);
    expect(await controller.nextPage(), isTrue);
    expect(controller.pageNumber, 2);
    expect(await controller.nextPage(), isTrue);
    expect(controller.pageNumber, 3);
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

  test('模式切换：paged ↔ continuous，幂等且不写进度', () async {
    expect(controller.mode, ReaderMode.pagedLtr);
    final before = recorder.events.length;

    controller.toggleMode();
    expect(controller.mode, ReaderMode.continuousTtb);
    controller.toggleMode();
    expect(controller.mode, ReaderMode.pagedLtr);
    controller.setMode(ReaderMode.pagedLtr); // 幂等
    expect(controller.mode, ReaderMode.pagedLtr);

    expect(recorder.events.length, before, reason: '切模式不是进度，不触发持久化');
  });

  test('缩放：钳制与非法值抛错；notify 触发状态可观察', () {
    expect(controller.zoom, 1.0);
    controller.zoomIn();
    expect(controller.zoom, 1.25);
    controller.zoomOut();
    expect(controller.zoom, 1.0);
    expect(() => controller.setZoom(0.5), throwsArgumentError);
    expect(() => controller.setZoom(9.0), throwsArgumentError);
    expect(controller.zoom, 1.0, reason: '非法缩放不改状态');
  });

  test('缓存命中/淘汰：预取相邻页命中内存，限量后旧图被淘汰', () async {
    // 从第 2 页起（索引 1），预取 +-1 → 三张图全部进内存。
    await controller.goToChapter(0);
    await controller.nextPage();
    await controller.preloadAround();
    expect(env.cache.memoryLength, 3);
    expect(env.cache.hits, 0);
    expect(env.cache.misses, 3);

    // 再取一次当前页：内存命中，loader 不会重新调用。
    final loadedBefore = env.loaded.length;
    await controller.loadCurrentImage();
    expect(env.cache.hits, 1);
    expect(env.loaded.length, loadedBefore);

    // 容量只有 3：再加载一张新图，最旧的被淘汰。
    await env.cache.load(ReaderImage.plain('extra-1.png'));
    expect(env.cache.memoryLength, 3);
    expect(env.cache.evictions, 1);
    expect(env.cache.isInMemory('p1-1.png'), isFalse, reason: '最旧图应被淘汰');
  });

  test('空章：currentImageUrl 为 null，loadCurrentImage 报错且不崩溃', () async {
    final empty = ReaderController(
      chapters: const <ComicChapter>[
        ComicChapter(title: '空章', images: <ReaderImage>[]),
      ],
      imageCache: env.cache,
    );
    addTearDown(empty.dispose);
    expect(empty.pageCount, 0);
    expect(empty.currentImageUrl, isNull);
    expect(empty.hasNextPage, isFalse);
    await expectLater(empty.loadCurrentImage(), throwsStateError);
    await empty.preloadAround(); // 空章预取是空操作
    expect(empty.chapterCount, 1);
  });

  test('持久化失败：errorMessage 被置位但翻页/切章状态不被破坏', () async {
    final failing = ReaderController(
      chapters: chapters(),
      recorder: _ThrowingRecorder(),
      imageCache: env.cache,
    );
    addTearDown(failing.dispose);

    await failing.nextPage();
    expect(failing.pageNumber, 2, reason: '写失败不应回滚翻页');
    expect(failing.errorMessage, contains('进度保存失败'));
    await failing.persistNow();
    expect(failing.errorMessage, contains('进度保存失败'));
  });

  test('预取失败被吞进 errorMessage，不向外抛', () async {
    final failing = ReaderTestEnv.create(errorUrls: <String>{'p1-1.png'});
    addTearDown(failing.close);
    final c = ReaderController(chapters: chapters(), imageCache: failing.cache);
    addTearDown(c.dispose);
    await c.preloadAround();
    expect(c.errorMessage, contains('预取失败'));
  });
}

class _ThrowingRecorder implements ProgressRecorder {
  @override
  Future<void> persist(ReadingProgress progress) async {
    throw StateError('boom');
  }
}
