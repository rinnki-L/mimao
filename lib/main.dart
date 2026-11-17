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
//   4. MediaKit 初始化 —— M2 引入 media_kit 时再接（M1 无消费者，不建空初始化）
//   5. 装配目录表（app_registry）→ runApp()
//   audio_service 的 init 不在本清单（M2 随番剧 audio_controller 接线）。
// ════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/window/window.dart';

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

  // 5. 装配目录表（app_registry 是唯一 import 模块处；M1 为空表）→ runApp
  runApp(LibraryScope(repository: library, child: const MimaoApp()));
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
