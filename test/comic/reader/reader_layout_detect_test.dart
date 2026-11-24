// 自动版式分类：条漫 / 页漫 / 样本不足或混杂不判断。

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_layout_detect.dart';
import 'package:mimao/comic/reader/reader_view_mode.dart';

void main() {
  test('长条图占 80% 以上判为纵向连续', () {
    final sizes = <Size>[
      const Size(800, 2400),
      const Size(800, 3000),
      const Size(800, 2200),
      const Size(800, 2600),
      const Size(800, 800),
    ];
    expect(
      detectReaderModeFromSizes(sizes),
      ReaderViewMode.continuousTopToBottom,
    );
  });

  test('常规页占 80% 且没有长图判为右到左翻页', () {
    final sizes = <Size>[
      const Size(1000, 1400),
      const Size(1000, 1500),
      const Size(1000, 1300),
      const Size(1000, 1000),
      const Size(1000, 900),
    ];
    expect(detectReaderModeFromSizes(sizes), ReaderViewMode.galleryRightToLeft);
  });

  test('样本不足 4 张不判断', () {
    expect(
      detectReaderModeFromSizes(<Size>[
        const Size(800, 2400),
        const Size(800, 2400),
        const Size(800, 2400),
      ]),
      isNull,
    );
  });

  test('页漫样本里混入长图时不判为页漫', () {
    final sizes = <Size>[
      const Size(1000, 1400),
      const Size(1000, 1500),
      const Size(1000, 1300),
      const Size(1000, 1000),
      const Size(1000, 4000),
    ];
    expect(detectReaderModeFromSizes(sizes), isNull);
  });

  test('尺寸为 0 的图被跳过', () {
    final sizes = <Size>[
      const Size(0, 0),
      const Size(800, 2400),
      const Size(800, 2400),
      const Size(800, 2400),
      const Size(800, 2400),
    ];
    expect(
      detectReaderModeFromSizes(sizes),
      ReaderViewMode.continuousTopToBottom,
    );
  });
}
