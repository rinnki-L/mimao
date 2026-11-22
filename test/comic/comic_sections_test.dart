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
import 'package:mimao/comic/pages/comic_search_page.dart';

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

/// 最小稍后阅读假 API（顺序测试用：让卡片可见即可）。
class _OneReadLaterApi implements ComicReadLaterApi {
  const _OneReadLaterApi();

  @override
  Future<List<ComicLibraryEntry>> readLater() async =>
      const <ComicLibraryEntry>[
        ComicLibraryEntry(id: 'yeyu', sourceName: 'fixture', title: '夜雨剑歌'),
      ];

  @override
  Future<bool> isReadLater(String id, String sourceName) async => false;

  @override
  Future<void> setReadLater({
    required String id,
    required String sourceName,
    required String title,
    String? coverUrl,
    String detailUrl = '',
    required bool included,
  }) async {}
}

/// 最小本地假 API（顺序测试用：让卡片可见即可）。
class _OneLocalApi implements ComicLocalApi {
  const _OneLocalApi();

  @override
  Future<List<ComicLibraryEntry>> local() async => const <ComicLibraryEntry>[];

  @override
  Future<ComicDetail> detail(ComicSummary item) => throw UnimplementedError();

  @override
  Future<void> remove(ComicSummary item) async {}
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

/// 聚合搜索假源：两个成功源 + 一个失败源（0 结果带诊断），验证按源分组渲染。
class _GroupedSearchDataSource implements GroupedComicDataSource {
  const _GroupedSearchDataSource({this.allFail = false});

  /// true 时所有源均 0 结果带诊断（验证全失败仍逐源可见）。
  final bool allFail;

  static const List<String> keys = <String>['源A', '源B', '坏源'];

  @override
  List<String> availableSourceKeys() => keys;

  @override
  Future<List<ComicSummary>> search(String keyword) async =>
      FixtureComicDataSource.defaultSearchResults;

  @override
  Future<List<ComicSourceSearchSection>> searchGrouped(String keyword) async =>
      allFail
      ? <ComicSourceSearchSection>[
          for (final key in keys)
            ComicSourceSearchSection(
              sourceKey: key,
              diagnostics: <String>['$key：搜索异常（boom）'],
            ),
        ]
      : <ComicSourceSearchSection>[
          ComicSourceSearchSection(
            sourceKey: '源A',
            items: const <ComicSummary>[FixtureComicDataSource.xingzhou],
          ),
          ComicSourceSearchSection(
            sourceKey: '源B',
            items: const <ComicSummary>[
              FixtureComicDataSource.yeyu,
              FixtureComicDataSource.mihuan,
            ],
          ),
          const ComicSourceSearchSection(
            sourceKey: '坏源',
            diagnostics: <String>['坏源：搜索异常（boom）'],
          ),
        ];

  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) async =>
      (await searchGrouped(
        keyword,
      )).firstWhere((s) => s.sourceKey == key).items;

  @override
  Future<ComicDetail> detail(ComicSummary item) => throw UnimplementedError();
  @override
  List<String> takeSearchDiagnostics() => const <String>[];
  @override
  Future<List<String>> recentSearchTerms() async => const <String>[];
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
    testWidgets('显示搜索入口、阅读历史卡片与源管理卡片（旧海报区块已移除）', (tester) async {
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
      // 四张卡片：阅读历史 / 稍后阅读（未接线时隐藏）/ 本地（未接线时隐藏）/ 源管理。
      expect(find.byKey(const Key('comic-home-history-card')), findsOneWidget);
      expect(find.text('阅读历史'), findsOneWidget);
      expect(find.text('继续阅读'), findsNothing);
      // 历史卡片内嵌海报带进度文案（旧的「本地漫画」大海报区已删除）。
      expect(find.text('第 1 章 · 看到第 3 页'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('comic-home-source-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空数据时历史卡片常显并给出引导文案（无整页空态）', (tester) async {
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

      // 历史卡片常显（即使无记录），空态收进卡片，不再有整页空态。
      expect(find.byKey(const Key('comic-home-history-card')), findsOneWidget);
      expect(find.text('阅读历史'), findsOneWidget);
      expect(find.text('0 条'), findsOneWidget);
      expect(find.text('搜索并阅读漫画后，会在这里按最近阅读汇总。'), findsOneWidget);
      expect(find.text('还没有阅读记录'), findsOneWidget);
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

    testWidgets('四卡片固定顺序：历史 → 稍后阅读 → 本地 → 源管理 → 快捷 chips', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _FakeLibrary(),
            readLater: const _OneReadLaterApi(),
            localApi: const _OneLocalApi(),
            onOpenSettings: () {},
            showAppBar: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 从主页 ListView 出发按 DFS 先序遍历收集 key：兄弟节点的 DFS 顺序即
      // 屏幕自上而下的顺序，比对各卡 key 出现的先后即可断言固定顺序。
      late Element listElement;
      tester
          .element(find.byKey(const Key('comic-home-search')))
          .visitAncestorElements((ancestor) {
            if (ancestor.widget is ListView) {
              listElement = ancestor;
              return false;
            }
            return true;
          });
      final keysInOrder = <String>[];
      void collect(Element element) {
        final key = element.widget.key;
        if (key is ValueKey<String>) keysInOrder.add(key.value);
        element.visitChildren(collect);
      }

      listElement.visitChildren(collect);

      const expected = <String>[
        'comic-home-search',
        'comic-home-history-card',
        'comic-home-read-later-card',
        'comic-home-local-card',
        'comic-home-source-card',
        'comic-home-settings-chip',
      ];
      final indexes = <int>[
        for (final key in expected) keysInOrder.indexOf(key),
      ];
      // 全部找得到，且 index 严格递增（顺序即列表自上而下）。
      for (final index in indexes) {
        expect(index, isNonNegative, reason: '有卡片 key 未在树中找到');
      }
      for (var i = 1; i < indexes.length; i++) {
        expect(
          indexes[i],
          greaterThan(indexes[i - 1]),
          reason: '「${expected[i]}」应排在「${expected[i - 1]}」之后',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('历史卡片最多展示 8 条海报，但计数是完整条数', (tester) async {
      _usePhoneSize(tester);
      final library = _MutableHistoryLibrary([
        for (var i = 0; i < 12; i++)
          ComicLibraryEntry(id: 'h$i', sourceName: 'fixture', title: '历史$i'),
      ]);
      await tester.pumpWidget(
        _app(ComicHomePage(dataSource: comicFixture, library: library)),
      );
      await tester.pumpAndSettle();

      expect(find.text('12 条'), findsOneWidget);
      // 历史卡片内嵌的横向 ComicPosterRow 是懒加载 ListView：直接读它的
      // itemCount 才能稳定验证截断（滚到底后屏外子项会被回收，数挂在树上的
      // 卡片不可靠）。数据 12 条 → 行 itemCount 恰为 8。
      final rowWidget = tester.widget<ListView>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(rowWidget.semanticChildCount, 8, reason: '最多展示 8 条海报');
      expect(
        find.byKey(const ValueKey<String>('home-recent-h0')),
        findsOneWidget,
      );
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
        ComicLibraryEntry(id: 'yeyu', sourceName: 'fixture', title: '夜雨剑歌'),
      ]);
      await tester.pumpWidget(
        _app(ComicHomePage(dataSource: comicFixture, library: library)),
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

    testWidgets('长按取消不删除；点清空 → 确认 → 历史卡片保留但转空态', (tester) async {
      _usePhoneSize(tester);
      final library = _MutableHistoryLibrary(const <ComicLibraryEntry>[
        ComicLibraryEntry(id: 'xingzhou', sourceName: 'fixture', title: '星舟漫游'),
      ]);
      await tester.pumpWidget(
        _app(ComicHomePage(dataSource: comicFixture, library: library)),
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
      // 卡片保留，海报变空态引导；计数归零。
      expect(find.byKey(const Key('comic-home-history-card')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home-recent-xingzhou')),
        findsNothing,
      );
      expect(find.text('0 条'), findsOneWidget);
      expect(find.text('搜索并阅读漫画后，会在这里按最近阅读汇总。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('源管理卡片：有源时显示前几个源名与启用统计', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _FakeLibrary(),
            onOpenSources: () {},
            sourceLister: () async => const <ComicSourceInfo>[
              ComicSourceInfo(id: 'a', name: '漫画DB', url: 'u1', enabled: true),
              ComicSourceInfo(id: 'b', name: '酷漫屋', url: 'u2', enabled: false),
              ComicSourceInfo(id: 'c', name: '第三源', url: 'u3', enabled: true),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-home-source-card')), findsOneWidget);
      expect(find.text('源管理'), findsOneWidget);
      expect(find.text('已启用 2 / 共 3 个源'), findsOneWidget);
      expect(find.text('漫画DB'), findsOneWidget);
      expect(find.text('酷漫屋'), findsOneWidget);
      expect(find.text('第三源'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('源管理卡片：最多显示 5 个且启用优先；无源显示导入提示', (tester) async {
      _usePhoneSize(tester);
      // 7 个源，2 个禁用——只显示启用优先的前 5 个。
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _FakeLibrary(),
            sourceLister: () async => <ComicSourceInfo>[
              for (var i = 0; i < 7; i++)
                ComicSourceInfo(
                  id: 's$i',
                  name: '源$i',
                  url: 'u$i',
                  enabled: i >= 2,
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已启用 5 / 共 7 个源'), findsOneWidget);
      // 两个禁用源（源0/源1）被挤掉，显示的是启用的源2..源6 共 5 个。
      expect(find.text('源2'), findsOneWidget);
      expect(find.text('源6'), findsOneWidget);
      expect(find.text('源0'), findsNothing);
      expect(find.text('源1'), findsNothing);

      // 无源：降级为导入提示，不崩。
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _EmptyLibrary(),
            sourceLister: () async => const <ComicSourceInfo>[],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有导入来源，点击导入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('源管理卡片：无 sourceLister 时降级显示导入提示不崩', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(ComicHomePage(dataSource: comicFixture, library: _FakeLibrary())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-home-source-card')), findsOneWidget);
      expect(find.text('还没有导入来源，点击导入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点源管理卡片触发 onOpenSources', (tester) async {
      _usePhoneSize(tester);
      var opened = 0;
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            library: _FakeLibrary(),
            onOpenSources: () => opened++,
            sourceLister: () async => const <ComicSourceInfo>[
              ComicSourceInfo(id: 'a', name: '漫画DB', url: 'u1'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('comic-home-source-card-tap')));
      await tester.pumpAndSettle();

      expect(opened, 1);
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
      expect(find.text('还没有阅读记录'), findsNothing);
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

  group('聚合搜索按源分组', () {
    testWidgets('聚合模式：每源一个可见 section + 汇总行 + 失败原因行', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: _GroupedSearchDataSource())),
      );
      await tester.pumpAndSettle();

      // chip 文案与 Key 保持不变。
      expect(find.text('聚合搜索'), findsOneWidget);
      expect(find.byKey(const Key('source-filter-all')), findsOneWidget);
      // 汇总：3 个源、3 部结果。
      expect(find.text('3 个源 · 3 部'), findsOneWidget);
      // 每个源都有 section（含 0 结果的失败源，不能静默消失）。
      for (final key in _GroupedSearchDataSource.keys) {
        expect(
          find.byKey(Key('search-group-$key')),
          findsOneWidget,
          reason: '$key 的 section 必须可见',
        );
      }
      // 失败源原因行可见。
      expect(find.text('• 坏源：搜索异常（boom）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('单源模式：仍为摊平网格，无分组 section，计数为「共 N 部」', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: _GroupedSearchDataSource())),
      );
      await tester.pumpAndSettle();

      // 先输入关键词再选单源：空关键词下选源仍走 search('')（保持旧语义）。
      await tester.enterText(find.byType(TextField), '关键词');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-filter-源B')));
      await tester.pumpAndSettle();

      // 单源走 searchSource，结果摊平网格、无按源 section。
      expect(find.text('共 2 部'), findsOneWidget);
      expect(find.byKey(const Key('search-group-summary')), findsNothing);
      expect(find.byKey(const Key('search-group-源B')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('search-result-yeyu')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('全源失败：每个失败源 section 仍可见并显示原因，不退回笼统空态', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicSearchPage(
            dataSource: _GroupedSearchDataSource(allFail: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 个源 · 0 部'), findsOneWidget);
      for (final key in _GroupedSearchDataSource.keys) {
        expect(find.byKey(Key('search-group-$key')), findsOneWidget);
        expect(find.text('• $key：搜索异常（boom）'), findsOneWidget);
      }
      expect(find.text('搜索未成功'), findsNothing);
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

    testWidgets('点主页源管理卡片进入源管理页（模块层导航）', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicModulePage(
            dataSource: comicFixture,
            sourceRepository: FixtureComicSourceRepository(),
            library: _FakeLibrary(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 卡片渲染了 fixture 仓库的源（漫画DB 等）。
      expect(find.text('漫画DB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('comic-home-source-card-tap')));
      await tester.pumpAndSettle();

      // 已进入源管理页：出现该页特有的导入入口。
      expect(find.text('从 URL 导入源'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('从源管理页返回后主页源管理卡片重读', (tester) async {
      _usePhoneSize(tester);
      final repo = _CountingSourceRepository();
      await tester.pumpWidget(
        _app(
          ComicModulePage(
            dataSource: comicFixture,
            sourceRepository: repo,
            library: _FakeLibrary(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 主页初次读一次（卡片）+ 源管理页 push 时再读，返回后应多一次。
      final before = repo.listCalls;
      expect(before, greaterThan(0));

      await tester.tap(find.byKey(const Key('comic-home-source-card-tap')));
      await tester.pumpAndSettle();
      expect(find.text('从 URL 导入源'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(repo.listCalls, greaterThan(before));
      expect(find.byKey(const Key('comic-home-source-card')), findsOneWidget);
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

/// 记录 listSources 调用的假仓库：验证从源管理页返回后卡片重读。
class _CountingSourceRepository extends FixtureComicSourceRepository {
  _CountingSourceRepository() : super(sources: const <ComicSourceInfo>[]);

  int listCalls = 0;

  @override
  Future<List<ComicSourceInfo>> listSources() async {
    listCalls++;
    return const <ComicSourceInfo>[];
  }
}
