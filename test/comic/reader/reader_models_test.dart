// 阅读器纯模型/手势辅助的单测（无副作用、无 IO）。
//
// closure-02：payload/文案统一收敛到 C′（comicProgressText），B′ 的
// readerProgressPayload / readerProgressText 已删除。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_page.dart';

void main() {
  test('pinchZoom：以基准倍率叠加手势 scale 并钳制到 [1,4]', () {
    expect(pinchZoom(1.0, 1.5), 1.5);
    expect(pinchZoom(2.0, 0.5), 1.0);
    expect(pinchZoom(2.0, 4.0), 4.0);
  });

  test('ComicChapter.pageCount 反映图片数；chapterId 默认空串', () {
    const chapter = ComicChapter(title: 'x', imageUrls: <String>['a', 'b']);
    expect(chapter.pageCount, 2);
    expect(chapter.chapterId, '');

    const stable = ComicChapter(
      title: 'y',
      chapterId: 'ep-7',
      imageUrls: <String>['c'],
    );
    expect(stable.chapterId, 'ep-7');
    expect(stable.pageCount, 1);
  });

  test('ReadingMode 两种模式枚举齐全', () {
    expect(ReadingMode.values, <ReadingMode>[
      ReadingMode.paged,
      ReadingMode.continuous,
    ]);
  });
}
