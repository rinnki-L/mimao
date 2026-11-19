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

  /// MD3 种子色：基础色板 + 用户动态取色（`dyn:` 前缀）。
  /// 未知名称回落到最初的 violet（entry_variants.html 三色之一）。
  static Color seed(String name) {
    final base = seedColors[name];
    if (base != null) return base.$2;
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
      builder: (_) => MaterialApp(
        title: 'mimao',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: seed(shellStore.themeSeed),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: seed(shellStore.themeSeed),
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}
