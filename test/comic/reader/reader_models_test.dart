// 阅读器纯模型/文案辅助的单测（无副作用、无 IO）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_page.dart';

void main() {
  test('pinchZoom：以基准倍率叠加手势 scale 并钳制到 [1,4]', () {
    expect(pinchZoom(1.0, 1.5), 1.5);
    expect(pinchZoom(2.0, 0.5), 1.0);
    expect(pinchZoom(2.0, 4.0), 4.0);
  });

  test('readerProgressPayload：chapter/page 1 基展示号原样写入 JSON', () {
    final raw = readerProgressPayload(chapter: 12, page: 3);
    expect(raw, '{"chapter":12,"page":3}');
    expect(jsonDecode(raw), <String, dynamic>{'chapter': 12, 'page': 3});
  });

  test('readerProgressText：三种分支（未读/有总页/无总页）', () {
    expect(readerProgressText(chapter: 0, page: 1, pageCount: 10), '尚未阅读');
    expect(
      readerProgressText(chapter: 2, page: 3, pageCount: 10),
      '第 2 章 · 第 3/10 页',
    );
    expect(readerProgressText(chapter: 2, page: 3, pageCount: 0), '读到第 2 章');
  });

  test('ComicChapter.pageCount 反映图片数', () {
    const chapter = ComicChapter(title: 'x', imageUrls: <String>['a', 'b']);
    expect(chapter.pageCount, 2);
  });

  test('ReadingMode 两种模式枚举齐全', () {
    expect(ReadingMode.values, <ReadingMode>[
      ReadingMode.paged,
      ReadingMode.continuous,
    ]);
  });
}
