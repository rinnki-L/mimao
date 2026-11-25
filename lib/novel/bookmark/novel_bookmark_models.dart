// 书签 / 划线 / 笔记的纯领域模型。
//
// 锚点与阅读器的 [NovelLocator] 同口径：章下标 + 段落下标 + 段内字符偏移。
// 不存页码、不存滚动比例——字号、窗口、翻页/滚动模式怎么变，只要正文没变，
// 就还能落回同一句话。
//
// 这一层不含 drift/IO：服务层负责行 ↔ 模型转换，渲染层只读这里的样式值。

import 'dart:convert';

import 'package:mimao/novel/reader/novel_locator.dart';

/// 书签锚点：定位一段文字所需的最小信息。
class NovelTextAnchor {
  const NovelTextAnchor({
    required this.bookId,
    this.sourceKey = '',
    required this.chapterIndex,
    this.paragraph = 0,
    this.charOffset = 0,
  });

  final String bookId;
  final String sourceKey;
  final int chapterIndex;
  final int paragraph;
  final int charOffset;

  NovelLocator get locator => NovelLocator(
    chapterIndex: chapterIndex,
    paragraph: paragraph,
    charOffset: charOffset,
    sourceKey: sourceKey,
  );

  @override
  bool operator ==(Object other) =>
      other is NovelTextAnchor &&
      other.bookId == bookId &&
      other.sourceKey == sourceKey &&
      other.chapterIndex == chapterIndex &&
      other.paragraph == paragraph &&
      other.charOffset == charOffset;

  @override
  int get hashCode =>
      Object.hash(bookId, sourceKey, chapterIndex, paragraph, charOffset);

  @override
  String toString() =>
      'NovelTextAnchor($bookId@$sourceKey:$chapterIndex/$paragraph+$charOffset)';
}

/// 一条书签（模型层；行在 `bookmark` 表）。
class NovelBookmark {
  const NovelBookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.createdAt,
    this.sourceKey = '',
    this.bookTitle = '',
    this.bookAuthor = '',
    this.bookUrl = '',
    this.paragraph = 0,
    this.charOffset = 0,
    this.chapterName = '',
    this.excerpt = '',
    this.unresolved = false,
  });

  final int id;
  final String bookId;
  final String sourceKey;
  final String bookTitle;
  final String bookAuthor;
  final String bookUrl;
  final int chapterIndex;
  final int paragraph;
  final int charOffset;
  final String chapterName;
  final String excerpt;

  /// 换源后重定位失败：仍保留，列表标「无法定位」，不静默丢弃。
  final bool unresolved;
  final DateTime createdAt;

  NovelTextAnchor get anchor => NovelTextAnchor(
    bookId: bookId,
    sourceKey: sourceKey,
    chapterIndex: chapterIndex,
    paragraph: paragraph,
    charOffset: charOffset,
  );

  NovelLocator get locator => anchor.locator;

  NovelBookmark copyWith({
    int? chapterIndex,
    String? sourceKey,
    int? paragraph,
    int? charOffset,
    String? chapterName,
    String? excerpt,
    bool? unresolved,
  }) => NovelBookmark(
    id: id,
    bookId: bookId,
    sourceKey: sourceKey ?? this.sourceKey,
    bookTitle: bookTitle,
    bookAuthor: bookAuthor,
    bookUrl: bookUrl,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    paragraph: paragraph ?? this.paragraph,
    charOffset: charOffset ?? this.charOffset,
    chapterName: chapterName ?? this.chapterName,
    excerpt: excerpt ?? this.excerpt,
    unresolved: unresolved ?? this.unresolved,
    createdAt: createdAt,
  );

  /// 列表展示用：优先书签名，其次章节名，最后「未命名书签」。
  String get displayTitle {
    if (bookTitle.isNotEmpty) return bookTitle;
    if (chapterName.isNotEmpty) return chapterName;
    return '未命名书签';
  }
}

/// 划线装饰：背景色块 / 下划线 / 波浪线。值落库，改名要兼容旧值。
enum NovelMarkingDecoration {
  background('背景'),
  underline('下划线'),
  wavy('波浪线');

  const NovelMarkingDecoration(this.label);

  final String label;

  static NovelMarkingDecoration parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return NovelMarkingDecoration.background;
  }
}

/// 划线样式（颜色 + 装饰）。颜色是阅读画布上的叠加色，不依赖主题角色；
/// 存 ARGB 整数，避免换主题后旧划线变色。
class NovelMarkingStyle {
  const NovelMarkingStyle({
    required this.colorArgb,
    this.decoration = NovelMarkingDecoration.background,
  });

  final int colorArgb;
  final NovelMarkingDecoration decoration;

  /// 默认样式：半透明黄底（与上游默认 highlight 接近）。
  static const NovelMarkingStyle yellow = NovelMarkingStyle(
    colorArgb: 0x66FFC107,
  );

  /// 可选颜色板（顺序即编辑面板里的展示顺序）。
  static const List<NovelMarkingStyle> presets = <NovelMarkingStyle>[
    NovelMarkingStyle.yellow,
    NovelMarkingStyle(colorArgb: 0x6666BB6A),
    NovelMarkingStyle(colorArgb: 0x6664B5F6),
    NovelMarkingStyle(colorArgb: 0x66F06292),
    NovelMarkingStyle(colorArgb: 0x66BA68C8),
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    'color': colorArgb,
    'decoration': decoration.name,
  };

  String encode() => jsonEncode(toJson());

  static NovelMarkingStyle fromJson(Map<String, Object?> json) {
    final color = json['color'];
    return NovelMarkingStyle(
      colorArgb: color is num ? color.toInt() : yellow.colorArgb,
      decoration: NovelMarkingDecoration.parse(json['decoration']),
    );
  }

  /// 坏 JSON / 缺字段一律回退默认样式，不让一条坏行让整章划线消失。
  static NovelMarkingStyle decode(String raw) {
    if (raw.isEmpty) return yellow;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return fromJson(Map<String, Object?>.from(decoded));
      }
      if (decoded is Map) {
        return fromJson(Map<String, Object?>.from(decoded));
      }
    } on Object {
      // 落到默认样式。
    }
    return yellow;
  }

  NovelMarkingStyle copyWith({
    int? colorArgb,
    NovelMarkingDecoration? decoration,
  }) => NovelMarkingStyle(
    colorArgb: colorArgb ?? this.colorArgb,
    decoration: decoration ?? this.decoration,
  );

  @override
  bool operator ==(Object other) =>
      other is NovelMarkingStyle &&
      other.colorArgb == colorArgb &&
      other.decoration == decoration;

  @override
  int get hashCode => Object.hash(colorArgb, decoration);
}

/// 一条划线/笔记（模型层；行在 `marking` 表）。
class NovelMarking {
  const NovelMarking({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.paragraph,
    required this.startOffset,
    required this.endOffset,
    required this.style,
    required this.createdAt,
    required this.updatedAt,
    this.sourceKey = '',
    this.bookTitle = '',
    this.bookAuthor = '',
    this.bookUrl = '',
    this.chapterName = '',
    this.note = '',
    this.unresolved = false,
  });

  final int id;
  final String bookId;
  final String sourceKey;
  final String bookTitle;
  final String bookAuthor;
  final String bookUrl;
  final int chapterIndex;
  final int paragraph;

  /// 段内区间 [startOffset, endOffset)，偏移不含段首缩进。
  final int startOffset;
  final int endOffset;
  final NovelMarkingStyle style;
  final String note;
  final String chapterName;
  final bool unresolved;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get length => endOffset - startOffset;

  bool get hasNote => note.trim().isNotEmpty;

  /// 同一段落内的区间是否重叠（用于「再划一次合并/替换」判定）。
  bool overlaps(int start, int end) => start < endOffset && end > startOffset;

  NovelMarking copyWith({
    int? startOffset,
    int? endOffset,
    NovelMarkingStyle? style,
    String? note,
    bool? unresolved,
    int? chapterIndex,
    DateTime? updatedAt,
  }) => NovelMarking(
    id: id,
    bookId: bookId,
    sourceKey: sourceKey,
    bookTitle: bookTitle,
    bookAuthor: bookAuthor,
    bookUrl: bookUrl,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    paragraph: paragraph,
    startOffset: startOffset ?? this.startOffset,
    endOffset: endOffset ?? this.endOffset,
    style: style ?? this.style,
    note: note ?? this.note,
    chapterName: chapterName,
    unresolved: unresolved ?? this.unresolved,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 标记区间的唯一校验口：越界 clamp、反向区间交换、空区间返回 null。
///
/// 服务层落库前与渲染层切片前都过这里，避免出现 start >= end 或越过段落
/// 末尾的区间把 `substring` 打崩。
({int start, int end})? normalizeNovelMarkingRange({
  required int start,
  required int end,
  required int paragraphLength,
}) {
  if (paragraphLength <= 0) return null;
  var from = start.clamp(0, paragraphLength);
  var to = end.clamp(0, paragraphLength);
  if (from > to) {
    final swap = from;
    from = to;
    to = swap;
  }
  if (to <= from) return null;
  return (start: from, end: to);
}

/// 章节标题归一：去空白/标点/书名号并转小写，用于换源后按标题匹配。
String normalizeNovelChapterTitle(String value) => value
    .replaceAll(RegExp(r'[\s《》「」『』（）()\[\]【】\-—_·,，。.!！?？:：;；]'), '')
    .toLowerCase();

/// 换源重定位结果：成功多少条、失败多少条（失败的行标 unresolved，不删）。
class NovelRelocateResult {
  const NovelRelocateResult({
    required this.total,
    required this.relocated,
    required this.unresolved,
  });

  final int total;

  /// 本次按标题找到了新章下标（含原本就对上的）的条数。
  final int relocated;

  /// 找不到对应章节、已标记「无法定位」的条数。
  final int unresolved;

  bool get hasChanges => relocated > 0 || unresolved > 0;

  @override
  String toString() =>
      'NovelRelocateResult(total: $total, relocated: $relocated, '
      'unresolved: $unresolved)';
}
