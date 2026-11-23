// 阅读页翻页模式：分页、左右点击切页、页脚页码与底部菜单入口。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

const _source = NovelBookSource(
  key: 'src1',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

final _chapters = <NovelChapter>[
  const NovelChapter(
    id: 'https://site.test/book/1/1',
    title: '第一章',
    index: 0,
    url: 'https://site.test/book/1/1',
  ),
  const NovelChapter(
    id: 'https://site.test/book/1/2',
    title: '第二章',
    index: 1,
    url: 'https://site.test/book/1/2',
  ),
];

class _LongEngine implements NovelOnlineEngine {
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
  }) async =>
      NovelDetail(ref: ref, title: '长书', author: '作者', chapters: _chapters);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => NovelContent(
    chapterId: chapter.id,
    title: chapter.title,
    paragraphs: <String>[
      for (var i = 0; i < 60; i++)
        '第$i段：${List<String>.filled(120, '字').join()}',
    ],
  );
}

class _FixedStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

Finder _footerWith(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data != null &&
      widget.data!.startsWith(prefix) &&
      widget.data!.contains('/'),
);

void main() {
  testWidgets('翻页模式：长章分多页，点右侧翻到第 2 页', (tester) async {
    final settingsStore = MemoryNovelReaderSettingsStore(
      const NovelReaderSettings(pageMode: NovelPageMode.page),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '长书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book/1',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: _LongEngine(),
          sourceStore: _FixedStore(),
          settingsStore: settingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 页脚：本章第 1 页 / 共 N 页。
    expect(_footerWith('1/'), findsOneWidget);

    // 右侧 30% 热区翻页。
    await tester.tapAt(const Offset(760, 300));
    await tester.pumpAndSettle();
    expect(_footerWith('2/'), findsOneWidget);

    // 左侧热区翻回第 1 页。
    await tester.tapAt(const Offset(40, 300));
    await tester.pumpAndSettle();
    expect(_footerWith('1/'), findsOneWidget);
  });

  testWidgets('书内搜索命中后只关面板，阅读页仍在', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => NovelReaderPage(
                      bookId: 'book1',
                      title: '长书',
                      sourceKey: 'src1',
                      bookUrl: 'https://site.test/book/1',
                      chapterIndex: 0,
                      chapters: _chapters,
                      onlineEngine: _LongEngine(),
                      sourceStore: _FixedStore(),
                      settingsStore: MemoryNovelReaderSettingsStore(),
                    ),
                  ),
                ),
                child: const Text('打开阅读器'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开阅读器'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('novel-reader-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('novel-search-field')), '第0段');
    await tester.tap(find.byKey(const Key('novel-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('novel-search-results')),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await tester.pumpAndSettle();

    // 面板自己 pop 一次；阅读页不能被连带弹掉。
    expect(find.text('打开阅读器'), findsNothing);
    expect(find.byKey(const Key('novel-reader-search')), findsOneWidget);
    expect(find.text('书内搜索'), findsNothing);
  });

  testWidgets('翻页模式刷新本章后仍停在原页码', (tester) async {
    final settingsStore = MemoryNovelReaderSettingsStore(
      const NovelReaderSettings(pageMode: NovelPageMode.page),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '长书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book/1',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: _LongEngine(),
          sourceStore: _FixedStore(),
          settingsStore: settingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(760, 300));
    await tester.pumpAndSettle();
    expect(_footerWith('2/'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-reader-refresh')));
    await tester.pumpAndSettle();
    expect(_footerWith('2/'), findsOneWidget);
  });

  testWidgets('滚动模式改字号后仍停在原来的章内比例', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '长书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book/1',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: _LongEngine(),
          sourceStore: _FixedStore(),
          settingsStore: MemoryNovelReaderSettingsStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final beforeMax = scrollable.position.maxScrollExtent;
    scrollable.position.jumpTo(beforeMax * 0.5);
    await tester.pumpAndSettle();
    final before = scrollable.position.pixels / beforeMax;
    expect(before, greaterThan(0.3));

    await tester.tap(find.byKey(const Key('novel-reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-font-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-settings-back')));
    await tester.pumpAndSettle();

    final afterMax = scrollable.position.maxScrollExtent;
    final after = afterMax <= 0 ? 0.0 : scrollable.position.pixels / afterMax;
    expect((after - before).abs(), lessThan(0.08));
  });

  testWidgets('底部菜单五个入口都在（搜索/自动翻页/目录/朗读/设置）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '长书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book/1',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: _LongEngine(),
          sourceStore: _FixedStore(),
          settingsStore: MemoryNovelReaderSettingsStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in <String>[
      'novel-reader-search',
      'novel-reader-auto-page',
      'novel-reader-catalog',
      'novel-reader-tts',
      'novel-reader-settings',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
  });
}
