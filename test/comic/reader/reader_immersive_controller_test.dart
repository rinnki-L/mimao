// 沉浸式阅读控制器：起始章/页采纳、切章归位、翻页模式按显示页推进。
// 用假章节源 + 内存 recorder，不碰网络/引擎。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_chapter_source.dart';
import 'package:mimao/comic/reader/reader_immersive_controller.dart';
import 'package:mimao/comic/reader/reader_settings.dart';
import 'package:mimao/comic/reader/reader_view_mode.dart';
import 'package:mimao/comic/reader/reader_waterfall_controller.dart';

import 'reader_test_env.dart';

class _Source implements ReaderChapterSource {
  _Source(this.chapters);

  final Map<int, List<String>> chapters;
  final List<int> loaded = <int>[];

  @override
  int get chapterCount => chapters.length;

  @override
  String chapterId(int chapter) => 'ep-$chapter';

  @override
  Future<List<String>> load(int chapter, ReaderLoadScope scope) async {
    loaded.add(chapter);
    return chapters[chapter] ?? const <String>[];
  }
}

Future<ImmersiveReaderController> _build({
  int initialChapter = 1,
  int initialPage = 1,
  ReaderSettings settings = const ReaderSettings(),
  int chapters = 3,
  int imagesPerChapter = 5,
}) async {
  final source = _Source(<int, List<String>>{
    for (var c = 1; c <= chapters; c++)
      c: <String>[for (var i = 1; i <= imagesPerChapter; i++) 'c$c-p$i'],
  });
  final waterfall = ReaderWaterfallController(
    source: source,
    initialChapter: initialChapter,
    initialChapterId: source.chapterId(initialChapter),
  );
  await waterfall.start();
  final controller = ImmersiveReaderController(
    waterfall: waterfall,
    chapterTitles: <String>[for (var c = 1; c <= chapters; c++) '第 $c 章'],
    recorder: RecordingRecorder(),
    initialPage: initialPage,
  )..updateSettings(settings);
  return controller;
}

void main() {
  test('起始章/页取自瀑布流起始章，不被 flow 空态冲成第 1 章', () async {
    final controller = await _build(initialChapter: 2, initialPage: 4);
    expect(controller.currentChapter, 2);
    expect(controller.position.chapter, 2);
    expect(controller.position.page, 4);
    expect(controller.position.pageCount, 5);
  });

  test('下一章回到第 1 页，章首往前按显示页回上一章末页', () async {
    final controller = await _build(initialChapter: 1, initialPage: 3);
    expect(await controller.nextChapter(), isTrue);
    expect(controller.position.chapter, 2);
    expect(controller.position.page, 1);

    await controller.turnPage(-1); // 第 2 章第 1 页再往前
    expect(controller.position.chapter, 1);
    expect(controller.position.page, 5);
  });

  test('翻页模式每屏 2 图：按显示页推进而不是逐图推进', () async {
    final controller = await _build(
      settings: const ReaderSettings(
        mode: ReaderViewMode.galleryLeftToRight,
        imagesPerPage: 2,
        singleImageOnFirstPage: false,
      ),
    );
    final recorder = controller.recorder! as RecordingRecorder;

    expect(controller.position.displayPage, 1);
    expect(controller.position.displayPageCount, 3);

    await controller.turnDisplayPage(1);
    expect(controller.position.page, 3, reason: '第二屏从第 3 张图开始');
    expect(controller.position.displayPage, 2);
    expect(recorder.events.last.page, 3, reason: '历史仍按源图序号落库');

    await controller.turnDisplayPage(1);
    expect(controller.position.displayPage, 3);
    expect(controller.position.page, 5, reason: '末屏只剩一张图');

    await controller.turnDisplayPage(1);
    expect(controller.position.chapter, 2);
    expect(controller.position.displayPage, 1);
  });

  test('跳到已在流里的章节也会切过去', () async {
    final controller = await _build();
    await controller.waterfall.ensureAfter(current: 1, threshold: 16);
    expect(controller.waterfall.flow.hasChapter(2), isTrue);

    final ok = await controller.goToChapter(2);
    expect(ok, isTrue);
    expect(controller.position.chapter, 2);
    expect(controller.position.page, 1);
  });
}
