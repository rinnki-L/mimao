// 首页 8b 的界面回归：模块开关/排序/自定义分组卡片、默认排布不变、
// 配置落 kv 后重建保持。用真实服务 + 内存库，不碰网络与插件。
// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/home/home_module_config.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_home_page.dart';
import 'package:mimao/novel/stats_service.dart';

class _FakePrefs implements NovelPrefsApi {
  _FakePrefs([Map<String, String>? seed]) : values = <String, String>{...?seed};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late AppDb appDb;
  late NovelDb novelDb;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;
  late NovelStatsService stats;

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    novelDb = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(novelDb, library);
    history = NovelHistoryService(novelDb, library);
    stats = NovelStatsService(novelDb);
  });

  tearDown(() async {
    await appDb.close();
    await novelDb.close();
  });

  Widget wrap(Widget page) => MaterialApp(home: Scaffold(body: page));

  Future<void> pumpHome(
    WidgetTester tester, {
    required NovelPrefsApi prefs,
  }) async {
    await tester.pumpWidget(
      wrap(
        NovelHomePage(
          active: true,
          collect: collect,
          history: history,
          stats: stats,
          prefs: prefs,
          onSelectTab: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openManager(WidgetTester tester) async {
    // 页头按钮与分组卡片上的设置图标共用这个 tooltip，取页头那个。
    await tester.tap(find.byKey(const Key('novel-home-modules')));
    await tester.pumpAndSettle();
  }

  testWidgets('默认配置渲染出改造前那几块', (tester) async {
    await pumpHome(tester, prefs: _FakePrefs());
    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('累计阅读'), findsOneWidget);
    expect(find.text('今日阅读目标'), findsOneWidget);
    expect(find.text('书源'), findsWidgets);
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.text('WebDAV 备份'), findsOneWidget);
  });

  testWidgets('关掉模块后首页不再渲染它，配置落 kv', (tester) async {
    final prefs = _FakePrefs();
    await pumpHome(tester, prefs: prefs);
    await openManager(tester);

    // 关掉「今日阅读目标」。
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('novel-home-module-goal')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-home-module-save')));
    await tester.pumpAndSettle();

    expect(find.text('今日阅读目标'), findsNothing);
    expect(find.text('最近阅读'), findsOneWidget);
    final saved = NovelHomeModuleConfig.decode(
      prefs.values[novelPrefHomeModules],
    );
    expect(saved.modules.firstWhere((m) => m.id == 'goal').enabled, isFalse);

    // 重建页面（模拟重启）：仍然不显示。
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, prefs: prefs);
    expect(find.text('今日阅读目标'), findsNothing);
  });

  testWidgets('上移改变顺序并落 kv，重启保持', (tester) async {
    final prefs = _FakePrefs();
    await pumpHome(tester, prefs: prefs);
    await openManager(tester);

    // 把「阅读统计」上移到第一位。
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('novel-home-module-stats')),
        matching: find.byTooltip('上移'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-home-module-save')));
    await tester.pumpAndSettle();

    final saved = NovelHomeModuleConfig.decode(
      prefs.values[novelPrefHomeModules],
    );
    expect(saved.modules.first.kind, NovelHomeModuleKind.stats);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpHome(tester, prefs: prefs);
    final statsY = tester.getTopLeft(find.text('累计阅读')).dy;
    final recentY = tester.getTopLeft(find.text('最近阅读')).dy;
    expect(statsY, lessThan(recentY));
  });

  testWidgets('自定义分组卡片：添加、展示该分组的书、可删除', (tester) async {
    final data = NovelSummary(id: 'b1', title: '三体', author: '刘慈欣');
    await collect.collect(data);
    await collect.setGroup('b1', '科幻');
    final prefs = _FakePrefs();
    await pumpHome(tester, prefs: prefs);
    await openManager(tester);

    await tester.tap(find.byKey(const Key('novel-home-module-add-group')));
    await tester.pumpAndSettle();
    // 已有分组以 chip 形式给出，点它即可添加（限定在对话框内，避免和
    // 管理器列表里的「分组卡片 · 科幻」标题撞名）。
    await tester.tap(
      find.descendant(
        // 管理器本身也是 AlertDialog，取最后弹出的那个（添加分组对话框）。
        of: find.byType(AlertDialog).last,
        matching: find.widgetWithText(ActionChip, '科幻'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-home-module-save')));
    await tester.pumpAndSettle();

    expect(find.text('分组卡片 · 科幻'), findsNothing); // 面板已关
    expect(find.text('科幻'), findsWidgets);
    // 卡片里展示了该分组的书。
    expect(find.text('三体'), findsWidgets);

    // 再打开面板删掉这张卡片。卡片排在列表末尾，先滚到它。
    await openManager(tester);
    final cardKey = find.byKey(const Key('novel-home-module-group:科幻'));
    await tester.scrollUntilVisible(
      cardKey,
      120,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: cardKey, matching: find.byTooltip('删除卡片')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-home-module-save')));
    await tester.pumpAndSettle();

    final saved = NovelHomeModuleConfig.decode(
      prefs.values[novelPrefHomeModules],
    );
    expect(
      saved.modules.where((m) => m.kind == NovelHomeModuleKind.customGroup),
      isEmpty,
    );
  });

  testWidgets('分组卡片里没有书时给出可操作说明', (tester) async {
    final prefs = _FakePrefs(<String, String>{
      novelPrefHomeModules: const NovelHomeModuleConfig(
        NovelHomeModuleConfig.defaults,
      ).addCustomGroup('空分组').encode(),
    });
    await pumpHome(tester, prefs: prefs);
    expect(find.textContaining('「空分组」里还没有书'), findsOneWidget);
  });

  testWidgets('全部关掉时首页给出恢复入口，点开能打开面板', (tester) async {
    final allOff = NovelHomeModuleConfig(<NovelHomeModule>[
      for (final module in NovelHomeModuleConfig.defaults)
        module.copyWith(enabled: false),
    ]);
    final prefs = _FakePrefs(<String, String>{
      novelPrefHomeModules: allOff.encode(),
    });
    await pumpHome(tester, prefs: prefs);
    expect(find.text('首页模块都被关掉了'), findsOneWidget);

    await tester.tap(find.text('管理模块'));
    await tester.pumpAndSettle();
    expect(find.text('首页模块'), findsWidgets);
  });

  testWidgets('恢复默认回到改造前排布', (tester) async {
    final prefs = _FakePrefs(<String, String>{
      novelPrefHomeModules: const NovelHomeModuleConfig(<NovelHomeModule>[
        NovelHomeModule(kind: NovelHomeModuleKind.stats, enabled: false),
      ]).encode(),
    });
    await pumpHome(tester, prefs: prefs);
    await openManager(tester);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-home-module-save')));
    await tester.pumpAndSettle();

    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('今日阅读目标'), findsOneWidget);
    final saved = NovelHomeModuleConfig.decode(
      prefs.values[novelPrefHomeModules],
    );
    expect(saved.modules, hasLength(NovelHomeModuleConfig.defaults.length));
    expect(saved.modules.every((m) => m.enabled), isTrue);
  });
}
