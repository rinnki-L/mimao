// ignore_for_file: deprecated_member_use — 与其他小说页面测试同款说明。
// 高亮规则页：空态、新建对话框、按书作用域保存。
//
// 这条用例同时守住一个运行时坑：对话框在 initState 里读 `Theme.of`
// 会触发「dependOnInheritedWidget… called before initState completed」，
// 只有真正把对话框建出来才会暴露。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/pages/novel_highlight_rules_page.dart';
import 'package:mimao/novel/reader/novel_highlight_rule_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rules.dart';

class _MemoryHighlightStore implements NovelHighlightRuleStorage {
  _MemoryHighlightStore([Iterable<NovelHighlightRule> initial = const []])
    : rules = <NovelHighlightRule>[...initial];

  final List<NovelHighlightRule> rules;
  int _nextId = 1;

  @override
  Future<List<NovelHighlightRule>> loadAll() async =>
      List<NovelHighlightRule>.of(rules);

  @override
  Future<NovelHighlightRule> save(NovelHighlightRule rule) async {
    final saved = rule.id == null ? rule.copyWith(id: _nextId++) : rule;
    final index = rules.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      rules[index] = saved;
    } else {
      rules.add(saved);
    }
    return saved;
  }

  @override
  Future<void> setEnabled(int id, bool enabled) async {
    final index = rules.indexWhere((rule) => rule.id == id);
    if (index >= 0) rules[index] = rules[index].copyWith(enabled: enabled);
  }

  @override
  Future<bool> delete(int id) async {
    final before = rules.length;
    rules.removeWhere((rule) => rule.id == id);
    return rules.length != before;
  }
}

void main() {
  testWidgets('新建高亮规则：空态 → 对话框 → 按书保存', (tester) async {
    final store = _MemoryHighlightStore();
    await tester.pumpWidget(
      MaterialApp(
        home: NovelHighlightRulesPage(
          store: store,
          bookId: 'book-1',
          bookTitle: '测试书',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有高亮规则'), findsOneWidget);
    await tester.tap(find.byKey(const Key('novel-highlight-new')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('novel-highlight-name')), '人名');
    await tester.enterText(
      find.byKey(const Key('novel-highlight-pattern')),
      '艾琳娜',
    );
    await tester.tap(find.text('仅《测试书》'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-highlight-save')));
    await tester.pumpAndSettle();

    expect(store.rules, hasLength(1));
    expect(store.rules.single.pattern, '艾琳娜');
    expect(store.rules.single.bookId, 'book-1');
    expect(find.text('人名'), findsOneWidget);
  });

  testWidgets('坏正则不保存并给可读提示', (tester) async {
    final store = _MemoryHighlightStore();
    await tester.pumpWidget(
      MaterialApp(
        home: NovelHighlightRulesPage(
          store: store,
          bookId: 'book-1',
          bookTitle: '测试书',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-highlight-new')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('novel-highlight-pattern')),
      '(',
    );
    await tester.tap(find.byKey(const Key('novel-highlight-save')));
    await tester.pumpAndSettle();

    expect(store.rules, isEmpty);
    expect(find.textContaining('正则不合法'), findsOneWidget);
  });
}
