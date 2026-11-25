// 四个新页面的三态与主路径（空 / 加载 / 错误；不含真实文件与网络）。
// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/dict/novel_dict_rule.dart';
import 'package:mimao/novel/dict/novel_dict_service.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/pages/novel_dict_page.dart';
import 'package:mimao/novel/pages/novel_keyboard_page.dart';
import 'package:mimao/novel/pages/novel_tag_rules_page.dart';
import 'package:mimao/novel/pages/novel_theme_import_page.dart';
import 'package:mimao/novel/reader/novel_keyboard_assist.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/tags/novel_tag_rule_service.dart';
import 'package:mimao/novel/tags/novel_tag_rules.dart';
import 'package:mimao/novel/theme/novel_theme_package.dart';
import 'package:mimao/novel/theme/novel_theme_package_service.dart';

class _FakeDictStorage implements NovelDictRuleStorage {
  _FakeDictStorage({this.rules = const <NovelDictRule>[], this.fail = false});

  List<NovelDictRule> rules;
  bool fail;

  @override
  Future<List<NovelDictRule>> loadAll() async {
    if (fail) throw StateError('boom');
    return rules;
  }

  @override
  Future<NovelDictRule> save(NovelDictRule rule) async => rule;

  @override
  Future<void> setEnabled(int id, bool enabled) async {}

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<void> replaceAll(Iterable<NovelDictRule> rules) async {}

  @override
  Future<void> restoreDefaults() async {}
}

class _FakeTagStorage implements NovelTagRuleStorage {
  _FakeTagStorage({this.rules = const <NovelTagRule>[]});

  List<NovelTagRule> rules;

  @override
  Future<List<NovelTagRule>> loadAll() async => rules;

  @override
  Future<NovelTagRule> save(NovelTagRule rule) async => rule;

  @override
  Future<void> setEnabled(int id, bool enabled) async {}

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<NovelTagApplyResult> applyToShelf() async => const NovelTagApplyResult(
    matched: 2,
    updated: 2,
    affectedNames: <String>['修仙'],
  );

  @override
  Future<void> replaceAll(Iterable<NovelTagRule> rules) async {}
}

class _FakeThemeStorage implements NovelThemePackageStorage {
  _FakeThemeStorage({this.records = const <NovelThemePackageRecord>[]});

  final List<NovelThemePackageRecord> records;
  int? appliedId;

  @override
  Future<List<NovelThemePackageRecord>> loadAll() async => records;

  @override
  Future<NovelThemePackageRecord> save(NovelThemePackage package) async =>
      NovelThemePackageRecord(
        id: 1,
        name: package.name,
        json: package.encode(),
        version: package.version,
        importedAt: DateTime(2026, 11, 25),
      );

  @override
  Future<void> markApplied(int id) async => appliedId = id;

  @override
  Future<bool> delete(int id) async => true;
}

Widget _app(Widget home) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF3366AA),
    brightness: Brightness.light,
  ),
  home: home,
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('字典规则页', () {
    testWidgets('空规则给「导入规则」入口', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _app(
          NovelDictPage(
            store: _FakeDictStorage(),
            lookup: NovelDictService(transport: _NoNetworkTransport()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有词典规则'), findsOneWidget);
      expect(find.text('导入规则'), findsWidgets);
    });

    testWidgets('读取失败进入错误态，可重试', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _app(
          NovelDictPage(
            store: _FakeDictStorage(fail: true),
            lookup: NovelDictService(transport: _NoNetworkTransport()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('读取词典规则失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('输入词查询：离线规则出结果', (tester) async {
      _size(tester);
      final offline = novelDefaultDictRules.firstWhere(
        (rule) => rule.urlRule.startsWith('data:'),
      );
      await tester.pumpWidget(
        _app(
          NovelDictPage(
            store: _FakeDictStorage(rules: <NovelDictRule>[offline]),
            lookup: NovelDictService(transport: _NoNetworkTransport()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('novel-dict-word')), '词典');
      await tester.tap(find.byKey(const Key('novel-dict-search')));
      await tester.pumpAndSettle();
      expect(find.textContaining('词条：词典'), findsOneWidget);
    });
  });

  group('标签规则页', () {
    testWidgets('有规则时展示与应用', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _app(
          NovelTagRulesPage(
            store: _FakeTagStorage(
              rules: const <NovelTagRule>[
                NovelTagRule(
                  name: '修仙',
                  pattern: r'修[真仙]',
                  colorArgb: 0xFF2E7D32,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('修仙'), findsOneWidget);
      await tester.tap(find.byKey(const Key('novel-tag-apply')));
      await tester.pumpAndSettle();
      expect(find.textContaining('新打标 2 本'), findsWidgets);
    });

    testWidgets('空规则给新建入口', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _app(NovelTagRulesPage(store: _FakeTagStorage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有标签规则'), findsOneWidget);
      expect(find.text('新建第一条规则'), findsOneWidget);
    });
  });

  group('主题包页', () {
    testWidgets('空列表给「存为第一个主题」入口，并展示当前设置预览', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _app(
          NovelThemeImportPage(
            store: _FakeThemeStorage(),
            settingsStore: MemoryNovelReaderSettingsStore(),
            keyboardStore: NovelKeyboardAssistStore(null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前阅读设置'), findsOneWidget);
      expect(find.text('还没有保存的主题'), findsOneWidget);
      expect(find.text('把当前设置存为第一个主题'), findsOneWidget);
    });

    testWidgets('已保存主题可应用（写入设置存储）', (tester) async {
      _size(tester);
      final package = NovelThemePackage(
        name: '羊皮纸',
        settings: const NovelReaderSettings(fontSize: 30),
      );
      final record = NovelThemePackageRecord(
        id: 7,
        name: package.name,
        json: package.encode(),
        version: package.version,
        importedAt: DateTime(2026, 11, 25),
      );
      final settingsStore = MemoryNovelReaderSettingsStore();
      await tester.pumpWidget(
        _app(
          NovelThemeImportPage(
            store: _FakeThemeStorage(
              records: <NovelThemePackageRecord>[record],
            ),
            settingsStore: settingsStore,
            keyboardStore: NovelKeyboardAssistStore(null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('我的主题  '), findsOneWidget);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      // 预览对话框：确认应用。
      await tester.tap(find.text('应用').last);
      await tester.pumpAndSettle();
      expect((await settingsStore.load()).fontSize, 30);
    });
  });

  group('键盘辅助页', () {
    testWidgets('键盘默认键位列出，可打开新增对话框', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _app(NovelKeyboardPage(store: NovelKeyboardAssistStore(null))),
      );
      await tester.pumpAndSettle();
      expect(find.text('ArrowLeft'), findsOneWidget);
      expect(find.text('Space'), findsOneWidget);
      await tester.tap(find.byKey(const Key('novel-keyboard-add')));
      await tester.pumpAndSettle();
      expect(find.text('新增按键映射'), findsOneWidget);
      expect(find.text('按下要绑定的按键'), findsOneWidget);
    });
  });
}

/// 任何请求都视为失败：这些页面测试只走离线规则，真发请求就是测试写错了。
class _NoNetworkTransport implements NovelHttpTransport {
  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    fail('页面测试不应发网络请求：${request.url}');
  }

  @override
  void close() {}
}
