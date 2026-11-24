// 跨章瀑布流的纯数据模型——不认识 Widget、不滚动、不联网。
//
// 照搬 Venera Next 的"章节段 + 全局流索引"设计，但用原生实现：
// - 章节段按 chapter 升序排列，重复章节忽略；
// - 全局流索引 1 基（0 留给列表顶部，imageCount+1 留给流末 UI）；
// - chapterId 参与反向校验，源站重排章节后旧位置直接失效而不是错位到别的章。
//
// 全局流索引只属于视图层；进度永远写"真实章节 + 章内页"，跨章不丢位置。

import 'reader_models.dart' show ComicChapter, ImageRequest;

/// 流中"一张图"的真实位置（进度记录的最小单位）。
class ReaderImagePosition {
  const ReaderImagePosition({
    required this.chapter, // 1 基，章节在原始列表中的序号
    required this.chapterId, // 源稳定 epId
    required this.page, // 1 基，章内页
  });

  final int chapter;
  final String chapterId;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is ReaderImagePosition &&
      other.chapter == chapter &&
      other.chapterId == chapterId &&
      other.page == page;

  @override
  int get hashCode => Object.hash(chapter, chapterId, page);

  @override
  String toString() => 'ReaderImagePosition($chapter, $chapterId, $page)';
}

/// 一个已加载的章节段：图片列表加载后不可变，只整段增删。
class ReaderChapterSegment {
  ReaderChapterSegment({
    required this.chapter,
    required this.chapterId,
    required List<ImageRequest> images,
  }) : images = List<ImageRequest>.unmodifiable(images);

  final int chapter;
  final String chapterId;
  final List<ImageRequest> images;

  int get length => images.length;

  bool matches(ReaderImagePosition position) =>
      position.chapter == chapter && position.chapterId == chapterId;
}

/// 流里一张图的引用：位置 + 请求 + 是否段首（段首用于插章节标题）。
class ReaderFlowImage {
  const ReaderFlowImage({
    required this.position,
    required this.request,
    required this.isFirstInSegment,
  });

  final ReaderImagePosition position;
  final ImageRequest request;

  String get url => request.url;
  final bool isFirstInSegment;
}

/// 跨章章节流：段的集合 + 流索引换算。视图只读，控制器负责增删。
class ReaderChapterFlow {
  ReaderChapterFlow({List<ReaderChapterSegment> segments = const []})
    : _segments = List<ReaderChapterSegment>.from(segments)
        ..sort((a, b) => a.chapter.compareTo(b.chapter));

  final List<ReaderChapterSegment> _segments;

  List<ReaderChapterSegment> get segments => List.unmodifiable(_segments);
  int get segmentCount => _segments.length;
  int get imageCount => _segments.fold(0, (sum, s) => sum + s.length);
  bool get isEmpty => _segments.isEmpty;

  int get firstChapter => _segments.isEmpty ? 0 : _segments.first.chapter;
  int get lastChapter => _segments.isEmpty ? 0 : _segments.last.chapter;

  bool hasChapter(int chapter) => _segments.any((s) => s.chapter == chapter);

  ReaderChapterSegment? segmentOf(int chapter) {
    for (final s in _segments) {
      if (s.chapter == chapter) return s;
    }
    return null;
  }

  /// 流索引（1 基）→ 一张图；0 或越界返回 null。
  ReaderFlowImage? imageAt(int index) {
    if (index <= 0) return null;
    var remain = index;
    for (final segment in _segments) {
      if (remain <= segment.length) {
        return ReaderFlowImage(
          position: ReaderImagePosition(
            chapter: segment.chapter,
            chapterId: segment.chapterId,
            page: remain,
          ),
          request: segment.images[remain - 1],
          isFirstInSegment: remain == 1,
        );
      }
      remain -= segment.length;
    }
    return null;
  }

  /// 真实位置 → 流索引（1 基）；章节不在流内 / chapterId 不符 / 页越界 → null。
  int? indexOf(ReaderImagePosition position) {
    if (position.page <= 0) return null;
    var index = 1;
    for (final segment in _segments) {
      if (segment.chapter == position.chapter) {
        if (!segment.matches(position) || position.page > segment.length) {
          return null;
        }
        return index + position.page - 1;
      }
      index += segment.length;
    }
    return null;
  }

  /// 某章首图在流中的索引；章不在流内返回 null。
  int? firstIndexOf(int chapter) {
    final segment = segmentOf(chapter);
    if (segment == null) return null;
    return indexOf(
      ReaderImagePosition(
        chapter: chapter,
        chapterId: segment.chapterId,
        page: 1,
      ),
    );
  }

  /// 在末尾追加一段；重复章节忽略。返回是否真的插入。
  bool addAfter(ReaderChapterSegment segment) {
    if (hasChapter(segment.chapter)) return false;
    _segments.add(segment);
    return true;
  }

  /// 在开头插入一段；重复章节忽略。返回插入的图片数（视图做锚点位移用）。
  int addBefore(ReaderChapterSegment segment) {
    if (hasChapter(segment.chapter)) return 0;
    _segments.insert(0, segment);
    return segment.length;
  }

  /// 是否该向后补章：剩余图片不足阈值且未到最大章。
  bool shouldLoadAfter({
    required int current,
    required int threshold,
    required int maxChapter,
  }) {
    if (_segments.isEmpty) return false;
    if (imageCount - current >= threshold) return false;
    return lastChapter < maxChapter;
  }

  /// 是否该向前补章：离顶部不足阈值且未到第一章。
  bool shouldLoadBefore({required int current, required int threshold}) {
    if (_segments.isEmpty) return false;
    if (current > threshold) return false;
    return firstChapter > 1;
  }

  /// 重置为单段（显式跳章后丢弃其余段）。
  void reset(ReaderChapterSegment segment) {
    _segments
      ..clear()
      ..add(segment);
  }

  /// 从 [chapters] 构造单章段（懒加载前的最小流）。
  static ReaderChapterSegment segmentFrom(ComicChapter chapter, int number) =>
      ReaderChapterSegment(
        chapter: number,
        chapterId: chapter.chapterId,
        images: <ImageRequest>[
          for (var i = 0; i < chapter.imageUrls.length; i++)
            chapter.requestAt(i),
        ],
      );
}
