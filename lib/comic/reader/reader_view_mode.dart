// 阅读视图模式：对齐 Venera Next 的"方向 × 翻页方式"七模式，但用 Flutter
// 原生 PageView / CustomScrollView 实现，不引入第三方图片/滚动库。
//
// 命名直接沿用 Next，方便对照上游行为；分类 getter 让 UI/控制器只判断
// isGallery / isWaterfall / isVertical / isReverse，不散落字符串比较。

import 'reader_models.dart' show ReadingMode;

/// 七种阅读模式（Next 的完整集合）。
///
/// - gallery*：一屏一"页"（页可含 1~N 张图），左右/上下滑动翻页；
/// - continuous*：单章内连续滚动，不跨章；
/// - waterfallTopToBottom：跨章瀑布流，接近章尾自动接下一章、上滚回上一章。
enum ReaderViewMode {
  waterfallTopToBottom,
  galleryLeftToRight,
  galleryRightToLeft,
  galleryTopToBottom,
  continuousTopToBottom,
  continuousLeftToRight,
  continuousRightToLeft;

  bool get isGallery =>
      this == galleryLeftToRight ||
      this == galleryRightToLeft ||
      this == galleryTopToBottom;

  bool get isWaterfall => this == waterfallTopToBottom;

  /// 连续类：单章连续 + 跨章瀑布。统一走"滚动列表"渲染。
  bool get isContinuous =>
      this == continuousTopToBottom ||
      this == continuousLeftToRight ||
      this == continuousRightToLeft;

  /// 纵向（内容自上而下）：瀑布 / 纵向分页 / 纵向连续。
  bool get isVertical =>
      this == waterfallTopToBottom ||
      this == galleryTopToBottom ||
      this == continuousTopToBottom;

  /// 反向（日漫从右到左 / 右到左横向连续）。
  bool get isReverse =>
      this == galleryRightToLeft || this == continuousRightToLeft;

  /// 水平轴（非纵向）。
  bool get isHorizontal => !isVertical;

  /// 旧 [ReadingMode]（paged/continuous）到新模式的兼容映射。
  /// paged → 左到右分页；continuous → 跨章瀑布（体验升级）。
  static ReaderViewMode fromLegacy(ReadingMode mode) =>
      mode == ReadingMode.paged ? galleryLeftToRight : waterfallTopToBottom;

  String get label => switch (this) {
    waterfallTopToBottom => '瀑布流（跨章）',
    galleryLeftToRight => '翻页 · 左到右',
    galleryRightToLeft => '翻页 · 右到左（日漫）',
    galleryTopToBottom => '翻页 · 上到下',
    continuousTopToBottom => '连续 · 上到下',
    continuousLeftToRight => '连续 · 左到右',
    continuousRightToLeft => '连续 · 右到左',
  };
}
