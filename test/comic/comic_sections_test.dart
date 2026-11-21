// 漫画四个功能分区（主页 / 收藏 / 发现 / 分类）的 widget 测试。
//
// 全部用离线 fixture（FixtureComicDataSource / FixtureComicBrowseSource /
// 内存假 ComicLibraryApi），不发网络、不碰 drift。
//
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/data/fixture_comic_data_source.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_category_page.dart';
import 'package:mimao/comic/pages/comic_discover_page.dart';
import 'package:mimao/comic/pages/comic_favorites_page.dart';
import 'package:mimao/comic/pages/comic_home_page.dart';
import 'package:mimao/comic/pages/comic_module_page.dart';

const FixtureComicDataSource comicFixture = FixtureComicDataSource();
const FixtureComicBrowseSource browseFixture = FixtureComicBrowseSource();

/// 假本地数据：2 条收藏、1 条历史、1 部本地漫画。
class _FakeLibrary implements ComicLibraryApi {
  const _FakeLibrary();

  static const List<ComicLibraryEntry> _defaultCollects = <ComicLibraryEntry>[
    ComicLibraryEntry(
      id: 'xingzhou',
      sourceName: 'fixture',
      title: '星舟漫游',
      subtitle: null,
    ),
    ComicLibraryEntry(id: 'yeyu', sourceName: 'fixture', title: '夜雨剑歌'),
  ];

  @override
  Future<List<ComicLibraryEntry>> collected() async => _defaultCollects;

  @override
  Future<List<ComicLibraryEntry>> recent({int limit = 20}) async =>
      const <ComicLibraryEntry>[
        ComicLibraryEntry(
          id: 'xingzhou',
          sourceName: 'fixture',
          title: '星舟漫游',
          subtitle: '第 1 章 · 看到第 3 页',
        ),
      ];

  @override
  Future<List<ComicLibraryEntry>> local() async => const <ComicLibraryEntry>[
    ComicLibraryEntry(
      id: 'local-1',
      sourceName: 'local',
      title: '本地画集',
      subtitle: '12 页',
    ),
  ];

  // interface 契约：implements 方需显式实现（接口默认体不 inherits）。
  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) async {}

  @override
  Future<void> clearHistory() async {}
}

/// 收藏为空、历史与本地也为空的假数据。
class _EmptyLibrary implements ComicLibraryApi {
  const _EmptyLibrary();

  @override
  Future<List<ComicLibraryEntry>> collected() async =>
      const <ComicLibraryEntry>[];

  @override
  Future<List<ComicLibraryEntry>> recent({int limit = 20}) async =>
      const <ComicLibraryEntry>[];

  @override
  Future<List<ComicLibraryEntry>> local() async => const <ComicLibraryEntry>[];

  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) async {}

  @override
  Future<void> clearHistory() async {}
}

/// 读数据必抛的假数据（错误态测试）。
class _BrokenLibrary implements ComicLibraryApi {
  const _BrokenLibrary();

  @override
  Future<List<ComicLibraryEntry>> collected() async =>
      throw StateError('db down');

  @override
  Future<List<ComicLibraryEntry>> recent({int limit = 20}) async =>
      throw StateError('db down');

  @override
  Future<List<ComicLibraryEntry>> local() async => throw StateError('db down');

  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) async => throw StateError('db down');

  @override
  Future<void> clearHistory() async => throw StateError('db down');
}

/// 分类树为 null 的浏览源（验证回退到 explore 分栏）。
class _NoCategoryBrowse implements ComicBrowseSource {
  const _NoCategoryBrowse(this.delegate);

  final ComicBrowseSource delegate;

  @override
  Future<List<ComicBrowseSourceInfo>> browseSources() =>
      delegate.browseSources();

  @override
  Future<List<ComicBrowseGroup>> exploreGroups(String key, {int page = 1}) =>
      delegate.exploreGroups(key, page: page);

  @override
  Future<ComicBrowseGroup> exploreSection(
    String key,
    int index, {
    int page = 1,
  }) => delegate.exploreSection(key, index, page: page);

  @override
  Future<ComicCategoryTree?> categoryTree(String key) async => null;

  @override
  Future<ComicBrowseGroup> categoryComics(
    String key,
    ComicCategoryNode node, {
    int page = 1,
  }) => delegate.categoryComics(key, node, page: page);
}

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF7C6BFF),
  ),
  home: home,
);

void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('主页分区', () {
    testWidgets('显示搜索入口、继续阅读与本地漫画', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _FakeLibrary(),
            onOpenSources: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-home-search')), findsOneWidget);
      expect(find.text('阅读历史'), findsOneWidget);
      expect(find.text('继续阅读'), findsNothing);
      expect(find.text('本地漫画'), findsOneWidget);
      // 历史行带进度文案；本地行带页数。
      expect(find.text('第 1 章 · 看到第 3 页'), findsOneWidget);
      expect(find.text('12 页'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home-local-local-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('空数据时显示空态提示', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicHomePage(
            dataSource: comicFixture,
            library: _EmptyLibrary(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有阅读记录或本地漫画'), findsOneWidget);
      expect(find.text('阅读历史'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('主页不再出现统一书架 chip', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _FakeLibrary(),
            onOpenSources: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-home-library')), findsNothing);
      expect(find.text('统一书架'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('长按阅读历史海报 → 确认 → 该条消失', (tester) async {
      _usePhoneSize(tester);
      final library = _MutableHistoryLibrary(const <ComicLibraryEntry>[
        ComicLibraryEntry(
          id: 'xingzhou',
          sourceName: 'fixture',
          title: '星舟漫游',
          subtitle: '第 1 章 · 看到第 3 页',
        ),
        ComicLibraryEntry(
          id: 'yeyu',
          sourceName: 'fixture',
          title: '夜雨剑歌',
        ),
      ]);
      await tester.pumpWidget(
        _app(
          ComicHomePage(dataSource: comicFixture, library: library),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
        findsOneWidget,
      );

      await tester.longPress(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
      );
      await tester.pumpAndSettle();
      expect(find.text('删除这条阅读历史？'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(library.removed, 1);
      expect(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('home-recent-yeyu')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('长按取消不删除；点清空 → 确认 → 阅读历史区消失并出空态', (tester) async {
      _usePhoneSize(tester);
      final library = _MutableHistoryLibrary(const <ComicLibraryEntry>[
        ComicLibraryEntry(
          id: 'xingzhou',
          sourceName: 'fixture',
          title: '星舟漫游',
        ),
      ]);
      await tester.pumpWidget(
        _app(
          ComicHomePage(dataSource: comicFixture, library: library),
        ),
      );
      await tester.pumpAndSettle();

      // 取消长按确认：条目保留。
      await tester.longPress(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(library.removed, 0);
      expect(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('comic-home-clear-history')));
      await tester.pumpAndSettle();
      expect(find.text('清空全部阅读历史？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();

      expect(library.cleared, 1);
      expect(find.text('阅读历史'), findsNothing);
      expect(find.text('还没有阅读记录或本地漫画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点搜索入口打开搜索页并可返回', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicHomePage(dataSource: comicFixture)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('comic-home-search')));
      await tester.pumpAndSettle();
      expect(find.text('共 4 部'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comic-home-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refreshKey 变化后重读历史（读完返回主页能看到新进度）', (tester) async {
      _usePhoneSize(tester);
      final library = _CountingLibrary();
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: library,
            refreshKey: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(library.recentCalls, 1);

      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: library,
            refreshKey: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(library.recentCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('读库失败显示错误态而非空态', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicHomePage(
            dataSource: comicFixture,
            library: _BrokenLibrary(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('阅读记录加载失败'), findsOneWidget);
      expect(find.text('还没有阅读记录或本地漫画'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点阅读历史条目回调打开详情', (tester) async {
      _usePhoneSize(tester);
      ComicSummary? opened;
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _FakeLibrary(),
            onOpenDetail: (item) => opened = item,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
      );
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.id, 'xingzhou');
      expect(opened!.sourceName, 'fixture');
      expect(tester.takeException(), isNull);
    });
  });

  group('收藏分区', () {
    testWidgets('渲染收藏网格与总数', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(ComicFavoritesPage(library: _FakeLibrary())),
      );
      await tester.pumpAndSettle();

      expect(find.text('共 2 部'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('favorite-xingzhou')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('favorite-yeyu')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('无收藏时显示空态', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicFavoritesPage(library: _EmptyLibrary())),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有收藏的漫画'), findsOneWidget);
      expect(find.textContaining('详情页点收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('读库失败显示错误态并可重试', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicFavoritesPage(library: _BrokenLibrary())),
      );
      await tester.pumpAndSettle();

      expect(find.text('收藏列表加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refreshKey 变化后重读列表', (tester) async {
      _usePhoneSize(tester);
      final library = _CountingLibrary();
      await tester.pumpWidget(
        _app(ComicFavoritesPage(library: library, refreshKey: 0)),
      );
      await tester.pumpAndSettle();
      expect(library.collectedCalls, 1);

      await tester.pumpWidget(
        _app(ComicFavoritesPage(library: library, refreshKey: 1)),
      );
      await tester.pumpAndSettle();
      expect(library.collectedCalls, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('发现分区', () {
    testWidgets('默认选中第一个源并展示各分区横向条', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicDiscoverPage(browseSource: browseFixture)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discover-source-fixture')), findsOneWidget);
      expect(find.text('推荐'), findsWidgets);
      expect(find.text('排行'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('discover-0-xingzhou')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('切源后展示新源的探索分区', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicDiscoverPage(browseSource: browseFixture)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('discover-source-fixture-plain')));
      await tester.pumpAndSettle();

      expect(find.text('最新'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('discover-0-haibian')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点卡片回调打开详情（sourceName 保留）', (tester) async {
      _usePhoneSize(tester);
      ComicSummary? opened;
      await tester.pumpWidget(
        _app(
          ComicDiscoverPage(
            browseSource: browseFixture,
            onOpenDetail: (item) => opened = item,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('discover-0-xingzhou')),
      );
      await tester.pumpAndSettle();

      expect(opened?.id, 'xingzhou');
      // fixture 条目的 sourceName 由 fixture 数据自带（漫画DB），回调原样透传。
      expect(opened?.sourceName, '漫画DB');
      expect(tester.takeException(), isNull);
    });

    testWidgets('无可用源时显示引导空态', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicDiscoverPage(
            browseSource: FixtureComicBrowseSource(
              sources: <ComicBrowseSourceInfo>[],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有可浏览的来源'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('分类分区', () {
    testWidgets('有分类树时列出分组与分类项，点分类拉列表', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicCategoryPage(browseSource: browseFixture)),
      );
      await tester.pumpAndSettle();

      expect(find.text('题材'), findsOneWidget);
      expect(find.byKey(const Key('category-item-cat-0-科幻')), findsOneWidget);
      expect(find.text('选择一个分类查看漫画'), findsOneWidget);

      await tester.tap(find.byKey(const Key('category-item-cat-0-科幻')));
      await tester.pumpAndSettle();

      expect(find.text('共 4 部'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('category-result-xingzhou')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('源没有 category 时回退到 explore 分栏并给提示', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicCategoryPage(
            browseSource: _NoCategoryBrowse(browseFixture),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('category-fallback-hint')), findsOneWidget);
      expect(find.text('探索'), findsOneWidget);
      // 回退项用分区标题（推荐/排行）作分类名。
      expect(find.byKey(const Key('category-item-explore-0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('category-item-explore-0')));
      await tester.pumpAndSettle();
      expect(find.text('共 4 部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('切源后分类树随之变化', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicCategoryPage(browseSource: browseFixture)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category-item-cat-0-科幻')), findsOneWidget);

      // 第二个源没有分类 → 回退提示。
      await tester.tap(find.byKey(const Key('category-source-fixture-plain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category-fallback-hint')), findsOneWidget);
      expect(find.byKey(const Key('category-item-cat-0-科幻')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('模块页四分区联动', () {
    testWidgets('四个 tab 均可切换且有内容', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicModulePage(
            dataSource: comicFixture,
            sourceRepository: FixtureComicSourceRepository(),
            browseSource: browseFixture,
            library: _FakeLibrary(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 主页
      expect(find.byKey(const Key('comic-home-search')), findsOneWidget);

      // 收藏
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('共 2 部'), findsOneWidget);

      // 发现
      await tester.tap(find.text('发现'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('discover-0-xingzhou')),
        findsOneWidget,
      );

      // 分类
      await tester.tap(find.text('分类'));
      await tester.pumpAndSettle();
      expect(find.text('选择一个分类查看漫画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('设置面板从主页按钮弹出（不占底部 tab）', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicModulePage(
            dataSource: comicFixture,
            sourceRepository: FixtureComicSourceRepository(),
            settingsTab: const Text('模块设置内容'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 底部栏只有四个功能分区，没有「设置」。
      expect(find.text('设置'), findsNothing);
      // 独立 pump（非 embedded）时设置入口在主页 AppBar 右上角。
      await tester.tap(find.byKey(const Key('comic-home-settings')));
      await tester.pumpAndSettle();

      expect(find.text('模块设置内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 记录 collected() 调用次数的假数据源（refreshKey 测试用）。
class _CountingLibrary implements ComicLibraryApi {
  int collectedCalls = 0;
  int recentCalls = 0;

  @override
  Future<List<ComicLibraryEntry>> collected() async {
    collectedCalls++;
    return _FakeLibrary._defaultCollects;
  }

  @override
  Future<List<ComicLibraryEntry>> recent({int limit = 20}) async {
    recentCalls++;
    return const <ComicLibraryEntry>[];
  }

  @override
  Future<List<ComicLibraryEntry>> local() async => const <ComicLibraryEntry>[];

  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) async {}

  @override
  Future<void> clearHistory() async {}
}


/// 可变历史假库：验证长按删除与一键清空后主页立即重读。
class _MutableHistoryLibrary implements ComicLibraryApi {
  _MutableHistoryLibrary(this._history);

  List<ComicLibraryEntry> _history;
  int removed = 0;
  int cleared = 0;

  @override
  Future<List<ComicLibraryEntry>> collected() async =>
      const <ComicLibraryEntry>[];

  @override
  Future<List<ComicLibraryEntry>> recent({int limit = 20}) async =>
      List<ComicLibraryEntry>.unmodifiable(_history);

  @override
  Future<List<ComicLibraryEntry>> local() async => const <ComicLibraryEntry>[];

  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) async {
    removed++;
    _history = [
      for (final entry in _history)
        if (!(entry.id == id && entry.sourceName == sourceName)) entry,
    ];
  }

  @override
  Future<void> clearHistory() async {
    cleared++;
    _history = const <ComicLibraryEntry>[];
  }
}
