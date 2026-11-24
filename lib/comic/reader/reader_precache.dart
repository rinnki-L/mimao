// 有界图片预取器：把"接下来要看的图"提前灌进 [ReaderImageCache]。
//
// 对照 Venera Next 的 ReaderImagePrecache（lib/features/reader/image_precache.dart）：
// 上游用 ImageWork + Flutter ImageCache 同时管"取编码字节"和"解码"；本仓阅读器
// 的图片字节统一走 [ReaderImageCache]，所以这里只保留同样重要的三条约束：
// - 并发有界（默认 2），不把整章图片同时打出去；
// - 窗口可替换：翻页后旧窗口里还没开始的请求直接丢弃，正在飞的请求让它完成
//   （字节进缓存不浪费），但不再回调；
// - 失败静默：预取失败不能污染界面，真正显示时由图片槽自己报错并重试。
//
// 预取器不认识 Widget，构造后由阅读视口在每次位置/设置变化时调用 [update]。

import 'dart:async';
import 'dart:typed_data';

import 'reader_cache.dart';
import 'reader_models.dart';

/// 一次预取任务（保持窗口内顺序，供"只解码前 N 张"判断）。
class _QueuedRequest {
  const _QueuedRequest(this.request, this.order);

  final ImageRequest request;

  /// 在最近一次 [ReaderImagePreloader.update] 窗口中的序号（0 基）。
  final int order;
}

/// 图片字节预取器。
class ReaderImagePreloader {
  ReaderImagePreloader({
    required this.cache,
    this.maxConcurrent = 2,
    this.decodeAhead = 2,
    this.onBytes,
  }) : assert(maxConcurrent > 0, '并发必须为正'),
       assert(decodeAhead >= 0, 'decodeAhead 不能为负');

  final ReaderImageCache cache;

  /// 同时最多几张图在取字节。
  final int maxConcurrent;

  /// 窗口内前几张取到字节后触发 [onBytes]（阅读视口用它做尺寸测量与解码预热）。
  final int decodeAhead;

  /// 取到字节后的回调；只对窗口内前 [decodeAhead] 张、且窗口未被替换时调用。
  ///
  /// 回调抛错会被吞掉：预取是尽力而为，不能因为解码预热失败把阅读器带崩。
  final void Function(ImageRequest request, Uint8List bytes)? onBytes;

  final List<_QueuedRequest> _queue = <_QueuedRequest>[];
  final Set<String> _queuedIds = <String>{};
  int _active = 0;
  int _generation = 0;
  bool _disposed = false;
  List<String> _wantedIds = const <String>[];
  Completer<void>? _idle;

  /// 当前窗口里还没开始 / 正在取字节的请求数（测试与诊断用）。
  int get pendingCount => _queue.length + _active;

  /// 用新窗口替换旧窗口。重复传入同一窗口是空操作。
  void update(Iterable<ImageRequest> requests) {
    if (_disposed) return;
    final seen = <String>{};
    final wanted = <ImageRequest>[
      for (final request in requests)
        if (seen.add(request.cacheIdentity)) request,
    ];
    final wantedIds = <String>[
      for (final request in wanted) request.cacheIdentity,
    ];
    if (_listEquals(wantedIds, _wantedIds)) {
      _pump();
      return;
    }

    _wantedIds = wantedIds;
    _generation++;
    _queue.clear();
    _queuedIds.clear();
    for (var index = 0; index < wanted.length; index++) {
      final request = wanted[index];
      // 内存已有字节：不需要再排队（解码预热交给真正显示它的图片槽）。
      if (cache.hasRequest(request)) continue;
      final id = request.cacheIdentity;
      if (_queuedIds.add(id)) {
        _queue.add(_QueuedRequest(request, index));
      }
    }
    _pump();
  }

  /// 等待当前窗口全部处理完（测试用；生产不需要）。
  Future<void> flush() {
    if (_disposed || pendingCount == 0) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _queuedIds.clear();
    _wantedIds = const <String>[];
    _completeIdle();
  }

  void _pump() {
    if (_disposed) return;
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _queuedIds.remove(item.request.cacheIdentity);
      _active++;
      final generation = _generation;
      unawaited(_run(item, generation));
    }
    if (pendingCount == 0) _completeIdle();
  }

  Future<void> _run(_QueuedRequest item, int generation) async {
    try {
      final bytes = await cache.loadRequest(item.request);
      // 窗口已换：字节留在缓存里就好，不再做尺寸/解码预热。
      if (_disposed || generation != _generation) return;
      if (item.order < decodeAhead) {
        try {
          onBytes?.call(item.request, bytes);
        } on Object {
          // 预热失败不影响已经拿到的字节。
        }
      }
    } on Object {
      // 预取失败静默；显示时图片槽会给出错误态与重试入口。
    } finally {
      _active--;
      if (!_disposed) _pump();
    }
  }

  void _completeIdle() {
    final idle = _idle;
    if (idle != null && !idle.isCompleted) idle.complete();
    _idle = null;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
