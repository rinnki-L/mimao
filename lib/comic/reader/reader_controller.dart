// 阅读器控制器：唯一持有阅读状态的地方（对齐 anime/player/PlayerController 的写法）。
//
// 依赖的是纯模型 + [ReaderChapterSource] + [ProgressRecorder] + [ReaderImageCache]，
// 不认识 Widget、不联网、不碰源引擎；UI 通过 [ChangeNotifier] 重建，单测直接断言状态。
//
// 过渡实现：章图片仍走"全章预载"（open() 时逐章 loadImages），懒加载/空章跳过/
// 预取节流由后续提交填充——公共 API 已定型，UI 与接线按此契约并行开发。

import 'package:flutter/foundation.dart';

import 'reader_cache.dart';
import 'reader_models.dart';
import 'reader_progress.dart';
import 'reader_settings.dart';

/// 章节图片的懒加载源：阅读器只认这个接口，不认识引擎/本地文件。
///
/// 集成层（comic_entry）提供生产实现；测试注入内存版。
/// [loadImages] 返回空列表表示"该章为空章"；抛异常表示加载失败。
abstract interface class ReaderChapterSource {
  int get chapterCount;
  String chapterTitle(int index);

  /// 稳定章节 id（源内 epId / 本地 `mimao-local:///<index>`），写进历史。
  String chapterId(int index);

  Future<List<ReaderImage>> loadImages(int index);
}

/// 阅读控制器：章节下标与页码都用 0 基存储，对外暴露 1 基的展示号。
class ReaderController extends ChangeNotifier {
  ReaderController({
    required ReaderChapterSource source,
    required this.imageCache,
    this.settingsStore,
    this.recorder,
    int initialChapter = 0,
    ReaderSettings settings = const ReaderSettings(),
  }) : _source = source,
       _settings = settings {
    if (chapterCount == 0) {
      throw ArgumentError.value(source, 'source', '章节列表不能为空');
    }
    if (initialChapter < 0 || initialChapter >= chapterCount) {
      throw RangeError.range(
        initialChapter,
        0,
        chapterCount - 1,
        'initialChapter',
      );
    }
    _chapterIndex = initialChapter;
  }

  static const double minZoom = 1.0;
  static const double maxZoom = 4.0;

  final ReaderChapterSource _source;
  final ReaderImageCache imageCache;

  /// 阅读偏好持久化；null 时不持久化（测试默认）。
  final ReaderSettingsStore? settingsStore;
  final ProgressRecorder? recorder;

  late int _chapterIndex;
  int _pageIndex = 0;
  ReaderSettings _settings;
  double _zoom = 1.0;
  String? _errorMessage;
  bool _disposed = false;

  /// 已加载的章图片（章下标 → 图片列表）；空列表 = 空章或加载失败。
  final Map<int, List<ReaderImage>> _loadedImages = <int, List<ReaderImage>>{};

  int get chapterIndex => _chapterIndex;
  int get pageIndex => _pageIndex;
  int get chapterCount => _source.chapterCount;
  ReaderSettings get settings => _settings;

  /// 1 基展示号（与 progress 一致）。
  int get chapterNumber => _chapterIndex + 1;
  int get pageNumber => _pageIndex + 1;

  /// 当前章标题（未加载也能从 source 拿到标题）。
  String get chapterTitle => _source.chapterTitle(_chapterIndex);

  /// 当前章的稳定 id。
  String get chapterId => _source.chapterId(_chapterIndex);

  /// 当前章是否在加载图片。
  bool get chapterLoading => _loadingChapter != null;
  int? _loadingChapter;

  /// 当前章加载失败原因（null = 无错/未尝试）。
  Object? get chapterError => _chapterError;
  Object? _chapterError;

  /// 当前章已加载的图片（空章/未加载时为空列表）。
  List<ReaderImage> get images =>
      _loadedImages[_chapterIndex] ?? const <ReaderImage>[];

  /// 当前章是否已加载且为空章。
  bool get isChapterEmpty =>
      _loadedImages.containsKey(_chapterIndex) &&
      _loadedImages[_chapterIndex]!.isEmpty;

  /// 当前章的纯地址列表（调试/联调用；取字节请走 [images] + 缓存）。
  List<String> get imageUrls => <String>[for (final image in images) image.url];

  int get pageCount => images.length;
  String? get currentImage => images.isEmpty
      ? null
      : images[_pageIndex.clamp(0, images.length - 1)].url;

  double get zoom => _zoom;
  String? get errorMessage => _errorMessage;
  bool get hasPreviousChapter => _chapterIndex > 0;
  bool get hasNextChapter => _chapterIndex < chapterCount - 1;
  bool get hasPreviousPage => pageCount > 0 && _pageIndex > 0;
  bool get hasNextPage => pageCount > 0 && _pageIndex < pageCount - 1;

  /// 当前持久化事件的运行时值（UI 顶部信息条/调试也用得上）。
  ReadingProgress get progress => ReadingProgress(
    chapter: chapterNumber,
    chapterId: chapterId,
    chapterTitle: chapterTitle,
    page: pageNumber,
    pageCount: pageCount,
  );

  /// 启动：装载阅读偏好（store 可用时）并加载初始章。
  /// 生产页在 initState 调一次；测试可手动调。
  Future<void> open() async {
    final store = settingsStore;
    if (store != null) {
      try {
        _settings = await store.load();
        _notify();
      } on Object {
        // 设置读不回来就用手动传入的初值。
      }
    }
    await _ensureChapterLoaded(_chapterIndex);
    await preloadAround();
  }

  /// 确保章图片已加载（已加载直接返回；失败置 [chapterError]）。
  Future<List<ReaderImage>> _ensureChapterLoaded(int index) async {
    final cached = _loadedImages[index];
    if (cached != null) return cached;
    _loadingChapter = index;
    _chapterError = null;
    _notify();
    try {
      final images = await _source.loadImages(index);
      _loadedImages[index] = List<ReaderImage>.unmodifiable(images);
      return _loadedImages[index]!;
    } on Object catch (error) {
      _chapterError = error;
      return const <ReaderImage>[];
    } finally {
      _loadingChapter = null;
      _notify();
    }
  }

  /// 切到指定章（0 基）并跳到 [page]。越界抛 [RangeError] 且不改状态。
  /// 切章是持久化点。
  Future<void> goToChapter(int index, {int page = 0}) async {
    if (index < 0 || index >= chapterCount) {
      throw RangeError.range(index, 0, chapterCount - 1, 'index');
    }
    if (_disposed) return;
    await _ensureChapterLoaded(index);
    if (_disposed) return;
    _chapterIndex = index;
    _pageIndex = images.isEmpty ? 0 : page.clamp(0, images.length - 1);
    _notify();
    await _persist();
    preloadAround();
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
    preloadAround();
    return true;
  }

  Future<bool> previousPage() async {
    if (!hasPreviousPage) return false;
    _pageIndex--;
    _notify();
    await _persist();
    preloadAround();
    return true;
  }

  /// 跳到当前章指定页（0 基，越界钳制）。跳页是持久化点。
  Future<void> goToPage(int index) async {
    if (images.isEmpty) return;
    final clamped = index.clamp(0, images.length - 1);
    if (_disposed || clamped == _pageIndex) return;
    _pageIndex = clamped;
    _notify();
    await _persist();
    preloadAround();
  }

  /// 连续模式滚动回报当前可见图（0 基）。只更新状态，不立即落库——
  /// 滚动是高频事件；持久化由调用方在退出时 [persistNow] 兜底。
  void setVisibleIndex(int index) {
    if (images.isEmpty) return;
    final clamped = index.clamp(0, images.length - 1);
    if (_disposed || clamped == _pageIndex) return;
    _pageIndex = clamped;
    _notify();
    preloadAround();
  }

  /// 切换阅读模式（验收点：模式切换）。不是进度，不触发持久化。
  void setMode(ReaderMode newMode) =>
      updateSettings(_settings.copyWith(mode: newMode));

  void toggleMode() => setMode(
    _settings.mode.isPaged ? ReaderMode.continuousTtb : ReaderMode.pagedLtr,
  );

  /// 整体更新阅读偏好：内存即时生效，store 持久化（fire-and-forget）。
  void updateSettings(ReaderSettings next) {
    if (_disposed || next == _settings) return;
    _settings = next.normalized();
    _notify();
    final store = settingsStore;
    if (store != null) {
      store.save(_settings).catchError((Object _) {});
    }
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

  /// 预取当前章的图片（当前页 ± settings.preloadCount）到缓存。
  /// 失败逐张吞掉（记 errorMessage），不向外抛、不打断阅读。
  Future<void> preloadAround() async {
    final all = images;
    if (all.isEmpty) return;
    final span = _settings.preloadCount;
    if (span <= 0) return;
    for (var i = _pageIndex - span; i <= _pageIndex + span; i++) {
      if (i < 0 || i >= all.length) continue;
      try {
        await imageCache.load(all[i]);
      } on Object catch (error) {
        _errorMessage = '预取失败：$error';
        _notify();
      }
    }
  }

  /// 取当前页字节（走缓存；供 UI/联调使用）。
  Future<Uint8List> loadCurrentImage() {
    final url = currentImage;
    if (url == null) {
      return Future.error(StateError('当前章节没有图片'));
    }
    return imageCache.load(ReaderImage.plain(url));
  }

  /// 手动持久化点（退出阅读页时由集成方调用）。
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
