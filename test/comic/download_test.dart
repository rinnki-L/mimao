// 下载任务单测：状态机合法/非法转移、进度计算；仓储落库与重试；无真实下载器。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/download.dart';
import 'package:mimao/comic/download_store.dart';

import 'comic_test_env.dart';

void main() {
  const ref = ComicRef(id: 'venera:1001', sourceName: '漫画源');
  final machine = ComicDownloadStateMachine();
  final t0 = DateTime(2026, 11, 17, 12);

  ComicDownloadTask task({
    String taskId = 'task-1',
    String chapterId = 'ch5',
    ComicDownloadStatus status = ComicDownloadStatus.pending,
  }) => ComicDownloadTask(
    taskId: taskId,
    ref: ref,
    chapterId: chapterId,
    status: status,
    updatedAt: t0,
  );

  group('状态机', () {
    test('合法链路 pending → running → done，done 收满字节', () {
      final running = machine.transition(
        task(),
        ComicDownloadStatus.running,
        receivedBytes: 10,
        totalBytes: 100,
        now: DateTime(2026, 11, 17, 12, 1),
      );
      expect(running.status, ComicDownloadStatus.running);
      expect(running.progress, 0.1);
      expect(running.error, isNull);

      final done = machine.transition(
        running,
        ComicDownloadStatus.done,
        now: DateTime(2026, 11, 17, 12, 2),
      );
      expect(done.status, ComicDownloadStatus.done);
      expect(done.receivedBytes, 100);
      expect(done.progress, 1);
      expect(done.updatedAt, DateTime(2026, 11, 17, 12, 2));
    });

    test('失败与重试链路 running → failed → pending，错误字段随之清理/保留', () {
      final running = machine.transition(task(), ComicDownloadStatus.running);
      final failed = machine.transition(
        running,
        ComicDownloadStatus.failed,
        error: '网络中断',
      );
      expect(failed.status, ComicDownloadStatus.failed);
      expect(failed.error, '网络中断');

      final retried = machine.transition(failed, ComicDownloadStatus.pending);
      expect(retried.status, ComicDownloadStatus.pending);
      expect(retried.error, isNull);

      final rerunning = machine.transition(
        retried,
        ComicDownloadStatus.running,
      );
      expect(rerunning.status, ComicDownloadStatus.running);
      expect(rerunning.error, isNull);
    });

    test('非法转移一律抛 InvalidDownloadTransition', () {
      expect(
        () => machine.transition(task(), ComicDownloadStatus.done),
        throwsA(isA<InvalidDownloadTransition>()),
      );
      expect(
        () => machine.transition(task(), ComicDownloadStatus.failed),
        throwsA(isA<InvalidDownloadTransition>()),
      );

      final done = task(status: ComicDownloadStatus.done);
      expect(
        () => machine.transition(done, ComicDownloadStatus.running),
        throwsA(isA<InvalidDownloadTransition>()),
      );

      final failed = task(status: ComicDownloadStatus.failed);
      expect(
        () => machine.transition(failed, ComicDownloadStatus.done),
        throwsA(isA<InvalidDownloadTransition>()),
      );

      final running = task(status: ComicDownloadStatus.running);
      expect(
        () => machine.transition(running, ComicDownloadStatus.running),
        throwsA(isA<InvalidDownloadTransition>()),
      );
      expect(
        ComicDownloadStateMachine.canTransition(
          ComicDownloadStatus.pending,
          ComicDownloadStatus.done,
        ),
        isFalse,
      );
    });

    test('progress 边界：总大小未知为 0，超界收拢到 0..1', () {
      expect(task().progress, 0);

      final over = ComicDownloadTask(
        taskId: 'over',
        ref: ref,
        chapterId: 'ch1',
        status: ComicDownloadStatus.running,
        receivedBytes: 200,
        totalBytes: 100,
        updatedAt: t0,
      );
      expect(over.progress, 1);

      final negative = ComicDownloadTask(
        taskId: 'negative',
        ref: ref,
        chapterId: 'ch1',
        status: ComicDownloadStatus.running,
        receivedBytes: -10,
        totalBytes: 100,
        updatedAt: t0,
      );
      expect(negative.progress, 0);
    });
  });

  group('仓储', () {
    late ComicTestEnv env;
    late ComicDownloadStore store;

    setUp(() {
      env = ComicTestEnv.create();
      store = ComicDownloadStore(env.comicDb);
    });

    tearDown(() => env.close());

    test('enqueue 与 transition 落库：pending → running → done', () async {
      await store.enqueue(task(), now: t0);
      expect((await store.find('task-1'))!.status, ComicDownloadStatus.pending);

      await store.transition(
        'task-1',
        ComicDownloadStatus.running,
        totalBytes: 100,
        receivedBytes: 30,
        now: DateTime(2026, 11, 17, 12, 1),
      );
      final running = (await store.find('task-1'))!;
      expect(running.status, ComicDownloadStatus.running);
      expect(running.progress, 0.3);

      await store.transition(
        'task-1',
        ComicDownloadStatus.done,
        now: DateTime(2026, 11, 17, 12, 2),
      );
      final done = (await store.find('task-1'))!;
      expect(done.status, ComicDownloadStatus.done);
      expect(done.receivedBytes, 100);
    });

    test('failed 重试回 pending 落库，非法转移不改库', () async {
      await store.enqueue(task(), now: t0);
      await store.transition(
        'task-1',
        ComicDownloadStatus.running,
        now: DateTime(2026, 11, 17, 12, 1),
      );
      await store.transition(
        'task-1',
        ComicDownloadStatus.failed,
        error: '磁盘满',
        now: DateTime(2026, 11, 17, 12, 2),
      );
      expect((await store.find('task-1'))!.error, '磁盘满');

      // 非法转移抛错且库中状态保持 failed。
      expect(
        () => store.transition('task-1', ComicDownloadStatus.done),
        throwsA(isA<InvalidDownloadTransition>()),
      );
      expect((await store.find('task-1'))!.status, ComicDownloadStatus.failed);

      await store.transition(
        'task-1',
        ComicDownloadStatus.pending,
        now: DateTime(2026, 11, 17, 12, 3),
      );
      final retried = (await store.find('task-1'))!;
      expect(retried.status, ComicDownloadStatus.pending);
      expect(retried.error, isNull);
    });

    test('下载任务无 core 书架投影', () async {
      await store.enqueue(task(), now: t0);
      expect(await env.library.timeline(), isEmpty);
    });
  });
}
