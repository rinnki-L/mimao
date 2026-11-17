import 'comic_models.dart';

/// 下载任务状态。本轮只有状态机与数据模型，真实下载器不实现
/// （避免与阅读器/网络层争抢文件句柄）。
enum ComicDownloadStatus { pending, running, done, failed }

/// 一个章节（或整本）的漫画下载任务（数据模型）。
class ComicDownloadTask {
  final String taskId;
  final ComicRef ref;
  final String chapterId;
  final ComicDownloadStatus status;
  final int receivedBytes;
  final int totalBytes;

  /// 仅 failed 时有值。
  final String? error;
  final DateTime updatedAt;

  const ComicDownloadTask({
    required this.taskId,
    required this.ref,
    required this.chapterId,
    required this.status,
    required this.updatedAt,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  /// 0..1；总大小未知时为 0。
  double get progress {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0, 1).toDouble();
  }

  @override
  String toString() =>
      'ComicDownloadTask($taskId, ${ref.toString()} ch$chapterId, $status)';
}

/// 非法状态转移（如 pending → done、done → running）。
class InvalidDownloadTransition implements Exception {
  final ComicDownloadStatus from;
  final ComicDownloadStatus to;

  const InvalidDownloadTransition(this.from, this.to);

  @override
  String toString() => '非法下载状态转移：${from.name} → ${to.name}（终态/跳步均不允许）';
}

/// 下载状态机：pending → running → done/failed；failed 可重试回 pending。
///
/// done 是唯一终态；没有取消态（取消直接删任务，不引入第五个状态）。
class ComicDownloadStateMachine {
  static const Map<ComicDownloadStatus, Set<ComicDownloadStatus>> allowed = {
    ComicDownloadStatus.pending: {ComicDownloadStatus.running},
    ComicDownloadStatus.running: {
      ComicDownloadStatus.done,
      ComicDownloadStatus.failed,
    },
    ComicDownloadStatus.done: <ComicDownloadStatus>{},
    ComicDownloadStatus.failed: {ComicDownloadStatus.pending},
  };

  static bool canTransition(ComicDownloadStatus from, ComicDownloadStatus to) =>
      allowed[from]?.contains(to) ?? false;

  /// 执行一次转移并返回新任务；非法转移抛 [InvalidDownloadTransition]。
  ComicDownloadTask transition(
    ComicDownloadTask task,
    ComicDownloadStatus to, {
    int? receivedBytes,
    int? totalBytes,
    String? error,
    DateTime? now,
  }) {
    if (!canTransition(task.status, to)) {
      throw InvalidDownloadTransition(task.status, to);
    }
    final total = totalBytes ?? task.totalBytes;
    final received = switch (to) {
      ComicDownloadStatus.done => total,
      _ => receivedBytes ?? task.receivedBytes,
    };
    return ComicDownloadTask(
      taskId: task.taskId,
      ref: task.ref,
      chapterId: task.chapterId,
      status: to,
      receivedBytes: received,
      totalBytes: total,
      error: to == ComicDownloadStatus.failed
          ? (error ?? task.error ?? '下载失败')
          : null,
      updatedAt: now ?? DateTime.now(),
    );
  }
}
