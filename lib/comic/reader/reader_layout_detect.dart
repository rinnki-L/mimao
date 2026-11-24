// 按图片宽高比判断条漫 / 页漫（对照 Venera-Next ComicLayoutProbe 的规则）。
//
// 上游采样当前章第 2~7 张（跳过封面），至少 4 张有效图后分类：
// - ≥80% 的 高/宽 ≥ 2.5 → 条漫（纵向连续）；
// - ≥80% 的 高/宽 落在 0.5~2.0 且没有长图 → 页漫（右到左翻页）；
// - 其它 → 不判断。
//
// 这里只保留纯分类函数；采样、超时与"只影响本次打开"由阅读页负责。

import 'package:flutter/widgets.dart' show Size;

import 'reader_view_mode.dart';

/// 从已测出的图片尺寸中判断推荐模式；样本不足或版式混杂时返回 null。
ReaderViewMode? detectReaderModeFromSizes(Iterable<Size> sizes) {
  final ratios = <double>[
    for (final size in sizes)
      if (size.width > 0 && size.height > 0) size.height / size.width,
  ];
  if (ratios.length < 4) return null;

  final strips = ratios.where((ratio) => ratio >= 2.5).length;
  final pages = ratios.where((ratio) => ratio >= 0.5 && ratio <= 2.0).length;
  final total = ratios.length;
  if (strips / total >= 0.8) return ReaderViewMode.continuousTopToBottom;
  if (pages / total >= 0.8 && strips == 0) {
    return ReaderViewMode.galleryRightToLeft;
  }
  return null;
}
