// 下载任务单测：状态机合法/非法转移与进度计算（本轮无真实下载器）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/download.dart';

void main() {
  const ref = AnimeRef(id: 'kazumi:1001', sourceName: '樱花动漫');
  final machine = DownloadStateMachine();
  final t0 = DateTime(2026, 11, 17, 12);

  DownloadTask task({
    String taskId = 'task-1',
    int episode = 5,
    DownloadStatus status = DownloadStatus.pending,
  }) => DownloadTask(
    taskId: taskId,
    ref: ref,
    episode: episode,
    status: status,
    updatedAt: t0,
  );

  test('合法链路 pending → running → done，done 收满字节', () {
    final running = machine.transition(
      task(),
      DownloadStatus.running,
      receivedBytes: 10,
      totalBytes: 100,
      now: DateTime(2026, 11, 17, 12, 1),
    );
    expect(running.status, DownloadStatus.running);
    expect(running.progress, 0.1);
    expect(running.error, isNull);

    final done = machine.transition(
      running,
      DownloadStatus.done,
      now: DateTime(2026, 11, 17, 12, 2),
    );
    expect(done.status, DownloadStatus.done);
    expect(done.receivedBytes, 100);
    expect(done.progress, 1);
    expect(done.updatedAt, DateTime(2026, 11, 17, 12, 2));
  });

  test('失败与重试链路 running → failed → pending，错误字段随之清理/保留', () {
    final running = machine.transition(task(), DownloadStatus.running);
    final failed = machine.transition(
      running,
      DownloadStatus.failed,
      error: '网络中断',
    );
    expect(failed.status, DownloadStatus.failed);
    expect(failed.error, '网络中断');

    final retried = machine.transition(failed, DownloadStatus.pending);
    expect(retried.status, DownloadStatus.pending);
    expect(retried.error, isNull);

    final rerunning = machine.transition(retried, DownloadStatus.running);
    expect(rerunning.status, DownloadStatus.running);
    expect(rerunning.error, isNull);
  });

  test('非法转移一律抛 InvalidDownloadTransition', () {
    expect(
      () => machine.transition(task(), DownloadStatus.done),
      throwsA(isA<InvalidDownloadTransition>()),
    );
    expect(
      () => machine.transition(task(), DownloadStatus.failed),
      throwsA(isA<InvalidDownloadTransition>()),
    );

    final done = task(status: DownloadStatus.done);
    expect(
      () => machine.transition(done, DownloadStatus.running),
      throwsA(isA<InvalidDownloadTransition>()),
    );

    final failed = task(status: DownloadStatus.failed);
    expect(
      () => machine.transition(failed, DownloadStatus.done),
      throwsA(isA<InvalidDownloadTransition>()),
    );

    final running = task(status: DownloadStatus.running);
    expect(
      () => machine.transition(running, DownloadStatus.running),
      throwsA(isA<InvalidDownloadTransition>()),
    );
    expect(
      DownloadStateMachine.canTransition(
        DownloadStatus.pending,
        DownloadStatus.done,
      ),
      isFalse,
    );
  });

  test('progress 边界：总大小未知为 0，超界收拢到 0..1', () {
    expect(task().progress, 0);

    final over = DownloadTask(
      taskId: 'over',
      ref: ref,
      episode: 1,
      status: DownloadStatus.running,
      receivedBytes: 200,
      totalBytes: 100,
      updatedAt: t0,
    );
    expect(over.progress, 1);

    final negative = DownloadTask(
      taskId: 'negative',
      ref: ref,
      episode: 1,
      status: DownloadStatus.running,
      receivedBytes: -10,
      totalBytes: 100,
      updatedAt: t0,
    );
    expect(negative.progress, 0);
  });
}
