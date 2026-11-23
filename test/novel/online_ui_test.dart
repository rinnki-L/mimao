// ignore_for_file: deprecated_member_use — 与小说页面同款 Flutter 3.50 说明。
// 在线书源 UI 单测：搜索页在线分组、详情目录、阅读器翻章、发现分类弹层。
//
// 全部 fake 注入，不访问网络；真实引擎链路由 legado_engine_test 覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_book_detail_page.dart';
import 'package:mimao/novel/pages/novel_explore_sheet.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_search_page.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

final NovelBookSource _source = NovelBookSource(
  key: 'src1',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: const <String, dynamic>{
    'bookSourceUrl': 'https://site.test',
    'searchUrl': '/search?kw={{key}}',
    'exploreUrl': '玄幻::/list/1/{{page}}.html',
  },
);

const NovelSummary _book = NovelSummary(
  id: 'src1::https://site.test/book/1',
  title: '测试书名',
  author: '测试作者',
  sourceName: novelSourceName,
  sourceKey: 'src1',
  bookUrl: 'https://site.test/book/1',
  intro: '测试简介',
);

final NovelDetail _detail = NovelDetail(
  ref: _book.ref,
  title: _book.title,
  author: _book.author,
  intro: _book.intro,
  chapters: const <NovelChapter>[
    NovelChapter(
      id: 'https://site.test/book/1/1',
      title: '第一章',
      index: 0,
      url: 'https://site.test/book/1/1',
    ),
    NovelChapter(
      id: 'https://site.test/book/1/2',
      title: '第二章',
      index: 1,
      url: 'https://site.test/book/1/2',
    ),
  ],
);

class _FakeStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

class _FakeEngine implements NovelOnlineEngine {
  int searchCalls = 0;
  int contentCalls = 0;

  @override
  void close() {}

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    searchCalls++;
    return <NovelSummary>[_book];
  }

  @override
  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async =>
      const <NovelExploreKind>[
        NovelExploreKind(name: '玄幻', url: '/list/1/{{page}}.html'),
      ];

  @override
  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async => <NovelSummary>[_book];

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async => _detail;

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async {
    contentCalls++;
    return NovelContent(
      chapterId: chapter.id,
      title: chapter.title,
      paragraphs: <String>['${chapter.title}的正文'],
    );
  }
}

class _FailingEngine extends _FakeEngine {
  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async => throw StateError('网络超时');

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async => throw StateError('目录抓取失败');

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => throw StateError('正文抓取失败');
}

class _FakeHistory implements NovelHistoryApi {
  _FakeHistory({this.resumeChapterNumber = 0});

  /// 历史库存的 1 起章号；0 = 无进度。
  final int resumeChapterNumber;
  final List<int> saved = <int>[];

  @override
  Future<void> open(NovelSummary book) async {}

  @override
  Future<void> saveProgress(
    NovelSummary book,
    int chapterIndex,
    int chapterCount,
  ) async {
    saved.add(chapterIndex);
  }

  @override
  Future<NovelHistoryItem?> latest(String bookId) async =>
      resumeChapterNumber <= 0
      ? null
      : NovelHistoryItem(
          book: _book,
          chapterIndex: resumeChapterNumber,
          chapterCount: 2,
          openedAt: DateTime(2026, 1, 1),
        );

  @override
  Future<List<NovelHistoryItem>> recent({int limit = 50}) async =>
      const <NovelHistoryItem>[];

  @override
  Future<void> remove(String bookId) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('搜索页：在线引擎结果按书源分组并展示', (tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: NovelSearchPage(onlineEngine: engine, sourceStore: _FakeStore()),
      ),
    );
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(engine.searchCalls, 1);
    expect(find.text('在线书源 · 1 个源命中'), findsOneWidget);
    expect(find.text('测试源 · 1'), findsOneWidget);
    expect(find.text('测试书名'), findsWidgets);
  });

  testWidgets('详情页：在线目录、简介与点章进阅读路由', (tester) async {
    NovelRoute? opened;
    Map<String, Object?>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: NovelBookDetailPage(
          bookId: _book.id,
          titleHint: _book.title,
          sourceKey: 'src1',
          bookUrl: _book.bookUrl,
          onlineEngine: _FakeEngine(),
          sourceStore: _FakeStore(),
          openRoute: (route, {args = const <String, Object?>{}}) async {
            opened = route;
            captured = args;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('测试书名'), findsWidgets);
    expect(find.text('测试简介'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('目录 · 2 章'), 300);
    expect(find.text('目录 · 2 章'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('第二章'), 200);
    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();
    expect(opened, NovelRoute.read);
    expect(captured?['chapterIndex'], 1);
    expect(captured?['sourceKey'], 'src1');
  });

  testWidgets('详情页续读：历史 1 起章号换回目录 0 起下标', (tester) async {
    NovelRoute? opened;
    Map<String, Object?>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: NovelBookDetailPage(
          bookId: _book.id,
          titleHint: _book.title,
          sourceKey: 'src1',
          bookUrl: _book.bookUrl,
          onlineEngine: _FakeEngine(),
          sourceStore: _FakeStore(),
          history: _FakeHistory(resumeChapterNumber: 2),
          openRoute: (route, {args = const <String, Object?>{}}) async {
            opened = route;
            captured = args;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 「继续阅读」用历史章号 2 找到 0 起 index=1 的第二章。
    await tester.tap(find.text('继续阅读'));
    await tester.pumpAndSettle();
    expect(opened, NovelRoute.read);
    expect(captured?['chapterIndex'], 1);
    expect(captured?['chapterId'], 'https://site.test/book/1/2');
  });

  testWidgets('阅读器：正文、翻章与进度上报', (tester) async {
    final engine = _FakeEngine();
    final history = _FakeHistory();
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: _book.id,
          title: _book.title,
          sourceKey: 'src1',
          bookUrl: _book.bookUrl,
          chapterIndex: 0,
          chapters: _detail.chapters,
          onlineEngine: engine,
          sourceStore: _FakeStore(),
          history: history,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一章的正文'), findsOneWidget);
    // 历史库存的是 1 起章号：0 起引擎索引 +1，第 1 章落库为 1（不是 0）。
    expect(history.saved, <int>[1]);

    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('第二章的正文'), findsOneWidget);
    expect(history.saved, <int>[1, 2]);
  });

  testWidgets('阅读器：目录抽屉存在时仍有返回入口，可退出阅读页', (tester) async {
    // 有 drawer 的 AppBar 默认把 leading 换成汉堡菜单，返回键消失；
    // 这里锁住「返回键必须存在且能出栈」，防止再次退不出阅读器。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => NovelReaderPage(
                      bookId: _book.id,
                      title: _book.title,
                      sourceKey: 'src1',
                      bookUrl: _book.bookUrl,
                      chapterIndex: 0,
                      chapters: _detail.chapters,
                      onlineEngine: _FakeEngine(),
                      sourceStore: _FakeStore(),
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
    expect(find.text('第一章的正文'), findsOneWidget);

    final back = find.byTooltip('返回');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.text('打开阅读器'), findsOneWidget);
    expect(find.text('第一章的正文'), findsNothing);
  });

  testWidgets('阅读器：替换规则在展示前作用于正文', (tester) async {
    final rules = _FakeReplaceStorage(<NovelReplaceRule>[
      NovelReplaceRule.fromLegado(<String, dynamic>{
        'name': '正文改词',
        'pattern': '正文',
        'replacement': '内容',
      }),
      NovelReplaceRule.fromLegado(<String, dynamic>{
        'name': '禁用规则',
        'pattern': '第一章',
        'replacement': '不该出现',
        'isEnabled': false,
      }),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: _book.id,
          title: _book.title,
          sourceKey: 'src1',
          bookUrl: _book.bookUrl,
          chapterIndex: 0,
          chapters: _detail.chapters,
          onlineEngine: _FakeEngine(),
          sourceStore: _FakeStore(),
          replaceRules: rules,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一章的内容'), findsOneWidget);
    expect(find.text('第一章的正文'), findsNothing);
    expect(find.text('不该出现的正文'), findsNothing);
  });

  testWidgets('搜索页：全部源失败时展示失败摘要', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelSearchPage(
          onlineEngine: _FailingEngine(),
          sourceStore: _FakeStore(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('在线书源没有结果'), findsOneWidget);
    expect(find.textContaining('测试源：'), findsOneWidget);
  });

  testWidgets('详情页：在线目录失败给可重试错误态', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NovelBookDetailPage(
          bookId: _book.id,
          titleHint: _book.title,
          sourceKey: 'src1',
          bookUrl: _book.bookUrl,
          onlineEngine: _FailingEngine(),
          sourceStore: _FakeStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('目录抓取失败'), findsOneWidget);
  });

  testWidgets('阅读器：正文失败给可重试错误态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: _book.id,
          title: _book.title,
          sourceKey: 'src1',
          bookUrl: _book.bookUrl,
          chapterIndex: 0,
          chapters: _detail.chapters,
          onlineEngine: _FailingEngine(),
          sourceStore: _FakeStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('正文抓取失败'), findsOneWidget);
    expect(find.text('重试'), findsWidgets);
  });

  testWidgets('发现分类弹层：分类 chip 与书单可点', (tester) async {
    NovelSummary? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelExploreSheet(
            source: _source,
            engine: _FakeEngine(),
            onOpenBook: (book) => opened = book,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('玄幻'), findsOneWidget);
    expect(find.text('测试书名'), findsOneWidget);
    await tester.tap(find.text('测试书名'));
    expect(opened?.id, _book.id);
  });
}

class _FakeReplaceStorage implements NovelReplaceRuleStorage {
  _FakeReplaceStorage(this.rules);

  final List<NovelReplaceRule> rules;

  @override
  Future<List<NovelReplaceRule>> loadAll() async => List.unmodifiable(rules);

  @override
  Future<int> saveAll(Iterable<NovelReplaceRule> input) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}
