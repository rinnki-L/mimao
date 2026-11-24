// 音量键翻页（Android）。
//
// 移植自 Venera-Next `volume_controller.dart` / `volume.dart` 的租约模型：
// 原生侧按 token 授权/撤销"监听音量键"，Dart 侧串行化启用/释放，避免快速
// 进出阅读器时通道状态错位。
//
// 与上游的差别：本仓不引 `uuid`，token 用进程内自增 + 时间戳；Windows/Linux/
// macOS 没有音量键语义，[isSupported] 为 false，调用直接空操作（桌面已用
// 方向键/滚轮翻页）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// 当前平台是否支持音量键翻页。
bool get supportsVolumeKeys => Platform.isAndroid;

/// 一次原生租约。
abstract interface class ReaderVolumeConnection {
  Future<void> get ready;
  Future<void> closeAndWait();
}

/// 多次失败聚合成一个异常（与上游同口径：释放失败也要暴露）。
class ReaderVolumeFailure implements Exception {
  ReaderVolumeFailure(
    Iterable<({Object error, StackTrace stackTrace})> failures,
  ) : failures = List.unmodifiable(failures);

  final List<({Object error, StackTrace stackTrace})> failures;

  @override
  String toString() => failures.map((failure) => failure.error).join('; ');
}

const MethodChannel _channel = MethodChannel('mimao/volume');

int _tokenSeed = 0;

/// 建立一次监听租约；[onEvent] 收到 1=上一页、2=下一页。
ReaderVolumeConnection connectReaderVolume(void Function(Object?) onEvent) {
  final token = '${DateTime.now().microsecondsSinceEpoch}-${++_tokenSeed}';
  return _VolumeLease(token, onEvent).._start();
}

class _VolumeLease implements ReaderVolumeConnection {
  _VolumeLease(this.token, this.onEvent);

  final String token;
  final void Function(Object?) onEvent;
  final Completer<void> _activation = Completer<void>();
  bool accepting = true;
  bool _released = false;
  Future<void>? _closing;

  @override
  Future<void> get ready => _activation.future;

  void _start() {
    // 激活失败也要保留到 cancel 确认，避免通道里残留 token。
    unawaited(
      _activation.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    _channel
        .invokeMethod<void>('listen', <String, Object?>{'token': token})
        .then<void>(
          (_) {
            if (!_activation.isCompleted) _activation.complete();
          },
          onError: (Object error, StackTrace stack) {
            if (!_activation.isCompleted) {
              _activation.completeError(error, stack);
            }
          },
        );
  }

  @override
  Future<void> closeAndWait() {
    final closing = _closing;
    if (closing != null) return closing;
    accepting = false;
    final future = _release();
    _closing = future;
    return future;
  }

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    try {
      await _channel.invokeMethod<void>('cancel', <String, Object?>{
        'token': token,
      });
    } on MissingPluginException {
      // 非 Android 平台没有该通道：视为已释放。
    } on PlatformException {
      // 原生侧已撤销或从未授权：同样视为已释放。
    }
  }
}

/// 把音量键事件接到翻页上；串行化启用/释放，快速进出阅读器不会错位。
class ReaderVolumeController {
  ReaderVolumeController({
    required this.nextPage,
    required this.previousPage,
    required this.nextChapter,
    required this.previousChapter,
    required this.onError,
    this.onInput,
    this.connect,
  });

  /// 翻页回调：返回 false 表示已在章尾/章首，交给切章。
  final bool Function() nextPage;
  final bool Function() previousPage;
  final void Function() nextChapter;
  final void Function() previousChapter;
  final void Function(Object error, StackTrace stack) onError;

  /// 收到按键时先通知（用于暂停自动阅读）。
  final void Function(bool forward)? onInput;

  /// 可注入的连接工厂（测试用）。
  final ReaderVolumeConnection Function(void Function(Object?) onEvent)?
  connect;

  ReaderVolumeConnection? _connection;
  Future<void> _queue = Future<void>.value();
  Future<void>? _closing;
  bool _enabled = false;
  bool _disposed = false;
  bool _ready = false;
  int _generation = 0;
  int? _connectedGeneration;

  Future<void> setEnabled(bool enabled) {
    if (_disposed) return _closing ?? Future<void>.value();
    if (_enabled != enabled) {
      _enabled = enabled;
      ++_generation;
    }
    return _schedule();
  }

  Future<void> _schedule() {
    final operation = _queue.then((_) async {
      try {
        await _reconcile();
      } on Object catch (error, stack) {
        try {
          onError(error, stack);
        } on Object catch (reportError, reportStack) {
          throw ReaderVolumeFailure(<({Object error, StackTrace stackTrace})>[
            (error: error, stackTrace: stack),
            (error: reportError, stackTrace: reportStack),
          ]);
        }
        rethrow;
      }
    });
    // 只有串行尾吞掉异常，调用方拿到真实结果。
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _release() async {
    final connection = _connection;
    if (connection == null) return;
    _ready = false;
    await connection.closeAndWait();
    _connection = null;
    _connectedGeneration = null;
  }

  Future<void> _reconcile() async {
    if (_connection != null &&
        (!_enabled ||
            _disposed ||
            !_ready ||
            _connectedGeneration != _generation)) {
      await _release();
    }
    if (_disposed || !_enabled || _connection != null) return;
    if (!supportsVolumeKeys && connect == null) return;
    final generation = _generation;
    _connectedGeneration = generation;
    final factory = connect ?? connectReaderVolume;
    final connection = _connection = factory((event) {
      if (!_ready || !_isCurrent(generation)) return;
      try {
        if (event == 1) {
          onInput?.call(false);
          if (!previousPage()) previousChapter();
        } else if (event == 2) {
          onInput?.call(true);
          if (!nextPage()) nextChapter();
        }
      } on Object catch (error, stack) {
        onError(error, stack);
      }
    });
    try {
      await connection.ready;
      _ready = true;
    } on Object catch (error, stack) {
      try {
        await _release();
      } on Object catch (releaseError, releaseStack) {
        throw ReaderVolumeFailure(<({Object error, StackTrace stackTrace})>[
          (error: error, stackTrace: stack),
          (error: releaseError, stackTrace: releaseStack),
        ]);
      }
      rethrow;
    }
    if (!_isCurrent(generation)) await _release();
  }

  bool _isCurrent(int generation) =>
      !_disposed && _enabled && generation == _generation;

  /// 并发 close 共用一个结果；失败保留租约，下次显式 close 只重试释放。
  Future<void> dispose() {
    final closing = _closing;
    if (closing != null) return closing;
    _disposed = true;
    _enabled = false;
    ++_generation;
    final future = _closing = _schedule();
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          _closing = null;
        },
      ),
    );
    return future;
  }
}
