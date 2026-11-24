// 沉浸式阅读控制器：包装跨章瀑布流，持有"真实章节/章内页"并负责翻页、
// 跳页、切章与进度落库。全局流索引只活在视图层，这里永远是真实位置。

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'reader_page_layout.dart';
import 'reader_progress.dart';
import 'reader_settings.dart';
import 'reader_waterfall_controller.dart';

/// 阅读位置快照（对外展示/进度用）。
class ReaderPosition {
  const ReaderPosition({
    required this.chapter,
    required this.chapterId,
    required this.page,
    required this.pageCount,
    required this.displayPage,
    required this.displayPageCount,
  });

  final int chapter; // 1 基
  final String chapterId;
  final int page; // 1 基，源图序号（历史表存这个，跨模式稳定）
  final int pageCount; // 本章源图总数

  /// 1 基显示页（翻页模式下可能一屏多图）；连续/瀑布模式等于 [page]。
  final int displayPage;
  final int displayPageCount;

  @override
  String toString() =>
      'ReaderPosition(ch=$chapter, p=$page/$pageCount, display=$displayPage/$displayPageCount)';
}

/// 沉浸式阅读控制器：ChangeNotifier，UI 通过 AnimatedBuilder 重建。
class ImmersiveReaderController extends ChangeNotifier {
  ImmersiveReaderController({
    required this.waterfall,
    required this.chapterTitles,
    this.recorder,
    int initialPage = 1,
  }) : _page = initialPage < 1 ? 1 : initialPage {
    // 起始章来自瀑布流控制器；flow 在 start() 之前是空的，不能拿 firstChapter。
    _chapter = waterfall.initialChapter > 0 ? waterfall.initialChapter : 1;
  }

  final ReaderWaterfallController waterfall;
  final List<String> chapterTitles;
  final ProgressRecorder? recorder;

  late int _chapter;
  int _page;
  ReaderSettings _settings = const ReaderSettings();
  bool _disposed = false;
  String? _message;
  Timer? _persistTimer;

  ReaderSettings get settings => _settings;
  String? get message => _message;

  /// 翻页模式的每屏图数布局；连续/瀑布模式恒为一屏一图。
  ReaderPageLayout get pageLayout => ReaderPageLayout(
    imagesPerPage: _settings.mode.isGallery
        ? _settings.imagesPerPage.clamp(1, 5)
        : 1,
    singleImageOnFirstPage:
        _settings.mode.isGallery && _settings.singleImageOnFirstPage,
  );

  /// 当前显示页（翻页模式下按每屏图数折算）。
  int get displayPage {
    final count = position.pageCount;
    if (count < 1) return 1;
    return pageLayout.pageForImage(position.page);
  }

  int get displayPageCount {
    final count = position.pageCount;
    return count < 1 ? 1 : pageLayout.pageCount(count);
  }

  /// 当前真实位置（页会被钳制到当前章实际页数）。
  ReaderPosition get position {
    final segment = waterfall.flow.segmentOf(_chapter);
    final count = segment?.length ?? 0;
    final page = count < 1 ? 1 : _page.clamp(1, count);
    final layout = pageLayout;
    final displayCount = count < 1 ? 1 : layout.pageCount(count);
    final displayPage = count < 1 ? 1 : layout.pageForImage(page);
    return ReaderPosition(
      chapter: _chapter,
      chapterId: segment?.chapterId ?? waterfall.source.chapterId(_chapter),
      page: page,
      pageCount: count,
      displayPage: displayPage,
      displayPageCount: displayCount,
    );
  }

  int get currentChapter => _chapter;
  String get chapterTitle => _chapter <= chapterTitles.length
      ? chapterTitles[_chapter - 1]
      : '第 $_chapter 章';

  void updateSettings(ReaderSettings settings) {
    if (_disposed) return;
    _settings = settings;
    _notify();
  }

  /// 翻页（画廊模式）：章内翻页，到章尾自动进下一章；章首往前同理。
  Future<void> turnPage(int delta) async {
    if (_disposed) return;
    final count = position.pageCount;
    var next = _page + delta;
    if (next < 1) {
      if (await previousChapter(toLastPage: true)) return;
      next = 1;
    } else if (next > count && count > 0) {
      if (await nextChapter()) return;
      next = count;
    }
    _page = next < 1 ? 1 : next;
    _notify();
    await _persist();
  }

  Future<void> goToPage(int page) async {
    if (_disposed) return;
    final count = position.pageCount;
    final target = count < 1 ? 1 : page.clamp(1, count);
    if (target == _page) return;
    _page = target;
    _notify();
    await _persist();
  }

  /// 跳到一个显示页（翻页模式一屏可能含多张图）。
  Future<void> goToDisplayPage(int page) async {
    if (_disposed) return;
    final count = position.pageCount;
    if (count < 1) return;
    final layout = pageLayout;
    final target = page.clamp(1, layout.pageCount(count));
    final image = layout.firstImageOnPage(target).clamp(1, count);
    if (image == _page) return;
    _page = image;
    _notify();
    await _persist();
  }

  /// 按显示页翻页；到章首/章尾时切章。
  ///
  /// 翻页模式的自动阅读、点击热区与键盘翻页都走这里，避免 `imagesPerPage > 1`
  /// 时一次只推进一章内的"图"，界面看起来卡在同一屏。
  Future<void> turnDisplayPage(int delta) async {
    if (_disposed || delta == 0) return;
    final count = position.pageCount;
    if (count < 1) return;
    final layout = pageLayout;
    final pages = layout.pageCount(count);
    var target = layout.pageForImage(_page) + delta;
    if (target < 1) {
      if (await previousChapter(toLastPage: true)) return;
      target = 1;
    } else if (target > pages) {
      if (await nextChapter()) return;
      target = pages;
    }
    final image = layout.firstImageOnPage(target).clamp(1, count);
    if (image == _page) return;
    _page = image;
    _notify();
    await _persist();
  }

  Future<bool> nextChapter({bool toLastPage = false}) =>
      goToChapter(_chapter + 1, toLastPage: toLastPage);

  Future<bool> previousChapter({bool toLastPage = false}) =>
      goToChapter(_chapter - 1, toLastPage: toLastPage);

  /// 跳到指定章（1 基）。
  ///
  /// 与旧实现的区别：即使目标章已经在流里，也会把当前章/页切过去；切章后
  /// 页码一律回到新章第一页（[toLastPage] 时回末页），不会带着旧页码落在
  /// 新章的随机位置。
  Future<bool> goToChapter(int chapter, {bool toLastPage = false}) async {
    if (_disposed) return false;
    if (chapter < 1 || chapter > waterfall.source.chapterCount) return false;
    try {
      final ok = await waterfall.goToChapter(chapter);
      if (!ok || _disposed) return false;
    } on Object catch (error) {
      _message = '加载第 $chapter 章失败：$error';
      _notify();
      return false;
    }
    _chapter = chapter;
    final segment = waterfall.flow.segmentOf(chapter);
    final count = segment?.length ?? 0;
    _page = toLastPage && count > 0 ? count : 1;
    _message = null;
    _notify();
    await _persist();
    return true;
  }

  /// 连续/瀑布模式：按视口滚动一屏（旧入口，保留给兼容调用）。
  Future<void> scrollByViewport(int direction) async {
    final step = _settings.preloadCount < 1 ? 1 : _settings.preloadCount;
    await turnPage(direction * step);
  }

  /// 瀑布流滚动上报：视图把当前可见的全局流索引换算出真实章节/页后调用。
  ///
  /// 前后补章由视图负责（它需要拿到 ensureBefore 插入的图片数做滚动锚点），
  /// 这里只更新"真实章节/页"并落库。
  Future<void> reportFlowIndex(int flowIndex) async {
    if (_disposed) return;
    final image = waterfall.flow.imageAt(flowIndex);
    if (image == null) return;
    final pos = image.position;
    if (pos.chapter == _chapter && pos.page == _page) return;
    _chapter = pos.chapter;
    _page = pos.page;
    _notify();
    // 滚动时可见项可能连续变化；落库做 400ms 合并，退出时在 dispose 里补写。
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  /// 切章/加载完成后，把内部位置同步到流（流式加载可能改变了段）。
  Future<void> syncToFlow() async {
    if (_disposed) return;
    final segment = waterfall.flow.segmentOf(_chapter);
    if (segment == null) {
      // 目标章还没进流：用起始章兜底，避免显示空。
      final first = waterfall.flow.firstChapter;
      if (first > 0) _chapter = first;
    }
    _notify();
  }

  /// 立即把待合并的滚动位置落库（切后台 / 退出前调用）。
  Future<void> flushProgress() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persist();
  }

  Future<void> _persist() async {
    final recorder = this.recorder;
    if (recorder == null) return;
    final pos = position;
    try {
      await recorder.persist(
        ReadingProgress(
          chapter: pos.chapter,
          chapterId: pos.chapterId,
          chapterTitle: chapterTitle,
          page: pos.page,
          pageCount: pos.pageCount,
        ),
      );
      _message = null;
    } on Object catch (error) {
      _message = '进度保存失败：$error';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _persistTimer?.cancel();
    _persistTimer = null;
    // 退出前把最后一次滚动位置补写掉；recorder 由模块层持有，可独立完成。
    unawaited(_persist());
    super.dispose();
  }
}
