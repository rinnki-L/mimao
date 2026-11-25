// 阅读页「桌面全屏」：Windows/macOS/Linux 用 window_manager 进全屏（隐藏标题栏
// 与任务栏），退出阅读时恢复。
//
// Android 的系统栏（隐藏状态栏 / 隐藏导航栏两个独立开关）已经挪进
// novel_platform.dart 的 AndroidNovelPlatform.applySystemBars —— 那里按开关组合出
// SystemUiMode，本文件只管桌面窗口，不再碰 SystemChrome。
//
// 测试环境（flutter test 的 flutter_tester）没有窗口插件，直接跳过系统调用。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

bool get _isTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// 进入/退出阅读页的系统级沉浸控制。
abstract final class NovelImmersive {
  static bool _entered = false;
  static bool _wasFullScreen = false;

  /// 进入阅读页时调用：桌面全屏。移动端由 [NovelPlatform] 处理系统栏。
  static Future<void> enter() async {
    if (_isTest || _entered || kIsWeb) return;
    _entered = true;
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        _wasFullScreen = await windowManager.isFullScreen();
        if (!_wasFullScreen) {
          await windowManager.setFullScreen(true);
        }
      }
    } on Object {
      // 插件不可用时保持普通窗口，不让阅读页打不开。
    }
  }

  /// 退出阅读页时调用：还原桌面窗口。
  static Future<void> exit() async {
    if (_isTest || !_entered || kIsWeb) return;
    _entered = false;
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        if (!_wasFullScreen) {
          await windowManager.setFullScreen(false);
        }
      }
    } on Object {
      // 还原失败不阻塞退出。
    }
  }
}
