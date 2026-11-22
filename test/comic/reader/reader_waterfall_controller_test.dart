// 跨章瀑布流控制器单测（验收：首章加载、跨章/跨空章补全、向前补章锚点、
// 迟到结果丢弃、跳章命中/未命中、失败重试、dispose 后静默）。
//
// 全部用假 [ReaderChapterSource]：可控的 Completer 让"加载在飞"这件事变成
// 测试可以精确编排的时序，不碰网络 / 源引擎 / 数据库。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_chapter_source.dart';
import 'package:mimao/comic/reader/reader_waterfall_controller.dart';

/// 假章节源：图片内容只要可辨识即可；[hold]/[release] 控制加载何时完成。
class FakeChapterSource implements ReaderChapterSource {
  FakeChapterSource(Map<int, List<String>> chapters)
    : _chapters = <int, List<String>>{
        for (final MapEntry<int, List<String>> entry in chapters.entries)
          entry.key: List<String>.of(entry.value),
      };

  final Map<int, List<String>> _chapters;

  /// 测试可覆盖某些章的 id，模拟 await 期间源切换 / 章节重排。
  final Map<int, String> ids = <int, String>{};

  /// 命中这些章时直接抛错。
  final Set<int> failing = <int>{};

  final Map<int, Completer<List<String>>> _gates =
      <int, Completer<List<String>>>{};

  int loadCalls = 0;
  final List<int> loadLog = <int>[];

  @override
  int get chapterCount {
    var maxChapter = 0;
    for (final int chapter in _chapters.keys) {
      if (chapter > maxChapter) maxChapter = chapter;
    }
    return maxChapter;
  }

  @override
  String chapterId(int chapter) => ids[chapter] ?? 'ep-$chapter';

  /// 让第 [chapter] 章的加载挂起，直到 [release] / [failWith]。
  void hold(int chapter) {
    _gates[chapter] = Completer<List<String>>();
  }

  void release(int chapter, List<String> images) {
    final Completer<List<String>>? gate = _gates.remove(chapter);
    if (gate != null && !gate.isCompleted) gate.complete(images);
  }

  void failWith(int chapter, Object error) {
    final Completer<List<String>>? gate = _gates.remove(chapter);
    if (gate != null && !gate.isCompleted) gate.completeError(error);
  }

  @override
  Future<List<String>> load(int chapter, ReaderLoadScope scope) async {
    loadCalls++;
    loadLog.add(chapter);
    final Completer<List<String>>? gate = _gates[chapter];
    final List<String> images = gate != null
        ? await gate.future
        : (_chapters[chapter] ?? const <String>[]);
    if (scope.isCancelled) throw StateError('cancelled');
    if (failing.contains(chapter)) throw StateError('boom chapter $chapter');
    return images;
  }
}

ReaderWaterfallController build(
  FakeChapterSource source, {
  int initialChapter = 1,
  int prefetchThreshold = 3,
}) {
  final ReaderWaterfallController controller = ReaderWaterfallController(
    source: source,
    initialChapter: initialChapter,
    initialChapterId: source.chapterId(initialChapter),
    prefetchThreshold: prefetchThreshold,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test('start：加载首章后 flow 单段、imageCount 正确', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a.png', 'b.png', 'c.png'],
      2: <String>['d.png'],
    });
    final ReaderWaterfallController controller = build(source);

    await controller.start();

    expect(controller.flow.segmentCount, 1);
    expect(controller.flow.firstChapter, 1);
    expect(controller.flow.lastChapter, 1);
    expect(controller.flow.imageCount, 3);
    expect(controller.flow.imageAt(1)?.url, 'a.png');
    expect(controller.flow.imageAt(3)?.url, 'c.png');
    expect(controller.loadingAfter, isFalse);
    expect(source.loadLog, <int>[1]);
  });

  test('ensureAfter：接近末章补下一章，并跨空章继续填', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a1.png', 'a2.png'],
      2: <String>[], // 空章：不计图，但必须被跨过
      3: <String>['c1.png', 'c2.png', 'c3.png'],
      4: <String>['d1.png'],
    });
    final ReaderWaterfallController controller = build(source);
    await controller.start();

    // current=2（视图在首章末尾），阈值 3：2 图不够，补到 3 章后
    // 共 5 图，5-2=3 达标停止。
    await controller.ensureAfter(current: 2);

    expect(controller.flow.segmentCount, 3);
    expect(controller.flow.segments.map((s) => s.chapter), <int>[
      1,
      2,
      3,
    ], reason: '空章 2 也要进流，才能保证章节号连续');
    expect(controller.flow.lastChapter, 3);
    expect(controller.flow.imageCount, 5);
    expect(source.loadLog, <int>[1, 2, 3]);
    expect(controller.afterError, isNull);
  });

  test('ensureAfter：到最大章停止，不会越界请求', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a.png'],
      2: <String>['b.png'],
    });
    final ReaderWaterfallController controller = build(source);
    await controller.start();

    await controller.ensureAfter(current: 1);

    expect(controller.flow.lastChapter, 2);
    expect(source.loadLog, <int>[1, 2]);
    await controller.ensureAfter(current: 2);
    expect(controller.flow.lastChapter, 2);
    expect(source.loadLog, <int>[1, 2], reason: '到末章后不再发请求');
  });

  test('ensureBefore：返回插入图片数；chapterId 漂移时不误插', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a.png'],
      2: <String>['b1.png', 'b2.png', 'b3.png', 'b4.png'],
      3: <String>['c1.png', 'c2.png'],
    });
    final ReaderWaterfallController controller = build(
      source,
      initialChapter: 3,
    );
    await controller.start();

    // 从第 3 章顶部附近向前补：一次只补第 2 章。
    final int inserted = await controller.ensureBefore(current: 1);
    expect(inserted, 4, reason: '返回插入的图片数供视图做锚点位移');
    expect(controller.flow.firstChapter, 2);
    expect(controller.flow.imageCount, 6);

    // 再补一次到第 1 章。
    expect(await controller.ensureBefore(current: 1), 1);
    expect(controller.flow.firstChapter, 1);

    // id 漂移场景：加载第 1 章期间源把 id 改了，结果必须丢弃。
    final FakeChapterSource drifting = FakeChapterSource(<int, List<String>>{
      1: <String>['a.png'],
      2: <String>['b.png'],
      3: <String>['c.png'],
    });
    final ReaderWaterfallController second = build(
      drifting,
      initialChapter: 2,
      prefetchThreshold: 5,
    );
    await second.start();

    drifting.hold(1);
    final Future<int> pending = second.ensureBefore(current: 1);
    await Future<void>.value(); // 让 load 真正挂起
    drifting.ids[1] = 'ep-1-renamed';
    drifting.release(1, <String>['a.png']);

    expect(await pending, 0);
    expect(second.flow.firstChapter, 2, reason: '章节 id 漂移，不能把结果插进来');
  });

  test('迟到结果：ensureAfter 在飞时跳章，旧结果不得插入（revision 校验）', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a1.png', 'a2.png'],
      2: <String>['b1.png', 'b2.png', 'b3.png'],
      3: <String>['c1.png'],
      4: <String>['d1.png', 'd2.png'],
    });
    final ReaderWaterfallController controller = build(source);
    await controller.start();

    source.hold(2);
    final Future<void> pendingAfter = controller.ensureAfter(current: 2);
    await Future<void>.value();
    expect(controller.loadingAfter, isTrue);

    // 跳章：revision++ + 取消旧 scope；第 4 章立即返回。
    final bool jumped = await controller.goToChapter(4);
    expect(jumped, isTrue);
    expect(controller.flow.segmentCount, 1);
    expect(controller.flow.firstChapter, 4);

    // 旧请求这时才返回，必须被丢弃。
    source.release(2, <String>['b1.png', 'b2.png', 'b3.png']);
    await pendingAfter;

    expect(controller.flow.segmentCount, 1, reason: '迟到结果不得插入');
    expect(controller.flow.firstChapter, 4);
    expect(controller.flow.hasChapter(2), isFalse);
    expect(controller.afterError, isNull, reason: '被取消的请求不算失败');
  });

  test('goToChapter：命中已加载章不重复请求，未命中则重置为单段', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      2: <String>['b1.png', 'b2.png'],
      3: <String>['c1.png', 'c2.png'],
      4: <String>['d1.png'],
    });
    final ReaderWaterfallController controller = build(
      source,
      initialChapter: 2,
    );
    await controller.start();
    expect(source.loadCalls, 1);

    expect(await controller.goToChapter(2), isTrue);
    expect(source.loadCalls, 1, reason: '目标章已在流内，不应发请求');
    expect(controller.flow.firstChapter, 2);

    expect(await controller.goToChapter(4), isTrue);
    expect(source.loadCalls, 2);
    expect(controller.flow.segmentCount, 1);
    expect(controller.flow.firstChapter, 4);
    expect(controller.flow.imageCount, 1);
  });

  test('goToChapter：越界章号抛 RangeError', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a.png'],
    });
    final ReaderWaterfallController controller = build(source);
    await controller.start();

    await expectLater(controller.goToChapter(0), throwsRangeError);
    await expectLater(controller.goToChapter(2), throwsRangeError);
    expect(controller.flow.firstChapter, 1);
  });

  test('ensureAfter 失败写 afterError，retryAfter 清除后重试', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a1.png', 'a2.png'],
      2: <String>['b1.png', 'b2.png'],
    });
    final ReaderWaterfallController controller = build(source);
    await controller.start();

    source.failing.add(2);
    await controller.ensureAfter(current: 2);

    expect(controller.afterError, contains('加载第 2 章失败'));
    expect(controller.flow.lastChapter, 1, reason: '失败不得插入半截结果');
    expect(controller.loadingAfter, isFalse);

    final int calls = source.loadCalls;
    await controller.ensureAfter(current: 2);
    expect(source.loadCalls, calls, reason: '错误锁存期间不自动重试');

    source.failing.remove(2);
    await controller.retryAfter(current: 2);
    expect(controller.afterError, isNull);
    expect(controller.flow.lastChapter, 2);
    expect(controller.flow.imageCount, 4);
  });

  test('goToChapter 失败：旧流仍有效时 rethrow', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a.png'],
      2: <String>['b.png'],
    });
    final ReaderWaterfallController controller = build(source);
    await controller.start();

    source.failing.add(2);
    await expectLater(controller.goToChapter(2), throwsStateError);
    expect(controller.flow.firstChapter, 1, reason: '失败保留旧流');
  });

  test('dispose：取消在途加载，回调不再 notify 且不抛异常', () async {
    final FakeChapterSource source = FakeChapterSource(<int, List<String>>{
      1: <String>['a.png'],
    });
    final ReaderWaterfallController controller = ReaderWaterfallController(
      source: source,
      initialChapter: 1,
      initialChapterId: 'ep-1',
      prefetchThreshold: 3,
    );
    int notifications = 0;
    controller.addListener(() => notifications++);

    source.hold(1);
    final Future<void> pending = controller.start();
    await Future<void>.value();
    expect(controller.loadingAfter, isTrue);
    expect(notifications, 1);

    controller.dispose();
    notifications = 0;

    // 在途结果此刻返回：应被丢弃，不得 notify，也不得抛。
    source.release(1, <String>['a.png']);
    await pending;

    expect(notifications, 0);
    expect(controller.flow.isEmpty, isTrue);
  });
}
