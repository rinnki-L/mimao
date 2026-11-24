// 小说模块接线验证（本次"假联通"修复的回归锚点）：
// 1. app_registry 生产装配把三服务注入 NovelModule（不再是零依赖空壳）；
// 2. NovelModulePage 书架/搜索 tab 真实消费注入服务的数据。
//
// 全部离线（内存 drift + fake 服务），不碰 path_provider/网络。
// ignore_for_file: deprecated_member_use — 与其他测试同款（material.dart 在 3.50 弃用）。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_entry.dart';
import 'package:mimao/novel/pages/novel_module_page.dart';
import 'package:mimao/novel/pages/novel_search_page.dart';
import 'package:mimao/novel/search_history_service.dart';
import 'package:mimao/shell/app_registry.dart';

import '../comic/comic_integration_env.dart'
    show FakeComicHttpClient, FakeSourceHost, MemoryComicSourceStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDb appDb;
  late NovelDb novelDb;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;
  late NovelSearchHistoryService searchHistory;

  setUp(() async {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    novelDb = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(novelDb, library);
    history = NovelHistoryService(novelDb, library);
    searchHistory = NovelSearchHistoryService(novelDb);
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await appDb.close();
    await novelDb.close();
  });

  test('registry 装配：注入内存 NovelDb + 三服务后 NovelModule 持有真实服务', () async {
    await initAppModules(
      library: library,
      // 漫画分件注入：避免其生产构造在无插件测试环境触发 path_provider 错误。
      comicDb: ComicDb.forTesting(NativeDatabase.memory()),
      comicSourceStore: MemoryComicSourceStore(),
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
      novelDb: novelDb,
      novelCollect: collect,
      novelHistory: history,
      novelSearchHistory: searchHistory,
    );

    expect(appModulesError, isNull);
    final module = moduleFor(MediaType.novel);
    expect(module, isA<NovelModule>());
    final novel = module as NovelModule;
    expect(novel.collect, same(collect));
    expect(novel.history, same(history));
    expect(novel.searchHistory, same(searchHistory));
    // 统计/偏好由生产装配自建（NovelStatsService），页面拿到非空实例。
    expect(novel.stats, isNotNull);
    expect(novel.prefs, isNotNull);
  });

  testWidgets('首页显示最近阅读，书架显示收藏与阅读进度（消费注入服务）', (tester) async {
    final book = NovelSummary(id: 'b1', title: '三体', author: '刘慈欣');
    await collect.collect(book);
    await history.saveProgress(book, 12, 400);

    await tester.pumpWidget(
      MaterialApp(
        home: NovelModulePage(
          collect: collect,
          history: history,
          searchHistory: searchHistory,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 首页：最近阅读卡 + 书架横条都读同一份本地数据。
    expect(find.text('三体'), findsWidgets);
    expect(find.text('刘慈欣'), findsWidgets);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.textContaining('看到第 12 章'), findsWidgets);

    // 切到书架（index 1）：网格显示收藏/历史并集与章节进度。
    await tester.tap(find.text('书架').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('三体'), findsWidgets);
    expect(find.textContaining('看到第 12 章'), findsWidgets);
  });

  testWidgets('搜索页读真实搜索历史，点历史词启动本地搜索', (tester) async {
    await searchHistory.record('三体');

    await tester.pumpWidget(
      MaterialApp(
        home: NovelSearchPage(
          collect: collect,
          history: history,
          searchHistory: searchHistory,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('三体'), findsWidgets);

    await tester.tap(find.text('三体').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 没有本地书/书源匹配 → 明示本地无结果；在线结果由引擎在下方单独给。
    expect(find.textContaining('本地没有匹配'), findsOneWidget);
    expect(await searchHistory.recent(), <String>['三体']);
  });
}
