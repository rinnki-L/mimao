// 阅读视口：把"章节流"渲染成可翻页/可滚动的图片视图，承载点击热区、双击/
// 长按/捏合缩放。全部用 Flutter 原生 PageView / CustomScrollView /
// InteractiveViewer 实现，不依赖第三方图片或滚动库。
//
// 全局流索引只在本文件里出现；位置变化经 [ImmersiveReaderController.reportFlowIndex]
// 折算成真实章节/页再落库。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'reader_cache.dart';
import 'reader_immersive_controller.dart';
import 'reader_models.dart';
import 'reader_settings.dart';
import 'reader_view_mode.dart';
import 'reader_waterfall_controller.dart';

/// 渲染视图。管理 PageController / ScrollController 与手势。
class ReaderViewport extends StatefulWidget {
  const ReaderViewport({
    super.key,
    required this.settings,
    required this.reading,
    required this.waterfall,
    required this.cache,
    required this.onTapCenter,
  });

  final ReaderSettings settings;
  final ImmersiveReaderController reading;
  final ReaderWaterfallController waterfall;
  final ReaderImageCache cache;
  final VoidCallback onTapCenter;

  @override
  State<ReaderViewport> createState() => _ReaderViewportState();
}

class _ReaderViewportState extends State<ReaderViewport> {
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  double _zoom = 1.0;
  bool _longPressZoom = false;

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _gallery => widget.settings.mode.isGallery;

  /// 当前视图里的总"图片位"数量（瀑布/连续 = 流图片数；分页 = 当前章页数）。
  int get _itemCount {
    if (_gallery) {
      final count = widget.reading.position.pageCount;
      // 首尾哨兵页：滑动越界切上一章/下一章。
      return count + 2;
    }
    return widget.waterfall.flow.imageCount + 2; // 顶部/流末保留位
  }

  /// 视图 index → 一张图的地址；null 表示哨兵位。
  ImageRequest? _imageAt(int index) {
    if (_gallery) {
      if (index == 0 || index == _itemCount - 1) return null;
      final chapter = widget.waterfall.flow.segmentOf(
        widget.reading.currentChapter,
      );
      final page = index; // 1 基
      final url = chapter != null && page <= chapter.length
          ? chapter.images[page - 1]
          : null;
      if (url == null) return null;
      return chapterRequest(chapter!.chapterId, page, url);
    }
    final image = widget.waterfall.flow.imageAt(index);
    if (image == null) return null;
    return ImageRequest.withReferer(
      url: image.url,
      referer: _refererFor(image.url),
    );
  }

  /// 从源引擎注入的每图请求头里取对应项；没有则只有 Referer。
  ImageRequest chapterRequest(String chapterId, int page, String url) {
    // 生产集成可把 imageRequests 注入到段；这里默认按站点推导 Referer。
    return ImageRequest.withReferer(url: url, referer: _refererFor(url));
  }

  String? _refererFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    return '${uri.scheme}://${uri.authority}/';
  }

  void _onTapUp(TapUpDetails details, BoxConstraints constraints) {
    if (!widget.settings.tapToTurnPages) {
      widget.onTapCenter();
      return;
    }
    final mode = widget.settings.mode;
    final pos = details.localPosition;
    final extent = mode.isVertical
        ? constraints.maxHeight
        : constraints.maxWidth;
    final offset = mode.isVertical ? pos.dy : pos.dx;
    final ratio = extent <= 0 ? 0.5 : offset / extent;
    if (ratio < 0.3) {
      unawaited(widget.reading.turnPage(_forward(-1)));
    } else if (ratio > 0.7) {
      unawaited(widget.reading.turnPage(_forward(1)));
    } else {
      widget.onTapCenter();
    }
  }

  int _forward(int direction) {
    var d = direction;
    if (widget.settings.mode.isReverse) d = -d;
    if (widget.settings.reverseTapToTurnPages) d = -d;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.settings.mode;
    final content = _gallery ? _buildGallery(mode) : _buildScroll(mode);

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        // 点击热区翻页 / 中间唤出菜单栏。
        onTapUp: (details) => _onTapUp(details, constraints),
        // 长按放大（按住时放大，松开还原）。
        onLongPressStart: widget.settings.longPressToZoom
            ? (_) => setState(() => _longPressZoom = true)
            : null,
        onLongPressEnd: widget.settings.longPressToZoom
            ? (_) => setState(() => _longPressZoom = false)
            : null,
        child: Listener(
          // 鼠标滚轮：翻页模式翻页，连续模式滚动。
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && _gallery) {
              unawaited(
                widget.reading.turnPage(
                  _forward(event.scrollDelta.dy > 0 ? 1 : -1),
                ),
              );
            }
          },
          child: content,
        ),
      ),
    );
  }

  Widget _buildGallery(ReaderViewMode mode) {
    final count = _itemCount;
    final initial = widget.reading.position.page.clamp(1, count - 1);
    WidgetsPostFrame.maybeJump(_pageController, initial);
    return PageView.builder(
      key: const Key('immersive-gallery'),
      controller: _pageController,
      scrollDirection: mode.isVertical ? Axis.vertical : Axis.horizontal,
      reverse: mode.isReverse,
      itemCount: count,
      onPageChanged: (index) {
        // 哨兵页：尝试切章；无相邻章则弹回第一张/最后一张。
        if (index == 0) {
          unawaited(_handleSentinel(-1));
        } else if (index == count - 1) {
          unawaited(_handleSentinel(1));
        } else {
          unawaited(widget.reading.goToPage(index));
        }
      },
      itemBuilder: (context, index) => _buildSlot(index),
    );
  }

  Future<void> _handleSentinel(int direction) async {
    final moved = direction > 0
        ? await widget.reading.nextChapter()
        : await widget.reading.previousChapter();
    if (moved) {
      WidgetsPostFrame.maybeJump(
        _pageController,
        direction > 0 ? 1 : _itemCount - 2,
      );
    } else {
      WidgetsPostFrame.maybeJump(
        _pageController,
        direction > 0 ? _itemCount - 2 : 1,
      );
    }
  }

  Widget _buildScroll(ReaderViewMode mode) {
    return ListView.builder(
      key: const Key('immersive-scroll'),
      controller: _scrollController,
      scrollDirection: mode.isVertical ? Axis.vertical : Axis.horizontal,
      reverse: mode.isReverse,
      itemCount: _itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return SizedBox(
            key: const Key('immersive-flow-top'),
            width: mode.isVertical ? double.infinity : 1,
            height: mode.isVertical ? 1 : double.infinity,
          );
        }
        if (index == _itemCount - 1) return _buildFlowEnd();
        return _buildSlot(index);
      },
    );
  }

  Widget _buildFlowEnd() {
    final controller = widget.waterfall;
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
                onPressed: () => unawaited(
                  controller.retryAfter(
                    current: widget.waterfall.flow.imageCount,
                  ),
                ),
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

  Widget _buildSlot(int index) {
    final request = _imageAt(index);
    if (request == null) {
      return SizedBox(
        key: Key('immersive-slot-empty-$index'),
        width: widget.settings.mode.isVertical ? double.infinity : 1,
        height: widget.settings.mode.isVertical ? 1 : double.infinity,
      );
    }
    return _ImmersiveImageSlot(
      key: Key('immersive-image-$index'),
      request: request,
      cache: widget.cache,
      index: index,
      zoom: _zoom,
      longPressZoom: _longPressZoom,
      doubleTapToZoom: widget.settings.doubleTapToZoom,
      limitWidth: widget.settings.limitImageWidth,
      isVertical: widget.settings.mode.isVertical,
      onZoom: (value) => setState(() => _zoom = value),
      onVisible: () {
        if (!_gallery) {
          unawaited(widget.reading.reportFlowIndex(index));
        }
      },
    );
  }
}

/// 单张图槽：加载 / 错误 / 成功三态 + 双击/长按/捏合缩放。
class _ImmersiveImageSlot extends StatefulWidget {
  const _ImmersiveImageSlot({
    super.key,
    required this.request,
    required this.cache,
    required this.index,
    required this.zoom,
    required this.longPressZoom,
    required this.doubleTapToZoom,
    required this.limitWidth,
    required this.isVertical,
    required this.onZoom,
    required this.onVisible,
  });

  final ImageRequest request;
  final ReaderImageCache cache;
  final int index;
  final double zoom;
  final bool longPressZoom;
  final bool doubleTapToZoom;
  final bool limitWidth;
  final bool isVertical;
  final ValueChanged<double> onZoom;
  final VoidCallback onVisible;

  @override
  State<_ImmersiveImageSlot> createState() => _ImmersiveImageSlotState();
}

class _ImmersiveImageSlotState extends State<_ImmersiveImageSlot> {
  Uint8List? _bytes;
  Object? _error;
  final TransformationController _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ImmersiveImageSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.cacheIdentity != widget.request.cacheIdentity) {
      _bytes = null;
      _error = null;
      _load();
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
      widget.onVisible();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return GestureDetector(
        key: Key('immersive-image-error-${widget.index}'),
        onTap: _load,
        child: SizedBox(
          height: widget.isVertical ? 320 : double.infinity,
          width: widget.isVertical ? double.infinity : 320,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, size: 48),
                const SizedBox(height: 8),
                Text('图片加载失败：$_error'),
                const SizedBox(height: 4),
                const Text('点此重试'),
              ],
            ),
          ),
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return SizedBox(
        key: const Key('immersive-image-loading'),
        height: widget.isVertical ? 320 : double.infinity,
        width: widget.isVertical ? double.infinity : 320,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final effectiveZoom = widget.longPressZoom ? 1.75 : widget.zoom;
    if (effectiveZoom != 1.0) {
      _transform.value = Matrix4.diagonal3Values(
        effectiveZoom,
        effectiveZoom,
        1.0,
      );
    }

    return InteractiveViewer(
      key: Key('immersive-image-${widget.index}'),
      transformationController: _transform,
      minScale: 1.0,
      maxScale: 4.0,
      constrained: false,
      onInteractionEnd: (_) =>
          widget.onZoom(_transform.value.getMaxScaleOnAxis().clamp(1.0, 4.0)),
      child: Image(
        image: MemoryImage(bytes),
        fit: BoxFit.contain,
        width: widget.isVertical ? (widget.limitWidth ? 720.0 : null) : null,
        height: widget.isVertical ? null : double.infinity,
        errorBuilder: (context, error, stack) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

/// PageController 初始跳转的小工具（在首帧后执行，避免在 build 中直接 jump）。
abstract final class WidgetsPostFrame {
  static void maybeJump(PageController controller, int page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.jumpToPage(page.clamp(0, 0x7fffffff));
      }
    });
  }
}
