// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';

/// MaterialApp + MD3 主题（种子色沿用 demo 01 的做法，可由设置切换）。
class MimaoApp extends StatelessWidget {
  const MimaoApp({super.key});

  /// 可选基础色板（有序）：键为 shellStore.themeSeed 值，值为 (中文名, 色值)。
  /// 设置页与 [seed] 共用这一份，避免两处漂移。
  static const Map<String, (String, Color)> seedColors = {
    'violet': ('紫罗兰', Color(0xFF7C6BFF)),
    'green': ('青绿', Color(0xFF3E8E6E)),
    'ochre': ('赭黄', Color(0xFFB4782E)),
    'blue': ('天蓝', Color(0xFF3D6FE0)),
    'rose': ('玫红', Color(0xFFD05474)),
    'teal': ('青碧', Color(0xFF00897B)),
    'orange': ('橘橙', Color(0xFFE06C00)),
    'slate': ('石板灰', Color(0xFF546E7A)),
  };

  /// “跟随系统强调色”模式的色源。由 main.dart 在 runApp 前装配（从
  /// SystemTheme.accentColor.accent 取值）；测试可注入 fake。
  /// 未装配或抛异常都回退 violet——取色失败绝不卡住启动/主题重建。
  static Color Function()? systemAccentProvider;

  /// 导航观察者注入缝（dev harness 的 /route 追踪器由此挂上，main.dart
  /// debug 下装配）。与 [systemAccentProvider] 同款静态注入模式——本文件不
  /// import dev/，保持壳对 dev 设施零感知；null = 不注入（测试/生产）。
  static List<NavigatorObserver> Function()? navigatorObserversProvider;

  /// 根 Navigator 的 key：dev /navigate 的 back 通道由此驱动 app 实际出栈。
  /// 放本文件保证 key 与 MaterialApp 同源（挂壳里不挂 dev/，同上零感知纪律）。
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// MD3 种子色：基础色板 + 用户动态取色（`dyn:` 前缀）+ `'system'` 跟随系统。
  /// 未知名称回落到最初的 violet（entry_variants.html 三色之一）。
  static Color seed(String name) {
    final base = seedColors[name];
    if (base != null) return base.$2;
    if (name == 'system') {
      final provider = systemAccentProvider;
      if (provider == null) return const Color(0xFF7C6BFF);
      try {
        return provider();
      } catch (_) {
        return const Color(0xFF7C6BFF);
      }
    }
    if (name.startsWith('dyn:')) return _parseDynamic(name);
    return const Color(0xFF7C6BFF);
  }

  static Color _parseDynamic(String value) {
    final hex = value.substring(4);
    final argb = int.tryParse(hex, radix: 16);
    if (argb == null || hex.length != 8) return const Color(0xFF7C6BFF);
    return Color(argb);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        // 建立对系统色变化 epoch 的依赖：系统强调色变 → epoch++ → 本 Observer
        // 重建 → seed('system') 从 provider 取新色。读 epoch 无副作用，可无条件读。
        final accentEpoch = shellStore.systemAccentEpoch;
        final seedColor = seed(shellStore.themeSeed);
        assert(accentEpoch >= 0); // 仅用于消费局部变量，表明“读一次即订阅”的意图。
        return MaterialApp(
          title: 'mimao',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: seedColor),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: seedColor,
            brightness: Brightness.dark,
          ),
          themeMode: ThemeMode.system,
          navigatorObservers:
              navigatorObserversProvider?.call() ?? const <NavigatorObserver>[],
          home: const HomeShell(),
        );
      },
    );
  }
}
