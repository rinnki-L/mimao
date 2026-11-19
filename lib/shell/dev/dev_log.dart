import 'dart:collection';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';

/// app 内错误与关键事件的环形缓冲——dev harness 的「眼睛」之一。
///
/// 动机：agent 开发时只能看到 flutter run 控制台输出，而 app 自己 catch 住的
/// 错误（Widget 构建异常、异步回调异常等）多半被框架或 try/catch 吞掉，控制台
/// 一片干净却功能不正常。这里把最关键的三类错误留档：
///   - flutter：FlutterError.onError 捕获的 widget/框架错误
///   - platform：PlatformDispatcher.onError 捕获的未捕获异步错误
///   - dev：dev harness 自身与 /db 等端点的运行记录
///
/// 环形缓冲定容（[capacity]），内存开销恒定；`flutter run` 下控制台照常
/// 打印——这里只是补一份可经 HTTP 查询的存档，不改变任何原有行为。
final class DevLog {
  DevLog._();

  /// 环形缓冲容量。超出后丢弃最旧条目。
  static const int capacity = 500;

  static final Queue<DevLogEntry> _entries = Queue<DevLogEntry>();

  static FlutterExceptionHandler? _prevFlutterOnError;
  static ErrorCallback? _prevPlatformOnError;
  static bool _installed = false;

  /// 安装错误钩子（幂等）。链式保留原 handler——只补存档，不吞错误。
  static void install() {
    if (_installed) return;
    _installed = true;

    _prevFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      record(
        level: 'error',
        kind: 'flutter',
        message: details.exception.toString(),
        details: details.toString(),
      );
      _prevFlutterOnError?.call(details);
    };

    _prevPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      record(
        level: 'error',
        kind: 'platform',
        message: error.toString(),
        details: stack.toString(),
      );
      final prev = _prevPlatformOnError;
      // 沿用原语义：有人处理过就算已处理，否则交还 zone 的默认路径。
      return prev != null ? prev(error, stack) : false;
    };
  }

  /// 卸载钩子并恢复原 handler（测试用；生产进程不卸载）。
  static void uninstall() {
    if (!_installed) return;
    _installed = false;
    FlutterError.onError = _prevFlutterOnError;
    PlatformDispatcher.instance.onError = _prevPlatformOnError;
    _prevFlutterOnError = null;
    _prevPlatformOnError = null;
  }

  /// 记录一条日志（手动入口，dev 端点与未来关键事件都走这里）。
  static void record({
    required String level,
    required String kind,
    required String message,
    Object? details,
  }) {
    _entries.addLast(
      DevLogEntry(
        ts: DateTime.now(),
        level: level,
        kind: kind,
        message: message,
        details: details?.toString(),
      ),
    );
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  static void info(String kind, String message, {Object? details}) =>
      record(level: 'info', kind: kind, message: message, details: details);

  static void warn(String kind, String message, {Object? details}) =>
      record(level: 'warn', kind: kind, message: message, details: details);

  static void error(String kind, String message, {Object? details}) =>
      record(level: 'error', kind: kind, message: message, details: details);

  /// 按时间正序（最旧在前）返回快照；[limit] 取最新的 N 条，[level] 过滤。
  static List<Map<String, Object?>> snapshot({int limit = 200, String? level}) {
    Iterable<DevLogEntry> selected = _entries;
    if (level != null && level.isNotEmpty) {
      selected = selected.where((e) => e.level == level);
    }
    if (selected.length > limit) {
      selected = selected.skip(selected.length - limit);
    }
    return <Map<String, Object?>>[
      for (final DevLogEntry e in selected) e.toJson(),
    ];
  }

  /// 测试用：清空缓冲。
  static void clearForTest() => _entries.clear();
}

/// 一条 dev 日志。
class DevLogEntry {
  final DateTime ts;
  final String level;
  final String kind;
  final String message;
  final String? details;

  const DevLogEntry({
    required this.ts,
    required this.level,
    required this.kind,
    required this.message,
    required this.details,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'ts': ts.toIso8601String(),
    'level': level,
    'kind': kind,
    'message': message,
    if (details != null) 'details': details,
  };
}
