// ignore_for_file: deprecated_member_use — 见 lib/anime/pages/ 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/fixture_anime_data_source.dart';
import 'package:mimao/anime/pages/anime_cover.dart';
import 'package:mimao/anime/pages/anime_detail_page.dart';
import 'package:mimao/anime/pages/anime_image_mirror.dart';
import 'package:mimao/anime/pages/anime_module_page.dart';
import 'package:mimao/anime/pages/anime_schedule_page.dart';
import 'package:mimao/anime/pages/anime_search_page.dart';

/// 固定 fixture：4 条搜索结果、星海旅人 5 集、时间表 4 天 7 部。
const FixtureAnimeDataSource fixture = FixtureAnimeDataSource();

/// 「假数据切换」测试用的第二个 fixture：只有 1 条、标题完全不同。
const FixtureAnimeDataSource switchedFixture = FixtureAnimeDataSource(
  searchResults: <AnimeSummary>[
    AnimeSummary(
      id: 'alt',
      title: '替换后的番剧',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/alt',
      subtitle: '全 1 话',
    ),
  ],
);

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
      await tester.pumpWidget(_app(const AnimeSearchPage(dataSource: fixture)));
      await tester.pumpAndSettle();

      expect(find.text('共 4 部'), findsOneWidget);
      for (final title in <String>['星海旅人', '赛博厨房', '雾都侦探社', '夏日回声']) {
        expect(find.text(title), findsOneWidget);
      }
      for (final id in <String>['xinghai', 'saibo', 'wudu', 'xiari']) {
        expect(
          find.byKey(ValueKey<String>('search-result-$id')),
          findsOneWidget,
        );
      }
    });

    testWidgets('搜索无结果时显示空态并回显关键词', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(_app(const AnimeSearchPage(dataSource: fixture)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '不存在的番剧');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('没有找到「不存在的番剧」'), findsOneWidget);
      expect(find.text('换个关键词试试'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
        findsNothing,
      );
    });

    testWidgets('切换数据源后结果网格更新', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(_app(const AnimeSearchPage(dataSource: fixture)));
      await tester.pumpAndSettle();
      expect(find.text('星海旅人'), findsOneWidget);

      await tester.pumpWidget(
        _app(const AnimeSearchPage(dataSource: switchedFixture)),
      );
      await tester.pumpAndSettle();

      expect(find.text('星海旅人'), findsNothing);
      expect(find.text('替换后的番剧'), findsOneWidget);
      expect(find.text('共 1 部'), findsOneWidget);
    });

    testWidgets('390 宽独立 pump 无溢出', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(_app(const AnimeSearchPage(dataSource: fixture)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('详情页', () {
    testWidgets('渲染标题、简介与 M=5 集列表', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const AnimeDetailPage(
            dataSource: fixture,
            summary: FixtureAnimeDataSource.xinghai,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('星海旅人'), findsOneWidget);
      expect(find.text('简介'), findsOneWidget);
      expect(find.textContaining('殖民船'), findsOneWidget);
      expect(find.text('共 5 集'), findsOneWidget);
      for (var number = 1; number <= 5; number++) {
        expect(find.byKey(ValueKey<String>('episode-$number')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey<String>('episode-6')), findsNothing);
    });

    testWidgets('追番按钮点击后回调并切换文案', (tester) async {
      _usePhoneSize(tester);
      bool? reported;
      await tester.pumpWidget(
        _app(
          AnimeDetailPage(
            dataSource: fixture,
            summary: FixtureAnimeDataSource.xinghai,
            onFavoriteChanged: (value) => reported = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('追番'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favorite-button')));
      await tester.pump();

      expect(reported, isTrue);
      expect(find.text('已追番'), findsOneWidget);

      await tester.tap(find.byKey(const Key('favorite-button')));
      await tester.pump();

      expect(reported, isFalse);
      expect(find.text('追番'), findsOneWidget);
    });

    testWidgets('390 宽独立 pump 无溢出', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const AnimeDetailPage(
            dataSource: fixture,
            summary: FixtureAnimeDataSource.xinghai,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('时间表页', () {
    testWidgets('按星期分组：4 天 / 7 部，数量正确', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const AnimeSchedulePage(dataSource: fixture)),
      );
      await tester.pumpAndSettle();

      expect(find.text('本周 4 天 · 7 部'), findsOneWidget);
      for (final day in <String>['monday', 'wednesday', 'friday', 'saturday']) {
        expect(
          find.byKey(ValueKey<String>('schedule-section-$day')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey<String>('schedule-section-tuesday')),
        findsNothing,
      );
      for (final id in <String>[
        'xinghai',
        'saibo',
        'wudu',
        'xiari',
        'yuemian',
        'shenhai',
        'zhishang',
      ]) {
        expect(
          find.byKey(ValueKey<String>('schedule-item-$id')),
          findsOneWidget,
        );
      }

      // 周一 2 部、周三/周六各 1 部、周五 3 部。
      expect(find.text('2 部'), findsOneWidget);
      expect(find.text('1 部'), findsNWidgets(2));
      expect(find.text('3 部'), findsOneWidget);
    });

    testWidgets('390 宽独立 pump 无溢出', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const AnimeSchedulePage(dataSource: fixture)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('模块层内部导航', () {
    testWidgets('搜索 → 详情 → 返回', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(_app(const AnimeModulePage(dataSource: fixture)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
        findsOneWidget,
      );
      await tester.tap(find.text('星海旅人'));
      await tester.pumpAndSettle();

      expect(find.text('番剧详情'), findsOneWidget);
      expect(find.text('共 5 集'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('episode-1')), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      expect(find.text('番剧详情'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
        findsOneWidget,
      );
    });

    testWidgets('底部导航切到时间表后可打开详情', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(_app(const AnimeModulePage(dataSource: fixture)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('时间表'));
      await tester.pumpAndSettle();
      expect(find.text('本周 4 天 · 7 部'), findsOneWidget);

      await tester.tap(find.text('星海旅人'));
      await tester.pumpAndSettle();
      expect(find.text('番剧详情'), findsOneWidget);
    });

    testWidgets('onOpenDetail 收到列表项，正常返回时详情照常打开', (tester) async {
      _usePhoneSize(tester);
      final openedIds = <String>[];
      await tester.pumpWidget(
        _app(
          AnimeModulePage(
            dataSource: fixture,
            onOpenDetail: (item) async => openedIds.add(item.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
      );
      await tester.pumpAndSettle();

      expect(openedIds, <String>['xinghai']);
      expect(find.text('番剧详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('缺省 onOpenDetail：行为与现状一致——详情照常打开、无异常', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(_app(const AnimeModulePage(dataSource: fixture)));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
      );
      await tester.pumpAndSettle();

      expect(find.text('番剧详情'), findsOneWidget);
      expect(find.text('共 5 集'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('换源（选择规则观看）', () {
    /// 三条规则都提供同一部番的详情，剧集 URL 带各自规则名，便于断言换源生效。
    late _MultiSourceDataSource multi;

    setUp(() {
      multi = _MultiSourceDataSource();
    });

    testWidgets('多规则时显示来源 chips，点选后剧集改为新规则的地址', (tester) async {
      _usePhoneSize(tester);
      AnimeSummary? tappedSource;
      await tester.pumpWidget(
        _app(
          AnimeDetailPage(
            dataSource: multi,
            summary: multi.sources.first,
            onEpisodeTap: (source, detail, episode) => tappedSource = source,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 三个来源 chips 都在，默认选中第一个规则。
      for (final source in multi.sources) {
        expect(
          find.byKey(
            ValueKey<String>('source-chip-${source.sourceName}-${source.id}'),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('选择规则观看（3 个来源）'), findsOneWidget);
      expect(find.text('共 5 集'), findsOneWidget);

      // 点「乙站」→ 详情重抓，剧集 URL 切换为乙站。
      final yiSource = multi.sources.firstWhere((s) => s.sourceName == '乙站');
      await tester.tap(
        find.byKey(ValueKey<String>('source-chip-乙站-${yiSource.id}')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('episode-1')));
      expect(tappedSource?.sourceName, '乙站');
      expect(multi.lastDetailSource, '乙站');
    });

    testWidgets('单来源时不渲染换源选择器', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          AnimeDetailPage(
            dataSource: fixture,
            summary: FixtureAnimeDataSource.xinghai,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('选择规则观看'), findsNothing);
    });
  });

  group('封面镜像', () {
    testWidgets('开关拨动后网络封面 URL 被改写为代理地址', (tester) async {
      _usePhoneSize(tester);
      final controller = AnimeImageMirrorController();
      await controller.set(false);
      const url = 'https://site.example/cover.jpg';
      final source = FixtureAnimeDataSource(
        searchResults: <AnimeSummary>[
          AnimeSummary(
            id: 'mirror-test',
            title: '镜像测试番',
            coverUrl: url,
            detailUrl: 'https://site.example/a',
          ),
        ],
      );

      await tester.pumpWidget(
        _app(AnimeSearchPage(dataSource: source, mirror: controller)),
      );
      await tester.pumpAndSettle();

      // 关闭时封面是原始地址。
      Image closedImage = tester.widget<Image>(
        find.descendant(
          of: find.byType(AnimeCover),
          matching: find.byType(Image),
        ),
      );
      expect((closedImage.image as NetworkImage).url, url);

      // 打开镜像（不经过 UI，直接拨 controller；UI 监听即时重建）。
      await controller.set(true);
      await tester.pumpAndSettle();

      Image openedImage = tester.widget<Image>(
        find.descendant(
          of: find.byType(AnimeCover),
          matching: find.byType(Image),
        ),
      );
      final mirroredUrl = (openedImage.image as NetworkImage).url;
      expect(mirroredUrl, isNot(url));
      expect(mirroredUrl, contains(Uri.encodeComponent(url)));
    });
  });
}

/// 三规则换源假数据源：每条规则的详情都给出 5 集，URL 带规则名。
class _MultiSourceDataSource extends FixtureAnimeDataSource {
  _MultiSourceDataSource() : lastDetailSource = _sources.first.sourceName ?? '';

  String lastDetailSource;

  static const List<AnimeSummary> _sources = <AnimeSummary>[
    AnimeSummary(
      id: 'https://a.test/anime/1',
      title: '同一部番',
      coverUrl: '',
      detailUrl: 'https://a.test/anime/1',
      sourceName: '甲站',
    ),
    AnimeSummary(
      id: 'https://b.test/anime/1',
      title: '同一部番',
      coverUrl: '',
      detailUrl: 'https://b.test/anime/1',
      sourceName: '乙站',
    ),
    AnimeSummary(
      id: 'https://c.test/anime/1',
      title: '同一部番',
      coverUrl: '',
      detailUrl: 'https://c.test/anime/1',
      sourceName: '丙站',
    ),
  ];

  List<AnimeSummary> get sources => _sources;

  @override
  Future<List<AnimeSummary>> watchSources(
    AnimeSummary item, {
    required String keyword,
  }) async => sources;

  @override
  Future<AnimeDetail> detail(AnimeSummary item) async {
    lastDetailSource = item.sourceName ?? '';
    final host = item.sourceName == '甲站'
        ? 'a.test'
        : item.sourceName == '乙站'
        ? 'b.test'
        : 'c.test';
    return AnimeDetail(
      title: item.title,
      coverUrl: '',
      detailUrl: item.detailUrl,
      description: '',
      sourceName: item.sourceName,
      episodes: <AnimeEpisode>[
        for (var i = 1; i <= 5; i++)
          AnimeEpisode(number: i, title: '第$i集', url: 'https://$host/play/$i'),
      ],
    );
  }
}
