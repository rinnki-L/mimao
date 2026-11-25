// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与壳的其它文件同款说明。
/// 应用退出/回前台的钩子注册表 + 一个把钩子接到窗口关闭上的小组件。
///
/// 为什么放在壳里：模块不能 import `shell/`（铁律 ③），而"关窗口"只能由壳来中断。
/// 于是壳提供注册口，`app_registry`（唯一允许 import 模块的地方）把模块自己的
/// 收尾动作挂上来——壳不知道备份是什么，模块也不知道窗口怎么关。
///
/// 纪律：退出钩子必须**有硬超时**。备份慢、网络挂、插件没响应，都不能让用户
/// 关不掉窗口。
library;

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:mimao/shell/window/window.dart' show isDesktop;

/// 退出/回前台时跑的一段动作。
typedef AppLifecycleHook = Future<void> Function();

/// 关窗钩子的默认超时：超过就直接关。
const Duration defaultAppExitTimeout = Duration(seconds: 10);

final List<AppLifecycleHook> _exitHooks = <AppLifecycleHook>[];
final List<AppLifecycleHook> _resumeHooks = <AppLifecycleHook>[];

/// 注册"关窗前跑一次"的钩子。
void registerAppExitHook(AppLifecycleHook hook) {
  _exitHooks.add(hook);
}

/// 注册"回到前台时跑一次"的钩子（用于每日备份的补跑）。
void registerAppResumeHook(AppLifecycleHook hook) {
  _resumeHooks.add(hook);
}

bool get hasAppExitHooks => _exitHooks.isNotEmpty;

bool get hasAppResumeHooks => _resumeHooks.isNotEmpty;

/// 测试用：清空注册表。
void resetAppLifecycleHooksForTest() {
  _exitHooks.clear();
  _resumeHooks.clear();
}

/// 跑一遍退出钩子；总时长不超过 [timeout]，单个钩子的异常只记日志。
Future<void> runAppExitHooks({Duration timeout = defaultAppExitTimeout}) =>
    _runAll(_exitHooks, timeout: timeout, label: '退出钩子');

/// 跑一遍回前台钩子（没有就不做）。
Future<void> runAppResumeHooks({Duration timeout = defaultAppExitTimeout}) =>
    _runAll(_resumeHooks, timeout: timeout, label: '回前台钩子');

Future<void> _runAll(
  List<AppLifecycleHook> hooks, {
  required Duration timeout,
  required String label,
}) async {
  if (hooks.isEmpty) return;
  final run = () async {
    for (final hook in hooks) {
      try {
        await hook();
      } on Object catch (error, stack) {
        debugPrint('mimao: $label失败 $error\n$stack');
      }
    }
  }();
  try {
    await Future.any(<Future<void>>[run, Future<void>.delayed(timeout)]);
  } on Object catch (error) {
    debugPrint('mimao: $label超时或异常 $error');
  }
}

/// 把退出/回前台钩子接到窗口上的小组件。
///
/// - 桌面：`setPreventClose(true)` + `onWindowClose` → 跑钩子 → 真关；
/// - Android：`AppLifecycleListener` 的 `onExitRequested` / `onResume` 兜底。
///
/// 没有注册任何钩子时**不装任何监听**——测试里 pump 整个 app 也不会碰插件。
class AppLifecycleGuard extends StatefulWidget {
  const AppLifecycleGuard({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleGuard> createState() => _AppLifecycleGuardState();
}

class _AppLifecycleGuardState extends State<AppLifecycleGuard>
    with WindowListener {
  AppLifecycleListener? _listener;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    if (hasAppExitHooks && isDesktop) {
      windowManager.setPreventClose(true).catchError((_) {});
      windowManager.addListener(this);
    }
    if (hasAppExitHooks || hasAppResumeHooks) {
      _listener = AppLifecycleListener(
        onExitRequested: () async {
          await runAppExitHooks();
          return AppExitResponse.exit;
        },
        onResume: () {
          if (hasAppResumeHooks) unawaited(runAppResumeHooks());
        },
      );
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    if (hasAppExitHooks && isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    _exiting = true;
    unawaited(_finishClose());
  }

  Future<void> _finishClose() async {
    try {
      await runAppExitHooks();
    } finally {
      try {
        await windowManager.setPreventClose(false);
      } on Object catch (error) {
        debugPrint('mimao: 解除关窗拦截失败 $error');
      }
      try {
        await windowManager.destroy();
      } on Object catch (error) {
        debugPrint('mimao: 关闭窗口失败 $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
