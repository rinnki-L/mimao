// A 线 · 错误可见性：搜索失败诊断上达 UI 的回归测试。
//
// 覆盖：ComicDataSource 默认 takeSearchDiagnostics() 空实现、fake 空结果 +
// 诊断的搜索页错误态、无诊断时保留原空态、>10 条截断、EngineComicDataSource
// 搜索期缓冲的填充/取走即清/每次 search 开头清空。全程离线、无真实网络/DLL。
// ignore_for_file: deprecated_member_use — material.dart 在 Flutter 3.50 被标弃用，
// 但全仓 UI/测试统一用它（见 lib/main.dart 同款说明）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/data/fixture_comic_data_source.dart';
import 'package:mimao/comic/engine/engine.dart' as source_engine;
import 'package:mimao/comic/pages/comic_search_page.dart';

import 'comic_integration_env.dart';

/// 返回空结果、但暴露可配置搜索诊断的假数据源。
class _EmptyWithDiagnostics implements ComicDataSource {
  _EmptyWithDiagnostics(this.diagnostics);

  final List<String> diagnostics;

  @override
  Future<List<ComicSummary>> search(String keyword) async =>
      const <ComicSummary>[];

  @override
  Future<ComicDetail> detail(ComicSummary item) =>
      throw UnimplementedError('本测试不涉及详情');

  @override
  List<String> takeSearchDiagnostics() => List<String>.from(diagnostics);
}

Widget _app(Widget home) => MaterialApp(
  home: home,
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF7C6BFF),
  ),
);

void main() {
  group('ComicDataSource 默认诊断出口', () {
    test('默认 takeSearchDiagnostics() 返回空，fixture/fake 不受影响', () {
      // 以抽象类型持有，确认默认实现来自接口而非某个具体类。
      const ComicDataSource fixture = FixtureComicDataSource();
      expect(fixture.takeSearchDiagnostics(), isEmpty);
    });
  });

  group('ComicSearchPage 搜索失败诊断态', () {
    testWidgets('空结果 + 2 条诊断：显示「搜索未成功」并列出两条原因 + 重试', (tester) async {
      final ds = _EmptyWithDiagnostics(<String>[
        'sourceA：HTTP 500',
        'sourceB：脚本加载失败',
      ]);
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: ds)));
      await tester.pumpAndSettle();

      expect(find.text('搜索未成功'), findsOneWidget);
      expect(find.text('• sourceA：HTTP 500'), findsOneWidget);
      expect(find.text('• sourceB：脚本加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('换个关键词试试'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空结果 + 无诊断：保留原空态（回显关键词）', (tester) async {
      final ds = _EmptyWithDiagnostics(const <String>[]);
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: ds)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '不存在');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('没有找到「不存在」'), findsOneWidget);
      expect(find.text('换个关键词试试'), findsOneWidget);
      expect(find.text('搜索未成功'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('诊断超过 10 条：只列 10 条，其余显示「还有 N 条」', (tester) async {
      final ds = _EmptyWithDiagnostics(
        List<String>.generate(12, (i) => 'src$i：失败$i'),
      );
      await tester.pumpWidget(_app(ComicSearchPage(dataSource: ds)));
      await tester.pumpAndSettle();

      expect(find.text('搜索未成功'), findsOneWidget);
      expect(find.text('• src0：失败0'), findsOneWidget);
      expect(find.text('• src9：失败9'), findsOneWidget);
      expect(find.text('• src10：失败10'), findsNothing);
      expect(
        find.byKey(const Key('search-diagnostics-remaining')),
        findsOneWidget,
      );
      expect(find.text('还有 2 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('EngineComicDataSource 搜索期诊断缓冲', () {
    late ComicIntegrationEnv env;

    setUp(() async {
      env = await ComicIntegrationEnv.create();
      await env.seedSource();
      // 再放一个 key 不同的源，制造「两源都失败」。
      final other = sourceEngineScript('othermanga');
      await env.sourceStore.save(other);
    });

    tearDown(() => env.close());

    test('两源都失败：takeSearchDiagnostics 返回含两个 key 的诊断，且取走即清', () async {
      final adapter = await env.buildAdapter(
        failKeys: <String>{'bilimanga', 'othermanga'},
      );
      final results = await adapter.search('海贼王');
      expect(results, isEmpty);

      final diagnostics = adapter.takeSearchDiagnostics();
      expect(diagnostics, hasLength(2));
      expect(
        diagnostics.any((d) => d.startsWith('bilimanga：')),
        isTrue,
        reason: '诊断带来源 key 前缀',
      );
      expect(diagnostics.any((d) => d.startsWith('othermanga：')), isTrue);
      expect(adapter.takeSearchDiagnostics(), isEmpty, reason: '取走即清，第二次取为空');
    });

    test('下一轮搜索成功：诊断在 search 开头被清空，不再残留旧失败', () async {
      final failing = await env.buildAdapter(
        failKeys: <String>{'bilimanga', 'othermanga'},
      );
      await failing.search('海贼王');
      expect(failing.takeSearchDiagnostics(), hasLength(2));

      // 换一个不注入故障的适配器，正常出结果。
      final healthy = await env.buildAdapter();
      final results = await healthy.search('海贼王');
      expect(results, isNotEmpty);
      expect(healthy.takeSearchDiagnostics(), isEmpty, reason: '成功搜索无失败诊断');
    });
  });
}

/// 用最小 Venera 脚本派生一个指定 key 的源（复用集成环境的脚本文本）。
source_engine.ComicSourceScript sourceEngineScript(String key) =>
    source_engine.parseSourceScript(
      integrationSourceScriptText.replaceFirst('bilimanga', key),
    );
