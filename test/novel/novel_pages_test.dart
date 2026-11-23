// 小说页面层测试：首页/书架/详情/阅读记录/设置/发现/订阅在真实服务 + 内存库上
// 渲染与交互。全部离线；文件选择注入 fake gate，不碰 path_provider/file_picker。
// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款。
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/booklist_io.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_book_detail_page.dart';
import 'package:mimao/novel/pages/novel_discover_page.dart';
import 'package:mimao/novel/pages/novel_history_page.dart';
import 'package:mimao/novel/pages/novel_home_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_settings_page.dart';
import 'package:mimao/novel/pages/novel_shelf_page.dart';
import 'package:mimao/novel/pages/novel_widgets.dart' show novelDurationParts;
import 'package:mimao/novel/pages/novel_subscribe_page.dart';
import 'package:mimao/novel/search_history_service.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';
import 'package:mimao/novel/stats_service.dart';

void main() {
  late AppDb appDb;
  late NovelDb novelDb;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;
  late NovelSearchHistoryService searchHistory;
  late NovelStatsService stats;

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    novelDb = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(novelDb, library);
    history = NovelHistoryService(novelDb, library);
    searchHistory = NovelSearchHistoryService(novelDb);
    stats = NovelStatsService(novelDb);
  });

  tearDown(() async {
    await appDb.close();
    await novelDb.close();
  });

  NovelSummary book(String id, String title, {String author = '作者'}) =>
      NovelSummary(id: id, title: title, author: author);

  Widget wrap(Widget page) {
    return MaterialApp(
      theme: buildMimaoTheme(
        seedColor: const Color(0xFF7C6BFF),
        brightness: Brightness.light,
      ),
      home: Scaffold(body: page),
    );
  }

  testWidgets('首页：最近阅读、统计、目标进度全部来自本地库', (tester) async {
    final data = book('b1', '迷雾之上', author: '薄情书生');
    await collect.collect(data);
    await history.saveProgress(data, 319, 450);
    await stats.addReadingTime(const Duration(minutes: 11));
    await stats.addReadingTime(
      const Duration(seconds: 429900),
      at: DateTime(2020, 1, 1),
    );

    await tester.pumpWidget(
      wrap(
        NovelHomePage(
          active: true,
          collect: collect,
          history: history,
          stats: stats,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('迷雾之上'), findsWidgets);
    expect(find.text('累计阅读'), findsOneWidget);
    expect(find.text('119.6'), findsOneWidget);
    expect(find.text('11 / 30'), findsOneWidget);
    expect(find.textContaining('还差 19 分钟'), findsOneWidget);
  });

  testWidgets('首页：书架只显示一次，且有 WebDAV 备份卡、无书源管理按钮', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrap(
        NovelHomePage(
          active: true,
          collect: collect,
          history: history,
          stats: stats,
          prefs: stats,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 需求4：我的书架标题只出现一次（旧版窄屏分支 + 底部各一次）。
    expect(find.text('我的书架'), findsOneWidget);
    // 需求5：首页有 WebDAV 备份入口。
    expect(find.text('WebDAV 备份'), findsOneWidget);
    // 需求3：首页书源卡不再有「管理」按钮，设置也不在首页。
    expect(find.byKey(const Key('novel-home-manage-source')), findsNothing);
    expect(find.byKey(const Key('novel-home-settings')), findsNothing);
    // 书源管理只保留在「订阅 → 导入规则 / 规则管理」等入口，首页不再出现。
    expect(find.byKey(const Key('novel-home-import-source')), findsNothing);
  });

  testWidgets('WebDAV 备份卡：点开可配置地址', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrap(
        NovelHomePage(
          active: true,
          collect: collect,
          history: history,
          stats: stats,
          prefs: stats,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('WebDAV 备份'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-webdav-url')), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
  });

  testWidgets('书架：筛选/分组/右键菜单入口与真实数据', (tester) async {
    final reading = book('b1', '迷雾之上');
    final unread = book('b2', '我有一座冒险屋');
    await collect.collect(reading);
    await collect.collect(unread);
    await collect.setGroup('b1', '在读组');
    await history.saveProgress(reading, 319, 450);

    await tester.pumpWidget(
      wrap(
        NovelShelfPage(
          active: true,
          collect: collect,
          history: history,
          prefs: stats,
          booklistGate: _FakeGate(),
          onSelectTab: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsWidgets);
    expect(find.textContaining('在读'), findsWidgets);
    expect(find.text('迷雾之上'), findsWidgets);
    expect(find.textContaining('看到第 319 章'), findsWidgets);
    // 「在读」默认筛掉未读的那本。
    expect(find.text('我有一座冒险屋'), findsNothing);

    await tester.tap(find.textContaining('全部').first);
    await tester.pumpAndSettle();
    expect(find.text('我有一座冒险屋'), findsWidgets);

    // 点卡片走 typed 路由（不真正 push，只观察参数）。
    NovelRoute? opened;
    Map<String, Object?>? openedArgs;
    await tester.pumpWidget(
      wrap(
        NovelShelfPage(
          active: true,
          collect: collect,
          history: history,
          prefs: stats,
          booklistGate: _FakeGate(),
          onSelectTab: (_) {},
          openRoute: (route, {args = const <String, Object?>{}}) async {
            opened = route;
            openedArgs = args;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('迷雾之上').first);
    await tester.pumpAndSettle();
    expect(opened, NovelRoute.bookInfo);
    expect(openedArgs?['bookId'], 'b1');
  });

  testWidgets('书架：导入/导出书单经 file gate 闭环', (tester) async {
    final gate = _FakeGate()
      ..pickFile = NovelPickedFile(
        name: 'list.json',
        bytes: Uint8List.fromList(
          utf8.encode(
            encodeNovelBooklist(const <NovelBooklistBook>[
              NovelBooklistBook(id: 'x1', title: '导入的书', groupName: '组A'),
            ]),
          ),
        ),
      );
    await tester.pumpWidget(
      wrap(
        NovelShelfPage(
          active: true,
          collect: collect,
          history: history,
          prefs: stats,
          booklistGate: gate,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入书单').last);
    await tester.pumpAndSettle();

    final imported = await collect.list();
    expect(imported.single.title, '导入的书');
    expect(imported.single.groupName, '组A');

    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出书单'));
    await tester.pumpAndSettle();
    expect(gate.savedName, contains('书单'));
    expect(utf8.decode(gate.savedBytes!), contains('导入的书'));
  });

  testWidgets('书籍详情：收藏切换与本地进度', (tester) async {
    final data = book('b1', '三体', author: '刘慈欣');
    await collect.collect(data);
    await history.saveProgress(data, 12, 400);

    await tester.pumpWidget(
      wrap(
        NovelBookDetailPage(bookId: 'b1', collect: collect, history: history),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('三体'), findsWidgets);
    expect(find.text('已收藏'), findsOneWidget);
    expect(find.textContaining('看到第 12 章'), findsWidgets);
    expect(find.text('本地阅读记录'), findsOneWidget);

    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();
    expect(find.text('未收藏'), findsOneWidget);
    expect(await collect.isCollected('b1'), isFalse);
    // 取消收藏但历史仍在 → 详情页继续显示这本书。
    expect(find.text('三体'), findsWidgets);
  });

  testWidgets('阅读记录：单条删除需确认，清空后显示空态', (tester) async {
    await history.saveProgress(book('b1', '三体'), 12, 400);
    await history.saveProgress(book('b2', '球状闪电'), 1, 10);

    await tester.pumpWidget(wrap(NovelHistoryPage(history: history)));
    await tester.pumpAndSettle();
    expect(find.text('三体'), findsWidgets);
    expect(find.text('球状闪电'), findsWidgets);

    await tester.tap(find.byTooltip('删除这条记录').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('删除《'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 两条记录 openedAt 相近，删除按钮顺序不稳定；只断言删掉了一条。
    final remaining =
        find.text('球状闪电').evaluate().length + find.text('三体').evaluate().length;
    expect(remaining, 1);

    await tester.tap(find.byTooltip('清空阅读记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读记录'), findsOneWidget);
  });

  testWidgets('设置页：改阅读目标落到模块 kv', (tester) async {
    await searchHistory.record('三体');

    await tester.pumpWidget(
      wrap(
        NovelSettingsPage(
          stats: stats,
          searchHistory: searchHistory,
          history: history,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每天 30 分钟 · 今日已读 0 分钟'), findsOneWidget);
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '45');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect((await stats.snapshot()).goalMinutes, 45);
    expect(find.textContaining('每天 45 分钟'), findsOneWidget);
  });

  testWidgets('发现与订阅：书源分组、筛选与启停', (tester) async {
    final store = _MemorySourceStorage(<NovelBookSource>[
      _source('源甲', 'https://a.example', '小说源'),
      _source('源乙', 'https://b.example', '常用,小说源'),
      _source('源丙', 'https://c.example', ''),
    ]);
    final importer = NovelSourceImporter(store, _ThrowingFetcher());

    await tester.pumpWidget(
      wrap(NovelDiscoverPage(active: true, sourceImporter: importer)),
    );
    await tester.pumpAndSettle();
    expect(find.text('发现'), findsWidgets);
    expect(find.text('小说源'), findsWidgets);
    expect(find.text('9 个书源'), findsNothing);
    expect(find.text('3 个书源'), findsNothing);
    expect(find.textContaining('3 个书源 · 3 个启用'), findsOneWidget);

    await tester.tap(find.textContaining('常用').first);
    await tester.pumpAndSettle();
    expect(find.text('源乙'), findsOneWidget);
    expect(find.text('源甲'), findsNothing);

    await tester.pumpWidget(
      wrap(NovelSubscribePage(active: true, sourceImporter: importer)),
    );
    await tester.pumpAndSettle();
    expect(find.text('订阅'), findsWidgets);
    // 订阅页只展示订阅卡片：默认「喵公子书源管理」，不再平铺单个书源。
    expect(find.text('喵公子书源管理'), findsOneWidget);
    expect(find.textContaining('个书源 · 点按打开网站'), findsOneWidget);
    expect(find.text('源甲'), findsNothing);
    expect(find.text('源丙'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('订阅页：点订阅卡片满窗口进站点页，返回回到订阅页', (tester) async {
    final store = _MemorySourceStorage(<NovelBookSource>[]);
    final importer = NovelSourceImporter(store, _ThrowingFetcher());

    await tester.pumpWidget(
      wrap(
        NovelSubscribePage(
          active: true,
          sourceImporter: importer,
          webViewBuilder: (context, onImportLink) =>
              const Center(child: Text('假站点页')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('喵公子书源管理'));
    await tester.pumpAndSettle();
    expect(find.text('假站点页'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('喵公子书源管理'), findsOneWidget);
    expect(find.text('假站点页'), findsNothing);
  });

  testWidgets('订阅页：导入规则弹窗带类型选择，导入后落库并给反馈', (tester) async {
    final store = _MemorySourceStorage(<NovelBookSource>[]);
    final importer = NovelSourceImporter(
      store,
      _JsonFetcher(<Object?>[
        <String, Object?>{
          'bookSourceName': '弹窗导入源',
          'bookSourceUrl': 'https://dialog.example',
        },
      ]),
    );

    await tester.pumpWidget(
      wrap(NovelSubscribePage(active: true, sourceImporter: importer)),
    );
    await tester.pumpAndSettle();

    // 旧入口「导入书源」已改名：三类规则共用一个入口。
    expect(find.text('导入书源'), findsNothing);
    await tester.tap(find.byKey(const Key('novel-subscribe-import-rule')));
    await tester.pumpAndSettle();

    // 弹窗标题与页头按钮同名，至少各出现一次。
    expect(find.text('导入规则'), findsWidgets);
    expect(find.byKey(const Key('novel-rule-import-submit')), findsOneWidget);
    for (final label in <String>['自动识别', '书源', '订阅源', '替换规则']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.enterText(
      find.byKey(const Key('novel-rule-import-link')),
      'https://dialog.example/books.json',
    );
    await tester.tap(find.byKey(const Key('novel-rule-import-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('已导入 1 个书源'), findsOneWidget);
    expect(store.sources, hasLength(1));
    expect(store.sources.single.name, '弹窗导入源');
  });

  test('阅读时长格式：0/不足一分钟/分钟/小时', () {
    expect(novelDurationParts(0), ('0', '分钟'));
    expect(novelDurationParts(30), ('不到 1', '分钟'));
    expect(novelDurationParts(5 * 60), ('5', '分钟'));
    expect(novelDurationParts(119.6 * 3600 ~/ 1), ('119.6', '小时'));
  });
}

NovelBookSource _source(String name, String url, String group) {
  final raw = <String, dynamic>{
    'bookSourceName': name,
    'bookSourceUrl': url,
    'bookSourceGroup': group,
    'bookSourceType': 0,
  };
  return NovelBookSource.fromLegado(raw);
}

class _FakeGate implements NovelBooklistFileGate {
  NovelPickedFile? pickFile;
  String? savedName;
  Uint8List? savedBytes;

  @override
  Future<NovelPickedFile?> pick() async => pickFile;

  @override
  Future<String?> save(String suggestedName, Uint8List bytes) async {
    savedName = suggestedName;
    savedBytes = bytes;
    return suggestedName;
  }
}

class _ThrowingFetcher implements NovelSourceFetcher {
  @override
  Future<NovelSourceFetchResult> fetch(String url) async =>
      throw StateError('not used');
}

class _JsonFetcher implements NovelSourceFetcher {
  _JsonFetcher(this.payload);

  final Object? payload;

  @override
  Future<NovelSourceFetchResult> fetch(String url) async =>
      NovelSourceFetchResult(text: jsonEncode(payload), finalUrl: url);
}

class _MemorySourceStorage implements NovelSourceStorage {
  _MemorySourceStorage(this.sources);

  final List<NovelBookSource> sources;

  @override
  Future<List<NovelBookSource>> loadAll() async => List.unmodifiable(sources);

  @override
  Future<int> saveAll(Iterable<NovelBookSource> input) async {
    final unique = <String, NovelBookSource>{for (final s in input) s.key: s};
    sources
      ..removeWhere((s) => unique.containsKey(s.key))
      ..addAll(unique.values);
    return unique.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {
    final index = sources.indexWhere((s) => s.key == key);
    if (index >= 0) sources[index] = sources[index].copyWith(enabled: enabled);
  }

  @override
  Future<bool> delete(String key) async {
    final before = sources.length;
    sources.removeWhere((s) => s.key == key);
    return sources.length != before;
  }
}
