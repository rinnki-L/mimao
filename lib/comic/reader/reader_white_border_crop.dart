// 纵向连续/瀑布模式的左右白边裁剪。
//
// 移植自 Venera-Next `lib/features/reader/white_border_crop.dart` 的扫描规则：
// 逐列检查左右边缘是否"整列近白"（alpha=0 或 RGB≥253），任一明显文字/画面
// 像素就停在该侧；整页全白、或单侧留白超过 1/4 宽度时保持原样。
//
// 与上游的差别只在调度层：上游用 ImageWork 管取消与预算；这里用有界队列
// （同时最多 [maxConcurrent] 次扫描、单张像素预算）并在阅读视口 dispose 时
// 整体丢弃，不引第三方依赖。
//
// 扫描只读编码后的字节，不改磁盘文件、不改下载缓存键。

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show Rect;

/// 左右白边宽度（像素）。返回 (左, 右)；不裁剪时为 (0, 0)。
///
/// 纯函数，可在 isolate 里跑，也便于单测。
(int, int) horizontalWhiteBorderInsets(Uint8List rgba, int width, int height) {
  if (width < 32 || height < 1 || rgba.length != width * height * 4) {
    return (0, 0);
  }
  final maximum = width ~/ 4;
  var left = maximum + 1, right = maximum + 1;
  bool white(int x, int y) {
    final offset = (y * width + x) * 4;
    if (rgba[offset + 3] == 0) return true;
    return rgba[offset + 3] == 255 &&
        rgba[offset] >= 253 &&
        rgba[offset + 1] >= 253 &&
        rgba[offset + 2] >= 253;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < left; x++) {
      if (!white(x, y)) {
        left = x;
        break;
      }
    }
    for (var x = 0; x < right; x++) {
      if (!white(width - x - 1, y)) {
        right = x;
        break;
      }
    }
    if (left == 0 && right == 0) break;
  }
  final padding = (width * 0.002).ceil().clamp(2, maximum);
  final minimum = (width * 0.01).ceil().clamp(4, maximum);
  int keep(int inset) =>
      inset > maximum || inset < minimum ? 0 : inset - padding;
  return (keep(left), keep(right));
}

/// 一次裁剪结果：按图片尺寸归一化的左右裁切比例（0~0.25）。
class WhiteBorderInsets {
  const WhiteBorderInsets({required this.left, required this.right});

  static const WhiteBorderInsets none = WhiteBorderInsets(left: 0, right: 0);

  final double left;
  final double right;

  bool get isNone => left <= 0 && right <= 0;

  /// 转成源图像素坐标里的可见区域。
  Rect visibleRect(double width, double height) =>
      Rect.fromLTRB(width * left, 0, width * (1 - right), height);

  @override
  bool operator ==(Object other) =>
      other is WhiteBorderInsets && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);
}

/// 有界的白边检测器：同一张图只算一次，并发与像素预算都封顶。
class ReaderWhiteBorderCrop {
  ReaderWhiteBorderCrop({
    this.maxConcurrent = 2,
    this.maxPixels = 8000000,
    this.maxEntries = 128,
  }) : assert(maxConcurrent > 0, '并发必须为正');

  /// 同时最多几张图在扫描。
  final int maxConcurrent;

  /// 单张图超过该像素数就跳过检测（解码 RGBA 内存约 4 字节/像素）。
  final int maxPixels;

  /// 结果缓存条目上限。
  final int maxEntries;

  final Map<String, WhiteBorderInsets> _cache = <String, WhiteBorderInsets>{};
  final Map<String, Future<WhiteBorderInsets>> _pending =
      <String, Future<WhiteBorderInsets>>{};
  int _active = 0;
  bool _disposed = false;

  /// 已算过的结果；没算过返回 null。
  WhiteBorderInsets? peek(String key) => _cache[key];

  /// 检测一张图；[key] 用缓存身份（地址 + 请求头）。
  ///
  /// 同一 key 的并发调用共享同一个 Future；解码失败、超预算、已释放都返回
  /// [WhiteBorderInsets.none]，调用方无需区分。
  Future<WhiteBorderInsets> measure(String key, Uint8List bytes) {
    if (_disposed) {
      return Future<WhiteBorderInsets>.value(WhiteBorderInsets.none);
    }
    final cached = _cache[key];
    if (cached != null) return Future<WhiteBorderInsets>.value(cached);
    final pending = _pending[key];
    if (pending != null) return pending;

    final future = _run(key, bytes);
    _pending[key] = future;
    return future;
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
    _pending.clear();
  }

  Future<WhiteBorderInsets> _run(String key, Uint8List bytes) async {
    try {
      // 排队：并发满了就等，而不是无界解码。
      while (_active >= maxConcurrent && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (_disposed) return WhiteBorderInsets.none;
      _active++;
      try {
        final result = await _scanBytes(bytes);
        if (_disposed) return WhiteBorderInsets.none;
        _put(key, result);
        return result;
      } finally {
        _active--;
      }
    } on Object {
      return WhiteBorderInsets.none;
    } finally {
      _pending.remove(key);
    }
  }

  Future<WhiteBorderInsets> _scanBytes(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final pixels = descriptor.width * descriptor.height;
      if (pixels <= 0 || pixels > maxPixels) return WhiteBorderInsets.none;

      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return WhiteBorderInsets.none;

      final rgba = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final (left, right) = await _scanInBackground(
        rgba,
        descriptor.width,
        descriptor.height,
      );
      if (left <= 0 && right <= 0) return WhiteBorderInsets.none;
      final width = descriptor.width;
      return WhiteBorderInsets(
        left: (left / width).clamp(0.0, 0.25),
        right: (right / width).clamp(0.0, 0.25),
      );
    } on Object {
      return WhiteBorderInsets.none;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// 扫描放到 isolate；创建失败（测试环境/平台不支持）时退回主 isolate。
  Future<(int, int)> _scanInBackground(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    try {
      return await Isolate.run(
        () => horizontalWhiteBorderInsets(rgba, width, height),
        debugName: 'reader-white-border',
      );
    } on Object {
      return horizontalWhiteBorderInsets(rgba, width, height);
    }
  }

  void _put(String key, WhiteBorderInsets insets) {
    if (maxEntries <= 0) return;
    _cache[key] = insets;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}
