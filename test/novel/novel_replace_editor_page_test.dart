// ignore_for_file: deprecated_member_use — 与其他小说页面测试同款说明。
// 替换编辑器 / 正文编辑页的定向 UI 回归（不依赖真机/插件）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_content_edit_page.dart';
import 'package:mimao/novel/pages/novel_replace_editor_page.dart';
import 'package:mimao/novel/reader/novel_content_override_service.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

class _MemoryReplaceStore implements NovelReplaceRuleStorage {
  _MemoryReplaceStore([Iterable<NovelReplaceRule> initial = const []])
    : rules = <NovelReplaceRule>[...initial];

  final List<NovelReplaceRule> rules;

  @override
  Future<List<NovelReplaceRule>> loadAll() async =>
      List<NovelReplaceRule>.of(rules);

  @override
  Future<int> saveAll(Iterable<NovelReplaceRule> input) async {
    final byKey = <String, NovelReplaceRule>{
      for (final rule in rules) rule.key: rule,
      for (final rule in input) rule.key: rule,
    };
    rules
      ..clear()
      ..addAll(byKey.values);
    return input.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {
    final index = rules.indexWhere((rule) => rule.key == key);
    if (index < 0) return;
    rules[index] = rules[index].copyWith(enabled: enabled);
  }

  @override
  Future<bool> delete(String key) async {
    final before = rules.length;
    rules.removeWhere((rule) => rule.key == key);
    return rules.length != before;
  }
}

class _MemoryOverrideStore implements NovelContentOverrideStorage {
  final Map<String, NovelContent> saved = <String, NovelContent>{};

  String _key(String bookId, String sourceKey, String chapterKey) =>
      '$bookId|$sourceKey|$chapterKey';

  @override
  Future<NovelContent?> load({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  }) async => saved[_key(bookId, sourceKey, chapterKey)];

  @override
  Future<bool> has({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  }) async => saved.containsKey(_key(bookId, sourceKey, chapterKey));

  @override
  Future<void> save({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
    required String chapterTitle,
    required List<String> paragraphs,
    String title = '',
    DateTime? now,
  }) async {
    saved[_key(bookId, sourceKey, chapterKey)] = NovelContent(
      chapterId: chapterKey,
      title: title.isEmpty ? chapterTitle : title,
      paragraphs: List<String>.of(paragraphs),
    );
  }

  @override
  Future<bool> remove({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  }) async => saved.remove(_key(bookId, sourceKey, chapterKey)) != null;
}

class _Store implements NovelSourceStorage {
  _Store(this.sources);

  final List<NovelBookSource> sources;

  @override
  Future<List<NovelBookSource>> loadAll() async => sources;

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

class _Engine implements NovelOnlineEngine {
  _Engine(this.paragraphs);

  final List<String> paragraphs;

  @override
  void close() {}

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async =>
      const <NovelExploreKind>[];

  @override
  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async => NovelDetail(
    ref: ref,
    title: '测试书',
    chapters: const <NovelChapter>[
      NovelChapter(id: 'c0', title: '第一章', index: 0, url: 'https://x/1'),
    ],
  );

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => NovelContent(
    chapterId: chapter.id,
    title: chapter.title,
    paragraphs: paragraphs,
  );
}

const _source = NovelBookSource(
  key: 'src-a',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

NovelReplaceRule _rule(
  String name,
  String pattern,
  String replacement, {
  bool isRegex = false,
}) => NovelReplaceRule(
  key: NovelReplaceRule.keyFor(name, pattern, replacement),
  name: name,
  pattern: pattern,
  replacement: replacement,
  isRegex: isRegex,
  enabled: true,
  scope: '',
  scopeTitle: false,
  scopeContent: true,
  raw: const <String, dynamic>{},
);

String? _previewText(WidgetTester tester, Key key) {
  final finder = find.descendant(
    of: find.byKey(key),
    matching: find.byType(SelectableText),
  );
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<SelectableText>(finder.first).data;
}

void main() {
  testWidgets('替换编辑器：实时预览 + 有效替换对照 + 保存', (tester) async {
    // 桌面宽窗：两栏布局 + 足够高，让预览区一次建出来（ListView 懒加载）。
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemoryReplaceStore(<NovelReplaceRule>[
      _rule('去掉广告', '广告', ''),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReplaceEditorPage(
          store: store,
          bookId: 'book-1',
          bookTitle: '测试书',
          sourceKey: 'src-a',
          bookUrl: 'https://site.test/book/1',
          sampleText: '正文里有广告，需要清掉。',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认选中第一条规则，实时预览把「广告」删掉。
    expect(
      _previewText(tester, const Key('novel-replace-preview-after')),
      '正文里有，需要清掉。',
    );

    // 切到「本书有效替换」，命中规则列出来并给出最终结果。
    await tester.tap(find.text('本书有效替换'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('novel-replace-effective-list')),
      findsOneWidget,
    );
    expect(
      _previewText(tester, const Key('novel-replace-effective-final')),
      '正文里有，需要清掉。',
    );

    // 新建一条规则并保存。
    await tester.tap(find.byKey(const Key('novel-replace-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('novel-replace-field-name')),
      '章节号加「第」',
    );
    await tester.enterText(
      find.byKey(const Key('novel-replace-field-pattern')),
      r'(\d+)章',
    );
    await tester.tap(find.byKey(const Key('novel-replace-regex')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('novel-replace-field-replacement')),
      r'第$1章',
    );
    await tester.tap(find.byKey(const Key('novel-replace-save')));
    await tester.pumpAndSettle();

    expect(store.rules.any((rule) => rule.name == '章节号加「第」'), isTrue);
    expect(
      store.rules.firstWhere((rule) => rule.name == '章节号加「第」').isRegex,
      isTrue,
    );
  });

  testWidgets('编辑已有规则改 key 时删掉旧规则，不留下重复项', (tester) async {
    final store = _MemoryReplaceStore(<NovelReplaceRule>[
      _rule('旧规则', '广告', ''),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReplaceEditorPage(store: store, sampleText: '这里有广告'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('novel-replace-field-pattern')),
      '广告位',
    );
    await tester.enterText(
      find.byKey(const Key('novel-replace-field-replacement')),
      '广告',
    );
    await tester.tap(find.byKey(const Key('novel-replace-save')));
    await tester.pumpAndSettle();

    expect(store.rules, hasLength(1));
    expect(store.rules.single.pattern, '广告位');
    expect(store.rules.single.replacement, '广告');
  });

  testWidgets('正文编辑：保存本地覆盖后阅读控制器立即使用', (tester) async {
    final overrides = _MemoryOverrideStore();
    final controller = NovelReaderController(
      bookId: 'book-1',
      title: '测试书',
      sourceKey: 'src-a',
      bookUrl: 'https://site.test/book/1',
      onlineEngine: _Engine(const <String>['引擎原文一', '引擎原文二']),
      sourceStore: _Store(<NovelBookSource>[_source]),
      contentOverrides: overrides,
      settingsStore: MemoryNovelReaderSettingsStore(
        const NovelReaderSettings(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.init();

    await tester.pumpWidget(
      MaterialApp(home: NovelContentEditPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('novel-content-edit-field')),
      '我改过的第一段\n我改过的第二段',
    );
    await tester.tap(find.byKey(const Key('novel-content-edit-save')));
    await tester.pumpAndSettle();

    expect(controller.content?.paragraphs, <String>['我改过的第一段', '我改过的第二段']);
    expect(controller.chapterIsLocalOverride, isTrue);
    expect(overrides.saved, hasLength(1));
  });

  testWidgets('正文编辑：有覆盖时可恢复原样', (tester) async {
    final overrides = _MemoryOverrideStore();
    await overrides.save(
      bookId: 'book-1',
      sourceKey: 'src-a',
      chapterKey: 'c0',
      chapterTitle: '第一章',
      paragraphs: const <String>['旧覆盖'],
    );
    final controller = NovelReaderController(
      bookId: 'book-1',
      title: '测试书',
      sourceKey: 'src-a',
      bookUrl: 'https://site.test/book/1',
      onlineEngine: _Engine(const <String>['引擎原文']),
      sourceStore: _Store(<NovelBookSource>[_source]),
      contentOverrides: overrides,
      settingsStore: MemoryNovelReaderSettingsStore(
        const NovelReaderSettings(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.init();
    expect(controller.content?.paragraphs, <String>['旧覆盖']);

    await tester.pumpWidget(
      MaterialApp(home: NovelContentEditPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-content-edit-restore')), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-content-edit-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复原样').last);
    await tester.pumpAndSettle();

    expect(controller.content?.paragraphs, <String>['引擎原文']);
    expect(controller.chapterIsLocalOverride, isFalse);
    expect(overrides.saved, isEmpty);
  });
}
