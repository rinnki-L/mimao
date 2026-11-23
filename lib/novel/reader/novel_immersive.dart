// 阅读页全屏沉浸：Windows 用 window_manager 进全屏（隐藏标题栏与任务栏），
// Android 用 SystemChrome 沉浸模式；退出阅读时恢复。
//
// 测试环境（flutter test 的 flutter_tester）没有窗口插件，直接跳过系统调用。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

bool get _isTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// 进入/退出阅读页的系统级沉浸控制。
abstract final class NovelImmersive {
  static bool _entered = false;
  static bool _wasFullScreen = false;

  /// 进入阅读页时调用：桌面全屏、移动端隐藏系统栏。
  static Future<void> enter() async {
    if (_isTest || _entered || kIsWeb) return;
    _entered = true;
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        _wasFullScreen = await windowManager.isFullScreen();
        if (!_wasFullScreen) {
          await windowManager.setFullScreen(true);
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Color(0x00000000),
            systemNavigationBarColor: Color(0x00000000),
          ),
        );
      }
    } on Object {
      // 插件不可用时保持普通窗口，不让阅读页打不开。
    }
  }

  /// 退出阅读页时调用：还原窗口/系统栏。
  static Future<void> exit() async {
    if (_isTest || !_entered || kIsWeb) return;
    _entered = false;
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        if (!_wasFullScreen) {
          await windowManager.setFullScreen(false);
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      }
    } on Object {
      // 还原失败不阻塞退出。
    }
  }
}
