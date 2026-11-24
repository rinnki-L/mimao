// 宽图（跨页）拆成上下两半显示。
//
// 移植自 Venera-Next `comic_image.dart` 的 splitWideImage* 与
// `image_position.dart` 的 splitWideImageSlices：横向图（宽 > 高）在纵向
// 连续/瀑布模式里，默认把右半放上、左半放下（跨页漫画的阅读顺序），
// 也可反序。拆分只影响绘制，历史进度仍按"同一张源图"记录。

import 'package:flutter/widgets.dart';

/// 是否需要拆分：横向图（宽 > 高）。
bool shouldSplitWideImage(Size imageSize) => imageSize.width > imageSize.height;

/// 拆分后的显示尺寸：宽减半、高加倍（两半上下堆叠）。
Size splitWideImageDisplaySize(Size imageSize) {
  if (!shouldSplitWideImage(imageSize)) return imageSize;
  return Size(imageSize.width / 2, imageSize.height * 2);
}

/// 拆分后的一半：源图上的横向起点（0 或 0.5）与显示区里的纵向起点。
class ReaderImageSlice {
  const ReaderImageSlice({required this.sourceLeft, required this.displayTop});

  final double sourceLeft;
  final double displayTop;

  double get sourceWidth => 0.5;
  double get displayHeight => 0.5;
}

/// 阅读顺序（纵向堆叠）：默认右半在上、左半在下；[invert] 时反过来。
List<ReaderImageSlice> splitWideImageSlices({required bool invert}) => invert
    ? const <ReaderImageSlice>[
        ReaderImageSlice(sourceLeft: 0, displayTop: 0),
        ReaderImageSlice(sourceLeft: 0.5, displayTop: 0.5),
      ]
    : const <ReaderImageSlice>[
        ReaderImageSlice(sourceLeft: 0.5, displayTop: 0),
        ReaderImageSlice(sourceLeft: 0, displayTop: 0.5),
      ];

/// 两半在源图上的矩形（按 [imageSize] 缩放）。
List<Rect> splitWideImageSourceRects(Size imageSize, {required bool invert}) =>
    [
      for (final slice in splitWideImageSlices(invert: invert))
        Rect.fromLTWH(
          imageSize.width * slice.sourceLeft,
          0,
          imageSize.width * slice.sourceWidth,
          imageSize.height,
        ),
    ];

/// 把一张横向图渲染成上下两半（不拆原图字节）。
///
/// 用 [Align] + [FractionallySizedBox] 定位：每半取源图的一半宽度、完整高度，
/// 再按显示框缩放。父级只需给一个"宽:高 = 半宽:双高"的框。
class SplitWideImageView extends StatelessWidget {
  const SplitWideImageView({
    super.key,
    required this.image,
    required this.sourceSize,
    this.invert = false,
    this.fit = BoxFit.contain,
  });

  final ImageProvider image;
  final Size sourceSize;
  final bool invert;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (!shouldSplitWideImage(sourceSize)) {
      return Image(image: image, fit: fit, gaplessPlayback: true);
    }
    final slices = splitWideImageSlices(invert: invert);
    return Column(
      children: <Widget>[
        for (final slice in slices)
          Expanded(
            child: ClipRect(
              child: Align(
                alignment: Alignment(slice.sourceLeft == 0 ? -1.0 : 1.0, 0),
                widthFactor: 0.5,
                child: Image(image: image, fit: fit, gaplessPlayback: true),
              ),
            ),
          ),
      ],
    );
  }
}
