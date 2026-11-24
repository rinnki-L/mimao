// 字符偏移定位器：切片 ↔ locator ↔ 页号，含段首缩进换算。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';

NovelTextSlice _slice(
  int paragraph,
  int start,
  int end, {
  bool title = false,
}) => NovelTextSlice(
  paragraph: paragraph,
  start: start,
  end: end,
  isTitle: title,
);

void main() {
  test('段内偏移不含缩进：切片起点 2 对应段落第 0 字', () {
    final locator = locatorForSlice(
      _slice(0, novelParagraphIndentLength, 30),
      chapterIndex: 3,
      sourceKey: 'src',
    );
    expect(locator.chapterIndex, 3);
    expect(locator.paragraph, 0);
    expect(locator.charOffset, 0);
    expect(locator.sourceKey, 'src');

    final continued = locatorForSlice(_slice(0, 10, 20), chapterIndex: 3);
    expect(continued.charOffset, 8);
  });

  test('标题切片定位到标题，不参与正文偏移', () {
    final locator = locatorForSlice(
      _slice(-1, 0, 6, title: true),
      chapterIndex: 0,
    );
    expect(locator.isTitle, isTrue);
  });

  test('locator 能反向落回所在页', () {
    final pages = <NovelTextPage>[
      NovelTextPage(<NovelTextSlice>[
        _slice(-1, 0, 4, title: true),
        _slice(0, 0, 40),
      ]),
      NovelTextPage(<NovelTextSlice>[
        _slice(0, 40, 80),
        _slice(1, 0, 60),
        _slice(2, 0, 50),
      ]),
      NovelTextPage(<NovelTextSlice>[_slice(3, 0, 50)]),
    ];

    expect(
      pageIndexForLocator(
        pages,
        const NovelLocator(chapterIndex: 0, paragraph: 0, charOffset: 5),
      ),
      0,
    );
    // 段落 0 的后半段在第 2 页，偏移 40 正好是第 2 页切片起点。
    expect(
      pageIndexForLocator(
        pages,
        const NovelLocator(chapterIndex: 0, paragraph: 0, charOffset: 40),
      ),
      1,
    );
    expect(
      pageIndexForLocator(
        pages,
        const NovelLocator(chapterIndex: 0, paragraph: 2, charOffset: 10),
      ),
      1,
    );
    expect(
      pageIndexForLocator(
        pages,
        const NovelLocator(chapterIndex: 0, paragraph: 3, charOffset: 0),
      ),
      2,
    );
  });

  test('locator 超出正文时落到末页，空页表返回 -1', () {
    final pages = <NovelTextPage>[
      NovelTextPage(<NovelTextSlice>[_slice(0, 0, 20)]),
    ];
    expect(
      pageIndexForLocator(
        pages,
        const NovelLocator(chapterIndex: 0, paragraph: 99),
      ),
      0,
    );
    expect(
      pageIndexForLocator(
        const <NovelTextPage>[],
        const NovelLocator(chapterIndex: 0),
      ),
      -1,
    );
  });

  test('页首段能生成 locator', () {
    final pages = <NovelTextPage>[
      NovelTextPage(<NovelTextSlice>[_slice(7, 2, 40)]),
    ];
    final locator = locatorForPage(pages, 0, chapterIndex: 2);
    expect(locator.chapterIndex, 2);
    expect(locator.paragraph, 7);
    expect(locator.charOffset, 0);
  });

  test('JSON 往返保留全部字段', () {
    const locator = NovelLocator(
      chapterIndex: 9,
      paragraph: 4,
      charOffset: 12,
      sourceKey: 's1',
    );
    final restored = NovelLocator.fromJson(locator.toJson());
    expect(restored, locator);
  });
}
