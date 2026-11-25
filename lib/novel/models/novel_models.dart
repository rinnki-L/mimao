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
  const NovelRef({
    required this.id,
    this.sourceName = novelSourceName,
    this.sourceKey = '',
    this.bookUrl = '',
  });

  final String id;
  final String sourceName;

  /// 书源主键（`NovelBookSource.key`，书源 URL 的 base64url）。
  ///
  /// 同一本书在不同书源里是不同实体；本地库主键仍只用 [id]，这个字段随书籍
  /// JSON 落库，供详情/阅读页重新找到源。
  final String sourceKey;

  /// 详情页绝对地址（legado 书源的 `bookUrl`）。
  final String bookUrl;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sourceName': sourceName,
    if (sourceKey.isNotEmpty) 'sourceKey': sourceKey,
    if (bookUrl.isNotEmpty) 'bookUrl': bookUrl,
  };

  factory NovelRef.fromJson(Map<String, Object?> json) => NovelRef(
    id: '${json['id'] ?? ''}',
    sourceName: '${json['sourceName'] ?? novelSourceName}',
    sourceKey: '${json['sourceKey'] ?? ''}',
    bookUrl: '${json['bookUrl'] ?? ''}',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelRef &&
          other.id == id &&
          other.sourceName == sourceName &&
          other.sourceKey == sourceKey &&
          other.bookUrl == bookUrl);

  @override
  int get hashCode => Object.hash(id, sourceName, sourceKey, bookUrl);

  @override
  String toString() => 'NovelRef($sourceName:$id)';
}

/// 章节进度文案：有可计算进度时返回「看到第 N 章 · P%」，否则返回 [novelReadText]。
///
/// 纯函数、无副作用。入参遵循历史库契约：chapterIndex 是 **1 起的章号**，
/// 0 表示无进度；百分比按 chapterIndex/chapterCount 计算并 clamp 到 0..100
/// 后取整。chapterCount<=0 或 chapterIndex<=0 视为「无可计算进度」。
/// 书源引擎的 0 起 chapter.index 在落库前由阅读页 +1（见 novel_reader_page.dart），
/// 不要在这里再转换。
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
    this.sourceKey = '',
    this.bookUrl = '',
    this.intro = '',
    this.kind = '',
    this.latestChapter = '',
    this.wordCount = '',
    this.updateTime = '',
    this.type = 0,
  });

  final String id;
  final String title;
  final String coverUrl;
  final String author;
  final String sourceName;

  /// 书源主键；老数据为空（无法继续在线抓取，但本地记录仍可展示）。
  final String sourceKey;

  /// 详情页绝对地址。
  final String bookUrl;
  final String intro;
  final String kind;
  final String latestChapter;
  final String wordCount;

  /// 书源给的更新时间原文（`ruleExplore/updateTime` 等规则的输出）。
  /// 可能是 `2026-11-25` 也可能是 `3小时前`，原样保存，展示时再判定。
  final String updateTime;

  /// legado `bookSourceType`：0 文本 / 1 音频 / 2 图片 / 3 文件 / 4 视频。
  final int type;

  NovelRef get ref => NovelRef(
    id: id,
    sourceName: sourceName,
    sourceKey: sourceKey,
    bookUrl: bookUrl,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'author': author,
    'sourceName': sourceName,
    if (sourceKey.isNotEmpty) 'sourceKey': sourceKey,
    if (bookUrl.isNotEmpty) 'bookUrl': bookUrl,
    if (intro.isNotEmpty) 'intro': intro,
    if (kind.isNotEmpty) 'kind': kind,
    if (latestChapter.isNotEmpty) 'latestChapter': latestChapter,
    if (wordCount.isNotEmpty) 'wordCount': wordCount,
    if (updateTime.isNotEmpty) 'updateTime': updateTime,
    if (type != 0) 'type': type,
  };

  factory NovelSummary.fromJson(Map<String, Object?> json) => NovelSummary(
    id: '${json['id'] ?? ''}',
    title: '${json['title'] ?? ''}',
    coverUrl: '${json['coverUrl'] ?? ''}',
    author: '${json['author'] ?? ''}',
    sourceName: '${json['sourceName'] ?? novelSourceName}',
    sourceKey: '${json['sourceKey'] ?? ''}',
    bookUrl: '${json['bookUrl'] ?? ''}',
    intro: '${json['intro'] ?? ''}',
    kind: '${json['kind'] ?? ''}',
    latestChapter: '${json['latestChapter'] ?? ''}',
    wordCount: '${json['wordCount'] ?? ''}',
    updateTime: '${json['updateTime'] ?? ''}',
    type: json['type'] is num ? (json['type']! as num).toInt() : 0,
  );
}

/// 一本书的目录（含详情页字段与章节列表）。
class NovelDetail {
  const NovelDetail({
    required this.ref,
    required this.title,
    this.coverUrl = '',
    this.author = '',
    this.intro = '',
    this.kind = '',
    this.latestChapter = '',
    this.wordCount = '',
    this.updateTime = '',
    this.chapters = const <NovelChapter>[],
  });

  final NovelRef ref;
  final String title;
  final String coverUrl;
  final String author;
  final String intro;
  final String kind;
  final String latestChapter;
  final String wordCount;

  /// 详情页给的更新时间原文（书源没配规则时为空串）。
  final String updateTime;
  final List<NovelChapter> chapters;

  NovelSummary get summary => NovelSummary(
    id: ref.id,
    title: title,
    coverUrl: coverUrl,
    author: author,
    sourceName: ref.sourceName,
    sourceKey: ref.sourceKey,
    bookUrl: ref.bookUrl,
    intro: intro,
    kind: kind,
    latestChapter: latestChapter,
    wordCount: wordCount,
    updateTime: updateTime,
    type: 0,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': ref.toJson(),
    'title': title,
    'coverUrl': coverUrl,
    if (author.isNotEmpty) 'author': author,
    if (intro.isNotEmpty) 'intro': intro,
    if (kind.isNotEmpty) 'kind': kind,
    if (latestChapter.isNotEmpty) 'latestChapter': latestChapter,
    if (wordCount.isNotEmpty) 'wordCount': wordCount,
    if (updateTime.isNotEmpty) 'updateTime': updateTime,
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
    author: '${json['author'] ?? ''}',
    intro: '${json['intro'] ?? ''}',
    kind: '${json['kind'] ?? ''}',
    latestChapter: '${json['latestChapter'] ?? ''}',
    wordCount: '${json['wordCount'] ?? ''}',
    updateTime: '${json['updateTime'] ?? ''}',
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
    this.isVolume = false,
    this.isVip = false,
    this.tag = '',
  });

  final String id;
  final String title;
  final int index;
  final String url;
  final bool isVolume;
  final bool isVip;
  final String tag;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'index': index,
    'url': url,
    if (isVolume) 'isVolume': true,
    if (isVip) 'isVip': true,
    if (tag.isNotEmpty) 'tag': tag,
  };

  factory NovelChapter.fromJson(Map<String, Object?> json) => NovelChapter(
    id: '${json['id'] ?? ''}',
    title: '${json['title'] ?? ''}',
    index: json['index'] is num ? (json['index']! as num).toInt() : 0,
    url: '${json['url'] ?? ''}',
    isVolume: json['isVolume'] == true,
    isVip: json['isVip'] == true,
    tag: '${json['tag'] ?? ''}',
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
