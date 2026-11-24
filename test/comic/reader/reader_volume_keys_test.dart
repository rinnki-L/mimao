// 音量键翻页控制器：串行化启用/释放、代次校验、翻页失败落切章。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_volume_keys.dart';

/// 可控租约：手动决定激活成功/失败、记录释放次数。
class _Lease implements ReaderVolumeConnection {
  _Lease(this.onEvent);

  final void Function(Object?) onEvent;
  final Completer<void> _ready = Completer<void>();
  int closes = 0;
  bool released = false;

  void activate() {
    if (!_ready.isCompleted) _ready.complete();
  }

  void fail() {
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('activation failed'));
    }
  }

  @override
  Future<void> get ready => _ready.future;

  @override
  Future<void> closeAndWait() async {
    closes++;
    released = true;
  }
}

class _Harness {
  final List<_Lease> leases = <_Lease>[];
  final List<String> actions = <String>[];
  final List<Object> errors = <Object>[];
  int pageIndex = 1;
  int chapter = 1;

  late final ReaderVolumeController controller = ReaderVolumeController(
    nextPage: () {
      if (pageIndex >= 3) return false;
      pageIndex++;
      actions.add('nextPage');
      return true;
    },
    previousPage: () {
      if (pageIndex <= 1) return false;
      pageIndex--;
      actions.add('prevPage');
      return true;
    },
    nextChapter: () {
      chapter++;
      pageIndex = 1;
      actions.add('nextChapter');
    },
    previousChapter: () {
      chapter--;
      pageIndex = 3;
      actions.add('prevChapter');
    },
    onError: (error, _) => errors.add(error),
    connect: (onEvent) {
      final lease = _Lease(onEvent);
      leases.add(lease);
      return lease;
    },
  );
}

void main() {
  test('启用后翻页；到章尾时切下一章', () async {
    final harness = _Harness();
    final enabling = harness.controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    harness.leases.single.activate();
    await enabling;

    harness.leases.single.onEvent(2);
    expect(harness.pageIndex, 2);
    harness.leases.single.onEvent(2);
    expect(harness.pageIndex, 3);
    harness.leases.single.onEvent(2);
    expect(harness.actions, contains('nextChapter'));
    expect(harness.chapter, 2);

    await harness.controller.dispose();
  });

  test('章首按上一页回上一章末页', () async {
    final harness = _Harness();
    final enabling = harness.controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    harness.leases.single.activate();
    await enabling;

    harness.leases.single.onEvent(1);
    expect(harness.actions, contains('prevChapter'));
    expect(harness.chapter, 0);
    await harness.controller.dispose();
  });

  test('停用后释放租约，再启用会重新连接', () async {
    final harness = _Harness();
    var enabling = harness.controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    harness.leases.single.activate();
    await enabling;

    final disabling = harness.controller.setEnabled(false);
    await Future<void>.delayed(Duration.zero);
    await disabling;
    expect(harness.leases.single.released, isTrue);

    enabling = harness.controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    harness.leases.last.activate();
    await enabling;
    expect(harness.leases, hasLength(2));

    await harness.controller.dispose();
  });

  test('激活失败上报错误并释放，不残留租约', () async {
    final harness = _Harness();
    final enabling = harness.controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    harness.leases.single.fail();
    await expectLater(enabling, throwsA(isA<StateError>()));
    expect(harness.leases.single.released, isTrue);
    expect(harness.errors, isNotEmpty);
    await harness.controller.dispose();
  });

  test('释放后迟到的事件不再翻页', () async {
    final harness = _Harness();
    final enabling = harness.controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    final lease = harness.leases.single;
    lease.activate();
    await enabling;

    final disabling = harness.controller.setEnabled(false);
    await Future<void>.delayed(Duration.zero);
    await disabling;

    lease.onEvent(2);
    expect(harness.actions, isEmpty, reason: '已释放的租约不接受事件');
    await harness.controller.dispose();
  });

  test('dispose 幂等且释放租约', () async {
    final harness = _Harness();
    final enabling = harness.controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    harness.leases.single.activate();
    await enabling;

    final first = harness.controller.dispose();
    final second = harness.controller.dispose();
    expect(identical(first, second), isTrue);
    await first;
    expect(harness.leases.single.released, isTrue);
  });
}
