// 阅读器控制器：唯一持有阅读状态的地方（对齐 anime/player/PlayerController 的写法）。
//
// 依赖的是纯模型 + [ProgressRecorder] + [ReaderImageCache]，不认识 Widget、不联网、
// 不碰源引擎；UI 通过 [ChangeNotifier] 重建，单测直接断言状态。
//
// 持久化点：翻页、切章后都调用 [_persist]，把"当前章/页"写进 core 投影。

import 'package:flutter/foundation.dart';

import 'reader_cache.dart';
import 'reader_models.dart';
import 'reader_progress.dart';
import 'reader_settings.dart';
import 'reader_view_mode.dart';

/// 阅读控制器：章节下标与页码都用 0 基存储，对外暴露 1 基的展示号。
class ReaderController extends ChangeNotifier {
  ReaderController({
    required List<ComicChapter> chapters,
    this.recorder,
    required this.imageCache,
    int initialChapter = 0,
    int initialPage = 0,
    ReadingMode mode = ReadingMode.paged,
    ReaderViewMode? viewMode,
    ReaderSettings? settings,
  }) : _chapters = List<ComicChapter>.unmodifiable(chapters),
       _chapterIndex = _validateChapter(chapters, initialChapter),
       _pageIndex = _validatePage(chapters, initialChapter, initialPage),
       viewMode = viewMode ?? ReaderViewMode.fromLegacy(mode),
       settings = settings ?? const ReaderSettings();

  static int _validateChapter(List<ComicChapter> chapters, int index) {
    if (chapters.isEmpty) {
      throw ArgumentError.value(chapters, 'chapters', '章节列表不能为空');
    }
    RangeError.checkValidIndex(index, chapters, 'initialChapter');
    return index;
  }

  static int _validatePage(List<ComicChapter> chapters, int chapter, int page) {
    final count = chapters[chapter].pageCount;
    if (count == 0) return 0;
    if (page < 0 || page >= count) {
      throw RangeError.range(page, 0, count - 1, 'initialPage');
    }
    return page;
  }

  static const double minZoom = 1.0;
  static const double maxZoom = 4.0;

  final List<ComicChapter> _chapters;
  final ProgressRecorder? recorder;
  final ReaderImageCache imageCache;

  int _chapterIndex;
  int _pageIndex;

  /// 七种视图模式是新契约；[mode] 保留作历史兼容（测试与外部旧调用）。
  ReaderViewMode viewMode = ReaderViewMode.waterfallTopToBottom;

  /// 当前阅读设置（由集成层注入；控制器只读它来响应手势/显示开关）。
  ReaderSettings settings = const ReaderSettings();

  double _zoom = 1.0;
  String? _errorMessage;
  bool _disposed = false;

  List<ComicChapter> get chapters => _chapters;
  int get chapterIndex => _chapterIndex;
  int get pageIndex => _pageIndex;
  int get chapterCount => _chapters.length;

  /// 1 基展示号（与 payload / progressText 一致）。
  int get chapterNumber => _chapterIndex + 1;
  int get pageNumber => _pageIndex + 1;

  ComicChapter get currentChapter => _chapters[_chapterIndex];
  int get pageCount => currentChapter.pageCount;
  String get chapterTitle => currentChapter.title;
  String? get currentImageUrl =>
      pageCount > 0 ? currentChapter.imageUrls[_pageIndex] : null;
  List<String> get imageUrls => currentChapter.imageUrls;

  double get zoom => _zoom;
  String? get errorMessage => _errorMessage;

  /// 历史 [ReadingMode] 视图：由 [viewMode] 折算而来，供旧测试/外部调用。
  /// paged ↔ 任一 gallery；continuous ↔ continuous* / 瀑布。
  ReadingMode get mode =>
      viewMode.isGallery ? ReadingMode.paged : ReadingMode.continuous;

  bool get hasPreviousChapter => _chapterIndex > 0;
  bool get hasNextChapter => _chapterIndex < _chapters.length - 1;
  bool get hasPreviousPage => _pageIndex > 0;
  bool get hasNextPage => pageCount > 0 && _pageIndex < pageCount - 1;

  /// 当前持久化事件的运行时值（UI 顶部信息条/调试也用得上）。
  ReadingProgress get progress => ReadingProgress(
    chapter: chapterNumber,
    chapterId: currentChapter.chapterId,
    chapterTitle: chapterTitle,
    page: pageNumber,
    pageCount: pageCount,
  );

  /// 切到指定章（0 基）。越界抛 [RangeError] 且不改状态（验收点：切章索引边界）。
  /// 切章是持久化点：重置到第 1 页后落库。
  Future<void> goToChapter(int index) async {
    RangeError.checkValidIndex(index, _chapters, 'index');
    if (_disposed) return;
    _chapterIndex = index;
    _pageIndex = 0;
    _notify();
    await _persist();
  }

  Future<void> nextChapter() =>
      hasNextChapter ? goToChapter(_chapterIndex + 1) : Future.value();

  Future<void> previousChapter() =>
      hasPreviousChapter ? goToChapter(_chapterIndex - 1) : Future.value();

  /// 翻页（验收点：翻页方向）。到章首/章尾不越界，返回是否真的移动了。
  /// 翻页是持久化点。
  Future<bool> nextPage() async {
    if (!hasNextPage) return false;
    _pageIndex++;
    _notify();
    await _persist();
    return true;
  }

  Future<bool> previousPage() async {
    if (!hasPreviousPage) return false;
    _pageIndex--;
    _notify();
    await _persist();
    return true;
  }

  /// 切换视图模式（新契约）。不是进度，不触发持久化。
  void setViewMode(ReaderViewMode newMode) {
    if (_disposed || viewMode == newMode) return;
    viewMode = newMode;
    _notify();
  }

  /// 历史模式切换（验收点）：映射到 gallery ↔ 瀑布两种新模式。
  /// 不是进度，不触发持久化。
  void setMode(ReadingMode newMode) => setViewMode(
    newMode == ReadingMode.paged
        ? ReaderViewMode.galleryLeftToRight
        : ReaderViewMode.waterfallTopToBottom,
  );

  void toggleMode() => setMode(
    mode == ReadingMode.paged ? ReadingMode.continuous : ReadingMode.paged,
  );

  /// 上报滚动/瀑布流当前可见的真实位置（章节 1 基、页 1 基）。
  /// 只有章/页真的变化才写进度，避免滚动每帧落库。
  Future<void> reportVisiblePosition(int chapter, int page) async {
    if (_disposed) return;
    final chapterIndex = chapter - 1;
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;
    final pageIndex = (page - 1).clamp(
      0,
      _chapters[chapterIndex].pageCount - 1,
    );
    if (chapterIndex == _chapterIndex && pageIndex == _pageIndex) return;
    _chapterIndex = chapterIndex;
    _pageIndex = pageIndex;
    _notify();
    await _persist();
  }

  /// 更新设置并通知 UI 重建（设置本身不是进度）。
  void updateSettings(ReaderSettings newSettings) {
    if (_disposed) return;
    settings = newSettings;
    setViewMode(newSettings.mode);
    _notify();
  }

  /// 缩放限制在 [minZoom, maxZoom]；非法值抛 [ArgumentError] 且状态不变。
  void setZoom(double value) {
    if (!value.isFinite || value < minZoom || value > maxZoom) {
      throw ArgumentError.value(value, 'zoom', '缩放必须位于 $minZoom–$maxZoom 之间');
    }
    if (_disposed || value == _zoom) return;
    _zoom = value;
    _notify();
  }

  void zoomIn() => setZoom((_zoom + 0.25).clamp(minZoom, maxZoom).toDouble());
  void zoomOut() => setZoom((_zoom - 0.25).clamp(minZoom, maxZoom).toDouble());

  /// 预取当前章的图片（当前页 + 相邻页）到缓存，让翻页大多命中内存。
  Future<void> preloadAround() async {
    final urls = imageUrls;
    if (urls.isEmpty) return;
    final indices = <int>{
      _pageIndex - 1,
      _pageIndex,
      _pageIndex + 1,
    }.where((i) => i >= 0 && i < urls.length);
    for (final i in indices) {
      try {
        await imageCache.load(urls[i]);
      } on Object catch (error) {
        _errorMessage = '预取失败：$error';
        _notify();
      }
    }
  }

  /// 取当前页字节（走缓存；供 UI/联调使用）。
  Future<Uint8List> loadCurrentImage() {
    final url = currentImageUrl;
    if (url == null) {
      return Future.error(StateError('当前章节没有图片'));
    }
    return imageCache.load(url);
  }

  /// 手动持久化点（如退出阅读页时由集成方调用）。
  Future<void> persistNow() => _persist();

  Future<void> _persist() async {
    final recorder = this.recorder;
    if (recorder == null) return;
    try {
      await recorder.persist(progress);
      _errorMessage = null;
    } on Object catch (error) {
      _errorMessage = '进度保存失败：$error';
    }
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
