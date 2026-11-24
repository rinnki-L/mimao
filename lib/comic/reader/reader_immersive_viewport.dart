// 阅读视口：把"章节流"渲染成可翻页/可滚动的图片视图，承载点击热区、双击/
// 长按/捏合缩放。翻页模式与连续/瀑布模式共用同一套图片槽与预取器。
//
// 对照 Venera-Next 的 gallery_view / continuous_view：
// - 翻页模式按 ReaderPageLayout 把 1~N 张源图铺成一屏，首尾保留哨兵页切章；
// - 连续/瀑布模式用 scrollable_positioned_list 做按项定位，配合
//   ReaderContinuousScrollController 在图片异步测量后修正滚动位置；
// - 可见项边界驱动进度上报与前后章预取，不再靠"图片加载完"猜位置；
// - 图片槽先按编码头宽高占位、再解码显示，避免列表高度突然撑开。
//
// 全局流索引只在本文件里出现；位置变化经 [ImmersiveReaderController.reportFlowIndex]
// 折算成真实章节/页再落库。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/theme.dart';
import 'reader_cache.dart';
import 'reader_continuous_scroll.dart';
import 'reader_flow.dart';
import 'reader_image_size.dart';
import 'reader_white_border_crop.dart';
import 'reader_immersive_controller.dart';
import 'reader_models.dart';
import 'reader_page_layout.dart';
import 'reader_precache.dart';
import 'reader_settings.dart';
import 'reader_view_mode.dart';
import 'reader_waterfall_controller.dart';

/// 阅读页给视口下命令的句柄（自动阅读、键盘、工具栏滑块共用）。
///
/// 视口是唯一拥有 PageController / ScrollController 的地方；页面不直接碰
/// 滚动实现，只通过这个句柄问"当前图就绪了吗""帮我滚一屏"。
class ReaderViewportController {
  _ReaderViewportDelegate? _delegate;

  void _attach(_ReaderViewportDelegate delegate) {
    _delegate = delegate;
  }

  void _detach(_ReaderViewportDelegate delegate) {
    if (identical(_delegate, delegate)) _delegate = null;
  }

  bool get isAttached => _delegate != null;

  bool get isScrollMode => _delegate?.isScrollMode ?? false;

  /// 当前可见图（翻页模式为整屏图）是否已加载或已失败。
  bool get currentImageReady => _delegate?.currentImageReady ?? true;

  /// 是否已到全书末尾（自动阅读据此停下，而不是空转写进度）。
  bool get atEnd => _delegate?.atEnd ?? false;

  /// 当前显示图（翻页模式取整屏第一张）的原始字节与地址；未加载时 null。
  Future<(Uint8List, String)?> currentImage() =>
      _delegate?.currentImage() ?? Future<(Uint8List, String)?>.value(null);

  Future<void> scrollViewport(int direction) =>
      _delegate?.scrollViewport(direction) ?? Future<void>.value();

  Future<void> turnGalleryPage(int direction) =>
      _delegate?.turnGalleryPage(direction) ?? Future<void>.value();
}

/// 视口对页面暴露的最小能力集。
abstract interface class _ReaderViewportDelegate {
  bool get isScrollMode;
  bool get currentImageReady;
  bool get atEnd;
  Future<(Uint8List, String)?> currentImage();
  Future<void> scrollViewport(int direction);
  Future<void> turnGalleryPage(int direction);
}

/// 渲染视图。管理 PageController / 滚动锚点与手势。
class ReaderViewport extends StatefulWidget {
  const ReaderViewport({
    super.key,
    required this.settings,
    required this.reading,
    required this.waterfall,
    required this.cache,
    required this.onTapCenter,
    this.chapterTitles = const <String>[],
    this.viewportController,
  });

  final ReaderSettings settings;
  final ImmersiveReaderController reading;
  final ReaderWaterfallController waterfall;
  final ReaderImageCache cache;
  final VoidCallback onTapCenter;
  final List<String> chapterTitles;
  final ReaderViewportController? viewportController;

  @override
  State<ReaderViewport> createState() => _ReaderViewportState();
}

class _ReaderViewportState extends State<ReaderViewport>
    implements _ReaderViewportDelegate {
  final PageController _pageController = PageController();
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final ScrollOffsetController _offset = ScrollOffsetController();
  final ReaderImageSizeCache _sizes = ReaderImageSizeCache();
  final ReaderWhiteBorderCrop _crop = ReaderWhiteBorderCrop();
  late final ReaderContinuousScrollController _scrollController;

  late ReaderImagePreloader _preloader;

  /// 最近一次上报的流索引（1 基；0 表示还没定位）。
  int _lastFlowIndex = 1;

  /// 最近一次由视口自己写入阅读控制器的位置，用来区分"外部跳页"。
  int _lastSyncedChapter = 0;
  int _lastSyncedPage = 0;

  int _lastWaterfallRevision = -1;
  bool _initialJumpScheduled = false;
  bool _sentinelBusy = false;

  /// 初始位置恢复完成前不回报可见项，否则第一帧会把保存的页码冲成第 1 页。
  bool _reportingReady = false;

  /// 向前补章插入内容时暂停上报，等锚点跳转完成再继续。
  bool _suppressReports = false;
  bool _emptyPrefetchScheduled = false;

  /// 已就绪/已失败的图片身份（按 cacheIdentity），供自动阅读判断。
  final Set<String> _readyIds = <String>{};
  final Set<String> _failedIds = <String>{};

  /// 已做解码预热的图片身份（有界，避免无限增长）。
  final Set<String> _decodedIds = <String>{};

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ReaderContinuousScrollController(
      _positions.itemPositions,
      onPositionChanged: _onScrollPositionChanged,
      canAnchor: (index) => index > 0 && index <= _flowImageCount,
    );
    _positions.itemPositions.addListener(_onItemPositionsChanged);
    _preloader = _createPreloader();
    widget.viewportController?._attach(this);
  }

  ReaderImagePreloader _createPreloader() => ReaderImagePreloader(
    cache: widget.cache,
    decodeAhead: 2,
    onBytes: _onPrefetchedBytes,
  );

  @override
  void didUpdateWidget(covariant ReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewportController, widget.viewportController)) {
      oldWidget.viewportController?._detach(this);
      widget.viewportController?._attach(this);
    }
    if (!identical(oldWidget.cache, widget.cache)) {
      _preloader.dispose();
      _preloader = _createPreloader();
    }
    if (oldWidget.settings.mode != widget.settings.mode) {
      _initialJumpScheduled = false;
      _reportingReady = false;
      _lastFlowIndex = 1;
    }
    if (widget.waterfall.revision != _lastWaterfallRevision) {
      _lastWaterfallRevision = widget.waterfall.revision;
      _syncToReadingPosition(animate: false);
    }
    final position = widget.reading.position;
    if (position.chapter != _lastSyncedChapter ||
        position.page != _lastSyncedPage) {
      _lastSyncedChapter = position.chapter;
      _lastSyncedPage = position.page;
      _syncToReadingPosition();
    }
    if (_flowImageCount > 0) _scheduleInitialJump();
    _preloader.update(_prefetchRequests());
  }

  @override
  void dispose() {
    _disposed = true;
    widget.viewportController?._detach(this);
    _positions.itemPositions.removeListener(_onItemPositionsChanged);
    _preloader.dispose();
    _sizes.clear();
    _crop.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool get _gallery => widget.settings.mode.isGallery;

  /// 瀑布流跨章；连续模式只渲染当前章，滚到边缘再切章（对齐上游语义）。
  bool get _crossChapter => widget.settings.mode.isWaterfall;

  int get _flowImageCount => _crossChapter
      ? widget.waterfall.flow.imageCount
      : (_segment?.length ?? 0);

  ReaderPageLayout get _layout => ReaderPageLayout(
    imagesPerPage: _gallery ? widget.settings.imagesPerPage.clamp(1, 5) : 1,
    singleImageOnFirstPage: _gallery && widget.settings.singleImageOnFirstPage,
  );

  ReaderChapterSegment? get _segment =>
      widget.waterfall.flow.segmentOf(widget.reading.currentChapter);

  @override
  bool get isScrollMode => !_gallery;

  @override
  bool get currentImageReady {
    final requests = _currentRequests;
    if (requests.isEmpty) return true;
    return requests.every(
      (request) =>
          _readyIds.contains(request.cacheIdentity) ||
          _failedIds.contains(request.cacheIdentity),
    );
  }

  @override
  bool get atEnd {
    if (_gallery) {
      final reading = widget.reading;
      return reading.currentChapter >= widget.waterfall.source.chapterCount &&
          reading.displayPage >= reading.displayPageCount;
    }
    if (!_crossChapter) {
      // 连续模式滚到底会切下一章；只有最后一章才真的到头。
      if (widget.reading.currentChapter <
          widget.waterfall.source.chapterCount) {
        return false;
      }
    } else if (widget.waterfall.flow.lastChapter <
        widget.waterfall.source.chapterCount) {
      return false;
    }
    if (widget.waterfall.loadingAfter) return false;
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return false;
    return position.maxScrollExtent - position.pixels <= 1;
  }

  /// 当前正在看的图（翻页模式是整屏，滚动模式是最大可见项）。
  List<ImageRequest> get _currentRequests {
    if (_gallery) {
      final segment = _segment;
      if (segment == null || segment.length == 0) return const <ImageRequest>[];
      final page = widget.reading.position.displayPage;
      final (start, end) = _layout.imageRange(page, segment.length);
      return <ImageRequest>[
        for (var i = start; i < end; i++) segment.images[i],
      ];
    }
    if (!_crossChapter) {
      final segment = _segment;
      if (segment == null ||
          _lastFlowIndex < 1 ||
          _lastFlowIndex > segment.length) {
        return const <ImageRequest>[];
      }
      return <ImageRequest>[segment.images[_lastFlowIndex - 1]];
    }
    final image = widget.waterfall.flow.imageAt(_lastFlowIndex);
    return image == null
        ? const <ImageRequest>[]
        : <ImageRequest>[image.request];
  }

  // ── 预取窗口 ────────────────────────────────────────────────────────

  List<ImageRequest> _prefetchRequests() {
    final limit = widget.settings.preloadCount.clamp(1, 16);
    final result = <ImageRequest>[];
    final seen = <String>{};
    void add(ImageRequest request) {
      if (seen.add(request.cacheIdentity)) result.add(request);
    }

    if (_gallery) {
      final segment = _segment;
      if (segment == null || segment.length == 0) return result;
      final layout = _layout;
      final pageCount = layout.pageCount(segment.length);
      final current = widget.reading.position.displayPage.clamp(1, pageCount);
      void addPage(int page) {
        final (start, end) = layout.imageRange(page, segment.length);
        for (var i = start; i < end; i++) {
          add(segment.images[i]);
        }
      }

      addPage(current);
      for (
        var page = current + 1;
        page <= math.min(pageCount, current + limit);
        page++
      ) {
        addPage(page);
      }
      if (current > 1) addPage(current - 1);
      // 下一章已预取进流时，顺手把它的头几张图也灌进缓存。
      final next = widget.waterfall.flow.segmentOf(
        widget.reading.currentChapter + 1,
      );
      if (next != null) {
        for (var i = 0; i < math.min(next.length, 2); i++) {
          add(next.images[i]);
        }
      }
      return result;
    }

    final segment = _segment;
    if (!_crossChapter) {
      if (segment == null || segment.length == 0) return result;
      final current = _lastFlowIndex.clamp(1, segment.length);
      for (
        var index = current;
        index <= math.min(segment.length, current + limit);
        index++
      ) {
        add(segment.images[index - 1]);
      }
      for (
        var index = current - 1;
        index >= math.max(1, current - 2);
        index--
      ) {
        add(segment.images[index - 1]);
      }
      return result;
    }

    final flow = widget.waterfall.flow;
    if (flow.imageCount == 0) return result;
    final current = _lastFlowIndex.clamp(1, flow.imageCount);
    for (
      var index = current;
      index <= math.min(flow.imageCount, current + limit);
      index++
    ) {
      final image = flow.imageAt(index);
      if (image != null) add(image.request);
    }
    for (var index = current - 1; index >= math.max(1, current - 2); index--) {
      final image = flow.imageAt(index);
      if (image != null) add(image.request);
    }
    return result;
  }

  void _onPrefetchedBytes(ImageRequest request, Uint8List bytes) {
    if (_disposed) return;
    // 先量尺寸：等图片真正进入列表时，占位高度已经是真实宽高比。
    unawaited(_sizes.measure(request, bytes));
    final id = request.cacheIdentity;
    if (_decodedIds.add(id)) {
      if (_decodedIds.length > 64) _decodedIds.remove(_decodedIds.first);
      if (mounted) {
        unawaited(
          precacheImage(
            MemoryImage(bytes),
            context,
            onError: (Object error, StackTrace? stack) {
              // 预热失败不影响真正显示时的重试。
            },
          ),
        );
      }
    }
  }

  // ── 位置同步 ────────────────────────────────────────────────────────

  void _onScrollPositionChanged() {
    if (!mounted) return;
    // 首帧列表还没发布可见项时，先按阅读位置恢复一次。
    if (_lastFlowIndex <= 1 && !_initialJumpScheduled) {
      _scheduleInitialJump();
    }
  }

  void _scheduleInitialJump() {
    if (_initialJumpScheduled || _disposed) return;
    if (_flowImageCount <= 0) return;
    _initialJumpScheduled = true;
    _reportingReady = false;
    _syncToReadingPosition(animate: false);
  }

  void _syncToReadingPosition({bool animate = true}) {
    if (_disposed) return;
    final position = widget.reading.position;
    _lastSyncedChapter = position.chapter;
    _lastSyncedPage = position.page;
    if (_gallery) {
      if (_segment == null) return;
      _scheduleGalleryJump(_layout.pageForImage(position.page));
      return;
    }
    final int index;
    if (!_crossChapter) {
      final count = _flowImageCount;
      index = count <= 0 ? 1 : position.page.clamp(1, count);
    } else {
      index =
          widget.waterfall.flow.indexOf(
            ReaderImagePosition(
              chapter: position.chapter,
              chapterId: position.chapterId,
              page: position.page,
            ),
          ) ??
          1;
    }
    if (!_gallery) _lastFlowIndex = index;
    if (!_gallery) _reportingReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || !_itemScroll.isAttached) {
        if (mounted) _reportingReady = true;
        return;
      }
      final allowed = animate && widget.settings.pageAnimation;
      if (allowed) {
        unawaited(
          _itemScroll
              .scrollTo(
                index: index,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(_finishProgrammaticJump),
        );
      } else {
        _itemScroll.jumpTo(index: index);
        _finishProgrammaticJump();
      }
    });
  }

  /// 程序化跳转后等列表真正落位再开放可见项上报，避免旧位置的迟到事件
  /// 把刚恢复/跳转到的页码冲掉。
  void _finishProgrammaticJump() {
    if (_disposed || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !mounted) return;
        _reportingReady = true;
        _onItemPositionsChanged();
      });
    });
  }

  void _scheduleGalleryJump(int page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || !_pageController.hasClients) {
        if (mounted) _reportingReady = true;
        return;
      }
      final segment = _segment;
      final count = segment?.length ?? 0;
      if (count == 0) {
        _reportingReady = true;
        return;
      }
      final target = page.clamp(1, _layout.pageCount(count));
      if (widget.settings.pageAnimation) {
        unawaited(
          _pageController.animateToPage(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _pageController.jumpToPage(target);
      }
      _reportingReady = true;
    });
  }

  void _onItemPositionsChanged() {
    if (_disposed || _gallery || !_reportingReady || _suppressReports) return;
    final positions = _positions.itemPositions.value;
    final imageCount = _flowImageCount;
    if (imageCount <= 0) return;

    ItemPosition? best;
    var bestVisible = -1.0;
    var bestDistance = double.infinity;
    for (final item in positions) {
      if (item.index < 1 || item.index > imageCount) continue;
      final leading = item.itemLeadingEdge;
      final trailing = item.itemTrailingEdge;
      if (trailing <= 0 || leading >= 1) continue;
      final visible = math.min(trailing, 1.0) - math.max(leading, 0.0);
      final distance = ((leading + trailing) / 2 - 0.5).abs();
      final better =
          visible > bestVisible + 0.000001 ||
          ((visible - bestVisible).abs() <= 0.000001 &&
              (item.index == _lastFlowIndex ||
                  (best?.index != _lastFlowIndex &&
                      distance < bestDistance - 0.000001)));
      if (better) {
        best = item;
        bestVisible = visible;
        bestDistance = distance;
      }
    }
    if (best == null) return;
    if (best.index != _lastFlowIndex) {
      _lastFlowIndex = best.index;
      final flowIndex = _crossChapter ? best.index : _toFlowIndex(best.index);
      if (flowIndex != null) {
        unawaited(widget.reading.reportFlowIndex(flowIndex));
      } else {
        unawaited(widget.reading.goToPage(best.index));
      }
      final position = widget.reading.position;
      _lastSyncedChapter = position.chapter;
      _lastSyncedPage = position.page;
      _preloader.update(_prefetchRequests());
      if (_crossChapter) _prefetchChapters(best.index);
    }
  }

  /// 连续模式的章内页 → 全局流索引（流里可能还留着其它章段）。
  int? _toFlowIndex(int page) {
    final segment = _segment;
    if (segment == null) return null;
    final first = widget.waterfall.flow.firstIndexOf(segment.chapter);
    if (first == null) return null;
    return first + page - 1;
  }

  void _prefetchChapters(int current) {
    final threshold = widget.settings.preloadCount.clamp(1, 16);
    unawaited(
      widget.waterfall.ensureAfter(current: current, threshold: threshold),
    );
    unawaited(_ensureBeforeWithAnchor(current, threshold));
  }

  /// 向前补章会插在当前项之前，插入后必须把滚动锚点一起挪过去。
  Future<void> _ensureBeforeWithAnchor(int current, int threshold) async {
    final inserted = await widget.waterfall.ensureBefore(
      current: current,
      threshold: threshold,
    );
    if (_disposed || !mounted || inserted <= 0) return;
    _suppressReports = true;
    _lastFlowIndex += inserted;
    final target = _lastFlowIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted && _itemScroll.isAttached) {
        _itemScroll.jumpTo(index: target);
      }
      _suppressReports = false;
    });
  }

  void _onGalleryPageChanged(int index, int total, int pageCount) {
    if (_sentinelBusy) return;
    if (index == 0) {
      unawaited(_handleSentinel(-1, pageCount));
      return;
    }
    if (index == total - 1) {
      unawaited(_handleSentinel(1, pageCount));
      return;
    }
    final segment = _segment;
    if (segment == null) return;
    final (start, _) = _layout.imageRange(index, segment.length);
    if (start >= segment.length) return;
    final imageNumber = start + 1;
    unawaited(widget.reading.goToPage(imageNumber));
    final position = widget.reading.position;
    _lastSyncedChapter = position.chapter;
    _lastSyncedPage = position.page;
    _preloader.update(_prefetchRequests());

    // 接近章尾就提前把下一章章节段拉进流，哨兵切章不再等网络。
    if (index >= pageCount - 2) {
      unawaited(
        widget.waterfall.ensureAfter(
          current: _flowImageCount,
          threshold: widget.settings.preloadCount.clamp(1, 16),
        ),
      );
    }
  }

  Future<void> _handleSentinel(int direction, int pageCount) async {
    if (_sentinelBusy) return;
    _sentinelBusy = true;
    try {
      final moved = direction > 0
          ? await widget.reading.nextChapter()
          : await widget.reading.previousChapter();
      if (_disposed || !mounted) return;
      final position = widget.reading.position;
      _lastSyncedChapter = position.chapter;
      _lastSyncedPage = position.page;
      if (moved) {
        final segment = _segment;
        final target = direction > 0
            ? 1
            : _layout.pageCount(segment?.length ?? 0);
        _scheduleGalleryJump(target);
        _initialJumpScheduled = true;
      } else {
        _scheduleGalleryJump(direction > 0 ? pageCount : 1);
      }
    } finally {
      _sentinelBusy = false;
    }
  }

  // ── 对外命令 ────────────────────────────────────────────────────────

  @override
  Future<void> scrollViewport(int direction) async {
    if (_gallery || direction == 0) return;
    if (!_crossChapter && _scrollController.hasClients) {
      final position = _scrollController.position;
      if (direction > 0 &&
          position.maxScrollExtent - position.pixels <= 1 &&
          widget.reading.currentChapter <
              widget.waterfall.source.chapterCount) {
        await widget.reading.nextChapter();
        return;
      }
      if (direction < 0 &&
          position.pixels - position.minScrollExtent <= 1 &&
          widget.reading.currentChapter > 1) {
        await widget.reading.previousChapter(toLastPage: true);
        return;
      }
    }
    final extent = _scrollController.hasClients
        ? _scrollController.position.viewportDimension
        : MediaQuery.sizeOf(context).height;
    await _scrollController.scrollBy(
      direction * extent * 0.85 * widget.settings.scrollSpeed,
      duration: widget.settings.pageAnimation
          ? const Duration(milliseconds: 260)
          : null,
    );
  }

  @override
  Future<void> turnGalleryPage(int direction) async {
    if (!_gallery || direction == 0) return;
    await widget.reading.turnDisplayPage(direction);
  }

  // ── 点击热区 ────────────────────────────────────────────────────────

  void _onTapAt(double ratio) {
    if (!widget.settings.tapToTurnPages) {
      widget.onTapCenter();
      return;
    }
    if (ratio < 0.3) {
      _turn(_forward(-1));
    } else if (ratio > 0.7) {
      _turn(_forward(1));
    } else {
      widget.onTapCenter();
    }
  }

  int _forward(int direction) {
    var delta = direction;
    if (widget.settings.mode.isReverse) delta = -delta;
    if (widget.settings.reverseTapToTurnPages) delta = -delta;
    return delta;
  }

  void _turn(int direction) {
    if (direction == 0) return;
    if (_gallery) {
      unawaited(widget.reading.turnDisplayPage(direction));
    } else {
      unawaited(scrollViewport(direction));
    }
  }

  // ── 构建 ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _preloader.update(_prefetchRequests());
    // 首次 build 时章节可能已经加载完成（start 的 Future 在首帧前就 resolve），
    // 此时 didUpdateWidget 不会再来一次；在 build 里补一次初始定位。
    if (_flowImageCount > 0) _scheduleInitialJump();
    final mode = widget.settings.mode;
    final content = _gallery ? _buildGallery(mode) : _buildScroll(mode);
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && _gallery) {
          final delta = event.scrollDelta.dy != 0
              ? event.scrollDelta.dy
              : event.scrollDelta.dx;
          if (delta != 0) {
            unawaited(widget.reading.turnDisplayPage(delta > 0 ? 1 : -1));
          }
        }
      },
      child: content,
    );
  }

  Widget _buildGallery(ReaderViewMode mode) {
    final segment = _segment;
    if (segment == null || segment.length == 0) return _buildStatus();
    final layout = _layout;
    final pageCount = layout.pageCount(segment.length);
    if (pageCount <= 0) return _buildEmptyChapter();
    final total = pageCount + 2;
    return PageView.builder(
      key: const Key('immersive-gallery'),
      controller: _pageController,
      scrollDirection: mode.isVertical ? Axis.vertical : Axis.horizontal,
      reverse: mode.isReverse,
      allowImplicitScrolling: true,
      itemCount: total,
      onPageChanged: (index) => _onGalleryPageChanged(index, total, pageCount),
      itemBuilder: (context, index) {
        if (index == 0 || index == total - 1) {
          return const SizedBox.shrink(key: Key('immersive-gallery-sentinel'));
        }
        final (start, end) = layout.imageRange(index, segment.length);
        if (start >= end) return const SizedBox.shrink();
        return _buildGalleryPage(segment, start, end, mode);
      },
    );
  }

  Widget _buildGalleryPage(
    ReaderChapterSegment segment,
    int start,
    int end,
    ReaderViewMode mode,
  ) {
    if (end - start == 1) {
      return _buildSlot(
        segment.images[start],
        index: start + 1,
        fill: true,
        vertical: mode.isVertical,
      );
    }
    final images = <Widget>[
      for (var i = start; i < end; i++)
        Expanded(
          child: _buildSlot(
            segment.images[i],
            index: i + 1,
            fill: true,
            vertical: mode.isVertical,
            alignment: _galleryAlignment(i - start, end - start, mode),
          ),
        ),
    ];
    if (images.length == 1) return images.first;
    if (mode.isReverse) {
      images.setAll(0, images.reversed.toList());
    }
    return mode.isVertical ? Column(children: images) : Row(children: images);
  }

  Alignment _galleryAlignment(int offset, int count, ReaderViewMode mode) {
    if (count < 2) return Alignment.center;
    if (mode.isVertical) {
      return offset == 0 ? Alignment.bottomCenter : Alignment.topCenter;
    }
    return offset == 0 ? Alignment.centerRight : Alignment.centerLeft;
  }

  Widget _buildScroll(ReaderViewMode mode) {
    final imageCount = _flowImageCount;
    if (imageCount <= 0) return _buildStatus();
    final total = imageCount + 2;
    return ScrollablePositionedList.builder(
      key: const Key('immersive-scroll'),
      itemCount: total,
      itemScrollController: _itemScroll,
      itemPositionsListener: _positions,
      scrollOffsetController: _offset,
      scrollDirection: mode.isVertical ? Axis.vertical : Axis.horizontal,
      reverse: mode.isReverse,
      physics: ReaderContinuousLayoutPhysics(controller: _scrollController),
      itemBuilder: (context, index) {
        if (index == 0) {
          return SizedBox(
            key: const Key('immersive-flow-top'),
            width: mode.isVertical ? double.infinity : 0.01,
            height: mode.isVertical ? 0.01 : double.infinity,
          );
        }
        if (index == total - 1) return _buildFlowEnd();
        ImageRequest? request;
        int? chapter;
        var firstInSegment = false;
        if (_crossChapter) {
          final image = widget.waterfall.flow.imageAt(index);
          if (image == null) return const SizedBox.shrink();
          request = image.request;
          chapter = image.position.chapter;
          firstInSegment = image.isFirstInSegment;
        } else {
          final segment = _segment;
          if (segment == null || index > segment.length) {
            return const SizedBox.shrink();
          }
          request = segment.images[index - 1];
          chapter = segment.chapter;
          firstInSegment = index == 1;
        }
        Widget item = _buildSlot(
          request,
          index: index,
          fill: false,
          vertical: mode.isVertical,
        );
        // 每章首图上方标一次章节标题，读者知道已经换章。
        if (firstInSegment && mode.isVertical) {
          item = Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[_buildChapterDivider(chapter), item],
          );
        }
        return ReaderContinuousScrollAnchor(
          controller: _scrollController,
          index: index,
          child: item,
        );
      },
    );
  }

  Widget _buildChapterDivider(int chapter) {
    final title = chapter >= 1 && chapter <= widget.chapterTitles.length
        ? widget.chapterTitles[chapter - 1]
        : '第 $chapter 章';
    final theme = Theme.of(context);
    return Padding(
      key: Key('immersive-chapter-divider-$chapter'),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.9,
          ),
          borderRadius: MimaoShapes.pill,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _goNextChapterFromEnd() async {
    final ok = await widget.reading.nextChapter();
    if (!mounted) return;
    if (!ok) {
      final message = widget.reading.message;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message ?? '没有下一章了')));
    }
  }

  Widget _buildFlowEnd() {
    final controller = widget.waterfall;
    if (!_crossChapter) {
      final hasNext =
          widget.reading.currentChapter < controller.source.chapterCount;
      if (hasNext) {
        return Padding(
          key: const Key('immersive-flow-next-chapter'),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: TextButton(
              onPressed: () => unawaited(_goNextChapterFromEnd()),
              child: const Text('下一章'),
            ),
          ),
        );
      }
      return const Padding(
        key: Key('immersive-flow-end'),
        padding: EdgeInsets.all(24),
        child: Center(child: Text('没有更多章节了')),
      );
    }
    if (controller.loadingAfter) {
      return const Padding(
        key: Key('immersive-flow-loading'),
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (controller.afterError != null) {
      return Padding(
        key: const Key('immersive-flow-error'),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Text('下一章加载失败：${controller.afterError}'),
              TextButton(
                onPressed: () =>
                    unawaited(controller.retryAfter(current: _flowImageCount)),
                child: const Text('点此重试'),
              ),
            ],
          ),
        ),
      );
    }
    return const Padding(
      key: Key('immersive-flow-end'),
      padding: EdgeInsets.all(24),
      child: Center(child: Text('没有更多章节了')),
    );
  }

  Widget _buildStatus() {
    final controller = widget.waterfall;
    // 当前章已加载但为空：不是"加载中"，也不能永远转圈。
    final currentEmpty =
        _flowImageCount == 0 &&
        controller.flow.segmentCount > 0 &&
        _segment != null;
    if (currentEmpty) {
      if (_crossChapter && !_emptyPrefetchScheduled) {
        _emptyPrefetchScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_disposed || !mounted) return;
          unawaited(
            controller.ensureAfter(
              current: 0,
              threshold: widget.settings.preloadCount.clamp(1, 16),
            ),
          );
        });
      }
      return _buildEmptyChapter();
    }
    if (controller.afterError != null) {
      return Center(
        key: const Key('immersive-chapter-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('章节加载失败：${controller.afterError}'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  unawaited(controller.retryAfter(current: _flowImageCount)),
              child: const Text('点此重试'),
            ),
          ],
        ),
      );
    }
    return const Center(
      key: Key('immersive-chapter-loading'),
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildEmptyChapter() {
    final hasNext =
        widget.reading.currentChapter < widget.waterfall.source.chapterCount;
    return Center(
      key: const Key('immersive-empty-chapter'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('本章暂无图片'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: hasNext
                ? () {
                    if (_crossChapter) {
                      unawaited(
                        widget.waterfall.ensureAfter(
                          current: 0,
                          threshold: widget.settings.preloadCount.clamp(1, 16),
                        ),
                      );
                    } else {
                      unawaited(_goNextChapterFromEnd());
                    }
                  }
                : null,
            child: Text(hasNext ? '加载下一章' : '已是最后一章'),
          ),
        ],
      ),
    );
  }

  Widget _buildSlot(
    ImageRequest request, {
    required int index,
    required bool fill,
    required bool vertical,
    Alignment alignment = Alignment.center,
  }) {
    return _ImmersiveImageSlot(
      key: Key('immersive-image-$index'),
      index: index,
      request: request,
      cache: widget.cache,
      sizeCache: _sizes,
      fill: fill,
      vertical: vertical,
      alignment: alignment,
      limitWidth: widget.settings.limitImageWidth,
      sideMargin: widget.settings.sideMargin,
      cropWhiteBorders: widget.settings.cropWhiteBorders && vertical && !fill,
      cropCache: _crop,
      doubleTapToZoom: widget.settings.doubleTapToZoom,
      longPressToZoom: widget.settings.longPressToZoom,
      onTapAt: _onTapAt,
      onState: (ready, failed) => _onImageState(request, ready, failed),
    );
  }

  @override
  Future<(Uint8List, String)?> currentImage() async {
    final requests = _currentRequests;
    if (requests.isEmpty) return null;
    final request = requests.first;
    try {
      final bytes = await widget.cache.loadRequest(request);
      return (bytes, request.url);
    } on Object {
      return null;
    }
  }

  void _onImageState(ImageRequest request, bool ready, bool failed) {
    final id = request.cacheIdentity;
    if (ready) {
      _readyIds.add(id);
    } else {
      _readyIds.remove(id);
    }
    if (failed) {
      _failedIds.add(id);
    } else if (ready) {
      _failedIds.remove(id);
    }
  }
}

/// 单张图槽：编码头宽高占位 → 解码显示；单击热区、双击/长按/捏合缩放。
class _ImmersiveImageSlot extends StatefulWidget {
  const _ImmersiveImageSlot({
    super.key,
    required this.index,
    required this.request,
    required this.cache,
    required this.sizeCache,
    required this.fill,
    required this.vertical,
    required this.alignment,
    required this.limitWidth,
    required this.sideMargin,
    required this.cropWhiteBorders,
    required this.cropCache,
    required this.doubleTapToZoom,
    required this.longPressToZoom,
    required this.onTapAt,
    required this.onState,
  });

  final int index;
  final ImageRequest request;
  final ReaderImageCache cache;
  final ReaderImageSizeCache sizeCache;

  /// true = 铺满父级可用框（翻页模式）；false = 按宽高比给连续列表一个确定高度。
  final bool fill;
  final bool vertical;
  final Alignment alignment;
  final bool limitWidth;
  final int sideMargin;
  final bool cropWhiteBorders;
  final ReaderWhiteBorderCrop cropCache;
  final bool doubleTapToZoom;
  final bool longPressToZoom;
  final ValueChanged<double> onTapAt;
  final void Function(bool ready, bool failed) onState;

  @override
  State<_ImmersiveImageSlot> createState() => _ImmersiveImageSlotState();
}

class _ImmersiveImageSlotState extends State<_ImmersiveImageSlot> {
  static const double _estimatedRatio = 0.72; // 常见漫画页宽/高，仅作占位
  static const double _maxImageWidth = 720;

  Uint8List? _bytes;
  Size? _size;
  WhiteBorderInsets _crop = WhiteBorderInsets.none;
  Object? _error;
  final TransformationController _transform = TransformationController();
  Matrix4? _savedTransform;
  Offset _lastTapPosition = Offset.zero;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _size = widget.sizeCache.peek(widget.request);
    final cached = widget.cache.peekRequest(widget.request);
    if (cached != null) {
      _bytes = cached;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onState(true, false);
      });
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant _ImmersiveImageSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.cacheIdentity != widget.request.cacheIdentity) {
      _bytes = null;
      _size = widget.sizeCache.peek(widget.request);
      _crop =
          widget.cropCache.peek(widget.request.cacheIdentity) ??
          WhiteBorderInsets.none;
      _error = null;
      _transform.value = Matrix4.identity();
      final cached = widget.cache.peekRequest(widget.request);
      if (cached != null) {
        _bytes = cached;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onState(true, false);
        });
      } else {
        unawaited(_load());
      }
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.cache.loadRequest(widget.request);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
      });
      widget.onState(true, false);
      final size = await widget.sizeCache.measure(widget.request, bytes);
      if (!mounted || !identical(_bytes, bytes)) return;
      if (size != null && size != _size) setState(() => _size = size);
      unawaited(_measureCrop(bytes));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      widget.onState(false, true);
    }
  }

  /// 白边检测在后台跑：先按原图显示，算完再收窄布局（不改原图）。
  Future<void> _measureCrop(Uint8List bytes) async {
    if (!widget.cropWhiteBorders) return;
    final insets = await widget.cropCache.measure(
      widget.request.cacheIdentity,
      bytes,
    );
    if (!mounted || insets.isNone || insets == _crop) return;
    setState(() => _crop = insets);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleDoubleTapZoom() {
    final current = _transform.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _transform.value = Matrix4.identity();
      return;
    }
    const zoom = 2.2;
    final point = _doubleTapPosition;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-point.dx * (zoom - 1), -point.dy * (zoom - 1), 0, 1)
      ..scaleByDouble(zoom, zoom, zoom, 1);
  }

  void _startLongPressZoom() {
    _savedTransform = _transform.value.clone();
    const zoom = 1.75;
    _transform.value = Matrix4.identity()..scaleByDouble(zoom, zoom, zoom, 1);
  }

  void _endLongPressZoom() {
    final saved = _savedTransform;
    _savedTransform = null;
    if (saved != null) _transform.value = saved;
  }

  double _ratio() {
    final size = _size;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return _estimatedRatio;
    }
    final ratio = size.width / size.height;
    // 裁掉左右白边后可见内容更窄，按同一缩放铺满容器时高度会变高：
    // 有效宽高比 = 原宽高比 × 可见宽度占比。
    final horizontal = _crop.left + _crop.right;
    if (horizontal > 0 && horizontal < 1) return ratio * (1 - horizontal);
    return ratio;
  }

  /// 连续列表里给这一项一个确定高度（图片解码前就占好位）。
  Widget _sizedContent(Widget child, BoxConstraints constraints) {
    final ratio = _ratio();
    final maxWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;
    final maxHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : MediaQuery.sizeOf(context).height;
    double width;
    double height;
    if (widget.vertical) {
      width = maxWidth;
      if (widget.limitWidth) width = math.min(width, _maxImageWidth);
      width *= 1 - 2 * widget.sideMargin / 100;
      height = width / ratio;
    } else {
      height = math.min(maxHeight, _maxImageWidth);
      width = height * ratio;
      if (width > maxWidth) {
        width = maxWidth;
        height = width / ratio;
      }
    }
    return Center(
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final error = _error;

    if (error != null) {
      return LayoutBuilder(
        builder: (context, constraints) => _wrapSlotBox(
          constraints,
          GestureDetector(
            key: Key('immersive-image-error-${widget.index}'),
            onTap: () {
              setState(() => _error = null);
              unawaited(_load());
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, size: 48),
                  const SizedBox(height: 8),
                  Text('图片加载失败', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  const Text('点此重试'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (bytes == null) {
      return LayoutBuilder(
        builder: (context, constraints) => _wrapSlotBox(
          constraints,
          const Center(
            key: Key('immersive-image-loading'),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    Widget image = SizedBox.expand(
      child: Image(
        image: MemoryImage(bytes),
        fit: BoxFit.contain,
        alignment: widget.alignment,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );

    // 白边裁剪：只改显示区域，不动原图字节。做法是横向放大 1/(1-l-r) 倍、
    // 把裁后区域对齐到框中心再裁掉溢出；框的宽高比同时换成裁后比例，
    // 所以画面本身不变形。
    if (!_crop.isNone) {
      final left = _crop.left;
      final right = _crop.right;
      final horizontal = left + right;
      if (horizontal > 0 && horizontal < 1) {
        image = LayoutBuilder(
          builder: (context, constraints) {
            final scale = 1 / (1 - horizontal);
            final width = constraints.maxWidth;
            if (!width.isFinite || width <= 0) return image;
            return ClipRect(
              child: OverflowBox(
                alignment: Alignment(-(left - right) / horizontal, 0),
                minWidth: width * scale,
                maxWidth: width * scale,
                minHeight: constraints.maxHeight,
                maxHeight: constraints.maxHeight,
                child: image,
              ),
            );
          },
        );
      }
    }

    final useDoubleTap = widget.doubleTapToZoom;
    image = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: useDoubleTap
          ? (details) => _lastTapPosition = details.localPosition
          : null,
      onTapUp: useDoubleTap ? null : _handleTapAt,
      onTap: useDoubleTap ? () => _handleTapPosition(_lastTapPosition) : null,
      onDoubleTapDown: useDoubleTap
          ? (details) => _doubleTapPosition = details.localPosition
          : null,
      onDoubleTap: useDoubleTap ? _toggleDoubleTapZoom : null,
      onLongPressStart: widget.longPressToZoom
          ? (_) => _startLongPressZoom()
          : null,
      onLongPressEnd: widget.longPressToZoom
          ? (_) => _endLongPressZoom()
          : null,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1.0,
        maxScale: 4.0,
        child: image,
      ),
    );

    if (widget.fill) return SizedBox.expand(child: image);
    return LayoutBuilder(
      builder: (context, constraints) => _sizedContent(image, constraints),
    );
  }

  void _handleTapAt(TapUpDetails details) =>
      _handleTapPosition(details.localPosition);

  void _handleTapPosition(Offset localPosition) {
    final box = context.size;
    if (box == null || box.isEmpty) return;
    final ratio = widget.vertical
        ? localPosition.dy / box.height
        : localPosition.dx / box.width;
    widget.onTapAt(ratio.clamp(0.0, 1.0));
  }

  Widget _wrapSlotBox(BoxConstraints constraints, Widget child) {
    if (widget.fill) return SizedBox.expand(child: child);
    return _sizedContent(child, constraints);
  }
}
