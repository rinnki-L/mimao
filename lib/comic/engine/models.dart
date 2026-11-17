/// 漫画源引擎的输出模型——纯数据结构，不依赖 UI、drift 或网络。
///
/// 语义对齐 Venera `init.js` 里的 `Comic` / `ComicDetails` / `chapter` /
/// `loadEp` 返回结构：社区源脚本产出这些对象，[JsComicBridge] 把它们收敛成
/// 这里稳定的 Dart 类型，上层（页面/存储）只消费这些类型。
library;

/// 搜索 / 探索 / 收藏页里的一个漫画条目（对齐 `new Comic({...})`）。
class ComicSummary {
  const ComicSummary({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.cover = '',
    this.tags = const <String>[],
    this.description = '',
    this.maxPage,
    this.language = '',
    this.favoriteId = '',
    this.stars,
  });

  /// 源内唯一 id（传给 `comic.loadInfo` / `comic.loadEp`）。
  final String id;
  final String title;

  /// 副标题 / 作者（`subTitle` 是同义字段，bridge 会归一到这里）。
  final String subtitle;
  final String cover;
  final List<String> tags;
  final String description;

  /// 已知总页数；未知为 null。
  final int? maxPage;
  final String language;

  /// 仅当条目来自收藏页时设置。
  final String favoriteId;

  /// 评分 0-5；未知为 null。
  final double? stars;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicSummary &&
          other.id == id &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.cover == cover &&
          _listEquals(other.tags, tags) &&
          other.description == description &&
          other.maxPage == maxPage &&
          other.language == language &&
          other.favoriteId == favoriteId &&
          other.stars == stars;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    subtitle,
    cover,
    Object.hashAll(tags),
    description,
    maxPage,
    language,
    favoriteId,
    stars,
  );

  @override
  String toString() => 'ComicSummary($id, $title)';
}

/// 一部漫画的详情（对齐 `new ComicDetails({...})`）。
class ComicDetail {
  const ComicDetail({
    required this.title,
    this.subtitle = '',
    this.cover = '',
    this.description = '',
    this.tags = const <String, List<String>>{},
    this.chapters = const <ComicChapter>[],
    this.thumbnails = const <String>[],
    this.recommend = const <ComicSummary>[],
    this.url = '',
    this.stars,
    this.maxPage,
  });

  final String title;
  final String subtitle;
  final String cover;
  final String description;

  /// 标签分组：键是分组名（如 "作者"），值是标签列表。
  final Map<String, List<String>> tags;

  /// 章节列表（由 `chapters` 的 `{id: title}` 映射按插入顺序展开）。
  final List<ComicChapter> chapters;
  final List<String> thumbnails;
  final List<ComicSummary> recommend;
  final String url;
  final double? stars;
  final int? maxPage;

  @override
  String toString() => 'ComicDetail($title, chapters: ${chapters.length})';
}

/// 一章（详情 `chapters` 里的一个键值对）。
class ComicChapter {
  const ComicChapter({required this.id, required this.title});

  /// 章节 id（传给 `comic.loadEp(comicId, epId)`）。
  final String id;
  final String title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicChapter && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);

  @override
  String toString() => 'ComicChapter($id, $title)';
}

/// 一章的图片地址（对齐 `loadEp` 返回的 `{images: string[]}`）。
class ComicImageRef {
  const ComicImageRef({
    required this.url,
    this.headers = const <String, String>{},
    this.method = 'GET',
  });

  final String url;

  /// 加载该图需要带的请求头（来自可选的 `comic.onImageLoad` 钩子）。
  final Map<String, String> headers;

  /// 加载方法（通常 GET）。
  final String method;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicImageRef &&
          other.url == url &&
          _mapEquals(other.headers, headers) &&
          other.method == method;

  @override
  int get hashCode => Object.hash(url, Object.hashAll(headers.entries), method);

  @override
  String toString() => 'ComicImageRef($url)';
}

/// 一次解析 / 执行的结果：数据 + 诊断信息。
///
/// 源脚本报错、超时、语法错都不会抛异常给上层，而是返回空 [items] 并在
/// [diagnostics] 说明原因——多个源聚合时可以逐源容错。
class ComicSourceResult<T> {
  const ComicSourceResult({
    List<T>? items,
    this.diagnostics = const <String>[],
    this.maxPage,
  }) : items = items ?? const [];

  final List<T> items;
  final List<String> diagnostics;

  /// 源脚本返回的分页总页数（如 `{comics, maxPage}`），供上层翻页；可为 null。
  final int? maxPage;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  @override
  String toString() =>
      'ComicSourceResult(items: ${items.length}, '
      'diagnostics: ${diagnostics.length})';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
