// 替换规则 / 高亮规则 / 单章内容覆盖的定向回归。
//
// 覆盖验收里要求的四类单测：
// - 替换规则作用范围、`$1` 与 `${name}` 展开；
// - 高亮正则匹配、坏正则跳过、区间越界夹取；
// - 内容覆盖的读写与恢复（服务层 + 阅读控制器优先级）。
// 全程离线：内存 drift / 假引擎，不碰插件与网络。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/reader/novel_content_override_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rule_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rules.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

NovelReplaceRule _rule(
  String pattern,
  String replacement, {
  bool isRegex = false,
  String scope = '',
  bool scopeContent = true,
  bool scopeTitle = false,
  String name = '规则',
}) => NovelReplaceRule(
  key: NovelReplaceRule.keyFor(name, pattern, replacement),
  name: name,
  pattern: pattern,
  replacement: replacement,
  isRegex: isRegex,
  enabled: true,
  scope: scope,
  scopeTitle: scopeTitle,
  scopeContent: scopeContent,
  raw: const <String, dynamic>{},
);

NovelHighlightRule _highlight({
  String pattern = r'广告',
  String bookId = '',
  bool enabled = true,
  bool bold = false,
  bool underline = false,
}) => NovelHighlightRule(
  id: 1,
  bookId: bookId,
  name: '高亮',
  pattern: pattern,
  foregroundLightArgb: 0xFF880000,
  backgroundLightArgb: 0x33FF0000,
  foregroundDarkArgb: 0xFFFFAAAA,
  backgroundDarkArgb: 0x33FFAAAA,
  enabled: enabled,
  underline: underline,
  bold: bold,
);

class _OpenUser implements QueryExecutorUser {
  _OpenUser(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

class _SourceStore implements NovelSourceStorage {
  _SourceStore(this.sources);

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
  _Engine(this.raw);

  NovelContent raw;

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
    author: '作者',
    chapters: const <NovelChapter>[
      NovelChapter(id: 'c0', title: '第一章', index: 0, url: 'https://x/1'),
    ],
  );

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => raw;
}

const _source = NovelBookSource(
  key: 'src-a',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

void main() {
  group('替换规则', () {
    test(r'$1 与 ${name} 命名组展开', () {
      final numbered = _rule(r'(\d+)章', r'第$1章', isRegex: true);
      expect(applyReplaceRules('12章', <NovelReplaceRule>[numbered]), '第12章');

      final named = _rule(r'(?<num>\d+)章', r'第${num}章', isRegex: true);
      expect(applyReplaceRules('12章', <NovelReplaceRule>[named]), '第12章');

      // 命名组不存在时与坏正则同款：跳过这条并保留原文，不让正文变成乱码。
      final missing = _rule(r'(\d+)章', r'第${nope}章', isRegex: true);
      expect(applyReplaceRules('12章', <NovelReplaceRule>[missing]), '12章');
    });

    test('作用范围：&& 全部命中，逗号/顿号/竖线任一命中', () {
      final andRule = _rule('广告', '', scope: '书名&&https://site.test');
      expect(
        andRule.appliesToBook(
          bookTitle: '书名',
          sourceKey: 'src-a',
          bookUrl: 'https://site.test/book/1',
        ),
        isTrue,
      );
      expect(
        andRule.appliesToBook(
          bookTitle: '书名',
          sourceKey: 'src-a',
          bookUrl: 'https://other/1',
        ),
        isFalse,
      );

      final orRule = _rule('广告', '', scope: '甲,乙、丙|丁');
      expect(
        orRule.appliesToBook(bookTitle: '丁', sourceKey: 'src-a', bookUrl: ''),
        isTrue,
      );
      expect(
        orRule.appliesToBook(bookTitle: '戊', sourceKey: 'src-a', bookUrl: ''),
        isFalse,
      );
    });

    test('有效替换预览逐条给出前/后并标记命中', () {
      final outcomes = previewReplaceRules('12章 广告', <NovelReplaceRule>[
        _rule(r'(\d+)章', r'第$1章', isRegex: true),
        _rule('广告', ''),
        _rule('不存在的词', 'x'),
      ]);
      expect(outcomes[0].matched, isTrue);
      expect(outcomes[0].after, '第12章 广告');
      expect(outcomes[1].matched, isTrue);
      expect(outcomes[1].after, '第12章 ');
      expect(outcomes[2].matched, isFalse);
    });
  });

  group('高亮规则', () {
    test('正则命中、作用域与日夜取色', () {
      final spans = matchNovelHighlights(
        '广告和广告',
        <NovelHighlightRule>[
          _highlight(pattern: '广告'),
          _highlight(pattern: '广告', bookId: 'other-book'),
        ],
        bookId: 'book-1',
        dark: false,
      );
      expect(spans, hasLength(2));
      expect(spans.first.start, 0);
      expect(spans.first.end, 2);
      expect(spans[1].start, 3);
      expect(spans.first.style.foreground.toARGB32(), 0xFF880000);

      final dark = matchNovelHighlights(
        '广告',
        <NovelHighlightRule>[_highlight(pattern: '广告')],
        bookId: 'book-1',
        dark: true,
      );
      expect(dark.single.style.foreground.toARGB32(), 0xFFFFAAAA);
    });

    test('坏正则整条跳过、停用的规则不命中', () {
      final spans = matchNovelHighlights(
        '广告',
        <NovelHighlightRule>[
          _highlight(pattern: '(', bold: true),
          _highlight(pattern: '广告', enabled: false),
        ],
        bookId: 'book-1',
        dark: false,
      );
      expect(spans, isEmpty);
    });

    test('区间越界夹取：完全在外返回 null，部分在外夹到文本长度', () {
      final rule = _highlight();
      const style = NovelHighlightStyle(foreground: Color(0xFF000000));
      final partial = NovelHighlightSpan(
        start: 2,
        end: 99,
        rule: rule,
        style: style,
      ).clampedTo(10);
      expect(partial?.start, 2);
      expect(partial?.end, 10);

      final outside = NovelHighlightSpan(
        start: 20,
        end: 30,
        rule: rule,
        style: style,
      ).clampedTo(10);
      expect(outside, isNull);
    });
  });

  group('内容覆盖', () {
    late NovelDb db;
    late NovelContentOverrideService service;

    setUp(() {
      db = NovelDb.forTesting(NativeDatabase.memory());
      service = NovelContentOverrideService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('保存 → 读取 → 覆盖 → 删除', () async {
      expect(
        await service.has(
          bookId: 'book-1',
          sourceKey: 'src-a',
          chapterKey: 'c0',
        ),
        isFalse,
      );
      expect(
        await service.load(
          bookId: 'book-1',
          sourceKey: 'src-a',
          chapterKey: 'c0',
        ),
        isNull,
      );

      await service.save(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterKey: 'c0',
        chapterTitle: '第一章',
        paragraphs: const <String>['改过的第一段', '', '改过的第二段'],
      );
      final loaded = await service.load(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterKey: 'c0',
      );
      expect(loaded, isNotNull);
      expect(loaded!.title, '第一章');
      expect(loaded.paragraphs, <String>['改过的第一段', '改过的第二段']);

      // 同键再存 = 覆盖，不叠行。
      await service.save(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterKey: 'c0',
        chapterTitle: '第一章',
        paragraphs: const <String>['第三版'],
      );
      final again = await service.load(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterKey: 'c0',
      );
      expect(again!.paragraphs, <String>['第三版']);

      expect(
        await service.remove(
          bookId: 'book-1',
          sourceKey: 'src-a',
          chapterKey: 'c0',
        ),
        isTrue,
      );
      expect(
        await service.load(
          bookId: 'book-1',
          sourceKey: 'src-a',
          chapterKey: 'c0',
        ),
        isNull,
      );
    });

    test('不同书源/章节互不串行', () async {
      await service.save(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterKey: 'c0',
        chapterTitle: '第一章',
        paragraphs: const <String>['A'],
      );
      expect(
        await service.load(
          bookId: 'book-1',
          sourceKey: 'src-b',
          chapterKey: 'c0',
        ),
        isNull,
      );
      expect(
        await service.load(
          bookId: 'book-2',
          sourceKey: 'src-a',
          chapterKey: 'c0',
        ),
        isNull,
      );
    });
  });

  test('v3 → v4 迁移只建两新表', () async {
    final executor = NativeDatabase.memory();
    await executor.ensureOpen(_OpenUser(3));
    final db = NovelDb.forTesting(executor);
    addTearDown(db.close);

    final migrator = Migrator(db);
    await db.migration.onUpgrade(migrator, 3, 4);

    await db
        .into(db.novelHighlightRules)
        .insert(
          NovelHighlightRulesCompanion.insert(
            pattern: '广告',
            foregroundLight: 0xFF000000,
            foregroundDark: 0xFFFFFFFF,
            createdAt: DateTime(2026, 11, 25),
            updatedAt: DateTime(2026, 11, 25),
          ),
        );
    await db
        .into(db.novelContentOverrides)
        .insert(
          NovelContentOverridesCompanion.insert(
            bookId: 'b',
            chapterKey: 'c',
            paragraphsJson: '["x"]',
            updatedAt: DateTime(2026, 11, 25),
          ),
        );
    expect(await db.select(db.novelHighlightRules).get(), hasLength(1));
    expect(await db.select(db.novelContentOverrides).get(), hasLength(1));
  });

  test('阅读控制器：本地覆盖优先于引擎正文，恢复后回到原文', () async {
    final db = NovelDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final overrides = NovelContentOverrideService(db);
    final highlights = NovelHighlightRuleService(db);
    final engine = _Engine(
      const NovelContent(
        chapterId: 'c0',
        title: '第一章',
        paragraphs: <String>['引擎原文一', '引擎原文二'],
      ),
    );
    final controller = NovelReaderController(
      bookId: 'book-1',
      title: '测试书',
      sourceKey: 'src-a',
      bookUrl: 'https://site.test/book/1',
      onlineEngine: engine,
      sourceStore: _SourceStore(<NovelBookSource>[_source]),
      replaceRules: null,
      highlightRules: highlights,
      contentOverrides: overrides,
      settingsStore: MemoryNovelReaderSettingsStore(
        const NovelReaderSettings(),
      ),
    );
    addTearDown(controller.dispose);

    await controller.init();
    expect(controller.content?.paragraphs, <String>['引擎原文一', '引擎原文二']);
    expect(controller.chapterIsLocalOverride, isFalse);

    final saved = await controller.saveChapterOverride(const <String>[
      '我改过的正文',
    ]);
    expect(saved, isTrue);
    expect(controller.content?.paragraphs, <String>['我改过的正文']);
    expect(controller.chapterIsLocalOverride, isTrue);

    final restored = await controller.restoreChapterOverride();
    expect(restored, isTrue);
    expect(controller.content?.paragraphs, <String>['引擎原文一', '引擎原文二']);
    expect(controller.chapterIsLocalOverride, isFalse);
    expect(
      await overrides.load(
        bookId: 'book-1',
        sourceKey: 'src-a',
        chapterKey: 'c0',
      ),
      isNull,
    );
  });
}
