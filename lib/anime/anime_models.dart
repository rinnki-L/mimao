/// 番剧模块的纯领域模型——不依赖 drift，也不认识壳。
///
/// 复合主键取 {id, sourceName}：同一部作品从不同规则源打开时是两条独立记录，
/// 与 `core/db.dart` 的 `{id, mediaType, sourceName}` 逐维对齐（mediaType 恒为 anime）。
library;

/// 源内引用：番剧模块内部的权威主键。
class AnimeRef {
  final String id;
  final String sourceName;

  const AnimeRef({required this.id, required this.sourceName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimeRef && other.id == id && other.sourceName == sourceName;

  @override
  int get hashCode => Object.hash(id, sourceName);

  @override
  String toString() => '$sourceName:$id';
}

/// 收藏读写用的展示元数据（标题/封面由来源提供，模块不解析）。
class AnimeMeta {
  final String title;
  final String? coverUrl;

  const AnimeMeta({required this.title, this.coverUrl});
}

/// 收藏记录（内部权威库的一行）。
class AnimeCollectEntry {
  final AnimeRef ref;
  final String title;
  final String? coverUrl;

  /// 模块私有 JSON（如规则包快照）；core 投影的 payload 由投影函数另行生成。
  final String payload;
  final DateTime collectedAt;

  const AnimeCollectEntry({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.payload,
    required this.collectedAt,
  });
}

/// 观看记录（内部权威库的一行）。
class AnimeWatchEntry {
  final AnimeRef ref;
  final String title;
  final String? coverUrl;
  final int episode;
  final int positionSec;
  final int durationSec;
  final DateTime openedAt;

  const AnimeWatchEntry({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.episode,
    required this.positionSec,
    required this.durationSec,
    required this.openedAt,
  });
}
