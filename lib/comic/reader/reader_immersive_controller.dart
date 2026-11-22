// 沉浸式阅读控制器：包装跨章瀑布流，持有"真实章节/章内页"并负责翻页、
// 跳页、切章与进度落库。全局流索引只活在视图层，这里永远是真实位置。

import 'dart:async';

import 'package:flutter/foundation.dart';

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
  });

  final int chapter; // 1 基
  final String chapterId;
  final int page; // 1 基
  final int pageCount;

  @override
  String toString() => 'ReaderPosition(ch=$chapter, p=$page/$pageCount)';
}

/// 沉浸式阅读控制器：ChangeNotifier，UI 通过 AnimatedBuilder 重建。
class ImmersiveReaderController extends ChangeNotifier {
  ImmersiveReaderController({
    required this.waterfall,
    required this.chapterTitles,
    this.recorder,
    int initialPage = 1,
  }) : _page = initialPage < 1 ? 1 : initialPage {
    _chapter = waterfall.flow.firstChapter > 0
        ? waterfall.flow.firstChapter
        : 1;
  }

  final ReaderWaterfallController waterfall;
  final List<String> chapterTitles;
  final ProgressRecorder? recorder;

  late int _chapter;
  int _page;
  ReaderSettings _settings = const ReaderSettings();
  bool _disposed = false;
  String? _message;

  ReaderSettings get settings => _settings;
  String? get message => _message;

  /// 当前真实位置（页会被钳制到当前章实际页数）。
  ReaderPosition get position {
    final segment = waterfall.flow.segmentOf(_chapter);
    final count = segment?.length ?? 0;
    final page = count < 1 ? 1 : _page.clamp(1, count);
    return ReaderPosition(
      chapter: _chapter,
      chapterId: segment?.chapterId ?? waterfall.source.chapterId(_chapter),
      page: page,
      pageCount: count,
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
      if (await previousChapter()) return;
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
    _page = count < 1 ? 1 : page.clamp(1, count);
    _notify();
    await _persist();
  }

  Future<bool> nextChapter() async {
    final target = _chapter + 1;
    if (target > waterfall.source.chapterCount) return false;
    final ok = await waterfall.goToChapter(target);
    if (!ok || _disposed) return false;
    await syncToFlow();
    await _persist();
    return true;
  }

  Future<bool> previousChapter() async {
    final target = _chapter - 1;
    if (target < 1) return false;
    final ok = await waterfall.goToChapter(target);
    if (!ok || _disposed) return false;
    await syncToFlow();
    await _persist();
    return true;
  }

  /// 连续/瀑布模式：按视口滚动一屏（用预取页数近似一屏）。
  Future<void> scrollByViewport(int direction) async {
    final step = _settings.preloadCount < 1 ? 1 : _settings.preloadCount;
    await turnPage(direction * step);
  }

  /// 瀑布流滚动上报：视图把当前可见的全局流索引换算出真实章节/页后调用。
  Future<void> reportFlowIndex(int flowIndex) async {
    if (_disposed) return;
    final image = waterfall.flow.imageAt(flowIndex);
    if (image == null) return;
    final pos = image.position;
    if (pos.chapter == _chapter && pos.page == _page) return;
    _chapter = pos.chapter;
    _page = pos.page;
    _notify();
    await _persist();
    // 触发前后补章（阈值 = 预取数）。
    unawaited(
      waterfall.ensureAfter(
        current: flowIndex,
        threshold: _settings.preloadCount,
      ),
    );
    unawaited(
      waterfall.ensureBefore(
        current: flowIndex,
        threshold: _settings.preloadCount,
      ),
    );
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
    _disposed = true;
    super.dispose();
  }
}
