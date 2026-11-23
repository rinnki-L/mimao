// 正文分页：把一章的标题 + 段落按给定字号/行高/宽度/高度切成页。
//
// 纯函数式测量（TextPainter），不依赖 Widget 树，可在单测里直接喂
// 固定 TextStyle 验证页数。页面渲染时按 [NovelTextSlice] 取子串，
// 因此「跨页段落」既能精确切在行边界，又能保持换行位置不变。

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// 一页里的一段文字切片：章节段落下标（标题为 -1）+ 子串范围。
class NovelTextSlice {
  const NovelTextSlice({
    required this.paragraph,
    required this.start,
    required this.end,
    this.isTitle = false,
  });

  final int paragraph;
  final int start;
  final int end;
  final bool isTitle;

  int get length => math.max(0, end - start);

  NovelTextSlice extendedTo(int nextEnd) => NovelTextSlice(
    paragraph: paragraph,
    start: start,
    end: nextEnd,
    isTitle: isTitle,
  );
}

/// 一页正文。
class NovelTextPage {
  const NovelTextPage(this.slices);

  final List<NovelTextSlice> slices;

  int get textLength => slices.fold<int>(0, (sum, slice) => sum + slice.length);

  bool get isEmpty => slices.isEmpty;
}

/// 分页器：构造一次、调 [paginate] 一次。
class NovelPaginator {
  NovelPaginator({
    required this.title,
    required this.paragraphs,
    required this.bodyStyle,
    required this.titleStyle,
    required this.maxWidth,
    required this.maxHeight,
    this.paragraphSpacing = 12,
    this.titleSpacing = 18,
    this.indent = '　　',
    this.textScaler = TextScaler.noScaling,
  });

  final String title;
  final List<String> paragraphs;
  final TextStyle bodyStyle;
  final TextStyle titleStyle;
  final double maxWidth;
  final double maxHeight;
  final double paragraphSpacing;
  final double titleSpacing;

  /// 段首缩进（两个全角空格，与中文排版一致）。
  final String indent;
  final TextScaler textScaler;

  static const double _epsilon = 0.5;

  final List<NovelTextPage> _pages = <NovelTextPage>[];
  final List<NovelTextSlice> _current = <NovelTextSlice>[];
  double _used = 0;

  /// 切页；尺寸无效时退化成单页（页面层会再按可用高度重算）。
  List<NovelTextPage> paginate() {
    _pages.clear();
    _current.clear();
    _used = 0;

    if (maxWidth <= 0 || maxHeight <= 0) {
      return <NovelTextPage>[
        NovelTextPage(<NovelTextSlice>[
          if (title.isNotEmpty)
            NovelTextSlice(
              paragraph: -1,
              start: 0,
              end: title.length,
              isTitle: true,
            ),
          for (var i = 0; i < paragraphs.length; i++)
            NovelTextSlice(
              paragraph: i,
              start: 0,
              end: paragraphs[i].length + indent.length,
            ),
        ]),
      ];
    }

    if (title.isNotEmpty) {
      _placeBlock(
        title,
        paragraphIndex: -1,
        style: titleStyle,
        spacingBefore: 0,
        isTitle: true,
      );
    }
    for (var i = 0; i < paragraphs.length; i++) {
      final spacing = (i == 0 && title.isNotEmpty)
          ? titleSpacing
          : (i == 0 ? 0.0 : paragraphSpacing);
      _placeBlock(
        '$indent${paragraphs[i]}',
        paragraphIndex: i,
        style: bodyStyle,
        spacingBefore: spacing,
        isTitle: false,
      );
    }
    _flushPage();
    if (_pages.isEmpty) {
      _pages.add(const NovelTextPage(<NovelTextSlice>[]));
    }
    return List<NovelTextPage>.unmodifiable(_pages);
  }

  void _placeBlock(
    String text, {
    required int paragraphIndex,
    required TextStyle style,
    required double spacingBefore,
    required bool isTitle,
  }) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) {
      painter.dispose();
      return;
    }

    final totalHeight = painter.height;
    final gap = _current.isEmpty ? 0.0 : spacingBefore;

    // 整段放得下：直接收进当前页。
    if (_used + gap + totalHeight <= maxHeight + _epsilon) {
      _used += gap;
      _append(
        NovelTextSlice(
          paragraph: paragraphIndex,
          start: 0,
          end: text.length,
          isTitle: isTitle,
        ),
      );
      _used += totalHeight;
      painter.dispose();
      return;
    }

    // 放不下：按行切，跨页的段落从行首断开。
    final lineStarts = <int>[];
    for (var i = 0; i < metrics.length; i++) {
      final line = metrics[i];
      final top = line.baseline - line.ascent;
      final position = painter.getPositionForOffset(
        Offset(0, top + line.height / 2),
      );
      lineStarts.add(position.offset);
    }
    lineStarts[0] = 0;
    for (var i = 1; i < lineStarts.length; i++) {
      // getPositionForOffset 在行首偶尔会返回上一行末尾，这里收紧成单调递增。
      lineStarts[i] = lineStarts[i].clamp(lineStarts[i - 1], text.length);
    }

    for (var i = 0; i < metrics.length; i++) {
      final lineHeight = metrics[i].height;
      final beforeLine = _current.isEmpty
          ? 0.0
          : (i == 0 ? spacingBefore : 0.0);
      if (_current.isNotEmpty &&
          _used + beforeLine + lineHeight > maxHeight + _epsilon) {
        _flushPage();
      }
      final gapOnPage = _current.isEmpty ? 0.0 : (i == 0 ? spacingBefore : 0.0);
      _used += gapOnPage;
      final start = lineStarts[i];
      final end = i + 1 < lineStarts.length ? lineStarts[i + 1] : text.length;
      if (end > start) {
        _append(
          NovelTextSlice(
            paragraph: paragraphIndex,
            start: start,
            end: end,
            isTitle: isTitle,
          ),
        );
      }
      _used += lineHeight;
    }
    painter.dispose();
  }

  /// 同段相邻切片合并，减少每页的 Text 数量。
  void _append(NovelTextSlice slice) {
    if (_current.isNotEmpty) {
      final last = _current.last;
      if (last.paragraph == slice.paragraph &&
          last.isTitle == slice.isTitle &&
          last.end == slice.start) {
        _current[_current.length - 1] = last.extendedTo(slice.end);
        return;
      }
    }
    _current.add(slice);
  }

  void _flushPage() {
    if (_current.isEmpty) return;
    _pages.add(NovelTextPage(List<NovelTextSlice>.unmodifiable(_current)));
    _current.clear();
    _used = 0;
  }
}
