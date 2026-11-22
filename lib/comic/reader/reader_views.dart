// 阅读器视图层：分页三模式（PageView + PhotoView.customChild）与
// 连续三模式（ScrollablePositionedList），外加统一的图片槽 / 章级三态占位。
//
// 只看 controller 的状态渲染，不写进度、不改设置；翻页/切章意图通过回调上抛，
// 由页面层统一处理（控制器才是唯一的阅读状态持有者）。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明
// （Flutter 3.50 弃用整个 material.dart，M1 起全仓沿用）。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'reader_cache.dart';
import 'reader_controller.dart';
import 'reader_models.dart';

/// 分页视图（pagedLtr / pagedRtl / pagedTtb）。
///
/// 首尾各加一张空哨兵页：滑入哨兵时由页面层决定切章或弹回。
/// 每页用 [PhotoView.customChild] 提供双击/捏合缩放、拖拽平移；缩放边界固定在
/// 1.0–4.0（contain 为基准倍率 1.0，双击在 contain 与 4×contain 间切换）。
class ReaderPagedView extends StatelessWidget {
  const ReaderPagedView({
    super.key,
    required this.controller,
    required this.pageController,
    required this.onSentinel,
  });

  final ReaderController controller;
  final PageController pageController;

  /// [delta] 为 -1（首哨兵/上一章）或 +1（尾哨兵/下一章）。
  final ValueChanged<int> onSentinel;

  @override
  Widget build(BuildContext context) {
    final mode = controller.settings.mode;
    final images = controller.images;
    final axis = mode.isVertical ? Axis.vertical : Axis.horizontal;
    final doubleTapZoom = controller.settings.doubleTapZoom;

    // PhotoViewGestureDetectorScope 让 photo_view 的拖动识别器在命中图片边缘时
    // 让位给外层 PageView，保证整页拖拽翻页不会被缩放/平移吞掉。
    return PhotoViewGestureDetectorScope(
      axis: axis,
      child: PageView.builder(
        key: const Key('reader-paged-view'),
        controller: pageController,
        scrollDirection: axis,
        reverse: mode.isRtl,
        itemCount: images.length + 2,
        onPageChanged: (viewIndex) {
          final imageIndex = viewIndex - 1;
          if (imageIndex < 0) {
            onSentinel(-1);
          } else if (imageIndex >= images.length) {
            onSentinel(1);
          } else if (imageIndex != controller.pageIndex) {
            // 拖拽翻页：以视图位置为准回报给控制器。
            controller.goToPage(imageIndex);
          }
        },
        itemBuilder: (context, viewIndex) {
          if (viewIndex == 0) {
            return const _SentinelPage(label: '松手切换上一章', isTrailing: false);
          }
          if (viewIndex == images.length + 1) {
            return const _SentinelPage(label: '松手切换下一章', isTrailing: true);
          }
          final index = viewIndex - 1;
          return _PhotoPage(
            image: images[index],
            cache: controller.imageCache,
            slotIndex: index,
            doubleTapZoom: doubleTapZoom,
          );
        },
      ),
    );
  }
}

/// 单页：PhotoView 包裹图片槽，负责双击/捏合缩放与拖拽平移。
/// 三区单击翻页由页面层统一用 Listener 处理，不走 PhotoView 的 onTapUp。
class _PhotoPage extends StatelessWidget {
  const _PhotoPage({
    required this.image,
    required this.cache,
    required this.slotIndex,
    required this.doubleTapZoom,
  });

  final ReaderImage image;
  final ReaderImageCache cache;
  final int slotIndex;
  final bool doubleTapZoom;

  @override
  Widget build(BuildContext context) {
    return PhotoView.customChild(
      // 索引变则重建缩放状态：翻走的页缩放置零，回到时以 contain 重新显示。
      key: ValueKey<int>(slotIndex),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * ReaderController.maxZoom,
      initialScale: PhotoViewComputedScale.contained,
      // 关闭双击缩放时给一个恒等 cycle，双击不改变倍率。
      scaleStateCycle: doubleTapZoom
          ? null
          : (actual) => PhotoViewScaleState.initial,
      child: ReaderImageSlot(image: image, cache: cache, slotIndex: slotIndex),
    );
  }
}

/// 哨兵页：空图片位 + 一行提示，滑到边界时提示"松手切章"。
class _SentinelPage extends StatelessWidget {
  const _SentinelPage({required this.label, required this.isTrailing});

  final String label;
  final bool isTrailing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isTrailing ? Icons.arrow_forward_ios : Icons.arrow_back_ios,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// 连续视图（continuousTtb / continuousLtr / continuousRtl）。
///
/// 用 ItemPositionsListener 回报当前可见图（取第一个可见项），页面层据此调用
/// controller.setVisibleIndex。v1 不做捏合缩放。
class ReaderContinuousView extends StatelessWidget {
  const ReaderContinuousView({
    super.key,
    required this.controller,
    required this.itemScrollController,
    required this.itemPositionsListener,
  });

  final ReaderController controller;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;

  @override
  Widget build(BuildContext context) {
    final mode = controller.settings.mode;
    final images = controller.images;
    final axis = mode.isVertical ? Axis.vertical : Axis.horizontal;

    return ScrollablePositionedList.builder(
      key: const Key('reader-continuous-list'),
      itemCount: images.length,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      initialScrollIndex: controller.pageIndex,
      scrollDirection: axis,
      reverse: mode.isRtl,
      itemBuilder: (context, index) => ReaderImageSlot(
        image: images[index],
        cache: controller.imageCache,
        slotIndex: index,
      ),
    );
  }
}

/// 单张图片槽：加载中转圈、失败占位可点重试、成功显示 [Image.memory]。
/// 字节统一经 [ReaderImageCache.load] 获取。
class ReaderImageSlot extends StatefulWidget {
  const ReaderImageSlot({
    super.key,
    required this.image,
    required this.cache,
    required this.slotIndex,
  });

  final ReaderImage image;
  final ReaderImageCache cache;
  final int slotIndex;

  @override
  State<ReaderImageSlot> createState() => _ReaderImageSlotState();
}

class _ReaderImageSlotState extends State<ReaderImageSlot> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReaderImageSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image || oldWidget.cache != widget.cache) {
      _bytes = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.cache.load(widget.image);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return GestureDetector(
        key: Key('reader-image-error-${widget.slotIndex}'),
        onTap: _load,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.broken_image_outlined, size: 48),
              const SizedBox(height: 8),
              Text('图片加载失败', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('点此重试', style: Theme.of(context).textTheme.labelMedium),
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
      child: Image(
        key: Key('reader-image-${widget.slotIndex}'),
        image: MemoryImage(bytes),
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

/// 章级三态占位：加载中 / 加载失败（可重试）/ 空章（可跳下一章）。
class ReaderChapterState extends StatelessWidget {
  const ReaderChapterState({
    super.key,
    required this.controller,
    required this.onRetry,
    required this.onNextChapter,
  });

  final ReaderController controller;
  final VoidCallback onRetry;
  final VoidCallback onNextChapter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (controller.chapterLoading) {
      return const Center(
        key: Key('reader-chapter-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载章节'),
          ],
        ),
      );
    }

    final error = controller.chapterError;
    if (error != null) {
      return Center(
        key: const Key('reader-chapter-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                '章节加载失败：$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('reader-chapter-retry'),
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    // 到这里必是空章（isChapterEmpty）；页面层只在三态命中时才构造本组件。
    return Center(
      key: const Key('reader-empty-chapter'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_stories_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('本章暂无图片', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '这一章没有可读的图片，通常是源尚未上传或章节已下架。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (controller.hasNextChapter)
              FilledButton(
                key: const Key('reader-empty-next'),
                onPressed: onNextChapter,
                child: const Text('跳到下一章'),
              ),
          ],
        ),
      ),
    );
  }
}
