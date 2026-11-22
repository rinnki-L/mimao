// 漫画沉浸式阅读页：全屏黑底 Stack，视图层 / 常驻页码 / 工具栏三层。
//
// 交互骨架对齐 Venera：三区单击翻页 / 呼出工具栏、六模式视图、首尾哨兵切章、
// 键盘与滚轮翻页、章级三态、设置面板。页面只持 UI 状态（工具栏可见性、
// PageController、连续列表控制器）；阅读状态一律经注入或自建的
// [ReaderController] 读写。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明
// （Flutter 3.50 弃用整个 material.dart，M1 起全仓沿用）。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'reader_cache.dart';
import 'reader_controller.dart';
import 'reader_models.dart';
import 'reader_progress.dart';
import 'reader_settings.dart';
import 'reader_settings_panel.dart';
import 'reader_toolbar.dart';
import 'reader_views.dart';

/// 捏合缩放映射：以开始时的倍率为基准，乘以手势 scale 后钳制到合法区间。
/// 纯函数，保留给 reader_models_test.dart 引用（widget 测试难稳定模拟双指）。
double pinchZoom(double baseZoom, double scale) => (baseZoom * scale)
    .clamp(ReaderController.minZoom, ReaderController.maxZoom)
    .toDouble();

/// 沉浸式漫画阅读页。
class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.title,
    required this.source,
    required this.imageCache,
    this.recorder,
    this.settingsStore,
    this.initialChapter = 0,
    this.initialPage = 0,
    this.controller,
  });

  final String title;
  final ReaderChapterSource source;
  final ReaderImageCache imageCache;
  final ProgressRecorder? recorder;
  final ReaderSettingsStore? settingsStore;
  final int initialChapter;
  final int initialPage;

  /// 可选：外部注入控制器（widget 测试用）。注入时页面不调 open()。
  final ReaderController? controller;

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  late final ReaderController _controller;
  late final bool _ownsController;
  bool _disposed = false;

  late final PageController _pageController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  /// 工具栏是否可见；默认显示，单击中间区切换。
  /// 滑入滑出用 AnimatedPositioned（~180ms），由这个布尔驱动。
  bool _toolbarVisible = true;

  /// 视图层的全局键，用于把点击坐标换算成视图内比例（不是整屏）。
  final GlobalKey _viewKey = GlobalKey(debugLabel: 'reader-view');

  /// 一次单击的按下位置；抬手时位移超过阈值即视为拖拽，不触发三区点击。
  Offset? _tapDownPosition;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = ReaderController(
        source: widget.source,
        imageCache: widget.imageCache,
        settingsStore: widget.settingsStore,
        recorder: widget.recorder,
        initialChapter: widget.initialChapter,
      );
      _ownsController = true;
      _controller.open().then((_) {
        if (_disposed) return;
        if (widget.initialPage > 0) {
          _controller.goToPage(widget.initialPage);
        }
        _syncPageController();
      });
    }

    // +1 跳过首哨兵：初始视图必须落在第 1 页而不是空白哨兵上。
    _pageController = PageController(initialPage: _controller.pageIndex + 1);

    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
  }

  @override
  void didUpdateWidget(covariant ComicReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.controller != _controller) {
      _controller = widget.controller!;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    _pageController.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onItemPositionsChanged() {
    if (!_controller.settings.mode.isContinuous) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions.reduce(
      (a, b) => a.itemLeadingEdge >= b.itemLeadingEdge ? a : b,
    );
    _controller.setVisibleIndex(first.index);
  }

  void _syncPageController() {
    final mode = _controller.settings.mode;
    if (!mode.isPaged || !_pageController.hasClients) return;
    final target = _controller.pageIndex + 1; // +1：首哨兵占位
    if (_pageController.page?.round() != target) {
      _pageController.jumpToPage(target);
    }
  }

  Future<bool> _turn({required bool next}) async {
    final moved = next
        ? await _controller.nextPage(wrapChapter: true)
        : await _controller.previousPage(wrapChapter: true);
    if (moved) _syncPageController();
    return moved;
  }

  Future<void> _switchChapter({required bool next}) async {
    final before = _controller.chapterIndex;
    if (next) {
      await _controller.nextChapter();
    } else {
      await _controller.previousChapter();
    }
    if (_controller.chapterIndex != before) _syncPageController();
  }

  /// 哨兵滑入：切到相邻章；无章可切则弹回当前章的第 1 页/末页。
  Future<void> _onSentinel(int delta) async {
    final next = delta > 0;
    final canSwitch = next
        ? _controller.hasNextChapter
        : _controller.hasPreviousChapter;
    if (canSwitch) {
      await _switchChapter(next: next);
      return;
    }
    final target = next ? _controller.pageCount - 1 : 0;
    await _controller.goToPage(target);
    _syncPageController();
  }

  void _toggleToolbar() => setState(() => _toolbarVisible = !_toolbarVisible);

  void _hideToolbar() {
    if (!_toolbarVisible) return;
    setState(() => _toolbarVisible = false);
  }

  /// 三区单击：横向按视图内 dx 的 30%/70%，纵向按 dy 同比例。
  /// 工具栏可见时任意单击先隐藏工具栏（不翻页）。
  void _onZoneTap(Offset globalPosition) {
    if (_toolbarVisible || !_controller.settings.tapToTurn) {
      _hideToolbar();
      return;
    }

    final mode = _controller.settings.mode;
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.sizeOf(context);
    final offset = box?.globalToLocal(globalPosition) ?? globalPosition;
    final double fraction;
    if (mode.isVertical) {
      fraction = size.height == 0 ? 0.5 : offset.dy / size.height;
    } else {
      fraction = size.width == 0 ? 0.5 : offset.dx / size.width;
    }

    bool forward;
    if (fraction < 0.30) {
      forward = false;
    } else if (fraction > 0.70) {
      forward = true;
    } else {
      _toggleToolbar();
      return;
    }
    final bool next = mode.isRtl ? !forward : forward;
    _turn(next: next);
  }

  void _onViewPointerDown(PointerDownEvent event) {
    _tapDownPosition = event.position;
  }

  void _onViewPointerUp(PointerUpEvent event) {
    final down = _tapDownPosition;
    _tapDownPosition = null;
    if (down == null) return;
    if ((event.position - down).distance > 10) return; // 拖拽，交给翻页手势
    _onZoneTap(event.position);
  }

  void _cycleMode() {
    const order = <ReaderMode>[
      ReaderMode.pagedLtr,
      ReaderMode.pagedRtl,
      ReaderMode.pagedTtb,
      ReaderMode.continuousTtb,
      ReaderMode.continuousLtr,
      ReaderMode.continuousRtl,
    ];
    final current = _controller.settings.mode;
    final next = order[(order.indexOf(current) + 1) % order.length];
    _controller.setMode(next);
    _syncPageController();
  }

  void _openSettings() {
    showReaderSettingsSheet(context, controller: _controller);
  }

  void _back() => Navigator.maybePop(context);

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    final mode = _controller.settings.mode;
    if (key == LogicalKeyboardKey.escape) {
      _back();
      return KeyEventResult.handled;
    }

    bool? next;
    if (key == LogicalKeyboardKey.pageDown) {
      next = true;
    } else if (key == LogicalKeyboardKey.pageUp) {
      next = false;
    } else if (mode.isVertical) {
      if (key == LogicalKeyboardKey.arrowDown) {
        next = true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        next = false;
      }
    } else {
      if (key == LogicalKeyboardKey.arrowRight) {
        next = true;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        next = false;
      }
    }
    if (key == LogicalKeyboardKey.home) {
      _jump(mode, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _jump(mode, _controller.pageCount - 1);
      return KeyEventResult.handled;
    }
    if (next == null) return KeyEventResult.ignored;

    final bool effectiveNext = mode.isRtl ? !next : next;
    if (mode.isPaged) {
      _turn(next: effectiveNext);
    } else {
      _stepContinuous(effectiveNext);
    }
    return KeyEventResult.handled;
  }

  void _stepContinuous(bool next) {
    final target = (_controller.pageIndex + (next ? 1 : -1)).clamp(
      0,
      _controller.pageCount - 1,
    );
    _jump(_controller.settings.mode, target);
  }

  void _jump(ReaderMode mode, int index) {
    if (_controller.pageCount == 0) return;
    final target = index.clamp(0, _controller.pageCount - 1);
    _controller.goToPage(target);
    if (mode.isPaged) {
      _syncPageController();
    } else if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: target);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_controller.settings.mode.isPaged) return;
    // 滚轮事件本身不带 modifiers，Ctrl/Cmd 只能从键盘状态读取。
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return;
    }
    _turn(next: event.scrollDelta.dy > 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => PopScope<void>(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) _controller.persistNow();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            autofocus: true,
            onKeyEvent: _onKeyEvent,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  child: Listener(
                    key: _viewKey,
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onViewPointerDown,
                    onPointerUp: _onViewPointerUp,
                    onPointerSignal: _onPointerSignal,
                    child: _buildViewLayer(),
                  ),
                ),
                if (!_toolbarVisible) ReaderPageInfo(controller: _controller),
                _buildTopBar(),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewLayer() {
    if (_controller.chapterLoading ||
        _controller.chapterError != null ||
        _controller.isChapterEmpty) {
      return ReaderChapterState(
        controller: _controller,
        onRetry: () => _controller.goToChapter(_controller.chapterIndex),
        onNextChapter: () => _controller.nextChapter(),
      );
    }
    final mode = _controller.settings.mode;
    if (mode.isPaged) {
      return ReaderPagedView(
        controller: _controller,
        pageController: _pageController,
        onSentinel: _onSentinel,
      );
    }
    return ReaderContinuousView(
      controller: _controller,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
    );
  }

  Widget _buildTopBar() {
    return AnimatedPositioned(
      key: const Key('reader-top-bar'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      top: _toolbarVisible ? 0 : -_barHeight,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_toolbarVisible,
        child: ReaderTopBar(
          title: widget.title,
          controller: _controller,
          onBack: _back,
          onSettings: _openSettings,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return AnimatedPositioned(
      key: const Key('reader-bottom-bar'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: 0,
      right: 0,
      bottom: _toolbarVisible ? 0 : -_barHeight,
      child: IgnorePointer(
        ignoring: !_toolbarVisible,
        child: ReaderBottomBar(
          controller: _controller,
          onPrevChapter: () => _switchChapter(next: false),
          onNextChapter: () => _switchChapter(next: true),
          onCycleMode: _cycleMode,
          onSettings: _openSettings,
        ),
      ),
    );
  }

  // 隐藏时把栏移出视口的估算高度（实际高度由内容决定，取足够大的值）。
  static const double _barHeight = 200;
}
