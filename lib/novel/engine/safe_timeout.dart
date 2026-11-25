/// 带超时的长任务工具：**超时后原 future 的迟到错误不会变成未处理异步异常**。
///
/// 为什么需要：`future.timeout(d)` 只是给自己加了一个计时器，原 future 仍在
/// 跑；它随后抛错时已经没有 await 方，Dart 会把它报成 unhandled async error，
/// debug 构建里直接崩掉 app。书源引擎的 JS 宿主、网络请求都可能在超时之后才
/// 失败，所以「加了超时」的地方都要走这个函数。
///
/// 实测（2026-11-25）：一条书源搜索 30s 超时后 JS 宿主迟到抛
/// `LegadoJsException`，把整个 app 打崩——修法就是给原 future 先挂一个吞错的
/// 监听，再单独 await 带超时的那条分支。
library;

import 'dart:async';

/// 给 [future] 加 [timeout]；超时抛 [TimeoutException]（带 [label]）。
///
/// [label] 只用于超时消息（面板与日志里能看出是哪一步超时）。
Future<T> withSafeTimeout<T>(
  Future<T> future,
  Duration timeout, {
  String label = '步骤',
}) {
  // 迟到错误的兜底监听：只为消除 unhandled，不改变下面 await 的结果语义。
  future.then<void>((_) {}, onError: (Object _) {});
  return future.timeout(
    timeout,
    onTimeout: () => throw TimeoutException(label, timeout),
  );
}
