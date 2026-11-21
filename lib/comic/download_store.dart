import 'package:drift/drift.dart';

import 'comic_db.dart';
import 'comic_models.dart';
import 'download.dart';

/// 下载任务的持久化仓储：只写模块内部 `comic_download_task` 表。
///
/// 本轮没有真实下载器；状态转移仍统一经过 [ComicDownloadStateMachine]，
/// 这里只负责把状态机产出的任务落库/读取。下载任务不是书架条目，无 core 投影。
class ComicDownloadStore {
  final ComicDb db;
  final ComicDownloadStateMachine _machine = ComicDownloadStateMachine();

  ComicDownloadStore(this.db);

  /// 新建 pending 任务。
  Future<ComicDownloadTask> enqueue(
    ComicDownloadTask task, {
    DateTime? now,
  }) async {
    if (task.status != ComicDownloadStatus.pending) {
      throw ArgumentError('新任务必须从 pending 开始');
    }
    await _write(task, now: now);
    return task;
  }

  /// 经过状态机转移并落库；合法转移返回新任务，非法转移抛
  /// [InvalidDownloadTransition] 且不改库。
  Future<ComicDownloadTask> transition(
    String taskId,
    ComicDownloadStatus to, {
    int? receivedBytes,
    int? totalBytes,
    String? error,
    DateTime? now,
  }) async {
    final current = await find(taskId);
    if (current == null) {
      throw ArgumentError('任务不存在：$taskId');
    }
    final next = _machine.transition(
      current,
      to,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      error: error,
      now: now,
    );
    await _write(next, now: now);
    return next;
  }

  /// 更新进行中任务的进度，不改状态。
  ///
  /// 进度不是状态转移：`running → running` 在状态机里是非法边，逐页更新若
  /// 走 [transition] 会让多页章节在第二页就失败。这里只改计数与时间戳，
  /// 状态仍由 `transition` 把守。
  Future<ComicDownloadTask> updateProgress(
    String taskId, {
    required int receivedBytes,
    required int totalBytes,
    DateTime? now,
  }) async {
    final current = await find(taskId);
    if (current == null) {
      throw ArgumentError('任务不存在：$taskId');
    }
    final next = ComicDownloadTask(
      taskId: current.taskId,
      ref: current.ref,
      chapterId: current.chapterId,
      status: current.status,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      error: current.error,
      updatedAt: now ?? DateTime.now(),
    );
    await _write(next, now: now);
    return next;
  }

  Future<ComicDownloadTask?> find(String taskId) async {
    final row = await db.downloadRow(taskId);
    return row == null ? null : _fromRow(row);
  }

  Future<List<ComicDownloadTask>> all() async {
    final rows = await (db.select(
      db.comicDownloadTasks,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<void> remove(String taskId) async {
    await (db.delete(
      db.comicDownloadTasks,
    )..where((t) => t.taskId.equals(taskId))).go();
  }

  Future<void> _write(ComicDownloadTask task, {DateTime? now}) async {
    await db
        .into(db.comicDownloadTasks)
        .insertOnConflictUpdate(
          ComicDownloadTasksCompanion.insert(
            taskId: task.taskId,
            id: task.ref.id,
            sourceName: task.ref.sourceName,
            chapterId: Value(task.chapterId),
            status: task.status.name,
            receivedBytes: Value(task.receivedBytes),
            totalBytes: Value(task.totalBytes),
            error: Value(task.error),
            updatedAt: now ?? task.updatedAt,
          ),
        );
  }

  ComicDownloadTask _fromRow(ComicDownloadRow row) => ComicDownloadTask(
    taskId: row.taskId,
    ref: ComicRef(id: row.id, sourceName: row.sourceName),
    chapterId: row.chapterId,
    status: ComicDownloadStatus.values.firstWhere(
      (s) => s.name == row.status,
      orElse: () => ComicDownloadStatus.failed,
    ),
    receivedBytes: row.receivedBytes,
    totalBytes: row.totalBytes,
    error: row.error,
    updatedAt: row.updatedAt,
  );
}
