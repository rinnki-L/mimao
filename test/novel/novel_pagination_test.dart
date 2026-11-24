// 正文分页：切片覆盖完整、跨页断在行首、页数随高度变化。

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bodyStyle = TextStyle(fontSize: 16, height: 1.5, fontFamily: 'Courier');
  const titleStyle = TextStyle(
    fontSize: 22,
    height: 1.4,
    fontFamily: 'Courier',
  );

  NovelPaginator build({
    required List<String> paragraphs,
    required double height,
    String title = '第一章',
  }) => NovelPaginator(
    title: title,
    paragraphs: paragraphs,
    bodyStyle: bodyStyle,
    titleStyle: titleStyle,
    maxWidth: 320,
    maxHeight: height,
    paragraphSpacing: 12,
    titleSpacing: 18,
    indent: '　　',
    textScaler: TextScaler.noScaling,
  );

  test('短章只有一页，切片覆盖标题与全部正文', () {
    final paragraphs = <String>['短段落一', '短段落二'];
    final pages = build(paragraphs: paragraphs, height: 600).paginate();
    expect(pages, hasLength(1));
    final slices = pages.single.slices;
    expect(slices.any((s) => s.isTitle), isTrue);
    for (var i = 0; i < paragraphs.length; i++) {
      final text = '　　${paragraphs[i]}';
      final covered = slices
          .where((s) => s.paragraph == i)
          .fold<int>(0, (sum, s) => sum + s.length);
      expect(covered, text.length);
    }
  });

  test('长章跨页，且每个段落的切片首尾相接、无丢字重字', () {
    final paragraph = List<String>.filled(200, '正').join();
    final paragraphs = <String>[paragraph, paragraph, paragraph];
    final pages = build(paragraphs: paragraphs, height: 240).paginate();
    expect(pages.length, greaterThan(1));
    expect(pages.every((page) => page.slices.isNotEmpty), isTrue);

    for (var i = 0; i < paragraphs.length; i++) {
      final text = '　　${paragraphs[i]}';
      final slices = <NovelTextSlice>[
        for (final page in pages)
          for (final slice in page.slices)
            if (slice.paragraph == i) slice,
      ];
      expect(slices.first.start, 0);
      expect(slices.last.end, text.length);
      for (var j = 1; j < slices.length; j++) {
        expect(slices[j].start, slices[j - 1].end);
      }
    }
  });

  test('页高越小页数越多', () {
    final paragraphs = <String>[List<String>.filled(300, '文').join()];
    final tall = build(paragraphs: paragraphs, height: 600).paginate();
    final short = build(paragraphs: paragraphs, height: 240).paginate();
    expect(short.length, greaterThan(tall.length));
  });

  test('空正文退化成单页，不抛异常', () {
    final pages = build(
      paragraphs: const <String>[],
      height: 300,
      title: '',
    ).paginate();
    expect(pages, hasLength(1));
    expect(pages.single.isEmpty, isTrue);
  });

  test('尺寸无效时返回单页兜底', () {
    final pages = NovelPaginator(
      title: '标题',
      paragraphs: const <String>['正文'],
      bodyStyle: bodyStyle,
      titleStyle: titleStyle,
      maxWidth: 0,
      maxHeight: 0,
    ).paginate();
    expect(pages, hasLength(1));
    expect(pages.single.slices, isNotEmpty);
  });

  test('字距/缩进/两端对齐/避头尾一起启用，切片仍首尾相接', () {
    const spaced = TextStyle(
      fontSize: 16,
      height: 1.6,
      letterSpacing: 0.6,
      fontFamily: 'Courier',
    );
    final paragraph = List<String>.filled(240, '文').join();
    final paragraphs = <String>['$paragraph。', paragraph, paragraph];
    final pages = NovelPaginator(
      title: '第一章 风起',
      paragraphs: paragraphs,
      bodyStyle: spaced,
      titleStyle: titleStyle,
      maxWidth: 320,
      maxHeight: 260,
      paragraphSpacing: 10,
      titleSpacing: 14,
      titleTopSpacing: 6,
      indent: '　　',
      bodyTextAlign: TextAlign.justify,
      titleTextAlign: TextAlign.center,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      kinsoku: true,
      columns: 1,
    ).paginate();
    expect(pages.length, greaterThan(1));
    _expectContinuous(pages, paragraphs, indent: '　　');
  });

  test('双栏：标题页独占整宽，正文切片仍无丢字', () {
    final paragraph = List<String>.filled(200, '正').join();
    final paragraphs = <String>[paragraph, paragraph, paragraph];
    final pages = NovelPaginator(
      title: '第一章',
      paragraphs: paragraphs,
      bodyStyle: bodyStyle,
      titleStyle: titleStyle,
      maxWidth: 640,
      maxHeight: 280,
      paragraphSpacing: 12,
      titleSpacing: 18,
      indent: '　　',
      columns: 2,
      columnGap: 32,
    ).paginate();
    expect(pages.first.hasTitle, isTrue);
    expect(pages.first.slices.every((slice) => slice.isTitle), isTrue);
    expect(pages.length, greaterThan(2));
    _expectContinuous(pages, paragraphs, indent: '　　');
  });
}

void _expectContinuous(
  List<NovelTextPage> pages,
  List<String> paragraphs, {
  required String indent,
}) {
  for (var i = 0; i < paragraphs.length; i++) {
    final text = '$indent${paragraphs[i]}';
    final slices = <NovelTextSlice>[
      for (final page in pages)
        for (final slice in page.slices)
          if (slice.paragraph == i) slice,
    ];
    expect(slices, isNotEmpty, reason: '段落 $i 没有切片');
    expect(slices.first.start, 0);
    expect(slices.last.end, text.length);
    for (var j = 1; j < slices.length; j++) {
      expect(slices[j].start, slices[j - 1].end, reason: '段落 $i 第 $j 段切片不相接');
    }
  }
}
