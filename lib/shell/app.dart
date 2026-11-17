// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';

/// MaterialApp + MD3 主题（种子色沿用 demo 01 的做法，可由设置切换）。
class MimaoApp extends StatelessWidget {
  const MimaoApp({super.key});

  /// entry_variants.html 的三颗种子色：violet / green / ochre。
  static Color seed(String name) => switch (name) {
    'green' => const Color(0xFF3E8E6E),
    'ochre' => const Color(0xFFB4782E),
    _ => const Color(0xFF7C6BFF),
  };

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
