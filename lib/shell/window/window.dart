// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口 / 托盘单文件 + **运行时平台判断**（docs/architecture.md §1 第 3 条）。
///
/// 桌面平台（Windows/Linux/macOS）才触碰 window_manager / tray_manager；
/// Android 及其他平台全部空操作，启动路径不炸。
/// 为什么不用条件 import：Dart 只有 dart.library.* 条件，Windows 与 Android
/// 同样满足 io/ffi，编译期分不开——窗口是运行时属性（Kazumi 同款做法）。
bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// 启动时序第 2 步（docs/architecture.md §1.1）：仅在桌面初始化窗口。
/// 参数照抄 Kazumi：低分辨率 840×600，否则 1280×860。
Future<void> initWindow() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 860),
    minimumSize: Size(840, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 托盘（M1 只搭通道，具体菜单 M2 随番剧播放接线）。
/// 图标设置失败不能阻断启动——托盘是增强项，try/catch 后静默降级。
Future<void> initTray() async {
  if (!isDesktop) return;
  try {
    await trayManager.setIcon('assets/mimao.png');
  } catch (_) {
    // 托盘图标不可用（某些 Linux DE / 无系统托盘环境）时忽略，不影响主窗口。
  }
}
