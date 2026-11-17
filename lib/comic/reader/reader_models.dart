// 漫画阅读器的纯领域模型——不依赖 drift，也不认识壳。
//
// 只描述"读什么、读到哪"，不碰源引擎/网络/搜索/详情页；章节图片地址与稳定
// chapterId 由集成层（A′ 适配器 / comic_entry）映射进来。权威主键复用
// comic_models.dart 的 ComicRef，与 core/db.dart 的 {id, mediaType, sourceName}
// 逐维对齐（mediaType 恒为 comic）。
library;

/// 一章：标题 + 稳定章节 id + 该章的图片地址列表。
///
/// [chapterId] 是源的稳定 epId（插入新章不会让进度错位），持久化进
/// `comic_history.chapterId`；测试用内存章节可留空（默认 `''`）。
/// 地址可以是本地文件路径，也可以是 http(s) URL——具体如何取字节由
/// [ImageByteLoader](reader_cache.dart) 决定，模型本身不解释。
class ComicChapter {
  final String title;

  /// 稳定章节 id（源内 epId）；本地/测试章节可为空串。
  final String chapterId;
  final List<String> imageUrls;

  const ComicChapter({
    required this.title,
    this.chapterId = '',
    required this.imageUrls,
  });

  int get pageCount => imageUrls.length;
}

/// 两种阅读手势模式。
///
/// - [paged]：左右翻页，一次显示一页；
/// - [continuous]：上下连续滚动，整章图片纵列排布。
enum ReadingMode { paged, continuous }
