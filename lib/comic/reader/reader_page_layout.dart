// 一张显示页与若干张源图之间的映射。
//
// 移植自 Venera-Next `lib/features/reader/page_layout.dart`（GPL-3.0 上游，
// 本仓按上游行为重写，不复制其应用层代码）。翻页模式支持一屏 1~5 张图，
// 并可让第一页只放一张（章节封面感）；历史进度仍以"源图序号"落库，切换
// 阅读模式或每屏图数时不丢位置。

import 'dart:math' as math;

/// 一基的显示页与源图序号之间的布局。
class ReaderPageLayout {
  const ReaderPageLayout({
    required this.imagesPerPage,
    required this.singleImageOnFirstPage,
  }) : assert(imagesPerPage > 0);

  final int imagesPerPage;
  final bool singleImageOnFirstPage;

  /// 图片数未知（null）时保留一张占位页；0 张图按上游语义处理。
  int pageCount(int? imageCount) {
    if (imageCount == null) return 1;
    return singleImageOnFirstPage
        ? 1 + ((imageCount - 1) / imagesPerPage).ceil()
        : (imageCount / imagesPerPage).ceil();
  }

  int pageForImage(int imageNumber) {
    if (imagesPerPage == 1) return imageNumber;
    return singleImageOnFirstPage
        ? ((imageNumber - 1) / imagesPerPage).ceil() + 1
        : (imageNumber / imagesPerPage).ceil();
  }

  int firstImageOnPage(int page) {
    if (singleImageOnFirstPage && page != 1) {
      return (page - 2) * imagesPerPage + 2;
    }
    return (page - 1) * imagesPerPage + 1;
  }

  /// 该显示页覆盖的源图区间（0 基、右开），可直接用于 `sublist`。
  (int start, int end) imageRange(int page, int imageCount) {
    if (imageCount == 0) return (0, 0);
    if (singleImageOnFirstPage && page == 1) return (0, 1);
    final start = firstImageOnPage(page) - 1;
    return (start, math.min(start + imagesPerPage, imageCount));
  }

  /// 读完最后一个显示页（或它的评论页）视为读完最后一张图。
  ///
  /// 本仓历史表按源图序号存页码，所以翻页模式落库时用它折算。
  int historyImage(int page, int imageCount) =>
      page >= pageCount(imageCount) ? imageCount : firstImageOnPage(page);

  /// 每屏图数变化后，把旧显示页映射到"仍包含旧页首图"的新显示页。
  ///
  /// 评论页之类的尾页（超过 [pageCount]）保持尾页语义。
  int remapPage(int page, ReaderPageLayout target, {required int? imageCount}) {
    final targetCount = target.pageCount(imageCount);
    if (page > pageCount(imageCount)) return targetCount + 1;
    return target
        .pageForImage(firstImageOnPage(page))
        .clamp(1, math.max(1, targetCount));
  }
}
