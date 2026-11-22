// 漫画阅读器的纯领域模型——不依赖 drift，也不认识壳。
//
// 只描述"读什么、读到哪"，不碰源引擎/网络/搜索/详情页；章节图片（含请求头）
// 与稳定 chapterId 由集成层（comic_entry / 引擎适配层）映射进来。权威主键
// 复用 comic_models.dart 的 ComicRef，与 core/db.dart 的
// {id, mediaType, sourceName} 逐维对齐（mediaType 恒为 comic）。
library;

/// 一张图：地址 + 可选请求头。
///
/// [url] 可以是 http(s) 地址，也可以是本地 `file://` 路径——具体如何取字节
/// 由 [ImageByteLoader]（reader_cache.dart）决定，模型本身不解释。
/// [headers] 来自源 `comic.onImageLoad` 钩子（Venera 契约的 ComicImageRef），
/// 不少站点要求带 Referer / Cookie 才不 403，必须在请求时直通。
class ReaderImage {
  final String url;

  /// 加载该图需要携带的请求头；空 map 表示无特殊要求（走 loader 的兜底头）。
  final Map<String, String> headers;

  const ReaderImage(this.url, {this.headers = const <String, String>{}});

  /// 无请求头的便捷构造（本地文件 / 测试用）。
  factory ReaderImage.plain(String url) =>
      ReaderImage(url, headers: const <String, String>{});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderImage &&
          other.url == url &&
          _mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(
    url,
    // MapEntry 自身的 hashCode 是恒等实现，不能直接 hashAll(entries)。
    Object.hashAll(<int>[
      for (final entry in headers.entries) Object.hash(entry.key, entry.value),
    ]),
  );

  @override
  String toString() => headers.isEmpty
      ? 'ReaderImage($url)'
      : 'ReaderImage($url, headers: ${headers.length} 项)';
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 一章：标题 + 稳定章节 id + 该章的图片列表。
///
/// [chapterId] 是源的稳定 epId（插入新章不会让进度错位），持久化进
/// `comic_history.chapterId`；测试用内存章节可留空（默认 `''`）。
class ComicChapter {
  final String title;

  /// 稳定章节 id（源内 epId）；本地/测试章节可为空串。
  final String chapterId;
  final List<ReaderImage> images;

  const ComicChapter({
    required this.title,
    this.chapterId = '',
    required this.images,
  });

  int get pageCount => images.length;
}

/// 阅读模式：分页（一次一屏）与连续（整章纵/横排布）各三个方向。
///
/// - `pagedLtr`：分页，左→右（默认，日漫右开本的镜像）；
/// - `pagedRtl`：分页，右→左（日漫原版方向）；
/// - `pagedTtb`：分页，上→下（条漫整页翻）；
/// - `continuousTtb`：连续，上→下（条漫滚动，最常用）；
/// - `continuousLtr` / `continuousRtl`：连续横排（少见，留全六向对称）。
///
/// 方向信息只给布尔（[isVertical] / [isRtl]），不暴露 Flutter 的
/// [Axis]——模型层保持不依赖 rendering。
enum ReaderMode {
  pagedLtr,
  pagedRtl,
  pagedTtb,
  continuousTtb,
  continuousLtr,
  continuousRtl;

  bool get isPaged =>
      this == ReaderMode.pagedLtr ||
      this == ReaderMode.pagedRtl ||
      this == ReaderMode.pagedTtb;

  bool get isContinuous => !isPaged;

  /// 主滚动/翻页轴是否竖直（ttb 两模式）。
  bool get isVertical =>
      this == ReaderMode.pagedTtb || this == ReaderMode.continuousTtb;

  /// 主轴前进方向是否与"左/上到右/下"相反（rtl 两模式）。
  bool get isRtl =>
      this == ReaderMode.pagedRtl || this == ReaderMode.continuousRtl;
}

/// 阅读偏好（进阅读器时装载，改动即持久化）。
///
/// 不含"读到了哪"——那是 [ReadingProgress]（reader_progress.dart）的职责，
/// 两者都写库但互不覆盖。
class ReaderSettings {
  /// 默认阅读模式（分页左→右）。
  final ReaderMode mode;

  /// 预加载张数：当前页前后各预取多少张进缓存（0 关闭，上限 12）。
  final int preloadCount;

  /// 单击左右（竖直模式下上下）边缘区是否翻页；关闭后单击只呼出工具栏。
  final bool tapToTurn;

  /// 分页模式下双击是否缩放（photo_view 内建双击缩放的开关）。
  final bool doubleTapZoom;

  static const int minPreloadCount = 0;
  static const int maxPreloadCount = 12;

  const ReaderSettings({
    this.mode = ReaderMode.pagedLtr,
    this.preloadCount = 4,
    this.tapToTurn = true,
    this.doubleTapZoom = true,
  });

  /// [preloadCount] 钳制到合法区间（设置面板滑杆外的脏值兜底）。
  ReaderSettings normalized() => copyWith(
    preloadCount: preloadCount.clamp(minPreloadCount, maxPreloadCount),
  );

  ReaderSettings copyWith({
    ReaderMode? mode,
    int? preloadCount,
    bool? tapToTurn,
    bool? doubleTapZoom,
  }) => ReaderSettings(
    mode: mode ?? this.mode,
    preloadCount: preloadCount ?? this.preloadCount,
    tapToTurn: tapToTurn ?? this.tapToTurn,
    doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderSettings &&
          other.mode == mode &&
          other.preloadCount == preloadCount &&
          other.tapToTurn == tapToTurn &&
          other.doubleTapZoom == doubleTapZoom;

  @override
  int get hashCode => Object.hash(mode, preloadCount, tapToTurn, doubleTapZoom);

  @override
  String toString() =>
      'ReaderSettings(${mode.name}, preload: $preloadCount, '
      'tap: $tapToTurn, doubleTapZoom: $doubleTapZoom)';
}
