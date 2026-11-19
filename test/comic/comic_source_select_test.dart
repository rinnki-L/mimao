// C 线：漫画搜索按来源筛选——契约默认回退、引擎单源搜索、排序 enabled key、
// 搜索页筛选 UI 与自动重搜。全部离线（内存 fake + 假引擎宿主），不碰网络/DLL。
// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/ 文件头同款说明。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/data/fixture_comic_data_source.dart';
import 'package:mimao/comic/engine/engine.dart' as source_engine;
import 'package:mimao/comic/pages/comic_search_page.dart';

import 'comic_integration_env.dart';

/// 「最小 fake」：实现 [ComicDataSource] 但两个新方法只给一行转发覆盖。
/// Dart 的 `implements` 不继承接口默认方法体（本仓 ComicDataSource 是
/// abstract interface class），因此直接 implements 的类必须补齐覆盖——这正是
/// 契约里「默认实现」落到调用点的语义：searchSource→search、keys→空。
class _MinimalComicDataSource implements ComicDataSource {
  int searchCalls = 0;

  @override
  Future<List<ComicSummary>> search(String keyword) async {
    searchCalls++;
    return <ComicSummary>[
      const ComicSummary(id: 'x', title: '测试', coverUrl: '', detailUrl: ''),
    ];
  }

  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) =>
      search(keyword);

  @override
  List<String> availableSourceKeys() => const <String>[];

  @override
  Future<ComicDetail> detail(ComicSummary item) => throw UnimplementedError();
}

/// 记录调用路径的搜索页 fake：验证 UI 把搜索路由到 search / searchSource。
class _SelectableComicDataSource implements ComicDataSource {
  _SelectableComicDataSource(this.sourceKeys, this.results);

  final List<String> sourceKeys;
  final List<ComicSummary> results;
  final List<String> calls = <String>[];

  @override
  Future<List<ComicSummary>> search(String keyword) async {
    calls.add('search:$keyword');
    return results;
  }

  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) async {
    calls.add('searchSource:$key:$keyword');
    return results.where((item) => item.sourceName == key).toList();
  }

  @override
  List<String> availableSourceKeys() => sourceKeys;

  @override
  Future<ComicDetail> detail(ComicSummary item) async => ComicDetail(
    title: item.title,
    coverUrl: '',
    detailUrl: '',
    description: '',
  );
}

/// 未提供来源列表的普通数据源（两个新方法走接口默认体回退）：验证页面在无来源
/// 时完全退化为全源 search。与既有 FixtureComicDataSource / _FlakyComicDataSource
/// 的形态一致——它们补一行转发覆盖后零行为变化。
class _NoSourceComicDataSource implements ComicDataSource {
  _NoSourceComicDataSource(this.results);

  final List<ComicSummary> results;
  final List<String> calls = <String>[];

  @override
  Future<List<ComicSummary>> search(String keyword) async {
    calls.add('search:$keyword');
    return results;
  }

  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) =>
      search(keyword);

  @override
  List<String> availableSourceKeys() => const <String>[];

  @override
  Future<ComicDetail> detail(ComicSummary item) async => ComicDetail(
    title: item.title,
    coverUrl: '',
    detailUrl: '',
    description: '',
  );
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
  group('契约默认实现', () {
    test(
      'fake 不 override：searchSource 回退 search，availableSourceKeys 为空',
      () async {
        final ds = _MinimalComicDataSource();
        final viaSource = await ds.searchSource('k1', 'kw');
        final viaSearch = await ds.search('kw');

        expect(viaSource, viaSearch, reason: '默认 searchSource 直接转发 search');
        expect(ds.searchCalls, 2, reason: '两次调用都落到 search');
        expect(ds.availableSourceKeys(), isEmpty, reason: '默认不提供任何来源');
      },
    );

    test('fixture 零行为变化：默认回退仍走 search', () async {
      const ds = FixtureComicDataSource();
      expect(await ds.searchSource('any', '星舟'), await ds.search('星舟'));
      expect(ds.availableSourceKeys(), isEmpty);
    });
  });

  group('引擎适配器单源搜索', () {
    late ComicIntegrationEnv env;

    setUp(() async {
      env = await ComicIntegrationEnv.create();
      await env.seedSource(); // bilimanga（enabled）
    });

    tearDown(() => env.close());

    test('searchSource 只产出指定 key 的结果，不触发其它源', () async {
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'othermanga'),
      );
      await env.sourceStore.save(other);
      // othermanga 设为故障源：若被触发，诊断串会带上它的 key。
      final adapter = await env.buildAdapter(failKeys: <String>{'othermanga'});

      final results = await adapter.searchSource('bilimanga', '海贼王');

      expect(results, hasLength(2));
      expect(results.map((e) => e.sourceName).toSet(), <String>{'bilimanga'});
      expect(
        adapter.takeDiagnostics().join(),
        isNot(contains('othermanga')),
        reason: '未选中的源不应被调用',
      );
    });

    test('searchSource 空关键词返回空列表（与 search 同语义）', () async {
      final adapter = await env.buildAdapter();
      expect(await adapter.searchSource('bilimanga', ''), isEmpty);
      expect(await adapter.searchSource('bilimanga', '   '), isEmpty);
    });

    test('availableSourceKeys 返回排序后的 enabled key', () async {
      final a = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'asource'),
      );
      final z = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'zsource'),
      );
      final disabled = source_engine
          .parseSourceScript(
            integrationSourceScriptText.replaceFirst('bilimanga', 'ddisabled'),
          )
          .copyWith(enabled: false);
      await env.sourceStore.save(a);
      await env.sourceStore.save(z);
      await env.sourceStore.save(disabled);

      final adapter = await env.buildAdapter();
      expect(adapter.availableSourceKeys(), <String>[
        'asource',
        'bilimanga',
        'zsource',
      ], reason: '按 key 排序且排除禁用源');
    });
  });

  group('搜索页来源筛选 UI', () {
    ComicSummary summary(String id, String source) => ComicSummary(
      id: id,
      title: '漫画-$id',
      coverUrl: '',
      detailUrl: '',
      sourceName: source,
    );

    testWidgets('多来源显示筛选器，选源触发 searchSource，选全部触发 search', (tester) async {
      _usePhoneSize(tester);
      final ds = _SelectableComicDataSource(
        <String>['k1', 'k2'],
        <ComicSummary>[
          summary('a', 'k1'),
          summary('b', 'k1'),
          summary('c', 'k2'),
        ],
      );
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: ds)));
      await tester.pumpAndSettle();

      // 有来源：显示「全部来源」+ 各源 chip。
      expect(find.byKey(const Key('source-filter-all')), findsOneWidget);
      expect(find.byKey(const Key('source-filter-k1')), findsOneWidget);
      expect(find.byKey(const Key('source-filter-k2')), findsOneWidget);
      expect(find.text('共 3 部'), findsOneWidget);

      // 先跑一次全源搜索。
      await tester.enterText(find.byType(TextField), '关键词');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(ds.calls, contains('search:关键词'));

      // 选 k1：自动重搜走 searchSource，只显示 k1 的 2 条。
      await tester.tap(find.byKey(const Key('source-filter-k1')));
      await tester.pumpAndSettle();
      expect(ds.calls, contains('searchSource:k1:关键词'));
      expect(find.text('共 2 部'), findsOneWidget);

      // 选「全部来源」：回到全源 search。
      await tester.tap(find.byKey(const Key('source-filter-all')));
      await tester.pumpAndSettle();
      expect(ds.calls.last, 'search:关键词');
      expect(find.text('共 3 部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无来源时不显示筛选器，仍走 search', (tester) async {
      _usePhoneSize(tester);
      final ds = _NoSourceComicDataSource(<ComicSummary>[summary('a', 'k1')]);
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: ds)));
      await tester.pumpAndSettle();

      expect(find.byType(FilterChip), findsNothing);
      await tester.enterText(find.byType(TextField), '关键词');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('共 1 部'), findsOneWidget);
      expect(ds.calls, contains('search:关键词'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('空关键词下选源不触发 searchSource（保持原语义）', (tester) async {
      _usePhoneSize(tester);
      final ds = _SelectableComicDataSource(
        <String>['k1'],
        <ComicSummary>[summary('a', 'k1')],
      );
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: ds)));
      await tester.pumpAndSettle();

      // 当前关键词为空，点选来源只应重跑 search('')，不该走 searchSource。
      await tester.tap(find.byKey(const Key('source-filter-k1')));
      await tester.pumpAndSettle();
      expect(ds.calls, contains('search:'));
      expect(ds.calls.where((c) => c.startsWith('searchSource')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('多来源 chip 在 390 宽无溢出', (tester) async {
      _usePhoneSize(tester);
      final ds = _SelectableComicDataSource(
        <String>['source-one', 'source-two', 'source-three', 'source-four'],
        <ComicSummary>[summary('a', 'source-one')],
      );
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: ds)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
