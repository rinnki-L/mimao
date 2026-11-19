// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/ 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/data/fixture_comic_data_source.dart';
import 'package:mimao/comic/pages/comic_detail_page.dart';
import 'package:mimao/comic/pages/comic_module_page.dart';
import 'package:mimao/comic/pages/comic_search_page.dart';
import 'package:mimao/comic/pages/comic_source_page.dart';

/// 固定 fixture：4 条搜索结果、星舟漫游 5 章、3 条来源。
const FixtureComicDataSource comicFixture = FixtureComicDataSource();

/// 「假数据切换」测试用的第二个数据源：只有 1 条、标题完全不同。
const FixtureComicDataSource switchedFixture = FixtureComicDataSource(
  searchResults: <ComicSummary>[
    ComicSummary(
      id: 'alt',
      title: '替换后的漫画',
      coverUrl: '',
      detailUrl: 'https://example.com/comic/alt',
      subtitle: '全 1 话',
    ),
  ],
);

/// 首次搜索失败、重试成功的假数据源（验证错误态 + 重试）。
class _FlakyComicDataSource implements ComicDataSource {
  _FlakyComicDataSource(this._delegate);
  final ComicDataSource _delegate;
  int _calls = 0;

  @override
  Future<List<ComicSummary>> search(String keyword) {
    _calls++;
    if (_calls == 1) {
      return Future<List<ComicSummary>>.error(StateError('network down'));
    }
    return _delegate.search(keyword);
  }

  @override
  Future<ComicDetail> detail(ComicSummary item) => _delegate.detail(item);

  // ComicDataSource 是 interface：默认方法体不被 implements 继承，补转发。
  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) =>
      search(keyword);

  @override
  List<String> availableSourceKeys() => const <String>[];
}

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF7C6BFF),
  ),
  home: home,
);

/// 小屏 390×844（验收要求）：任何 render overflow 都会作为异常让测试失败。
void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('搜索页', () {
    testWidgets('渲染 fixture 的 4 条结果并显示总数', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: comicFixture)),
      );
      await tester.pumpAndSettle();

      expect(find.text('共 4 部'), findsOneWidget);
      for (final title in <String>['星舟漫游', '夜雨剑歌', '迷幻都市', '海边文库']) {
        expect(find.text(title), findsOneWidget);
      }
      for (final id in <String>['xingzhou', 'yeyu', 'mihuan', 'haibian']) {
        expect(
          find.byKey(ValueKey<String>('search-result-$id')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜索无结果时显示空态并回显关键词', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: comicFixture)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '不存在的漫画');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('没有找到「不存在的漫画」'), findsOneWidget);
      expect(find.text('换个关键词试试'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('search-result-xingzhou')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜索出错显示错误态，点重试恢复结果', (tester) async {
      _usePhoneSize(tester);
      final flaky = _FlakyComicDataSource(comicFixture);
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: flaky)));
      await tester.pumpAndSettle();

      expect(find.text('搜索失败，请稍后重试'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('搜索失败，请稍后重试'), findsNothing);
      expect(find.text('共 4 部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('切换数据源后结果网格更新', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: comicFixture)),
      );
      await tester.pumpAndSettle();
      expect(find.text('星舟漫游'), findsOneWidget);

      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: switchedFixture)),
      );
      await tester.pumpAndSettle();

      expect(find.text('星舟漫游'), findsNothing);
      expect(find.text('替换后的漫画'), findsOneWidget);
      expect(find.text('共 1 部'), findsOneWidget);
    });

    testWidgets('390 宽独立 pump 无溢出', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: comicFixture)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('详情页', () {
    testWidgets('渲染标题、简介与 M=5 章列表', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('星舟漫游'), findsOneWidget);
      expect(find.text('简介'), findsOneWidget);
      expect(find.textContaining('殖民船'), findsOneWidget);
      expect(find.text('共 5 章'), findsOneWidget);
      for (var number = 1; number <= 5; number++) {
        expect(find.byKey(ValueKey<String>('chapter-$number')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey<String>('chapter-6')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('收藏按钮点击后回调并切换文案', (tester) async {
      _usePhoneSize(tester);
      bool? reported;
      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
            onFavoriteChanged: (value) => reported = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('收藏'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favorite-button')));
      await tester.pump();

      expect(reported, isTrue);
      expect(find.text('已收藏'), findsOneWidget);

      await tester.tap(find.byKey(const Key('favorite-button')));
      await tester.pump();

      expect(reported, isFalse);
      expect(find.text('收藏'), findsOneWidget);
    });

    testWidgets('复用详情页到另一部漫画时收藏态随新条目重置', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
            initiallyFavorite: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已收藏'), findsOneWidget);

      // 同一个 State 被复用：换 summary 且 initiallyFavorite=false，
      // 收藏按钮必须回到「收藏」而不是沿用上一部的「已收藏」。
      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.yeyu,
            initiallyFavorite: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('已收藏'), findsNothing);
    });

    testWidgets('开始阅读按钮回传详情与章节', (tester) async {
      _usePhoneSize(tester);
      ComicDetail? receivedDetail;
      ComicChapter? receivedChapter;
      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
            onStartReading: (detail, chapter) {
              receivedDetail = detail;
              receivedChapter = chapter;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('start-reading-button')));
      await tester.pump();

      expect(receivedDetail, isNotNull);
      expect(receivedDetail!.title, '星舟漫游');
      expect(receivedChapter, isNull);

      // 点单章也应走阅读回调，并带上具体章节。
      await tester.tap(find.byKey(const ValueKey<String>('chapter-2')));
      await tester.pump();
      expect(receivedChapter, isNotNull);
      expect(receivedChapter!.number, 2);
    });

    testWidgets('390 宽独立 pump 无溢出', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('源管理页', () {
    testWidgets('渲染 3 条来源并显示总数', (tester) async {
      _usePhoneSize(tester);
      final repo = FixtureComicSourceRepository();
      await tester.pumpWidget(_app(ComicSourcePage(repository: repo)));
      await tester.pumpAndSettle();

      expect(find.text('已导入 3 个来源'), findsOneWidget);
      for (final id in <String>['manhuadb', 'kumanwu', 'local']) {
        expect(find.byKey(ValueKey<String>('source-$id')), findsOneWidget);
      }
      expect(find.text('从 URL 导入源'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('从 URL 导入源回调触发且列表增长', (tester) async {
      _usePhoneSize(tester);
      final repo = FixtureComicSourceRepository();
      String? importedUrl;
      await tester.pumpWidget(
        _app(
          ComicSourcePage(
            repository: repo,
            onImport: (url) => importedUrl = url,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const url = 'https://example.com/src/newsrc';
      await tester.enterText(find.byType(TextField), url);
      await tester.tap(find.byKey(const Key('import-source-button')));
      await tester.pumpAndSettle();

      expect(importedUrl, url);
      expect(find.text('已导入 4 个来源'), findsOneWidget);
      expect(find.text('newsrc'), findsOneWidget);
    });

    testWidgets('删除源回调触发且列表减少', (tester) async {
      _usePhoneSize(tester);
      final repo = FixtureComicSourceRepository();
      ComicSourceInfo? deleted;
      await tester.pumpWidget(
        _app(
          ComicSourcePage(
            repository: repo,
            onDelete: (source) => deleted = source,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete-manhuadb')));
      await tester.pumpAndSettle();

      expect(deleted, isNotNull);
      expect(deleted!.id, 'manhuadb');
      expect(find.text('已导入 2 个来源'), findsOneWidget);
      expect(find.byKey(const Key('source-manhuadb')), findsNothing);
    });

    testWidgets('启用开关回调并更新状态', (tester) async {
      _usePhoneSize(tester);
      final repo = FixtureComicSourceRepository();
      String? toggledId;
      bool? toggledEnabled;
      ComicSourceInfo? toggledSource;
      await tester.pumpWidget(
        _app(
          ComicSourcePage(
            repository: repo,
            onToggle: (source, enabled) {
              toggledId = source.id;
              toggledEnabled = enabled;
              toggledSource = source;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // local 源初始为停用，打开它。
      final switchWidget = tester.widget<Switch>(
        find.byKey(const Key('toggle-local')),
      );
      expect(switchWidget.value, isFalse);
      await tester.tap(find.byKey(const Key('toggle-local')));
      await tester.pumpAndSettle();

      expect(toggledId, 'local');
      expect(toggledEnabled, isTrue);
      // 回传的实体必须已经是新状态，而不是切换前的旧对象。
      expect(toggledSource, isNotNull);
      expect(toggledSource!.enabled, isTrue);
      final updated = tester.widget<Switch>(
        find.byKey(const Key('toggle-local')),
      );
      expect(updated.value, isTrue);
    });

    testWidgets('390 宽独立 pump 无溢出', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(ComicSourcePage(repository: FixtureComicSourceRepository())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('模块层内部导航', () {
    testWidgets('搜索 → 详情 → 返回', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicModulePage(
            dataSource: comicFixture,
            sourceRepository: FixtureComicSourceRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('search-result-xingzhou')),
        findsOneWidget,
      );
      await tester.tap(find.text('星舟漫游'));
      await tester.pumpAndSettle();

      expect(find.text('漫画详情'), findsOneWidget);
      expect(find.text('共 5 章'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('chapter-1')), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      expect(find.text('漫画详情'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('search-result-xingzhou')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('底部导航切到源管理再切回搜索', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicModulePage(
            dataSource: comicFixture,
            sourceRepository: FixtureComicSourceRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('源管理'));
      await tester.pumpAndSettle();
      expect(find.text('已导入 3 个来源'), findsOneWidget);

      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('共 4 部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('三页可独立 pump', () {
    testWidgets('每页单独 pumpWidget 均可渲染且无溢出', (tester) async {
      _usePhoneSize(tester);

      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: comicFixture)),
      );
      await tester.pumpAndSettle();
      expect(find.text('共 4 部'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          const ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('共 5 章'), findsOneWidget);

      await tester.pumpWidget(
        _app(ComicSourcePage(repository: FixtureComicSourceRepository())),
      );
      await tester.pumpAndSettle();
      expect(find.text('已导入 3 个来源'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
