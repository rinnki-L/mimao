// 播放器进度写入口：B 线只保留窄接口 + 适配器，不再自带权威存储。
//
// 收敛说明（docs/anime-dual-ledger.md §5 已更新）：
//   ① 权威 = 番剧模块内部库 `anime_history`（`AnimeHistoryService.saveProgress`）；
//   ② 写入点 = [AnimeHistoryProgressRecorder.persist]——它把播放器的运行时值
//      翻译成 `AnimeHistoryService.saveProgress` 调用，后者在同一个函数内先写
//      内部权威行，紧接着经 `syncAnimeProjection` 写 core 投影；
//   ③ 校正点 = 打开详情/播放器时 `AnimeHistoryService.open`（本文件不负责）；
//   ④ 展示 = 壳只读 `progressText`，由 `animeProgressText` 统一生成。
//
// 这里刻意不出现内存/JSON store、不直接调 `LibraryRepository.upsert`，
// 以保证同一 `{id, sourceName}` 只有一条权威路径可写。
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/history_service.dart';

/// 一次进度持久化事件的运行时值（controller → recorder）。
class EpisodeProgress {
  /// 集号（1 起的展示号，不是列表下标）。
  final int episode;
  final String episodeTitle;
  final Duration position;
  final Duration total;

  const EpisodeProgress({
    required this.episode,
    required this.episodeTitle,
    required this.position,
    required this.total,
  });
}

/// controller 与持久化层之间的窄接口：单测注入假实现即可，不碰数据库。
abstract interface class ProgressRecorder {
  Future<void> persist(EpisodeProgress progress);
}

/// 播放器进度的唯一写入实现：把 [EpisodeProgress] 适配到 C 线权威写入口
/// [AnimeHistoryService.saveProgress]。
///
/// 自身不持有任何存储，也不写 core 投影——两笔账都由 `saveProgress` 在同一次
/// 调用里完成。payload 因此固定为 `{episode, positionSec, durationSec}`，
/// 文案固定由 `animeProgressText` 生成，与收藏/历史写入口完全一致。
class AnimeHistoryProgressRecorder implements ProgressRecorder {
  AnimeHistoryProgressRecorder({
    required this.history,
    required this.entryId,
    required this.sourceName,
    required this.title,
    this.coverUrl,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final AnimeHistoryService history;
  final String entryId;
  final String sourceName;
  final String title;
  final String? coverUrl;
  final DateTime Function() now;

  @override
  Future<void> persist(EpisodeProgress progress) => history.saveProgress(
    AnimeRef(id: entryId, sourceName: sourceName),
    title: title,
    coverUrl: coverUrl,
    episode: progress.episode,
    positionSec: progress.position.inSeconds,
    durationSec: progress.total.inSeconds,
    openedAt: now(),
  );
}
