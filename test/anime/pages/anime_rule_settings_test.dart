// closure-01：AnimeRuleSettings 面板测试——空态、导入成功/失败、非法 URL、
// 删除确认/取消、读取失败。全程 fake AnimeHttpClient + 内存 RuleStore，
// 不联网、不碰 dart:io（widget 测试的 FakeAsync 不会推进文件 I/O future）。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/engine.dart';
import 'package:mimao/anime/pages/anime_rule_settings.dart';

import '../fixtures.dart';

/// 可控 fake：按 URL 返回 JSON 或注入失败，并记录抓取过的 URL。
///
/// 给了 [indexBody] 时，`index.json` 请求返回清单、其余 URL 返回 [body]；
/// 未给时沿用最初行为（所有请求都返回 [body]），保证旧测试不受影响。
class _FakeClient implements AnimeHttpClient {
  _FakeClient({
    this.body = '',
    this.indexBody,
    this.statusCode = 200,
    this.fail = false,
  });

  final String body;
  final String? indexBody;
  final int statusCode;
  final bool fail;
  final List<String> fetched = <String>[];

  @override
  Future<AnimeHttpResponse> fetch(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async {
    fetched.add(url);
    if (fail) throw StateError('网络不可用');
    final isIndex = url.endsWith('index.json');
    if (isIndex && indexBody != null) {
      return AnimeHttpResponse(statusCode: 200, body: indexBody!);
    }
    return AnimeHttpResponse(statusCode: statusCode, body: body);
  }
}

/// 内存 RuleStore：覆盖 dart:io 的读写方法，让 widget 测试完全离线/即时。
class _MemoryRuleStore extends RuleStore {
  _MemoryRuleStore() : super(Directory.systemTemp); // 构造参数不会被用到（所有方法已覆盖）。

  final Map<String, AnimeRule> _rules = <String, AnimeRule>{};

  bool failLoad = false;

  @override
  Future<RuleLoadResult> loadAllDetailed() async {
    if (failLoad) throw StateError('磁盘读取失败');
    return RuleLoadResult(rules: List<AnimeRule>.unmodifiable(_rules.values));
  }

  @override
  Future<List<File>> saveAll(Iterable<AnimeRule> rules) async {
    for (final rule in rules) {
      _rules[rule.name] = rule;
    }
    return const <File>[];
  }

  @override
  Future<bool> delete(String name) async => _rules.remove(name) != null;
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _panel(
  _MemoryRuleStore store,
  RuleImporter importer, {
  VoidCallback? onChanged,
}) => AnimeRuleSettings(
  store: store,
  importer: importer,
  onRulesChanged: onChanged,
);

Map<String, dynamic> _ruleMap(String name) => <String, dynamic>{
  'name': name,
  'version': '1.0',
  'baseURL': 'https://example.com/',
  'searchList': '//div',
  'searchName': '//a',
  'searchResult': '//a',
  'chapterRoads': '//ul',
  'chapterResult': '//li',
};

const String _indexJson =
    '[{"name":"repo-one","version":"1.2","lastUpdate":1790853597000},'
    '{"name":"repo-two","version":"2.0","lastUpdate":0}]';

const String _repoUrl = 'https://rules.test/repo/';

void main() {
  late _MemoryRuleStore store;

  setUp(() => store = _MemoryRuleStore());

  testWidgets('空态文案存在', (tester) async {
    await tester.pumpWidget(
      _app(_panel(store, RuleImporter(client: _FakeClient()))),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('anime-rule-empty')), findsOneWidget);
    expect(find.text('还没有规则，先从 KazumiRules 导入'), findsOneWidget);
  });

  testWidgets('导入成功：写入 store、列表显示名称/版本/baseURL、显示数量', (tester) async {
    final client = _FakeClient(body: demoRuleJson);
    var changed = 0;
    await tester.pumpWidget(
      _app(
        _panel(store, RuleImporter(client: client), onChanged: () => changed++),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('anime-rule-url')),
      'https://example.com/rules.json',
    );
    await tester.tap(find.byKey(const Key('anime-rule-import')));
    await tester.pumpAndSettle();

    expect(client.fetched, <String>['https://example.com/rules.json']);
    expect((await store.loadAllDetailed()).rules, hasLength(1));
    expect(find.byKey(const Key('anime-rule-item-demo03')), findsOneWidget);
    expect(find.textContaining('v1.0'), findsOneWidget);
    expect(find.textContaining('https://example.com/'), findsWidgets);
    expect(find.text('导入 1 条'), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('导入返回 0 条 + failures：显示失败原因，不清空已有规则', (tester) async {
    await store.saveAll(<AnimeRule>[AnimeRule.fromJson(_ruleMap('existing'))]);
    final client = _FakeClient(body: 'not-json');
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('anime-rule-url')),
      'https://example.com/bad.json',
    );
    await tester.tap(find.byKey(const Key('anime-rule-import')));
    await tester.pumpAndSettle();

    expect(find.textContaining('失败'), findsWidgets);
    expect((await store.loadAllDetailed()).rules, hasLength(1));
    expect(find.byKey(const Key('anime-rule-item-existing')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('anime-rule-import')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('HTTP 非 2xx：显示下载失败，已有规则不清空', (tester) async {
    final client = _FakeClient(body: demoRuleJson, statusCode: 404);
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('anime-rule-url')),
      'https://example.com/404.json',
    );
    await tester.tap(find.byKey(const Key('anime-rule-import')));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 404'), findsOneWidget);
    expect((await store.loadAllDetailed()).rules, isEmpty);
  });

  testWidgets('网络异常：导入器不抛，显示失败提示，按钮恢复', (tester) async {
    final client = _FakeClient(fail: true);
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('anime-rule-url')),
      'https://example.com/unreachable.json',
    );
    await tester.tap(find.byKey(const Key('anime-rule-import')));
    await tester.pumpAndSettle();

    expect(find.textContaining('规则下载失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('anime-rule-import')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('非法/空 URL：不发起请求，显示校验提示', (tester) async {
    final client = _FakeClient(body: demoRuleJson);
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('anime-rule-import')));
    await tester.pumpAndSettle();
    expect(find.text('请输入合法的 http(s) 规则 URL'), findsOneWidget);
    expect(client.fetched, isEmpty);

    await tester.enterText(find.byKey(const Key('anime-rule-url')), 'ftp://x');
    await tester.tap(find.byKey(const Key('anime-rule-import')));
    await tester.pumpAndSettle();
    expect(client.fetched, isEmpty);
  });

  testWidgets('删除规则：确认后从 store 与列表消失', (tester) async {
    await store.saveAll(<AnimeRule>[AnimeRule.fromJson(_ruleMap('demo03'))]);
    await tester.pumpWidget(
      _app(_panel(store, RuleImporter(client: _FakeClient()))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('anime-rule-item-demo03')), findsOneWidget);

    await tester.tap(find.byKey(const Key('anime-rule-delete-demo03')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('anime-rule-delete-confirm')));
    await tester.pumpAndSettle();

    expect((await store.loadAllDetailed()).rules, isEmpty);
    expect(find.byKey(const Key('anime-rule-item-demo03')), findsNothing);
  });

  testWidgets('取消删除：规则保留', (tester) async {
    await store.saveAll(<AnimeRule>[AnimeRule.fromJson(_ruleMap('demo03'))]);
    await tester.pumpWidget(
      _app(_panel(store, RuleImporter(client: _FakeClient()))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('anime-rule-delete-demo03')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect((await store.loadAllDetailed()).rules, hasLength(1));
    expect(find.byKey(const Key('anime-rule-item-demo03')), findsOneWidget);
  });

  testWidgets('读取失败显示错误态并可重试，不崩溃', (tester) async {
    store.failLoad = true;
    await tester.pumpWidget(
      _app(_panel(store, RuleImporter(client: _FakeClient()))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('读取规则失败'), findsOneWidget);
    expect(find.byKey(const Key('anime-rule-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── 仓库浏览 + 勾选导入 ──

  Future<void> browseRepo(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('anime-repo-url')), _repoUrl);
    await tester.tap(find.byKey(const Key('anime-repo-browse')));
    await tester.pumpAndSettle();
  }

  testWidgets('浏览仓库：列出清单规则，标明已安装', (tester) async {
    await store.saveAll(<AnimeRule>[AnimeRule.fromJson(_ruleMap('repo-one'))]);
    final client = _FakeClient(indexBody: _indexJson);
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await browseRepo(tester);

    expect(client.fetched, contains('${_repoUrl}index.json'));
    expect(find.byKey(const Key('anime-repo-check-repo-one')), findsOneWidget);
    expect(find.byKey(const Key('anime-repo-check-repo-two')), findsOneWidget);
    expect(find.textContaining('v1.2 · 2026-10-01 · 已安装'), findsOneWidget);
    expect(find.textContaining('发现 2 条规则'), findsOneWidget);
  });

  testWidgets('全选并导入选中：逐条下载写入 store，刷新列表并回调', (tester) async {
    final client = _FakeClient(indexBody: _indexJson, body: demoRuleJson);
    var changed = 0;
    await tester.pumpWidget(
      _app(
        _panel(store, RuleImporter(client: client), onChanged: () => changed++),
      ),
    );
    await tester.pumpAndSettle();

    await browseRepo(tester);
    await tester.tap(find.byKey(const Key('anime-repo-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('anime-repo-import-selected')));
    await tester.pumpAndSettle();

    expect(
      client.fetched,
      containsAll(<String>[
        '${_repoUrl}index.json',
        '${_repoUrl}repo-one.json',
        '${_repoUrl}repo-two.json',
      ]),
    );
    // demoRuleJson 解析为 demo03，两条下载都是同名 → store 里一条。
    expect((await store.loadAllDetailed()).rules, hasLength(1));
    expect(find.byKey(const Key('anime-rule-item-demo03')), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('非法仓库地址：不发请求，显示校验提示', (tester) async {
    final client = _FakeClient(indexBody: _indexJson);
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('anime-repo-url')),
      'https://user:pw@rules.test/',
    );
    await tester.tap(find.byKey(const Key('anime-repo-browse')));
    await tester.pumpAndSettle();

    expect(client.fetched, isEmpty);
    expect(find.textContaining('仓库地址不合法'), findsOneWidget);
  });

  testWidgets('清单读取失败：显示失败原因，不发规则下载请求', (tester) async {
    final client = _FakeClient(indexBody: 'not json', body: demoRuleJson);
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await browseRepo(tester);

    expect(find.textContaining('不是合法 JSON'), findsOneWidget);
    expect(client.fetched, <String>['${_repoUrl}index.json']);
    expect(find.byKey(const Key('anime-repo-check-repo-one')), findsNothing);
  });

  testWidgets('空清单：显示无规则提示，不显示导入按钮', (tester) async {
    final client = _FakeClient(indexBody: '[]');
    await tester.pumpWidget(_app(_panel(store, RuleImporter(client: client))));
    await tester.pumpAndSettle();

    await browseRepo(tester);

    expect(find.byKey(const Key('anime-repo-empty')), findsOneWidget);
    expect(find.byKey(const Key('anime-repo-import-selected')), findsNothing);
  });
}
