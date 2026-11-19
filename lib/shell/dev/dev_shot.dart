import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:mimao/shell/dev/dev_route.dart';

/// `/shot` 端点：从根 RepaintBoundary 抓当前帧存 PNG（debug-only）。
///
/// 抓图对象是 [devRootShotKey] 挂的那层 boundary（包住整个 app）；像素比取
/// 当前 View 的 devicePixelRatio（封顶 3，防超采样）。平台层（video 纹理等）
/// 不进 RepaintBoundary 快照——番剧播放页截图会是空画面，属已知限制。
///
/// GET /shot 即抓一张；文件落在 dev harness 的 shots 目录，响应回全路径。
Future<Map<String, Object?>> captureScreenshot({
  required String shotsDir,
  Element? root,
  int maxPixelRatio = 3,
}) async {
  final effectiveRoot = root ?? WidgetsBinding.instance.rootElement;
  if (effectiveRoot == null) {
    return <String, Object?>{'ok': false, 'error': 'widget 树尚未构建'};
  }

  Element? boundaryElement;
  void visit(Element element) {
    if (boundaryElement != null) return;
    if (element.widget.key == devRootShotKey) {
      boundaryElement = element;
      return;
    }
    element.visitChildren(visit);
  }

  visit(effectiveRoot);
  if (boundaryElement == null) {
    return <String, Object?>{
      'ok': false,
      'error':
          '找不到根 RepaintBoundary（app 不是经 DevReassembleProbe 装配的？'
          '—main.dart 的 kDebugMode 分支）',
    };
  }

  final renderObject = boundaryElement!.renderObject;
  if (renderObject is! RenderRepaintBoundary) {
    return <String, Object?>{
      'ok': false,
      'error':
          'boundary 的 renderObject 不是 RenderRepaintBoundary：'
          '${renderObject.runtimeType}',
    };
  }

  final ratio = View.of(boundaryElement!).devicePixelRatio;
  final pixelRatio = ratio > maxPixelRatio ? maxPixelRatio.toDouble() : ratio;

  try {
    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    final int width = image.width;
    final int height = image.height;
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    if (data == null) {
      return <String, Object?>{'ok': false, 'error': 'PNG 编码返回空'};
    }

    await Directory(shotsDir).create(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('$shotsDir${Platform.pathSeparator}shot-$timestamp.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return <String, Object?>{
      'ok': true,
      'file': file.path,
      'width': width,
      'height': height,
      'bytes': data.lengthInBytes,
      'pixelRatio': pixelRatio,
    };
  } catch (error) {
    return <String, Object?>{'ok': false, 'error': '抓图失败：$error'};
  }
}
