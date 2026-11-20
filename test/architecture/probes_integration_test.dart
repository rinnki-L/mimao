// 四条探针线集成回归（probes-integration.md §三.3）。
//
// 目标：验证 A/C 在漫画搜索页共存、D 的 system seed 取值链路在集成后仍成立。
// 全部离线：不访问网络、不加载 system_theme 插件（只注入 fake provider）、
// 不碰 path_provider / flutter_qjs_plugin.dll。
// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/ 文件头同款说明。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/pages/comic_search_page.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/shell_store.dart';

/// 同时具备 A（搜索诊断）与 C（来源筛选）能力的假数据源：
/// 暴露多个来源 key、返回空结果并给出两条诊断，验证两种 UI 分区互不覆盖。
class _ACoexistDataSource implements ComicDataSource {
  const _ACoexistDataSource();

  @override
  Future<List<ComicSummary>> search(String keyword) async =>
      const <ComicSummary>[];

  @override
  Future<ComicDetail> detail(ComicSummary item) =>
      throw UnimplementedError('本测试不涉及详情');

  @override
  List<String> takeSearchDiagnostics() => const <String>[
    '源A：连接超时',
    '源B：返回 403',
  ];

  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) async =>
      const <ComicSummary>[];

  @override
  List<String> availableSourceKeys() => const <String>['源A', '源B'];
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

void main() {
  const violet = Color(0xFF7C6BFF);

  tearDown(() {
    MimaoApp.systemAccentProvider = null;
    shellStore.setThemeSeed('violet');
  });

  group('集成 · A+C 漫画搜索页共存', () {
    testWidgets('失败诊断态与来源筛选 chip 同时出现、互不覆盖', (tester) async {
      await tester.pumpWidget(
        _app(const ComicSearchPage(dataSource: _ACoexistDataSource())),
      );
      await tester.pumpAndSettle();

      // C 线：来源筛选区（全部 + 两个源）存在。
      expect(find.byKey(const Key('source-filter-all')), findsOneWidget);
      expect(find.byKey(const Key('source-filter-源A')), findsOneWidget);
      expect(find.byKey(const Key('source-filter-源B')), findsOneWidget);

      // A 线：空结果 + 有诊断 → 「搜索未成功」并逐条列出原因。
      expect(find.text('搜索未成功'), findsOneWidget);
      expect(find.text('• 源A：连接超时'), findsOneWidget);
      expect(find.text('• 源B：返回 403'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('集成 · D 系统强调色 seed 链路', () {
    test('seed(system) 取注入 provider 色；清空后回退 violet', () {
      const accent = Color(0xFF00AABB);
      MimaoApp.systemAccentProvider = () => accent;
      expect(MimaoApp.seed('system'), accent);

      MimaoApp.systemAccentProvider = null;
      expect(MimaoApp.seed('system'), violet);
    });

    test('选择 system 后 seed(themeSeed) 走系统色分支', () {
      const accent = Color(0xFF123456);
      MimaoApp.systemAccentProvider = () => accent;
      shellStore.setThemeSeed('system');
      expect(shellStore.themeSeed, 'system');
      expect(MimaoApp.seed(shellStore.themeSeed), accent);
    });
  });
}
