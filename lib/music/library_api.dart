/// 本地库门面（C 线实现：MusicDb + 三服务）。
///
/// 为什么用接口而不是直接暴露服务类：C 线的 drift 库/服务文件在并行期
/// 不存在，入口与页面若直接依赖具体类就编译不过。接口放契约层，三条线
/// 都能在对方未落地时独立编译。
library;

import 'package:mimao/music/models/music_models.dart';

/// 收藏门面（权威库 `music_collect`，写后投影 core）。
abstract interface class MusicCollectApi {
  Future<void> collect(MusicSong song);

  Future<void> remove(String songId);

  Future<bool> isCollected(String songId);

  /// 批量判断（列表一次性预载，避免逐行查询）。
  Future<Set<String>> collectedIds();
}

/// 一条播放历史（含可重建的曲目快照）。
class MusicHistoryItem {
  const MusicHistoryItem({
    required this.song,
    required this.position,
    required this.duration,
    required this.openedAt,
  });

  final MusicSong song;
  final Duration position;
  final Duration duration;
  final DateTime openedAt;
}

/// 历史门面（权威库 `music_history`，持久化点/打开点投影 core）。
abstract interface class MusicHistoryApi {
  /// 打开点校正：历史行不存在时不建行、不写投影。
  Future<void> open(MusicSong song);

  /// 持久化点：写内部行（含播放次数）并同步投影。
  Future<void> saveProgress(
    MusicSong song,
    Duration position,
    Duration duration,
  );

  Future<MusicHistoryItem?> latest(String songId);

  Future<List<MusicHistoryItem>> recent({int limit = 50});
}

/// 搜索历史门面。
abstract interface class MusicSearchHistoryApi {
  Future<void> record(String keyword);

  Future<List<String>> recent({int limit = 20});

  Future<void> clear();
}
