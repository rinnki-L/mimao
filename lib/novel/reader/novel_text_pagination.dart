// 正文分页：把一章的标题 + 段落按给定字号/行高/宽度/高度切成页。
//
// 纯函数式测量（TextPainter），不依赖 Widget 树，可在单测里直接喂
// 固定 TextStyle 验证页数。页面渲染时按 [NovelTextSlice] 取子串，
// 因此「跨页段落」既能精确切在行边界，又能保持换行位置不变。
//
// 版式参数全部来自 NovelReaderSettings：字距/加粗/斜体/缩进/两端对齐由
// TextStyle/TextAlign 传入；行距是否含行内留白用 TextHeightBehavior 表达；
// 双栏在分页层按「有效列宽」切，返回的仍是一列一页，页面层再把两列并排；
// 避头尾断行走 [applyKinsokuBreaks]（纯函数，见 novel_line_break.dart）。

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'novel_line_break.dart';

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
  const NovelTextPage(this.slices, {this.columnIndex = 0});

  final List<NovelTextSlice> slices;

  /// 双栏时这一页属于第几列（0 左 / 1 右）；单栏恒为 0。
  final int columnIndex;

  bool get isEmpty => slices.isEmpty;

  /// 这一页是否含章节标题（双栏渲染时标题页不拆）。
  bool get hasTitle => slices.any((slice) => slice.isTitle);
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
    this.titleTopSpacing = 0,
    double? titleBottomSpacing,
    this.indent = '　　',
    this.textScaler = TextScaler.noScaling,
    this.bodyTextAlign = TextAlign.start,
    this.titleTextAlign = TextAlign.start,
    this.textHeightBehavior,
    this.kinsoku = true,
    this.columns = 1,
    this.columnGap = 24,
  }) : _titleBottomSpacing = titleBottomSpacing;

  final String title;
  final List<String> paragraphs;
  final TextStyle bodyStyle;
  final TextStyle titleStyle;
  final double maxWidth;
  final double maxHeight;
  final double paragraphSpacing;

  /// 旧参数：标题与正文之间的留白（没有 [titleBottomSpacing] 时生效）。
  final double titleSpacing;
  final double titleTopSpacing;
  final double? _titleBottomSpacing;

  /// 段首缩进（默认两个全角空格，与中文排版一致）。
  final String indent;
  final TextScaler textScaler;
  final TextAlign bodyTextAlign;
  final TextAlign titleTextAlign;
  final TextHeightBehavior? textHeightBehavior;

  /// 是否启用避头尾（默认开）。
  final bool kinsoku;

  /// 列数：1 = 单栏，2 = 双栏；双栏时按「(宽 - 间距) / 2」测每一列。
  final int columns;
  final double columnGap;

  static const double _epsilon = 0.5;

  double get _effectiveTitleBottomSpacing =>
      _titleBottomSpacing ?? titleSpacing;

  /// 单列实际排版宽度。
  double get effectiveWidth {
    if (columns <= 1 || maxWidth <= 0) return maxWidth;
    final available = maxWidth - columnGap * (columns - 1);
    return math.max(0, available / columns);
  }

  final List<NovelTextPage> _pages = <NovelTextPage>[];
  final List<NovelTextSlice> _current = <NovelTextSlice>[];
  double _used = 0;

  /// 切页；尺寸无效时退化成单页（页面层会再按可用高度重算）。
  List<NovelTextPage> paginate() {
    _pages.clear();
    _current.clear();
    _used = 0;

    final width = effectiveWidth;
    if (width <= 0 || maxHeight <= 0) {
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
        spacingBefore: titleTopSpacing,
        isTitle: true,
        align: titleTextAlign,
        widthOverride: columns > 1 ? maxWidth : null,
      );
      // 双栏时标题页独占整宽，不跟正文切到同一列（「标题页不拆」）。
      if (columns > 1) _flushPage();
    }
    for (var i = 0; i < paragraphs.length; i++) {
      final spacing = (i == 0 && title.isNotEmpty)
          ? _effectiveTitleBottomSpacing
          : (i == 0 ? 0.0 : paragraphSpacing);
      _placeBlock(
        '$indent${paragraphs[i]}',
        paragraphIndex: i,
        style: bodyStyle,
        spacingBefore: spacing,
        isTitle: false,
        align: bodyTextAlign,
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
    required TextAlign align,
    double? widthOverride,
  }) {
    if (text.isEmpty) return;
    final width = widthOverride ?? effectiveWidth;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      textScaler: textScaler,
      textHeightBehavior: textHeightBehavior,
      maxLines: null,
    )..layout(maxWidth: width);

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
    if (kinsoku) {
      final adjusted = applyKinsokuBreaks(text, lineStarts);
      for (var i = 0; i < lineStarts.length; i++) {
        lineStarts[i] = adjusted[i].clamp(0, text.length);
      }
    }

    for (var i = 0; i < metrics.length; i++) {
      final start = lineStarts[i];
      final end = i + 1 < lineStarts.length ? lineStarts[i + 1] : text.length;
      // 避头尾会把字符挪到上一行，切片因此可能比原来那一行多折一行；
      // 页高必须按「实际要渲染的切片」重新测量，否则渲染时会撑破页高。
      final sliceHeight = _measureSliceHeight(
        text,
        start,
        end,
        style,
        align,
        width,
      );
      final beforeLine = _current.isEmpty
          ? 0.0
          : (i == 0 ? spacingBefore : 0.0);
      if (_current.isNotEmpty &&
          _used + beforeLine + sliceHeight > maxHeight + _epsilon) {
        _flushPage();
      }
      final gapOnPage = _current.isEmpty ? 0.0 : (i == 0 ? spacingBefore : 0.0);
      _used += gapOnPage;
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
      _used += sliceHeight;
    }
    painter.dispose();
  }

  /// 单个切片（渲染层就是一段独立 Text）的真实高度。
  double _measureSliceHeight(
    String text,
    int start,
    int end,
    TextStyle style,
    TextAlign align,
    double width,
  ) {
    if (end <= start) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text.substring(start, end), style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      textScaler: textScaler,
      textHeightBehavior: textHeightBehavior,
      maxLines: null,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
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
    _pages.add(
      NovelTextPage(
        List<NovelTextSlice>.unmodifiable(_current),
        columnIndex: _pages.length % (columns < 1 ? 1 : columns),
      ),
    );
    _current.clear();
    _used = 0;
  }
}
