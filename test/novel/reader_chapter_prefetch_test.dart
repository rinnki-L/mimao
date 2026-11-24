// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 换章不白屏：下一章未就绪时保留当前正文，只有底部加载条；就绪后原子替换。

import 'dart:async';

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
    id: 'c1',
    title: '第一章',
    index: 0,
    url: 'https://site.test/1',
  ),
  const NovelChapter(
    id: 'c2',
    title: '第二章',
    index: 1,
    url: 'https://site.test/2',
  ),
];

class _GatedEngine implements NovelOnlineEngine {
  final Completer<NovelContent> second = Completer<NovelContent>();
  int callsForSecond = 0;

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
  }) async => NovelDetail(ref: ref, title: '书', chapters: _chapters);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) {
    if (chapter.index == 0) {
      return Future<NovelContent>.value(
        NovelContent(
          chapterId: chapter.id,
          title: chapter.title,
          paragraphs: <String>['第一章正文，当前页应该一直可见。'],
        ),
      );
    }
    callsForSecond++;
    return second.future;
  }
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

void main() {
  testWidgets('下一章未就绪时保留当前正文，完成后原子替换', (tester) async {
    final engine = _GatedEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: engine,
          sourceStore: _FixedStore(),
          settingsStore: MemoryNovelReaderSettingsStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第一章正文'), findsOneWidget);

    // 预取会在打开第一章后就去抓第二章，这里等它进入 in-flight。
    expect(engine.callsForSecond, greaterThanOrEqualTo(1));

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // 章末按钮在正文手势之内，必须能点（旧的全屏热区会把它吃掉）。
    await tester.tap(find.byKey(const Key('novel-reader-next-chapter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 关键断言：没有整屏「正在加载正文…」，上一章内容还在。
    expect(find.text('正在加载正文…'), findsNothing);
    expect(find.textContaining('第一章正文'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-chapter-loading')),
      findsOneWidget,
    );
    expect(find.textContaining('正在加载「第二章」'), findsOneWidget);

    engine.second.complete(
      const NovelContent(
        chapterId: 'c2',
        title: '第二章',
        paragraphs: <String>['第二章正文。'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第二章正文'), findsOneWidget);
    expect(find.textContaining('正在加载「第二章」'), findsNothing);
    expect(find.textContaining('第一章正文'), findsNothing);
  });
}
