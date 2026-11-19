// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';

/// MaterialApp + MD3 主题（种子色沿用 demo 01 的做法，可由设置切换）。
class MimaoApp extends StatelessWidget {
  const MimaoApp({super.key});

  /// 系统强调色提供器（可注入缝）。
  ///
  /// 直接返回 [Color]（而非 `dyn:` 字符串）：provider 在 [seed] 被调用时读取
  /// `SystemTheme.accentColor.accent` 的"当下"值，避免字符串拼接/解析开销，
  /// 也和系统色变化时的 epoch 重建语义更直接。生产环境由 main.dart 装配；
  /// 测试注入 fake provider，绝不触发 system_theme 插件。
  static Color Function()? systemAccentProvider;

  /// 回退色：与最初 violet 一致（entry_variants.html 三色之一）。
  static const Color _kViolet = Color(0xFF7C6BFF);

  /// 可选基础色板（有序）：键为 shellStore.themeSeed 值，值为 (中文名, 色值)。
  /// 设置页与 [seed] 共用这一份，避免两处漂移。
  /// 注意："跟随系统"不在基础色板里，它是设置页单独一枚 chip，themeSeed 值为 'system'。
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

  /// MD3 种子色：基础色板 + 用户动态取色（`dyn:` 前缀）+ 跟随系统（`'system'`）。
  /// 未知名称回落到最初的 violet（entry_variants.html 三色之一）。
  ///
  /// [accentEpoch] 仅供 [build] 的 Observer 读取 `shellStore.systemAccentEpoch`
  /// 建立 MobX 依赖——系统色变化时 epoch 递增会触发重建，从而重新调用本方法
  /// 从 provider 取到新色；其值本身不参与色值计算，可安全忽略。
  static Color seed(String name, {int accentEpoch = 0}) {
    if (name == 'system') {
      final provider = systemAccentProvider;
      if (provider == null) return _kViolet;
      try {
        return provider();
      } catch (_) {
        return _kViolet;
      }
    }
    final base = seedColors[name];
    if (base != null) return base.$2;
    if (name.startsWith('dyn:')) return _parseDynamic(name);
    return _kViolet;
  }

  static Color _parseDynamic(String value) {
    final hex = value.substring(4);
    final argb = int.tryParse(hex, radix: 16);
    if (argb == null || hex.length != 8) return _kViolet;
    return Color(argb);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        // 读一次 epoch 建立依赖：Windows 强调色变化 → bumpSystemAccent() →
        // epoch++ → Observer 重建 → 下面 seed('system') 取到 provider 的新色。
        final accentEpoch = shellStore.systemAccentEpoch;
        final colorSchemeSeed = seed(
          shellStore.themeSeed,
          accentEpoch: accentEpoch,
        );
        return MaterialApp(
          title: 'mimao',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: colorSchemeSeed,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: colorSchemeSeed,
            brightness: Brightness.dark,
          ),
          themeMode: ThemeMode.system,
          home: const HomeShell(),
        );
      },
    );
  }
}
