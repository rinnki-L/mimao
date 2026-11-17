import 'anime_models.dart';

/// 下载任务状态。本轮只有状态机与数据模型，真实下载器不实现
/// （避免与 media_kit 播放器争抢网络/文件句柄）。
enum DownloadStatus { pending, running, done, failed }

/// 一个剧集下载任务（纯内存模型，可被将来的下载器/持久化层复用）。
class DownloadTask {
  final String taskId;
  final AnimeRef ref;
  final int episode;
  final DownloadStatus status;
  final int receivedBytes;
  final int totalBytes;

  /// 仅 failed 时有值。
  final String? error;
  final DateTime updatedAt;

  const DownloadTask({
    required this.taskId,
    required this.ref,
    required this.episode,
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
      'DownloadTask($taskId, ${ref.toString()} ep$episode, $status)';
}

/// 非法状态转移（如 pending → done、done → running）。
class InvalidDownloadTransition implements Exception {
  final DownloadStatus from;
  final DownloadStatus to;

  const InvalidDownloadTransition(this.from, this.to);

  @override
  String toString() => '非法下载状态转移：${from.name} → ${to.name}（终态/跳步均不允许）';
}

/// 下载状态机：pending → running → done/failed；failed 可重试回 pending。
///
/// done 是唯一终态；没有取消态（取消直接删任务，不引入第五个状态）。
class DownloadStateMachine {
  static const Map<DownloadStatus, Set<DownloadStatus>> allowed = {
    DownloadStatus.pending: {DownloadStatus.running},
    DownloadStatus.running: {DownloadStatus.done, DownloadStatus.failed},
    DownloadStatus.done: <DownloadStatus>{},
    DownloadStatus.failed: {DownloadStatus.pending},
  };

  static bool canTransition(DownloadStatus from, DownloadStatus to) =>
      allowed[from]?.contains(to) ?? false;

  /// 执行一次转移并返回新任务；非法转移抛 [InvalidDownloadTransition]。
  DownloadTask transition(
    DownloadTask task,
    DownloadStatus to, {
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
      DownloadStatus.done => total,
      _ => receivedBytes ?? task.receivedBytes,
    };
    return DownloadTask(
      taskId: task.taskId,
      ref: task.ref,
      episode: task.episode,
      status: to,
      receivedBytes: received,
      totalBytes: total,
      error: to == DownloadStatus.failed
          ? (error ?? task.error ?? '下载失败')
          : null,
      updatedAt: now ?? DateTime.now(),
    );
  }
}
