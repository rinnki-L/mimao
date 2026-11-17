// 壳的冒烟测试：验证入口拼贴页四个入口齐全、钻进/返回导航可用。
// 顺带把 shell/ 与其生成的 shell_store.g.dart 拉进覆盖率分母并真实执行。
// closure-01：加入"初始化后进入番剧"与"设置抽屉显示模块设置"用例，
// 并在 setUp/tearDown 调 resetAppModulesForTest() 避免全局注册表跨测试泄漏。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';

import '../anime/anime_integration_env.dart';

void main() {
  late AnimeIntegrationEnv env;

  setUp(() async {
    env = await AnimeIntegrationEnv.create();
    shellStore.goHome();
    shellStore.closeSettings();
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await env.close();
  });

  Widget pumpApp() {
    return LibraryScope(repository: env.library, child: const MimaoApp());
  }

  testWidgets('入口页展示标题与四个媒体入口', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    expect(find.text('mimao'), findsOneWidget);
    for (final type in MediaType.values) {
      expect(find.text(type.label), findsWidgets);
    }
  });

  testWidgets('点入口卡片钻进模块层，返回后回到入口页', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text(MediaType.anime.label).first);
    await tester.pumpAndSettle();
    expect(find.text('${MediaType.anime.label}模块尚未接入'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('mimao'), findsOneWidget);
  });

  testWidgets('统一书架入口显示空态', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('统一书架'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有观看记录'), findsOneWidget);
    expect(find.textContaining('追番或播放后会出现在这里'), findsOneWidget);
  });

  testWidgets('设置抽屉可打开，四个模块分组齐全', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    // 全局抽屉按「外观 / 存储 / 四模块」分组（用户拍板的 C + 全局一个设置）
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('存储'), findsOneWidget);
    for (final type in MediaType.values) {
      expect(find.text(type.label), findsWidgets);
    }
  });

  group('closure-01：模块注册后', () {
    Future<void> initModules() => initAppModules(
      library: env.library,
      animeDb: env.animeDb,
      ruleStore: env.memoryRuleStore,
      animeDataSource: env.dataSource,
      playbackEngineFactory: env.engineFactory,
    );

    testWidgets('注册后点番剧进入搜索页，不再显示占位', (tester) async {
      await initModules();
      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text(MediaType.anime.label).first);
      await tester.pumpAndSettle();

      expect(find.text('${MediaType.anime.label}模块尚未接入'), findsNothing);
      expect(find.text('共 4 部'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
        findsOneWidget,
      );
    });

    testWidgets('模块层只有一套顶部导航，返回后可再次进入', (tester) async {
      await initModules();
      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text(MediaType.anime.label).first);
      await tester.pumpAndSettle();

      // 壳的"返回 + 番剧"存在；搜索页不再画自己的"搜索" AppBar
      // （导航栏上的"搜索"标签不是 AppBar，用 descendant 精确排除）。
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.text('番剧'), findsWidgets);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('搜索')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('mimao'), findsOneWidget);

      await tester.tap(find.text(MediaType.anime.label).first);
      await tester.pumpAndSettle();
      expect(find.text('共 4 部'), findsOneWidget);
    });

    testWidgets('设置抽屉展开番剧分组显示规则面板', (tester) async {
      await initModules();
      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      // 打开番剧分组（ ExpansionTile 在抽屉里，标签与入口卡同文，取抽屉内的）。
      final animeTile = find.widgetWithText(ExpansionTile, '番剧');
      await tester.tap(animeTile.first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('anime-rule-url')), findsOneWidget);
      expect(find.byKey(const Key('anime-rule-import')), findsOneWidget);
      expect(find.text('还没有规则，先从 KazumiRules 导入'), findsOneWidget);
      expect(find.textContaining('该模块设置将在接入后开放'), findsNothing);
    });
  });
}
