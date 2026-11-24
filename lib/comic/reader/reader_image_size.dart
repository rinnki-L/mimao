// 图片原始尺寸缓存：只读编码头，不解整张位图。
//
// 对照 Venera Next 的 image_dimensions.dart / ReaderLayoutDetection：上游用
// ImageStream 观察解码结果，拿尺寸排布连续视图；本仓阅读器在连续/瀑布模式下
// 每个列表项高度未知，图片加载完成前高度为 0，随后突然撑开会让正在读的位置
// 跳动。这里在拿到字节时用 [ImageDescriptor] 读编码头里的宽高（廉价），
// 让列表项在图片解码前就能按正确宽高比占位。
//
// 尺寸只按 [ImageRequest.cacheIdentity] 缓存（含防盗链头），有界 LRU。

import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show Size;

import 'reader_models.dart';

/// 有界的"图片地址 → 原始像素尺寸"缓存。
class ReaderImageSizeCache {
  ReaderImageSizeCache({
    this.maxEntries = 256,
    Future<Size?> Function(Uint8List)? measure,
  }) : _measureBytes = measure ?? _measureEncoded;

  final int maxEntries;

  /// 可注入的尺寸解析器；默认读编码头，测试可替换成确定性实现。
  final Future<Size?> Function(Uint8List bytes) _measureBytes;

  final LinkedHashMap<String, Size> _sizes = LinkedHashMap<String, Size>();
  final Map<String, Future<Size?>> _pending = <String, Future<Size?>>{};

  /// 已量过的尺寸；未量过返回 null。
  Size? peek(ImageRequest request) {
    final key = request.cacheIdentity;
    final size = _sizes.remove(key);
    if (size == null) return null;
    _sizes[key] = size;
    return size;
  }

  bool contains(ImageRequest request) =>
      _sizes.containsKey(request.cacheIdentity);

  /// 读取编码头尺寸；同一地址的并发调用共享同一个 Future。
  ///
  /// 字节无法识别时返回 null（界面退回估算宽高比），不抛错。
  Future<Size?> measure(ImageRequest request, Uint8List bytes) {
    final key = request.cacheIdentity;
    final known = peek(request);
    if (known != null) return Future<Size?>.value(known);
    final pending = _pending[key];
    if (pending != null) return pending;

    final future = _runMeasure(key, bytes);
    _pending[key] = future;
    return future;
  }

  Future<Size?> _runMeasure(String key, Uint8List bytes) async {
    try {
      final size = await _measureBytes(bytes);
      if (size != null) _put(key, size);
      return size;
    } on Object {
      return null;
    } finally {
      _pending.remove(key);
    }
  }

  void clear() {
    _sizes.clear();
    _pending.clear();
  }

  void _put(String key, Size size) {
    if (maxEntries <= 0) return;
    _sizes.remove(key);
    _sizes[key] = size;
    while (_sizes.length > maxEntries) {
      _sizes.remove(_sizes.keys.first);
    }
  }

  static Future<Size?> _measureEncoded(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
