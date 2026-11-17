// 阅读进度的**持久化点**：B′ 只保留 ProgressRecorder 窄接口，唯一生产实现
// [ComicLibraryProgressRecorder] 委托 C′ 权威写入口 ComicHistoryService.saveProgress
// ——它先写内部 `comic_history`，同函数内经 syncComicProjection 投影（双记账）。
//
// 收敛说明（closure-02 §2，docs/comic-integration-decisions.md 决策①②③）：
//   ① payload 统一为 `{chapterId, page, pageCount}`（chapterId = 源稳定 epId）；
//   ② progressText 统一由 `comicProgressText` 生成（B′ 旧的
//      syncComicProgress / readerProgressPayload / readerProgressText 已删除）；
//   ③ 翻页/切章每次都写（本地库亚毫秒级，不节流）；
//   ④ 校正点在打开动作：ComicHistoryService.open(ref)（由集成层接线）。

import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/history_service.dart';

/// 一次进度持久化事件的运行时值（controller → recorder）。
class ReadingProgress {
  /// 章节在阅读器里的位置（1 起展示号，非稳定 id）。
  final int chapter;

  /// 当前章的稳定 epId；本地/测试章节可为空串。
  final String chapterId;
  final String chapterTitle;
  final int page;
  final int pageCount;

  const ReadingProgress({
    required this.chapter,
    this.chapterId = '',
    required this.chapterTitle,
    required this.page,
    required this.pageCount,
  });
}

/// controller 与持久化层之间的窄接口：单测注入假实现即可，不碰数据库。
abstract interface class ProgressRecorder {
  Future<void> persist(ReadingProgress progress);
}

/// [ProgressRecorder] 的唯一生产实现：把 [ReadingProgress] 适配到 C′ 权威
/// 写入口 [ComicHistoryService.saveProgress]。自身不持有存储、不写 core 投影
/// ——两笔账（内部库 + 投影）都在 saveProgress 的同一次调用里完成，收藏的
/// starred/coverUrl/createdAt 由投影函数从内部权威行自动保留。
class ComicLibraryProgressRecorder implements ProgressRecorder {
  ComicLibraryProgressRecorder({
    required this.history,
    required this.ref,
    required this.title,
    this.coverUrl,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final ComicHistoryService history;
  final ComicRef ref;
  final String title;
  final String? coverUrl;
  final DateTime Function() now;

  @override
  Future<void> persist(ReadingProgress progress) => history.saveProgress(
    ref,
    title: title,
    coverUrl: coverUrl,
    chapterId: progress.chapterId,
    page: progress.page,
    pageCount: progress.pageCount,
    openedAt: now(),
  );
}
