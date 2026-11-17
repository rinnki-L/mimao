// 漫画阅读器的纯领域模型——不依赖 drift，也不认识壳。
//
// 只描述"读什么、读到哪"，不碰源引擎/网络/搜索/详情页；这些由 A′ 线在联调时
// 把章节图片地址映射进来。权威主键复用 comic_models.dart 的 ComicRef，
// 与 core/db.dart 的 {id, mediaType, sourceName} 逐维对齐（mediaType 恒为 comic）。
library;

import 'dart:convert';

/// 一章：标题 + 该章的图片地址列表。
///
/// 地址可以是本地文件路径，也可以是 http(s) URL——具体如何取字节由
/// [ImageByteLoader](reader_cache.dart) 决定，模型本身不解释。
class ComicChapter {
  final String title;
  final List<String> imageUrls;

  const ComicChapter({required this.title, required this.imageUrls});

  int get pageCount => imageUrls.length;
}

/// 两种阅读手势模式。
///
/// - [paged]：左右翻页，一次显示一页；
/// - [continuous]：上下连续滚动，整章图片纵列排布。
enum ReadingMode { paged, continuous }

/// 模块私有 JSON：core 与壳都不解释它（architecture.md §3.1 规则④）。
///
/// chapter/page 都是 1 起的展示号，与 progressText 里的数字一致。
String readerProgressPayload({required int chapter, required int page}) =>
    jsonEncode(<String, int>{'chapter': chapter, 'page': page});

/// progressText 由模块写，壳只读不解析。
String readerProgressText({
  required int chapter,
  required int page,
  required int pageCount,
}) {
  if (chapter <= 0) return '尚未阅读';
  if (pageCount > 0 && page > 0) {
    return '第 $chapter 章 · 第 $page/$pageCount 页';
  }
  return '读到第 $chapter 章';
}
