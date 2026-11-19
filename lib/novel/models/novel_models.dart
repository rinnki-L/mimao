/// 小说域纯领域模型与主键/进度契约（M5 地基切片）。
///
/// 本文件只含 const 构造的值对象与纯函数，不含任何抓取、解析或 IO；
/// 历史 payload 通过各模型的 [fromJson] 重建。后续切片按这里的签名对接。
library;

/// 投影 `sourceName` 的固定值（core `media_entries` 复合主键的源维度）。
const String novelSourceName = 'legado';

/// 没有可读进度时展示的文案（未读）。
const String novelUnreadText = '尚未阅读';

/// 有历史记录但没有可计算章节进度时展示的文案。
const String novelReadText = '读过';

/// 小说模块内部权威主键：源内书 id + 来源名（默认 [novelSourceName]）。
class NovelRef {
  const NovelRef({required this.id, this.sourceName = novelSourceName});

  final String id;
  final String sourceName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sourceName': sourceName,
  };

  factory NovelRef.fromJson(Map<String, Object?> json) => NovelRef(
    id: '${json['id'] ?? ''}',
    sourceName: '${json['sourceName'] ?? novelSourceName}',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelRef && other.id == id && other.sourceName == sourceName);

  @override
  int get hashCode => Object.hash(id, sourceName);

  @override
  String toString() => 'NovelRef($sourceName:$id)';
}

/// 章节进度文案：有可计算进度时返回「看到第 N 章 · P%」，否则返回 [novelReadText]。
///
/// 纯函数、无副作用；百分比按 chapterIndex/chapterCount 计算并 clamp 到 0..100
/// 后取整。chapterCount<=0 或 chapterIndex<=0 视为「无可计算进度」。
String novelProgressText({
  required int chapterIndex,
  required int chapterCount,
}) {
  if (chapterCount <= 0 || chapterIndex <= 0) return novelReadText;
  final percent = ((chapterIndex / chapterCount) * 100).clamp(0, 100).round();
  return '看到第 $chapterIndex 章 · $percent%';
}

/// 搜索/发现结果里的一本书（列表项）。
class NovelSummary {
  const NovelSummary({
    required this.id,
    required this.title,
    this.coverUrl = '',
    this.author = '',
    this.sourceName = novelSourceName,
  });

  final String id;
  final String title;
  final String coverUrl;
  final String author;
  final String sourceName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'author': author,
    'sourceName': sourceName,
  };

  factory NovelSummary.fromJson(Map<String, Object?> json) => NovelSummary(
    id: '${json['id'] ?? ''}',
    title: '${json['title'] ?? ''}',
    coverUrl: '${json['coverUrl'] ?? ''}',
    author: '${json['author'] ?? ''}',
    sourceName: '${json['sourceName'] ?? novelSourceName}',
  );
}

/// 一本书的目录（含章节列表）。
class NovelDetail {
  const NovelDetail({
    required this.ref,
    required this.title,
    this.coverUrl = '',
    this.chapters = const <NovelChapter>[],
  });

  final NovelRef ref;
  final String title;
  final String coverUrl;
  final List<NovelChapter> chapters;

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': ref.toJson(),
    'title': title,
    'coverUrl': coverUrl,
    'chapters': <Object?>[for (final chapter in chapters) chapter.toJson()],
  };

  factory NovelDetail.fromJson(Map<String, Object?> json) => NovelDetail(
    ref: NovelRef.fromJson(
      Map<String, Object?>.from(
        json['ref'] as Map? ?? const <String, Object?>{},
      ),
    ),
    title: '${json['title'] ?? ''}',
    coverUrl: '${json['coverUrl'] ?? ''}',
    chapters: <NovelChapter>[
      for (final raw
          in (json['chapters'] as List<Object?>? ?? const <Object?>[]))
        NovelChapter.fromJson(Map<String, Object?>.from(raw! as Map)),
    ],
  );
}

/// 目录里的一章。
class NovelChapter {
  const NovelChapter({
    required this.id,
    required this.title,
    required this.index,
    this.url = '',
  });

  final String id;
  final String title;
  final int index;
  final String url;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'index': index,
    'url': url,
  };

  factory NovelChapter.fromJson(Map<String, Object?> json) => NovelChapter(
    id: '${json['id'] ?? ''}',
    title: '${json['title'] ?? ''}',
    index: json['index'] is num ? (json['index']! as num).toInt() : 0,
    url: '${json['url'] ?? ''}',
  );
}

/// 一章的正文（段落列表）。
class NovelContent {
  const NovelContent({
    required this.chapterId,
    required this.title,
    this.paragraphs = const <String>[],
  });

  final String chapterId;
  final String title;
  final List<String> paragraphs;

  Map<String, Object?> toJson() => <String, Object?>{
    'chapterId': chapterId,
    'title': title,
    'paragraphs': <Object?>[...paragraphs],
  };

  factory NovelContent.fromJson(Map<String, Object?> json) => NovelContent(
    chapterId: '${json['chapterId'] ?? ''}',
    title: '${json['title'] ?? ''}',
    paragraphs: <String>[
      for (final raw
          in (json['paragraphs'] as List<Object?>? ?? const <Object?>[]))
        '$raw',
    ],
  );
}
