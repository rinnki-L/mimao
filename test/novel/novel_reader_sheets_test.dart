// 书内搜索 / 换源两个弹层：结果展示、点击回传。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_search_sheet.dart';
import 'package:mimao/novel/reader/novel_source_switch_sheet.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

NovelBookSource _source(String key, String name) => NovelBookSource(
  key: key,
  name: name,
  url: 'https://$key.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

class _SearchEngine implements NovelOnlineEngine {
  _SearchEngine({this.failKeys = const <String>{}});

  final Set<String> failKeys;

  @override
  void close() {}

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    if (failKeys.contains(source.key)) throw StateError('源挂了');
    return <NovelSummary>[
      NovelSummary(
        id: '${source.key}-book',
        title: '目标书',
        author: '作者甲',
        sourceKey: source.key,
        bookUrl: 'https://${source.key}.test/book/1',
      ),
      const NovelSummary(id: 'other', title: '无关的书', author: '作者乙'),
    ];
  }

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
  }) async => throw UnimplementedError();

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => throw UnimplementedError();
}

void main() {
  testWidgets('书内搜索：搜索本章命中段落，点结果回传章节与段落下标', (tester) async {
    int? pickedChapter;
    int? pickedParagraph;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelSearchSheet(
            chapterTitles: const <String>['第一章', '第二章'],
            currentChapterIndex: 0,
            loadChapter: (index) async => <String>['第一段没有关键词', '第二段有关键词，能搜到'],
            onPick: (chapter, paragraph) {
              pickedChapter = chapter;
              pickedParagraph = paragraph;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('novel-search-field')), '关键词');
    await tester.tap(find.byKey(const Key('novel-search-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('第二段有关键词'), findsWidgets);
    expect(find.text('第一章'), findsWidgets);

    await tester.tap(find.textContaining('第二段有关键词').first);
    await tester.pumpAndSettle();
    expect(pickedChapter, 0);
    expect(pickedParagraph, 1);
  });

  testWidgets('换源：同名书按源列出，点结果回传源与书籍', (tester) async {
    NovelSourceHit? picked;
    final current = _source('cur', '当前源');
    final good = _source('a', '可用源');
    final bad = _source('b', '挂掉的源');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<NovelSourceHit>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => NovelSourceSwitchSheet(
                      title: '目标书',
                      author: '作者甲',
                      currentSourceKey: current.key,
                      sources: <NovelBookSource>[current, good, bad],
                      engine: _SearchEngine(failKeys: <String>{'b'}),
                    ),
                  );
                },
                child: const Text('打开换源'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开换源'));
    await tester.pumpAndSettle();

    expect(find.text('目标书'), findsWidgets);
    expect(find.textContaining('可用源'), findsOneWidget);
    expect(find.text('无关的书'), findsNothing);

    await tester.tap(find.textContaining('可用源'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.source.key, 'a');
    expect(picked!.book.title, '目标书');
  });

  testWidgets('换源：没有其它启用源时明说不可切换', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelSourceSwitchSheet(
            title: '目标书',
            author: '',
            currentSourceKey: 'cur',
            sources: <NovelBookSource>[_source('cur', '当前源')],
            engine: _SearchEngine(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('没有其它启用的书源'), findsOneWidget);
  });
}
