// 换章结算归属：这一段时间必须记到「刚读完的那一章」，不是新章。
//
// 旧实现只在 flush 时读 `_controller.chapter`，而控制器是先换章再 notify，
// 所以每段时长都会记到下一章头上（章节维度会全错一格）。这里用可控计时器
// 把「读了两分钟」喂进去，断言落库的章号。
// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_reading_clock.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';
import 'package:mimao/novel/stats_service.dart';

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

class _Engine implements NovelOnlineEngine {
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
    paragraphs: <String>['${chapter.title} 的正文。'],
  );
}

class _Store implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

/// 可控计时器：测试手动决定「这一段读了多久」。
class _FakeClock implements NovelReadingClock {
  Duration elapsed = Duration.zero;
  bool running = false;

  @override
  void start() => running = true;

  @override
  void stop() => running = false;

  @override
  void reset() => elapsed = Duration.zero;

  @override
  bool get isRunning => running;
}

void main() {
  late NovelDb db;
  late NovelStatsService stats;
  late _FakeClock clock;

  setUp(() {
    db = NovelDb.forTesting(NativeDatabase.memory());
    stats = NovelStatsService(db);
    clock = _FakeClock();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('换章结算记到上一章，退出结算记到当前章', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookId: 'book1',
          title: '长书',
          sourceKey: 'src1',
          bookUrl: 'https://site.test/book/1',
          chapterIndex: 0,
          chapters: _chapters,
          onlineEngine: _Engine(),
          sourceStore: _Store(),
          settingsStore: MemoryNovelReaderSettingsStore(),
          stats: stats,
          readingClock: clock,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第一章读了两分钟，然后点章末「下一章」换章。
    clock.elapsed = const Duration(minutes: 2);
    await tester.tap(find.byKey(const Key('novel-reader-next-chapter')));
    await tester.pumpAndSettle();

    var chapters = await stats.bookChapters('book1');
    expect(chapters, hasLength(1));
    expect(chapters.single.chapterIndex, 1, reason: '应记到第一章，不是新章');
    expect(chapters.single.chapterName, '第一章');
    expect(chapters.single.seconds, 120);

    // 第二章再读一分钟，退出页面结算。
    clock.elapsed = const Duration(minutes: 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    chapters = await stats.bookChapters('book1');
    expect(chapters.map((c) => c.chapterIndex), <int>[1, 2]);
    expect(chapters[1].seconds, 60);
    expect(chapters[1].chapterName, '第二章');

    // 时长归属到「长书」，书名来自详情。
    final timeline = await stats.timeline();
    expect(timeline.single.books.single.title, '长书');
    expect(timeline.single.seconds, 180);
  });
}
