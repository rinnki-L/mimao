// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
// ════════════════════════════════════════════════════════════════════════
// mimao — 聚合番剧 / 漫画 / 小说 / 音乐的本地媒体应用
//
// ── 四条铁律（docs/architecture.md §2，test/architecture/boundary_test.dart 把守）
//   ① core/ 永不 import shell/ 与四个模块目录（anime/comic/music/novel）
//   ② 四个模块目录互不 import
//   ③ 四个模块目录不 import shell/（只准 import core/）
//   ④ shell/ 中仅 app_registry.dart 允许 import 四个模块目录
//   注：开工当天（M1）不建任何模块目录；未接入模块在壳里显示占位页。
//
// ── 启动时序（docs/architecture.md §1.1，M1 一次定型）
//   1. WidgetsFlutterBinding.ensureInitialized()
//   2. 桌面平台（运行时判断）：windowManager.ensureInitialized + waitUntilReadyToShow
//   3. 打开 AppDb（失败进错误页并 return——学 Kazumi 的 StorageErrorPage 兜底）
//   4. 系统强调色（D 线）：await SystemTheme.accentColor.load() + 变化监听 +
//      装配 MimaoApp.systemAccentProvider；失败 try/catch 兜底，不卡启动
//   5. MediaKit 初始化 —— M2 引入 media_kit 时再接（M1 无消费者，不建空初始化）
//   6. 装配目录表（app_registry）→ runApp()
//   audio_service 的 init 不在本清单（M2 随番剧 audio_controller 接线）。
// ════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/dev/dev_harness.dart';
import 'package:mimao/shell/dev/dev_route.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';
import 'package:mimao/shell/window/window.dart';
import 'package:system_theme/system_theme.dart';

Future<void> main() async {
  // 1. 绑定引擎
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 桌面窗口 / 托盘（运行时平台判断，Android 走空操作）
  await initWindow();
  await initTray();

  // 3. 打开统一库（失败进错误页，不带着坏 DB 继续跑）
  final AppDb db;
  try {
    db = AppDb();
    // 触发一次读，确保数据库文件真的可打开（建表在此完成）
    await db.select(db.appSettings).get();
  } catch (e) {
    runApp(StorageErrorPage(error: e));
    return;
  }

  final library = LibraryRepository(db);

  // 3.5 dev harness（debug-only，release 零存在）：错误日志环形缓冲 +
  //     本地 introspection 端点（/health /logs /route /state /db）+ driver.json。
  //     失败绝不影响启动（内部全吞）；导航观察者经 MimaoApp 的静态注入缝挂上，
  //     壳不感知 dev/。
  if (kDebugMode) {
    await startDevHarness(appDb: db);
    MimaoApp.navigatorObserversProvider = () => [devRouteTracker];
  }

  // 4. 系统强调色（D 线：跟随系统）。必须在 runApp 前 await load，否则首帧
  //    拿不到色。取色/监听失败一律 try/catch 兜底，绝不因插件问题卡住启动。
  await _initSystemAccent();

  // 6. 装配目录表（app_registry 是唯一 import 模块处；失败只会让番剧占位，
  //    不影响其它模块/书架）→ runApp
  await initAppModules(library: library);
  runApp(
    // debug-only 装配件：热重载时重置 /route 追踪（Navigator 重放初始路由
    // 会造成幻影帧，见 dev_route.dart）。kDebugMode 常量分支，release 整体剔除。
    kDebugMode
        ? DevReassembleProbe(
            child: LibraryScope(repository: library, child: const MimaoApp()),
          )
        : LibraryScope(repository: library, child: const MimaoApp()),
  );
}

/// 装配“跟随系统强调色”：加载系统色 → 注入 provider → 监听变化。
///
/// provider 直接返回 [Color]（由 [SystemTheme.accentColor] 每次读取现值），
/// seed('system') 取色时就拿到最新 accent；变化时用 onChange 流 bump epoch
/// 触发主题重建。system_theme 2.3.1 没有 addListener，变化通知走 onChange
/// stream（包内 SystemAccentColor 自身也订阅同一 stream 更新缓存）。
Future<void> _initSystemAccent() async {
  try {
    await SystemTheme.accentColor.load();
  } catch (_) {
    // 取色失败：provider 仍可读到 fallback 色，不卡启动。
  }

  // 直接返回 Color：seed('system') 每次调用都读 accent 的当前值。
  MimaoApp.systemAccentProvider = () => SystemTheme.accentColor.accent;

  // 系统色变化 → 递增 epoch → MimaoApp 的 Observer 重建 → 重新取色。
  // load() 内部已订阅 onChange 更新 accent；这里再订阅一次只为触发 MobX 重建。
  SystemTheme.onChange.listen(
    (_) => shellStore.bumpSystemAccent(),
    onError: (_) {
      // 平台事件流异常不应冒成 unhandled error；忽略，保留当前色。
    },
  );
}

/// 统一库打开失败时的兜底页（Kazumi StorageErrorPage 同款思路）。
class StorageErrorPage extends StatelessWidget {
  final Object error;

  const StorageErrorPage({super.key, required this.error});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 12),
              Text('本地存储打开失败', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
