// 阅读器控制器：唯一持有阅读状态的地方（对齐 anime/player/PlayerController 的写法）。
//
// 依赖的是纯模型 + [ReaderChapterSource] + [ProgressRecorder] + [ReaderImageCache]，
// 不认识 Widget、不联网、不碰源引擎；UI 通过 [ChangeNotifier] 重建，单测直接断言状态。
//
// 行为取舍：
//  - 章图片按章懒加载，且只缓存"成功加载"的章：空章（0 张）算成功，缓存后不重拉；
//    失败章不入缓存，重试时必然重新调 loadImages。
//  - open/切章统一走同一落点解析：先向后找非空章，到尾再向前回退，全空停目标章；
//    加载失败是停靠点（交给 [chapterError] 显示错误），不参与跳过。
//  - 翻页默认不跨章；UI/键盘传 wrapChapter: true 才跨章，跨章沿用上面的跳过逻辑。
//  - 进度：翻页/切章/跳页立即写；连续模式滚动回报走 1 秒防抖，
//    persistNow / dispose 兜底把挂起的那次补写掉。

import 'dart:async';

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

  /// 跨章翻到上一章末页时传给 goToChapter 的哨兵页码，
  /// 由落点章的真实页数钳制（落点可能因空章跳过而继续前移）。
  static const int _lastPageSentinel = 1 << 30;

  /// 连续模式滚动回报的落库防抖窗口。
  static const Duration _persistDebounceDelay = Duration(seconds: 1);

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

  /// 成功加载的章图片（章下标 → 图片列表）；空列表 = 空章。
  /// 失败章绝不写进来，因此重拉不需要额外的"失效"步骤。
  final Map<int, List<ReaderImage>> _loadedImages = <int, List<ReaderImage>>{};

  /// 滚动回报挂起的防抖落库；立即持久化与 dispose 都会取消它。
  Timer? _persistDebounce;

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

  /// 当前章是否已加载且为空章（与"加载失败"区分开）。
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
  /// 生产页在 initState 调一次；测试可手动调。open 不是进度持久化点。
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
    if (_disposed) return;
    final target = _chapterIndex;
    final landing = await _resolveLandingChapter(target);
    if (_disposed) return;
    _chapterIndex = landing;
    _pageIndex = 0;
    _notify();
    await preloadAround();
  }

  /// 确保章图片已加载：命中缓存直接复用（空章也算命中且不重拉），
  /// 否则只调一次 loadImages；失败置 [chapterError] 且不留缓存记录。
  Future<List<ReaderImage>> _ensureChapterLoaded(int index) async {
    final cached = _loadedImages[index];
    if (cached != null) {
      // 命中缓存的章没有加载错误，别把上一章的失败状态带过来。
      _chapterError = null;
      return cached;
    }
    _loadingChapter = index;
    _chapterError = null;
    _notify();
    try {
      final images = await _source.loadImages(index);
      final stored = List<ReaderImage>.unmodifiable(images);
      _loadedImages[index] = stored;
      return stored;
    } on Object catch (error) {
      _chapterError = error;
      // 失败不入缓存：重试时必然重新 loadImages。
      return const <ReaderImage>[];
    } finally {
      _loadingChapter = null;
      _notify();
    }
  }

  /// 落点解析（正向优先）：从 [target] 起向后找第一个非空章；到尾再向前回退找；
  /// 全空则停在 target。加载失败是停靠点（显示错误），不继续跳过。
  Future<int> _resolveLandingChapter(int target) async {
    for (var i = target; i < chapterCount; i++) {
      final images = await _ensureChapterLoaded(i);
      if (_chapterError != null || images.isNotEmpty) return i;
    }
    for (var i = target - 1; i >= 0; i--) {
      final images = await _ensureChapterLoaded(i);
      if (_chapterError != null || images.isNotEmpty) return i;
    }
    return target;
  }

  /// 落点解析（反向优先）：从 [target] 起向前找第一个非空章；到头再向后回退找。
  /// 上一章 wrap 走这条——空章要继续往更早的章找，不能跳回当前章。
  Future<int> _resolveLandingChapterBackward(int target) async {
    for (var i = target; i >= 0; i--) {
      final images = await _ensureChapterLoaded(i);
      if (_chapterError != null || images.isNotEmpty) return i;
    }
    for (var i = target + 1; i < chapterCount; i++) {
      final images = await _ensureChapterLoaded(i);
      if (_chapterError != null || images.isNotEmpty) return i;
    }
    return target;
  }

  /// 落到目标章：解析空章跳过后的真实落点、钳制页码、持久化并预取。
  Future<void> _landOnChapter(
    int target, {
    int page = 0,
    bool backward = false,
  }) async {
    final landing = backward
        ? await _resolveLandingChapterBackward(target)
        : await _resolveLandingChapter(target);
    if (_disposed) return;
    _chapterIndex = landing;
    final count = images.length;
    _pageIndex = count == 0 ? 0 : page.clamp(0, count - 1);
    _notify();
    await _persist();
    preloadAround();
  }

  /// 切到指定章（0 基）并跳到 [page]。越界抛 [RangeError] 且不改状态。
  /// 空章自动跳过；切章是持久化点。
  Future<void> goToChapter(int index, {int page = 0}) async {
    if (index < 0 || index >= chapterCount) {
      throw RangeError.range(index, 0, chapterCount - 1, 'index');
    }
    if (_disposed) return;
    if (_chapterError != null && index == _chapterIndex) {
      // 用户重试当前失败章：显式清一次记录，确保重新拉。
      _loadedImages.remove(index);
    }
    await _landOnChapter(index, page: page);
  }

  Future<void> nextChapter() =>
      hasNextChapter ? goToChapter(_chapterIndex + 1) : Future.value();

  Future<void> previousChapter() =>
      hasPreviousChapter ? goToChapter(_chapterIndex - 1) : Future.value();

  /// 翻页（验收点：翻页方向）。到章首/章尾默认不越界，返回是否真的移动了。
  /// [wrapChapter] 为真时在章尾切下一章第 0 页（空章由切章逻辑跳过）。
  /// 翻页是持久化点。
  Future<bool> nextPage({bool wrapChapter = false}) async {
    if (hasNextPage) {
      _pageIndex++;
      _notify();
      await _persist();
      preloadAround();
      return true;
    }
    if (!wrapChapter || !hasNextChapter) return false;
    await goToChapter(_chapterIndex + 1, page: 0);
    return true;
  }

  Future<bool> previousPage({bool wrapChapter = false}) async {
    if (hasPreviousPage) {
      _pageIndex--;
      _notify();
      await _persist();
      preloadAround();
      return true;
    }
    if (!wrapChapter || !hasPreviousChapter) return false;
    await _landOnChapter(
      _chapterIndex - 1,
      page: _lastPageSentinel,
      backward: true,
    );
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

  /// 连续模式滚动回报当前可见图（0 基）。只更新状态，落库走 1 秒防抖——
  /// 滚动是高频事件，静止后再写一次；退出时由 [dispose]/[persistNow] 兜底。
  void setVisibleIndex(int index) {
    if (images.isEmpty) return;
    final clamped = index.clamp(0, images.length - 1);
    if (_disposed || clamped == _pageIndex) return;
    _pageIndex = clamped;
    _notify();
    preloadAround();
    _persistDebounce?.cancel();
    _persistDebounce = Timer(_persistDebounceDelay, () {
      _persistDebounce = null;
      // 防抖到期后 fire-and-forget；_persist 内部已收敛失败。
      _persist();
    });
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

  /// 手动持久化点：取消挂起的防抖落库，按当前状态立即写一次。
  Future<void> persistNow() => _persist();

  Future<void> _persist() async {
    // 立即写时顺手取消挂起的防抖，避免同一进度写两遍。
    final pending = _persistDebounce;
    if (pending != null) {
      pending.cancel();
      _persistDebounce = null;
    }
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
    if (_persistDebounce != null) {
      // 退出时把挂起的滚动落库补写一次；fire-and-forget，catch 收尾不抛。
      _persist().catchError((Object _) {});
    }
    super.dispose();
  }
}
