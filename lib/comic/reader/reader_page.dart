// 阅读器 Widget：样式从简，核心是翻页/滚动手势 + 加载态/失败占位 + 缩放。
//
// 每张图都经 [ReaderImageCache.load] 取字节（缓存命中/落盘逻辑不被绕过），拿到字节后
// 用 Image.memory 显示。图片的"取字节"由 ReaderImageCache 的 loader 决定，测试注入
// 返回固定字节的假 loader 即可，不碰真实网络与 A′ 源引擎。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明
// （Flutter 3.50 弃用整个 material.dart，M1 起全仓沿用）。

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'reader_cache.dart';
import 'reader_controller.dart';
import 'reader_models.dart';
import 'reader_progress.dart';

/// 捏合缩放映射：以开始时的倍率为基准，乘以手势 scale 后钳制到合法区间。
/// 纯函数，便于单测（widget 测试难以稳定模拟双指手势）。
double pinchZoom(double baseZoom, double scale) => (baseZoom * scale)
    .clamp(ReaderController.minZoom, ReaderController.maxZoom)
    .toDouble();

/// 最小可运行阅读页。自己创建并持有 [ReaderController]。
class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.title,
    required this.chapters,
    required this.imageCache,
    this.recorder,
    this.initialChapter = 0,
    this.initialPage = 0,
    this.initialMode = ReadingMode.paged,
    this.controller,
  });

  final String title;
  final List<ComicChapter> chapters;
  final ReaderImageCache imageCache;
  final ProgressRecorder? recorder;
  final int initialChapter;
  final int initialPage;
  final ReadingMode initialMode;

  /// 可选：外部注入控制器（widget 测试用），不传则内部自建。
  final ReaderController? controller;

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  late final ReaderController _controller;
  bool _ownsController = false;
  final PageController _pageController = PageController();

  /// 一次捏合开始时的倍率；onScaleUpdate 以此为基准叠加，避免抖动。
  double _pinchBaseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = ReaderController(
        chapters: widget.chapters,
        recorder: widget.recorder,
        imageCache: widget.imageCache,
        initialChapter: widget.initialChapter,
        initialPage: widget.initialPage,
        mode: widget.initialMode,
      );
      _ownsController = true;
    }
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
    _pageController.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _turn(int delta) async {
    final moved = delta > 0
        ? await _controller.nextPage()
        : await _controller.previousPage();
    if (moved && _pageController.hasClients) {
      await _pageController.animateToPage(
        _controller.pageIndex,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _switchChapter(int delta) async {
    final before = _controller.chapterIndex;
    if (delta > 0) {
      await _controller.nextChapter();
    } else {
      await _controller.previousChapter();
    }
    if (_controller.chapterIndex != before && _pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              key: const Key('reader-toggle-mode'),
              icon: Icon(
                _controller.mode == ReadingMode.paged
                    ? Icons.view_agenda_outlined
                    : Icons.auto_stories_outlined,
              ),
              tooltip: '切换阅读模式',
              onPressed: () => _controller.toggleMode(),
            ),
            IconButton(
              key: const Key('reader-zoom-in'),
              icon: const Icon(Icons.zoom_in),
              tooltip: '放大',
              onPressed: () => _controller.zoomIn(),
            ),
            IconButton(
              key: const Key('reader-zoom-out'),
              icon: const Icon(Icons.zoom_out),
              tooltip: '缩小',
              onPressed: () => _controller.zoomOut(),
            ),
          ],
        ),
        body: Column(
          children: [
            _InfoBar(controller: _controller),
            Expanded(
              child: GestureDetector(
                // 双指捏合缩放（与翻页/滚动手势并存；单指仍交给子 PageView/ListView）。
                onScaleStart: (_) => _pinchBaseZoom = _controller.zoom,
                onScaleUpdate: (details) => _controller.setZoom(
                  pinchZoom(_pinchBaseZoom, details.scale),
                ),
                child: _controller.mode == ReadingMode.paged
                    ? _PagedView(
                        controller: _controller,
                        pageController: _pageController,
                        onTurn: _turn,
                      )
                    : _ContinuousView(controller: _controller),
              ),
            ),
            _NavBar(
              controller: _controller,
              onPrevChapter: () => _switchChapter(-1),
              onNextChapter: () => _switchChapter(1),
              onPrevPage: () => _turn(-1),
              onNextPage: () => _turn(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        '${controller.chapterTitle} · ${controller.pageNumber}/${controller.pageCount}'
        ' · ${controller.mode.name} · ${controller.zoom.toStringAsFixed(2)}x',
        key: const Key('reader-info'),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.controller,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onPrevPage,
    required this.onNextPage,
  });

  final ReaderController controller;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton(
            key: const Key('reader-prev-chapter'),
            onPressed: controller.hasPreviousChapter ? onPrevChapter : null,
            child: const Text('上一章'),
          ),
          TextButton(
            key: const Key('reader-prev-page'),
            onPressed: controller.hasPreviousPage ? onPrevPage : null,
            child: const Text('上一页'),
          ),
          TextButton(
            key: const Key('reader-next-page'),
            onPressed: controller.hasNextPage ? onNextPage : null,
            child: const Text('下一页'),
          ),
          TextButton(
            key: const Key('reader-next-chapter'),
            onPressed: controller.hasNextChapter ? onNextChapter : null,
            child: const Text('下一章'),
          ),
        ],
      ),
    );
  }
}

/// 左右翻页模式：PageView + 水平拖拽手势天然支持左右滑动翻页。
class _PagedView extends StatelessWidget {
  const _PagedView({
    required this.controller,
    required this.pageController,
    required this.onTurn,
  });

  final ReaderController controller;
  final PageController pageController;
  final Future<void> Function(int delta) onTurn;

  @override
  Widget build(BuildContext context) {
    final urls = controller.imageUrls;
    if (urls.isEmpty) return const _EmptyChapter();
    return PageView.builder(
      key: const Key('reader-paged-view'),
      controller: pageController,
      itemCount: urls.length,
      onPageChanged: (index) {
        if (index != controller.pageIndex) {
          onTurn(index > controller.pageIndex ? 1 : -1);
        }
      },
      itemBuilder: (context, index) => GestureDetector(
        // 点屏幕左右半边也能翻页（与左右滑动互补）。
        onTapUp: (details) {
          final width = MediaQuery.sizeOf(context).width;
          onTurn(details.globalPosition.dx > width / 2 ? 1 : -1);
        },
        child: _ImageSlot(
          url: urls[index],
          cache: controller.imageCache,
          zoom: controller.zoom,
          slotIndex: index,
        ),
      ),
    );
  }
}

/// 上下连续滚动模式：整章图片纵列排布。
class _ContinuousView extends StatelessWidget {
  const _ContinuousView({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final urls = controller.imageUrls;
    if (urls.isEmpty) return const _EmptyChapter();
    return ListView.builder(
      key: const Key('reader-continuous-list'),
      itemCount: urls.length,
      itemBuilder: (context, index) => _ImageSlot(
        url: urls[index],
        cache: controller.imageCache,
        zoom: controller.zoom,
        slotIndex: index,
      ),
    );
  }
}

class _EmptyChapter extends StatelessWidget {
  const _EmptyChapter();

  @override
  Widget build(BuildContext context) =>
      const Center(key: Key('reader-empty-chapter'), child: Text('本章暂无图片'));
}

/// 单张图片槽：加载中显示转圈，失败显示占位（可点重试），成功显示图片。
/// 字节统一经 [ReaderImageCache.load] 获取。
class _ImageSlot extends StatefulWidget {
  const _ImageSlot({
    required this.url,
    required this.cache,
    required this.zoom,
    required this.slotIndex,
  });

  final String url;
  final ReaderImageCache cache;
  final double zoom;
  final int slotIndex;

  @override
  State<_ImageSlot> createState() => _ImageSlotState();
}

class _ImageSlotState extends State<_ImageSlot> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ImageSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.cache.load(widget.url);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return GestureDetector(
        key: Key('reader-image-error-${widget.slotIndex}'),
        onTap: _load,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 48),
              SizedBox(height: 8),
              Text('图片加载失败'),
              SizedBox(height: 4),
              Text('点此重试'),
            ],
          ),
        ),
      );
    }

    final bytes = _bytes;
    if (bytes == null) {
      return const Center(
        key: Key('reader-image-loading'),
        child: CircularProgressIndicator(),
      );
    }

    return Center(
      child: FittedBox(
        child: Image(
          key: Key('reader-image-${widget.slotIndex}'),
          image: MemoryImage(bytes),
          fit: BoxFit.contain,
          width: 320.0 * widget.zoom,
          height: 480.0 * widget.zoom,
        ),
      ),
    );
  }
}
