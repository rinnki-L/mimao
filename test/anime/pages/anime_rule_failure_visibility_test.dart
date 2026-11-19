// A 线 · 错误可见性：番剧导入失败原因全显的回归测试。
//
// 通过注入可控的假 RuleImporter / 假 RuleStore，驱动 AnimeRuleSettings 的
// _formatFailures：7 条失败 → 5 条 + "还有 2 条失败未列出"；1 条原样；
// 0 条不显示失败区。全程离线（内存 store + 假 client），不碰 dart:io 读写、
// 不访问网络。

// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/engine.dart';
import 'package:mimao/anime/pages/anime_rule_settings.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

class _FakeClient implements AnimeHttpClient {
  @override
  Future<AnimeHttpResponse> fetch(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async => const AnimeHttpResponse(statusCode: 200, body: '{}');
}

/// 可控导入器：覆盖三条返回失败的方法，分别喂给 _importMessage / _indexMessage /
/// _repoImportMessage 路径。
class _FakeImporter extends RuleImporter {
  _FakeImporter({this.importFailures = const <String>[]})
    : super(client: _FakeClient());

  final List<String> importFailures;

  @override
  Future<RuleImportResult> importFromUrl(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async =>
      RuleImportResult(rules: const <AnimeRule>[], failures: importFailures);

  @override
  Future<RuleIndexResult> fetchIndex(
    String baseUrl, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async => RuleIndexResult(
    entries: const <RuleIndexEntry>[],
    failures: importFailures,
  );
}

/// 内存 RuleStore：可注入 loadFailures 驱动坏文件读取失败区。
class _MemoryRuleStore extends RuleStore {
  _MemoryRuleStore() : super(Directory.systemTemp);

  List<String> loadFailures = const <String>[];

  @override
  Future<RuleLoadResult> loadAllDetailed() async =>
      RuleLoadResult(rules: const <AnimeRule>[], failures: loadFailures);

  @override
  Future<List<File>> saveAll(Iterable<AnimeRule> rules) async => const <File>[];

  @override
  Future<bool> delete(String name) async => true;
}

String _messageText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('anime-rule-message'))).data ?? '';

Future<void> _doImport(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('anime-rule-url')),
    'https://example.com/rules.json',
  );
  await tester.tap(find.byKey(const Key('anime-rule-import')));
  await tester.pumpAndSettle();
}

void main() {
  late _MemoryRuleStore store;

  setUp(() => store = _MemoryRuleStore());

  testWidgets('7 条失败：展示前 5 条 + 「还有 2 条失败未列出」', (tester) async {
    final importer = _FakeImporter(
      importFailures: List<String>.generate(7, (i) => '失败原因${i + 1}'),
    );
    await tester.pumpWidget(
      _app(AnimeRuleSettings(store: store, importer: importer)),
    );
    await tester.pumpAndSettle();
    await _doImport(tester);

    final text = _messageText(tester);
    expect(text, contains('失败 7 条'));
    for (var i = 1; i <= 5; i++) {
      expect(text, contains('失败原因$i'), reason: '第 $i 条应展示');
    }
    expect(text, contains('失败原因1'), reason: '第 1 条（原 first）应展示');
    expect(text, isNot(contains('失败原因6')), reason: '第 6 条不应展示');
    expect(text, isNot(contains('失败原因7')), reason: '第 7 条不应展示');
    expect(text, contains('还有 2 条失败未列出'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1 条失败：原样展示，无「还有 N 条」', (tester) async {
    final importer = _FakeImporter(importFailures: const <String>['唯一失败']);
    await tester.pumpWidget(
      _app(AnimeRuleSettings(store: store, importer: importer)),
    );
    await tester.pumpAndSettle();
    await _doImport(tester);

    final text = _messageText(tester);
    expect(text, contains('失败 1 条'));
    expect(text, contains('唯一失败'));
    expect(text, isNot(contains('还有')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('0 条失败 + 0 条规则：显示「没有可导入的规则」，无失败区', (tester) async {
    final importer = _FakeImporter();
    await tester.pumpWidget(
      _app(AnimeRuleSettings(store: store, importer: importer)),
    );
    await tester.pumpAndSettle();
    await _doImport(tester);

    expect(_messageText(tester), contains('没有可导入的规则'));
    expect(find.byKey(const Key('anime-rule-message')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('坏文件读取 7 条失败：列表展示前 5 条 + 「还有 2 条失败未列出」', (tester) async {
    store.loadFailures = List<String>.generate(7, (i) => '坏文件${i + 1}.json：损坏');
    await tester.pumpWidget(
      _app(AnimeRuleSettings(store: store, importer: _FakeImporter())),
    );
    await tester.pumpAndSettle();

    final widget = tester.widget<Text>(
      find.byKey(const Key('anime-rule-load-failures')),
    );
    final text = widget.data ?? '';
    expect(text, contains('读取时跳过 7 个坏文件'));
    for (var i = 1; i <= 5; i++) {
      expect(text, contains('坏文件$i.json'), reason: '坏文件 $i 应展示');
    }
    expect(text, isNot(contains('坏文件6.json')));
    expect(text, isNot(contains('坏文件7.json')));
    expect(text, contains('还有 2 条失败未列出'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('清单读取 7 条失败：展示前 5 条 + 「还有 2 条失败未列出」', (tester) async {
    final importer = _FakeImporter(
      importFailures: List<String>.generate(7, (i) => '清单失败${i + 1}'),
    );
    await tester.pumpWidget(
      _app(AnimeRuleSettings(store: store, importer: importer)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('anime-repo-url')),
      'https://rules.test/repo/',
    );
    await tester.tap(find.byKey(const Key('anime-repo-browse')));
    await tester.pumpAndSettle();

    final text = _messageText(tester);
    expect(text, contains('失败 7 条'));
    expect(text, contains('清单失败1'));
    expect(text, contains('清单失败5'));
    expect(text, isNot(contains('清单失败6')));
    expect(text, contains('还有 2 条失败未列出'));
    expect(tester.takeException(), isNull);
  });
}
