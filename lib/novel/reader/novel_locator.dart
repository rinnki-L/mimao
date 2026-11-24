// 章内绝对位置：章下标 + 段落下标 + 段内字符偏移。
//
// 与 legado 的 Bookmark.chapterPos / ReadBook.durChapterPos 同口径：位置锚在
// 正文本身，而不是「第几页 / 滚动比例」。字号、行高、窗口宽度、翻页/滚动
// 模式怎么变，只要正文没变，就能落回同一句话。
//
// 段落内偏移以「原始段落文本」为准（不含段首全角缩进）；分页切片里的
// start/end 含缩进，换算时统一减 [novelParagraphIndentLength]。

import 'package:mimao/novel/reader/novel_text_pagination.dart';

/// 段首缩进「　　」的长度；切片偏移换算用。
const int novelParagraphIndentLength = 2;

class NovelLocator {
  const NovelLocator({
    required this.chapterIndex,
    this.paragraph = 0,
    this.charOffset = 0,
    this.sourceKey = '',
  });

  /// 0 起章下标（引擎口径）。
  final int chapterIndex;

  /// 0 起段落下标；-1 表示章标题。
  final int paragraph;

  /// 段内字符偏移（不含缩进）。
  final int charOffset;

  /// 书源 key；换源后同一本书的 locator 不应跨源复用。
  final String sourceKey;

  bool get isTitle => paragraph < 0;

  NovelLocator copyWith({int? paragraph, int? charOffset}) => NovelLocator(
    chapterIndex: chapterIndex,
    paragraph: paragraph ?? this.paragraph,
    charOffset: charOffset ?? this.charOffset,
    sourceKey: sourceKey,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'chapterIndex': chapterIndex,
    'paragraph': paragraph,
    'charOffset': charOffset,
    'sourceKey': sourceKey,
  };

  static NovelLocator? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chapter = raw['chapterIndex'];
    if (chapter is! num) return null;
    final paragraph = raw['paragraph'];
    final offset = raw['charOffset'];
    return NovelLocator(
      chapterIndex: chapter.toInt(),
      paragraph: paragraph is num ? paragraph.toInt() : 0,
      charOffset: offset is num ? offset.toInt() : 0,
      sourceKey: '${raw['sourceKey'] ?? ''}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NovelLocator &&
      other.chapterIndex == chapterIndex &&
      other.paragraph == paragraph &&
      other.charOffset == charOffset &&
      other.sourceKey == sourceKey;

  @override
  int get hashCode =>
      Object.hash(chapterIndex, paragraph, charOffset, sourceKey);
}

/// 分页切片 → locator。段内偏移落在切片起点，滚动/翻页共用。
NovelLocator locatorForSlice(
  NovelTextSlice slice, {
  required int chapterIndex,
  String sourceKey = '',
}) {
  if (slice.isTitle) {
    return NovelLocator(
      chapterIndex: chapterIndex,
      paragraph: -1,
      sourceKey: sourceKey,
    );
  }
  final offset = (slice.start - novelParagraphIndentLength).clamp(0, 1 << 31);
  return NovelLocator(
    chapterIndex: chapterIndex,
    paragraph: slice.paragraph,
    charOffset: offset,
    sourceKey: sourceKey,
  );
}

/// locator → 页下标；找不到时返回 -1，由调用方决定回退（章首/末页）。
int pageIndexForLocator(List<NovelTextPage> pages, NovelLocator locator) {
  if (pages.isEmpty) return -1;
  if (locator.isTitle) return 0;
  final target = locator.charOffset + novelParagraphIndentLength;
  for (var i = 0; i < pages.length; i++) {
    for (final slice in pages[i].slices) {
      if (slice.isTitle) continue;
      if (slice.paragraph > locator.paragraph) return i;
      if (slice.paragraph == locator.paragraph && slice.end > target) {
        return i;
      }
    }
  }
  return pages.length - 1;
}

/// 页首段 → locator。用于离开某页时回写位置。
NovelLocator locatorForPage(
  List<NovelTextPage> pages,
  int pageIndex, {
  required int chapterIndex,
  String sourceKey = '',
}) {
  if (pages.isEmpty) {
    return NovelLocator(chapterIndex: chapterIndex, sourceKey: sourceKey);
  }
  final index = pageIndex.clamp(0, pages.length - 1);
  for (final slice in pages[index].slices) {
    if (!slice.isTitle) {
      return locatorForSlice(
        slice,
        chapterIndex: chapterIndex,
        sourceKey: sourceKey,
      );
    }
  }
  return NovelLocator(chapterIndex: chapterIndex, sourceKey: sourceKey);
}
