// 漫画阅读器的纯领域模型——不依赖 drift，也不认识壳。
//
// 只描述"读什么、读到哪"，不碰源引擎/网络/搜索/详情页；章节图片地址与稳定
// chapterId 由集成层（A′ 适配器 / comic_entry）映射进来。权威主键复用
// comic_models.dart 的 ComicRef，与 core/db.dart 的 {id, mediaType, sourceName}
// 逐维对齐（mediaType 恒为 comic）。
library;

/// 取一张图所需的完整信息：地址 + 可选的请求头（防盗链 / Cookie / UA）。
///
/// 旧契约 [ComicChapter.imageUrls] 只是纯地址串；生产环境里不少站点按
/// Referer / Cookie 防盗链，单靠地址拿不到图。[ImageRequest] 把"地址 + 头"
/// 绑在一起，交给新的 [ImageRequestLoader](reader_image_loader.dart) 取字节。
/// 测试与本地章节的头为空，走默认加载器即可。
class ImageRequest {
  const ImageRequest({
    required this.url,
    this.referer,
    this.headers = const <String, String>{},
  });

  /// 按站点 Referer 构造（防盗链常用：图片 URL 同源根）。
  factory ImageRequest.withReferer({required String url, String? referer}) =>
      ImageRequest(url: url, referer: referer);

  final String url;

  /// 可选的 Referer（防盗链常用）。null = 由加载器按站点推导。
  final String? referer;

  /// 额外请求头（如站点要求的自定义头）。大小写不敏感由底层处理。
  final Map<String, String> headers;

  /// 缓存身份：地址 + 头都参与，避免同一地址不同头时串图。
  /// 无头时退化为纯地址，与旧 [cacheKey](reader_cache.dart) 契约一致。
  String get cacheIdentity {
    if (referer == null && headers.isEmpty) return url;
    final buffer = StringBuffer(url)..write('|r=${referer ?? ''}');
    final keys = headers.keys.toList()..sort();
    for (final key in keys) {
      buffer
        ..write('|')
        ..write(key)
        ..write('=')
        ..write(headers[key]);
    }
    return buffer.toString();
  }
}

/// 一章：标题 + 稳定章节 id + 该章的图片地址列表。
///
/// [chapterId] 是源的稳定 epId（插入新章不会让进度错位），持久化进
/// `comic_history.chapterId`；测试用内存章节可留空（默认 `''`）。
/// 地址可以是本地文件路径，也可以是 http(s) URL——具体如何取字节由
/// [ImageRequestLoader](reader_image_loader.dart) 决定，模型本身不解释。
class ComicChapter {
  final String title;

  /// 稳定章节 id（源内 epId）；本地/测试章节可为空串。
  final String chapterId;
  final List<String> imageUrls;

  /// 与 [imageUrls] 逐张对齐的可选请求头；缺省为空（走默认加载器）。
  /// 生产由源引擎注入（每张图的 Referer / Cookie），测试可忽略。
  final List<ImageRequest> imageRequests;

  const ComicChapter({
    required this.title,
    this.chapterId = '',
    required this.imageUrls,
    this.imageRequests = const <ImageRequest>[],
  });

  int get pageCount => imageUrls.length;

  /// 第 [index] 张图的请求信息：优先用注入的 [imageRequests]，否则用纯地址。
  ImageRequest requestAt(int index) => index < imageRequests.length
      ? imageRequests[index]
      : ImageRequest(url: imageUrls[index]);
}

/// 两种阅读手势模式（历史契约，保留给旧的 [ComicReaderPage.initialMode]）。
///
/// - [paged]：左右翻页，一次显示一页；
/// - [continuous]：上下连续滚动，整章图片纵列排布。
///
/// 更细的七种模式见 [ReaderViewMode](reader_view_mode.dart)；本枚举作为兼容层。
enum ReadingMode { paged, continuous }
