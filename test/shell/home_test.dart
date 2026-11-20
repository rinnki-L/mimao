// 壳的冒烟测试：验证入口拼贴页三个入口齐全、钻进/返回导航可用。
// 顺带把 shell/ 与其生成的 shell_store.g.dart 拉进覆盖率分母并真实执行。
// 番剧已整体下线（Bangumi 搜索国内不可用），只保留漫画/小说/音乐。
// 并在 setUp/tearDown 调 resetAppModulesForTest() 避免全局注册表跨测试泄漏。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';

import '../comic/comic_integration_env.dart'
    show FakeComicHttpClient, FakeSourceHost, MemoryComicSourceStore;

void main() {
  late AppDb appDb;
  late LibraryRepository library;

  // closure-02：漫画生产装配的分件注入（内存 DB/源仓库/假宿主）。不注入的话
  // ComicDb() 生产构造的 drift eager 连接在无插件测试环境会以 unhandled
  // async error 逃逸。
  late ComicDb comicDb;
  late MemoryComicSourceStore comicSourceStore;

  setUp(() async {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    comicDb = ComicDb.forTesting(NativeDatabase.memory());
    comicSourceStore = MemoryComicSourceStore();
    shellStore.goHome();
    shellStore.closeSettings();
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await comicDb.close();
    await appDb.close();
  });

  Widget pumpApp() {
    return LibraryScope(repository: library, child: const MimaoApp());
  }

  testWidgets('入口页展示三个媒体入口，无品牌标题、无番剧入口', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    // 品牌标题块（logo + mimao + 副标题）已去掉，不是商业软件不带门面。
    expect(find.text('mimao'), findsNothing);
    expect(find.text('漫画 · 小说 · 音乐，一站聚合'), findsNothing);
    for (final type in entryTypes) {
      expect(find.text(type.label), findsWidgets);
    }
    // 番剧不再进入口卡（代码/注册保留）。
    expect(find.text('番剧'), findsNothing);
  });

  testWidgets('点斜带钻进模块，返回后回到入口页', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    // 斜切带：点漫画带内的文字 → 一步钻进模块（按点击 y 坐标换算落带）。
    await tester.tap(find.text(MediaType.comic.label).first);
    await tester.pumpAndSettle();
    expect(find.text('${MediaType.comic.label}模块尚未接入'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    // 返回后品牌标题不会回来，用功能按钮做锚点。
    expect(find.byTooltip('统一书架'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
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
    expect(find.byTooltip('统一书架'), findsOneWidget);
  });

  testWidgets('设置抽屉可打开，只剩通用分组（外观/存储），无模块分组', (tester) async {
    await tester.pumpWidget(pumpApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    // 用户拍板：总设置与各入口设置分开——抽屉只留外观/网络/存储。
    expect(find.text('外观'), findsOneWidget);
    // 三组叠加后「存储」在绘制视口外，先滚到它再断言。
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(find.text('网络'), findsOneWidget);
    expect(find.text('存储'), findsOneWidget);
    for (final type in MediaType.values) {
      expect(find.widgetWithText(ExpansionTile, type.label), findsNothing);
    }
    expect(find.textContaining('该模块设置将在接入后开放'), findsNothing);
  });

  // 漫画（closure-02）分件注入：内存 DB/源仓库 + 假宿主（CI 无 DLL/插件）。
  // 音乐（M4 骨架）走生产装配——身份仓库惰性解析、注册留到首搜，正常用例
  // 不会触达；这里仍注入临时目录仓库，把「点开音乐设置分组也不会碰
  // path_provider 插件」的陷阱钉死。
  Future<void> initModules() => initAppModules(
    library: library,
    comicDb: comicDb,
    comicSourceStore: comicSourceStore,
    comicHttpClient: FakeComicHttpClient(),
    comicHostFactory: () => FakeSourceHost(),
    musicIdentityStore: KugouIdentityStore(Directory.systemTemp),
  );

  group('closure-02：漫画注册后', () {
    testWidgets('注册后点漫画进入 ComicModulePage，不再显示占位；返回回入口页', (tester) async {
      await initModules();
      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();

      // 斜切带：点漫画带内文字 → 一步进模块。
      await tester.tap(find.text(MediaType.comic.label).first);
      await tester.pumpAndSettle();

      expect(find.text('${MediaType.comic.label}模块尚未接入'), findsNothing);
      // 模块层内部导航（搜索/源管理）存在；内存源仓库为空 → 搜索空态兜底。
      expect(find.text('源管理'), findsOneWidget);
      expect(find.text('暂时没有可搜索的漫画'), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('统一书架'), findsOneWidget);
    });

    testWidgets('漫画设置收进模块页底部导航最右「设置」tab', (tester) async {
      await initModules();
      await tester.pumpWidget(pumpApp());
      await tester.pumpAndSettle();

      // 一步进入模块。
      await tester.tap(find.text(MediaType.comic.label).first);
      await tester.pumpAndSettle();
      // 底部导航最右一枚是「设置」；点它切到模块设置面板。
      expect(find.text('设置'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comic-settings-open-sources')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('comic-settings-clear-history')),
        findsOneWidget,
      );
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
