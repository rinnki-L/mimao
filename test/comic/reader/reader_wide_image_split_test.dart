// 宽图拆分：判定、显示尺寸、两半顺序与源图矩形。

import 'package:flutter/widgets.dart' show Size, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_wide_image_split.dart';

void main() {
  test('只有横向图需要拆分', () {
    expect(shouldSplitWideImage(const Size(1600, 1200)), isTrue);
    expect(shouldSplitWideImage(const Size(1200, 1600)), isFalse);
    expect(shouldSplitWideImage(const Size(1000, 1000)), isFalse);
  });

  test('拆分后宽减半、高加倍；竖图原样', () {
    expect(
      splitWideImageDisplaySize(const Size(1600, 1200)),
      const Size(800, 2400),
    );
    expect(
      splitWideImageDisplaySize(const Size(800, 1200)),
      const Size(800, 1200),
    );
  });

  test('默认右半在上，invert 时左半在上', () {
    final normal = splitWideImageSlices(invert: false);
    expect(normal.first.sourceLeft, 0.5);
    expect(normal.first.displayTop, 0);
    expect(normal.last.sourceLeft, 0);
    expect(normal.last.displayTop, 0.5);

    final inverted = splitWideImageSlices(invert: true);
    expect(inverted.first.sourceLeft, 0);
    expect(inverted.last.sourceLeft, 0.5);
  });

  test('源图矩形按图片尺寸缩放且左右各半', () {
    final rects = splitWideImageSourceRects(
      const Size(1600, 1200),
      invert: false,
    );
    expect(rects, hasLength(2));
    expect(rects[0], const Rect.fromLTWH(800, 0, 800, 1200));
    expect(rects[1], const Rect.fromLTWH(0, 0, 800, 1200));
  });
}
