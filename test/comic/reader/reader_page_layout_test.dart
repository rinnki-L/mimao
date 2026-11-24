// 翻页布局映射测试：移植 Venera-Next 的 page_layout_test.dart，锁定
// "显示页分区无空洞/重复、旧页首图在重排后仍可见" 这些容易在改写中丢掉的不变量。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_page_layout.dart';

void main() {
  test('显示页区间无空洞、无重复地覆盖整章图片', () {
    for (var count = 1; count <= 37; count++) {
      for (var perPage = 1; perPage <= 5; perPage++) {
        for (final singleFirst in <bool>[false, true]) {
          final layout = ReaderPageLayout(
            imagesPerPage: perPage,
            singleImageOnFirstPage: singleFirst,
          );
          final visited = <int>[];
          for (var page = 1; page <= layout.pageCount(count); page++) {
            final (start, end) = layout.imageRange(page, count);
            expect(start, visited.length);
            expect(end, greaterThan(start));
            expect(end - start, lessThanOrEqualTo(perPage));
            for (var index = start; index < end; index++) {
              expect(layout.pageForImage(index + 1), page);
              visited.add(index);
            }
          }
          expect(visited, List<int>.generate(count, (i) => i));
        }
      }
    }
  });

  test('首页单图与末页不足时以首图作为稳定锚点', () {
    const cover = ReaderPageLayout(
      imagesPerPage: 2,
      singleImageOnFirstPage: true,
    );
    const paired = ReaderPageLayout(
      imagesPerPage: 2,
      singleImageOnFirstPage: false,
    );
    expect(
      <int>[for (var i = 1; i <= 6; i++) cover.pageForImage(i)],
      <int>[1, 2, 2, 3, 3, 4],
    );
    expect(cover.imageRange(4, 6), (5, 6));
    expect(paired.imageRange(3, 5), (4, 5));
    expect(cover.historyImage(2, 6), 2);
    expect(paired.historyImage(2, 6), 3);
    expect(paired.historyImage(3, 6), 6);
    expect(paired.historyImage(4, 6), 6);
    expect(cover.historyImage(5, 6), 6);
  });

  test('每屏图数变化后旧页首图仍落在新页内', () {
    for (var count = 1; count <= 25; count++) {
      for (var oldSize = 1; oldSize <= 3; oldSize++) {
        for (var newSize = 1; newSize <= 3; newSize++) {
          for (final singleFirst in <bool>[false, true]) {
            final old = ReaderPageLayout(
              imagesPerPage: oldSize,
              singleImageOnFirstPage: singleFirst,
            );
            final next = ReaderPageLayout(
              imagesPerPage: newSize,
              singleImageOnFirstPage: singleFirst,
            );
            for (var page = 1; page <= old.pageCount(count); page++) {
              final anchor = old.firstImageOnPage(page) - 1;
              final remapped = old.remapPage(page, next, imageCount: count);
              final (start, end) = next.imageRange(remapped, count);
              expect(anchor, inInclusiveRange(start, end - 1));
            }
            expect(
              old.remapPage(old.pageCount(count) + 1, next, imageCount: count),
              next.pageCount(count) + 1,
            );
          }
        }
      }
    }
  });

  test('加载中与空章沿用既有页数语义', () {
    const single = ReaderPageLayout(
      imagesPerPage: 1,
      singleImageOnFirstPage: false,
    );
    const paired = ReaderPageLayout(
      imagesPerPage: 2,
      singleImageOnFirstPage: false,
    );
    const cover = ReaderPageLayout(
      imagesPerPage: 2,
      singleImageOnFirstPage: true,
    );
    expect(paired.pageCount(null), 1);
    expect(single.pageCount(0), 0);
    expect(paired.pageCount(0), 0);
    expect(cover.pageCount(0), 1);
    expect(cover.imageRange(1, 0), (0, 0));
    expect(paired.remapPage(0, single, imageCount: null), 1);
    expect(paired.remapPage(2, single, imageCount: null), 2);
    expect(paired.historyImage(1, 0), 0);
  });
}
