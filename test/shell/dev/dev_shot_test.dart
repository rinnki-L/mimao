// ignore_for_file: deprecated_member_use — Flutter 3.47+ 弃用 material.dart，
// 与 main.dart/上游镜像同款纪律：M1 继续用，保类型一致。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/shell/dev/dev_route.dart';
import 'package:mimao/shell/dev/dev_shot.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mimao_dev_shot_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('经 DevReassembleProbe 装配后抓图：PNG 落盘且尺寸正确', (tester) async {
    await tester.pumpWidget(
      DevReassembleProbe(
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: Container(color: const Color(0xFF00FF00))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // toImage 依赖引擎真实异步回调，fake-async 区永不完成——runAsync 放行。
    final result = (await tester.runAsync(
      () => captureScreenshot(shotsDir: tempDir.path),
    ))!;

    expect(result['ok'], true, reason: '${result['error']}');
    final file = File(result['file']! as String);
    expect(file.existsSync(), true);
    final bytes = file.readAsBytesSync();
    expect(bytes.length, greaterThan(100));
    // PNG 魔数：89 50 4E 47。
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(result['width'], greaterThan(0));
    expect(result['height'], greaterThan(0));
    // 测试视口 800×600 × devicePixelRatio（封顶 3）。
    final ratio = (result['pixelRatio']! as num).toInt();
    expect(result['width'], 800 * ratio);
    expect(result['height'], 600 * ratio);
  });

  testWidgets('无 boundary 装配（不挂 probe）时给出可读错误', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pumpAndSettle();

    final result = await captureScreenshot(shotsDir: tempDir.path);

    expect(result['ok'], false);
    expect(result['error'], contains('RepaintBoundary'));
  });
}
