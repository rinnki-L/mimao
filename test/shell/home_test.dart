// 壳的冒烟测试：验证入口拼贴页四个入口齐全、钻进/返回导航可用。
// 顺带把 shell/ 与其生成的 shell_store.g.dart 拉进覆盖率分母并真实执行。
// closure-01：加入"初始化后进入番剧"与"设置抽屉显示模块设置"用例，
// 并在 setUp/tearDown 调 resetAppModulesForTest() 避免全局注册表跨测试泄漏。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';

import '../anime/anime_integration_env.dart';
import '../comic/comic_integration_env.dart'
    show FakeComicHttpClient, FakeSourceHost, MemoryComicSourceStore;

void main() {
  late AnimeIntegrationEnv env;

  // closure-02：漫画生产装配的分件注入（内存 DB/源仓库/假宿主）。不注入的话
  // ComicDb() 生产构造的 drift eager 连接在无插件测试环境会以 unhandled
  // async error 逃逸。
  late ComicDb comicDb;
  late MemoryComicSourceStore comicSourceStore;

  setUp(() async {
    env = await AnimeIntegrationEnv.create();
    comicDb = ComicDb.forTesting(NativeDatabase.memory());
    comicSourceStore = MemoryComicSourceStore();
    shellStore.goHome();
    shellStore.closeSettings();
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await comicDb.close();
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

  testWidgets('统一书架页有返回入口，返回后回到入口页', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('统一书架'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有观看记录'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('mimao'), findsOneWidget);
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

  // 番剧（closure-01）与漫画（closure-02）都分件注入：番剧用 fixture 数据源
  // 与 fake 播放器；漫画用内存 DB/源仓库 + 假宿主（CI 无 DLL/插件）。
  // 音乐（M4 骨架）走生产装配——身份仓库惰性解析、注册留到首搜，正常用例
  // 不会触达；这里仍注入临时目录仓库，把「点开音乐设置分组也不会碰
  // path_provider 插件」的陷阱钉死。
  Future<void> initModules() => initAppModules(
    library: env.library,
    animeDb: env.animeDb,
    ruleStore: env.memoryRuleStore,
    animeDataSource: env.dataSource,
    playbackEngineFactory: env.engineFactory,
    comicDb: comicDb,
    comicSourceStore: comicSourceStore,
    comicHttpClient: FakeComicHttpClient(),
    comicHostFactory: () => FakeSourceHost(),
    musicIdentityStore: KugouIdentityStore(Directory.systemTemp),
  );

  group('closure-01：模块注册后', () {
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
      // 外观组展开后较高，番剧分组常在首屏之下：先把抽屉滚出来再点。
      // （skipOffstage 的 finder 会跳过视口外仍在缓存区的 tile——非「懒」问题，
      // scrollUntilVisible 是滚动容器的正解。）
      final animeTile = find.widgetWithText(ExpansionTile, '番剧');
      await tester.scrollUntilVisible(
        animeTile,
        100,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ).last,
      );
      // scrollUntilVisible 在 tile 进入「缓存区」即停（可能仍在视口下方），
      // ensureVisible 把它真正滚进屏幕再点。
      await tester.ensureVisible(animeTile.first);
      await tester.pumpAndSettle();
      await tester.tap(animeTile.first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('anime-rule-url')), findsOneWidget);
      expect(find.byKey(const Key('anime-rule-import')), findsOneWidget);
      expect(find.text('还没有规则，先从 KazumiRules 导入'), findsOneWidget);
      expect(find.textContaining('该模块设置将在接入后开放'), findsNothing);
    });
  });

  group('closure-02：漫画注册后', () {
    testWidgets('注册后点漫画进入 ComicModulePage，不再显示占位；返回回入口页', (tester) async {
      await initModules();
      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text(MediaType.comic.label).first);
      await tester.pumpAndSettle();

      expect(find.text('${MediaType.comic.label}模块尚未接入'), findsNothing);
      // 模块层内部导航（搜索/源管理）存在；内存源仓库为空 → 搜索空态兜底。
      expect(find.text('源管理'), findsOneWidget);
      expect(find.text('暂时没有可搜索的漫画'), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('mimao'), findsOneWidget);
    });

    testWidgets('设置抽屉展开漫画分组显示模块设置面板', (tester) async {
      await initModules();
      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      // 同 closure-01：漫画分组在首屏之下时先滚出来再点。
      final comicTile = find.widgetWithText(ExpansionTile, '漫画');
      await tester.scrollUntilVisible(
        comicTile,
        100,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ).last,
      );
      // 同 closure-01：缓存区 ≠ 可见，ensureVisible 后再点。
      await tester.ensureVisible(comicTile.first);
      await tester.pumpAndSettle();
      await tester.tap(comicTile.first);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comic-settings-open-sources')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('comic-settings-clear-history')),
        findsOneWidget,
      );
      expect(find.textContaining('该模块设置将在接入后开放'), findsNothing);
    });

    testWidgets('resetAppModulesForTest 后漫画恢复占位', (tester) async {
      await initModules();
      await resetAppModulesForTest();

      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text(MediaType.comic.label).first);
      await tester.pumpAndSettle();
      expect(find.text('${MediaType.comic.label}模块尚未接入'), findsOneWidget);
    });
  });
}
