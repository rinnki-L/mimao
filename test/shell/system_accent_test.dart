// D 线 · 系统强调色离线单测。
//
// 关键纪律：所有用例只通过 MimaoApp.systemAccentProvider 注入 fake 色值，
// 绝不调用 SystemTheme.accentColor.load()，也不 import system_theme 插件——
// CI 是 Linux/无 Windows，真实插件绝不能在测试路径被触发。
// main.dart 的 load/listen 只在生产 main() 里，测试不跑 main。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/settings_page.dart';
import 'package:mimao/shell/shell_store.dart';

void main() {
  const violet = Color(0xFF7C6BFF);

  setUp(() {
    // 每个用例都从干净状态开始：清 provider、清 themeSeed/epoch。
    MimaoApp.systemAccentProvider = null;
    shellStore.setThemeSeed('violet');
    shellStore.systemAccentEpoch = 0;
  });

  tearDown(() {
    MimaoApp.systemAccentProvider = null;
  });

  group('MimaoApp.seed("system")', () {
    test('注入 fake provider 时返回 fake 色（直接 Color，不触发插件）', () {
      const fake = Color(0xFF123456);
      MimaoApp.systemAccentProvider = () => fake;
      expect(MimaoApp.seed('system'), fake);
    });

    test('无 provider 时回退 violet', () {
      MimaoApp.systemAccentProvider = null;
      expect(MimaoApp.seed('system'), violet);
    });

    test('provider 抛异常时回退 violet，不把异常抛给调用方', () {
      MimaoApp.systemAccentProvider = () => throw StateError('plugin down');
      expect(MimaoApp.seed('system'), violet);
    });

    test('provider 每次调用都重新读色（epoch 重建可取到新色）', () {
      var current = const Color(0xFF111111);
      MimaoApp.systemAccentProvider = () => current;
      expect(MimaoApp.seed('system'), current);
      current = const Color(0xFF222222);
      expect(MimaoApp.seed('system'), current);
    });
  });

  group('MimaoApp.seed 动态解析（既有逻辑补测）', () {
    test('seed("dyn:FF123456") 解析为对应 ARGB 色', () {
      expect(MimaoApp.seed('dyn:FF123456'), const Color(0xFF123456));
    });

    test('非法 hex 回退 violet', () {
      expect(MimaoApp.seed('dyn:ZZZZZZZZ'), violet);
      expect(MimaoApp.seed('dyn:123'), violet);
    });

    test('seedColors 8 色结构不变，仍由 seed 返回色板值', () {
      expect(MimaoApp.seedColors.length, 8);
      for (final entry in MimaoApp.seedColors.entries) {
        expect(MimaoApp.seed(entry.key), entry.value.$2);
      }
      expect(MimaoApp.seed('unknown-seed'), violet);
    });
  });

  group('shellStore.bumpSystemAccent', () {
    test('递增 systemAccentEpoch', () {
      expect(shellStore.systemAccentEpoch, 0);
      shellStore.bumpSystemAccent();
      expect(shellStore.systemAccentEpoch, 1);
      shellStore.bumpSystemAccent();
      expect(shellStore.systemAccentEpoch, 2);
    });
  });

  group('设置页"跟随系统"chip', () {
    testWidgets('外观组共 9 枚 seed chip（8 色 + 跟随系统），点击跟随系统置 themeSeed', (
      tester,
    ) async {
      // 注册表置空，避免模块设置面板干扰；本用例只看外观组。
      await resetAppModulesForTest();
      const fake = Color(0xFF123456);
      MimaoApp.systemAccentProvider = () => fake;

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsPage())),
      );
      await tester.pumpAndSettle();

      // ChoiceChip 共 9 枚：8 色 + 1 跟随系统。
      expect(find.byType(ChoiceChip), findsNWidgets(9));
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.byKey(const Key('theme-seed-system')), findsOneWidget);

      await tester.tap(find.byKey(const Key('theme-seed-system')));
      await tester.pumpAndSettle();

      expect(shellStore.themeSeed, 'system');
      expect(MimaoApp.seed(shellStore.themeSeed), fake);
    });

    testWidgets('选中跟随系统后，chip 的 selected 态为 true', (tester) async {
      await resetAppModulesForTest();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SettingsPage())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme-seed-system')));
      await tester.pumpAndSettle();

      final chip = tester.widget<ChoiceChip>(
        find.byKey(const Key('theme-seed-system')),
      );
      expect(chip.selected, isTrue);
    });
  });
}
