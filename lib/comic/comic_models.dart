/// 漫画模块的纯领域模型——不依赖 drift，也不认识壳。
///
/// 复合主键取 {id, sourceName}：同一部漫画从不同来源打开时是两条独立记录，
/// 与 `core/db.dart` 的 `{id, mediaType, sourceName}` 逐维对齐（mediaType 恒为 comic）。
library;

/// 源内引用：漫画模块内部的权威主键。
class ComicRef {
  final String id;
  final String sourceName;

  const ComicRef({required this.id, required this.sourceName});

  /// 本地漫画固定使用的来源名（导入本地文件夹时）。
  static const String localSource = 'local';

  factory ComicRef.local(String folderId) =>
      ComicRef(id: folderId, sourceName: localSource);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicRef && other.id == id && other.sourceName == sourceName;

  @override
  int get hashCode => Object.hash(id, sourceName);

  @override
  String toString() => '$sourceName:$id';
}

/// 收藏写入用的展示元数据（标题/封面由来源提供，模块不解析）。
class ComicMeta {
  final String title;
  final String? coverUrl;

  const ComicMeta({required this.title, this.coverUrl});
}

/// 收藏记录（内部权威库的一行）。
class ComicCollectEntry {
  final ComicRef ref;
  final String title;
  final String? coverUrl;

  /// 模块私有 JSON（如源规则快照）；投影 payload 由投影函数另行生成。
  final String payload;
  final DateTime collectedAt;

  const ComicCollectEntry({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.payload,
    required this.collectedAt,
  });
}

/// 阅读记录（内部权威库的一行）。
///
/// 进度以"页"为单位（漫画没有时长/秒），章节 id 仅作展示辅助。
class ComicReadEntry {
  final ComicRef ref;
  final String title;
  final String? coverUrl;
  final String chapterId;
  final int page;
  final int pageCount;
  final DateTime openedAt;

  const ComicReadEntry({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.chapterId,
    required this.page,
    required this.pageCount,
    required this.openedAt,
  });
}

/// 稍后阅读记录（内部权威库的一行）。
///
/// 与收藏分离：不参与 core 投影，仅作为主页「稍后阅读」卡片的待读队列。
class ComicReadLaterEntry {
  final ComicRef ref;
  final String title;
  final String? coverUrl;
  final String detailUrl;
  final String payload;
  final DateTime addedAt;

  const ComicReadLaterEntry({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.detailUrl,
    required this.payload,
    required this.addedAt,
  });
}

/// 本地漫画元数据（导入本地文件夹作为漫画时留底）。
class ComicLocalEntry {
  final ComicRef ref;
  final String title;
  final String folderPath;
  final String? coverPath;
  final int pageCount;

  /// 模块私有 JSON；core 投影不解析它。
  final String payload;
  final DateTime importedAt;

  const ComicLocalEntry({
    required this.ref,
    required this.title,
    required this.folderPath,
    required this.coverPath,
    required this.pageCount,
    required this.payload,
    required this.importedAt,
  });
}
