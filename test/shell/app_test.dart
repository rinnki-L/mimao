// D 线 · 主题跟随系统强调色的离线单测。
// 全部走注入的 fake provider，不加载 system_theme 平台插件——
// main.dart 的 load/监听只在生产路径，测试不跑 main（CI/Linux 安全）。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/settings_page.dart';
import 'package:mimao/shell/shell_store.dart';

void main() {
  const violet = Color(0xFF7C6BFF);

  setUp(() {
    // 每例都从干净状态起：清 provider、复位 seed 与 epoch。
    MimaoApp.systemAccentProvider = null;
    shellStore.setThemeSeed('violet');
    shellStore.systemAccentEpoch = 0;
  });

  tearDown(() {
    MimaoApp.systemAccentProvider = null;
    shellStore.setThemeSeed('violet');
  });

  group('MimaoApp.seed', () {
    test('注入 fake provider 时 seed(system) 返回 fake 色', () {
      const fake = Color(0xFF123456);
      MimaoApp.systemAccentProvider = () => fake;
      expect(MimaoApp.seed('system'), fake);
    });

    test('无 provider 时 seed(system) 回退 violet', () {
      expect(MimaoApp.seed('system'), violet);
    });

    test('provider 抛异常时 seed(system) 回退 violet（取色失败不崩）', () {
      MimaoApp.systemAccentProvider = () => throw StateError('no accent');
      expect(MimaoApp.seed('system'), violet);
    });

    test('seed(dyn:FF123456) 解析为对应 ARGB 色', () {
      expect(MimaoApp.seed('dyn:FF123456'), const Color(0xFF123456));
    });

    test('非法 dyn hex 回退 violet', () {
      expect(MimaoApp.seed('dyn:zzzzzzzz'), violet);
      expect(MimaoApp.seed('dyn:123'), violet);
    });

    test('基础色板 seed 不受 system 改动影响', () {
      MimaoApp.systemAccentProvider = () => const Color(0xFF000000);
      expect(MimaoApp.seed('violet'), violet);
      expect(MimaoApp.seed('green'), MimaoApp.seedColors['green']!.$2);
    });
  });

  group('ShellStore 系统色 epoch', () {
    test('bumpSystemAccent 递增 epoch', () {
      expect(shellStore.systemAccentEpoch, 0);
      shellStore.bumpSystemAccent();
      expect(shellStore.systemAccentEpoch, 1);
      shellStore.bumpSystemAccent();
      expect(shellStore.systemAccentEpoch, 2);
    });
  });

  group('设置页外观组', () {
    testWidgets('外观组共 9 枚色块（8 色 + 跟随系统）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsPage())),
      );
      await tester.pumpAndSettle();

      // 8 枚基础色 chip + 1 枚“跟随系统”chip = 9 枚 ChoiceChip。
      expect(find.byType(ChoiceChip), findsNWidgets(9));
      expect(find.text('跟随系统'), findsOneWidget);
    });

    testWidgets('点“跟随系统”后 themeSeed == system', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsPage())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('theme-seed-system')));
      await tester.pumpAndSettle();

      expect(shellStore.themeSeed, 'system');
    });
  });
}
