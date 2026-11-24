// 白边裁剪：纯扫描规则 + 有界调度器。
// 扫描规则逐条对应 Venera-Next `horizontalWhiteBorderInsets` 的边界条件。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_white_border_crop.dart';

/// 生成 width×height 的 RGBA：默认白，[paint] 返回非 null 时写该像素。
Uint8List _rgba(
  int width,
  int height, {
  void Function(int x, int y, int offset, Uint8List out)? paint,
}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      bytes[offset] = 255;
      bytes[offset + 1] = 255;
      bytes[offset + 2] = 255;
      bytes[offset + 3] = 255;
      paint?.call(x, y, offset, bytes);
    }
  }
  return bytes;
}

void main() {
  group('horizontalWhiteBorderInsets', () {
    test('左右各留 20px 白边：两侧都裁掉', () {
      final bytes = _rgba(
        200,
        100,
        paint: (x, y, offset, out) {
          if (x >= 20 && x < 180) {
            out[offset] = 10;
            out[offset + 1] = 10;
            out[offset + 2] = 10;
          }
        },
      );
      final (left, right) = horizontalWhiteBorderInsets(bytes, 200, 100);
      expect(left, inInclusiveRange(15, 20));
      expect(right, inInclusiveRange(15, 20));
    });

    test('整页全白不裁剪（避免把白页裁成空）', () {
      final bytes = _rgba(200, 100);
      expect(horizontalWhiteBorderInsets(bytes, 200, 100), (0, 0));
    });

    test('画面顶到边缘时不裁剪', () {
      final bytes = _rgba(
        200,
        100,
        paint: (x, y, offset, out) {
          out[offset] = 20;
          out[offset + 1] = 20;
          out[offset + 2] = 20;
        },
      );
      expect(horizontalWhiteBorderInsets(bytes, 200, 100), (0, 0));
    });

    test('单侧留白超过 1/4 宽度时该侧不裁', () {
      // 左 80px 白（宽度 200 的 40% > 25%），右侧贴边。
      final bytes = _rgba(
        200,
        100,
        paint: (x, y, offset, out) {
          if (x >= 80) {
            out[offset] = 15;
            out[offset + 1] = 15;
            out[offset + 2] = 15;
          }
        },
      );
      final (left, right) = horizontalWhiteBorderInsets(bytes, 200, 100);
      expect(left, 0);
      expect(right, 0);
    });

    test('单行有深色像素就会停在该列（不整列全白不裁）', () {
      final bytes = _rgba(
        200,
        100,
        paint: (x, y, offset, out) {
          if (x >= 30) {
            out[offset] = 5;
            out[offset + 1] = 5;
            out[offset + 2] = 5;
          }
          // 第 50 行最左边写一个深点，阻止左侧继续裁到 30。
          if (x == 12 && y == 50) {
            out[offset] = 0;
            out[offset + 1] = 0;
            out[offset + 2] = 0;
          }
        },
      );
      final (left, _) = horizontalWhiteBorderInsets(bytes, 200, 100);
      expect(left, lessThanOrEqualTo(12));
    });

    test('透明像素按白色处理', () {
      final bytes = _rgba(
        200,
        100,
        paint: (x, y, offset, out) {
          if (x < 20) {
            out[offset + 3] = 0;
          } else {
            out[offset] = 0;
            out[offset + 1] = 0;
            out[offset + 2] = 0;
          }
        },
      );
      final (left, _) = horizontalWhiteBorderInsets(bytes, 200, 100);
      expect(left, inInclusiveRange(15, 20));
    });

    test('过窄或字节数不匹配直接返回 0', () {
      expect(horizontalWhiteBorderInsets(Uint8List(16 * 4), 16, 1), (0, 0));
      expect(horizontalWhiteBorderInsets(Uint8List(10), 100, 100), (0, 0));
    });
  });

  group('WhiteBorderInsets', () {
    test('按比例换算可见区域', () {
      const insets = WhiteBorderInsets(left: 0.1, right: 0.2);
      final rect = insets.visibleRect(1000, 800);
      expect(rect.left, 100);
      expect(rect.right, 800);
      expect(rect.top, 0);
      expect(rect.bottom, 800);
    });

    test('isNone 判断', () {
      expect(WhiteBorderInsets.none.isNone, isTrue);
      expect(const WhiteBorderInsets(left: 0.01, right: 0).isNone, isFalse);
    });
  });
}
