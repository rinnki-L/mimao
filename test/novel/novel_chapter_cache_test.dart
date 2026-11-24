// 会话内章节缓存：命中、并发去重、预取、LRU 淘汰、失败不缓存。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_chapter_cache.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

const _source = NovelBookSource(
  key: 'src',
  name: '源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

const _ref = NovelRef(id: 'book', sourceKey: 'src', bookUrl: '/book');

NovelChapter _chapter(int index) => NovelChapter(
  id: 'c$index',
  title: '第$index章',
  index: index,
  url: '/c/$index',
);

NovelContent _content(int index, {int chars = 4}) => NovelContent(
  chapterId: 'c$index',
  title: '第$index章',
  paragraphs: <String>[List<String>.filled(chars, '字').join()],
);

class _Engine implements NovelOnlineEngine {
  int calls = 0;
  final Map<int, Completer<NovelContent>> gates =
      <int, Completer<NovelContent>>{};
  bool fail = false;

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
      const NovelDetail(ref: _ref, title: '书', chapters: <NovelChapter>[]);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) {
    calls++;
    if (fail) return Future<NovelContent>.error(StateError('boom'));
    final gate = gates[chapter.index];
    if (gate != null) return gate.future;
    return Future<NovelContent>.value(_content(chapter.index));
  }
}

void main() {
  test('命中缓存后不再走引擎', () async {
    final engine = _Engine();
    final cache = NovelChapterCache();
    final chapter = _chapter(0);

    final first = await cache.load(
      engine: engine,
      source: _source,
      ref: _ref,
      chapter: chapter,
    );
    final second = await cache.load(
      engine: engine,
      source: _source,
      ref: _ref,
      chapter: chapter,
    );

    expect(first.title, '第0章');
    expect(second, same(first));
    expect(engine.calls, 1);
    expect(cache.contains(chapter), isTrue);
  });

  test('同章并发请求合并为一次抓取', () async {
    final engine = _Engine();
    final gate = Completer<NovelContent>();
    engine.gates[1] = gate;
    final cache = NovelChapterCache();
    final chapter = _chapter(1);

    final a = cache.load(
      engine: engine,
      source: _source,
      ref: _ref,
      chapter: chapter,
    );
    final b = cache.load(
      engine: engine,
      source: _source,
      ref: _ref,
      chapter: chapter,
    );
    expect(engine.calls, 1);

    gate.complete(_content(1));
    expect((await a).title, '第1章');
    expect((await b).title, '第1章');
    expect(engine.calls, 1);
  });

  test('失败不写缓存，下次会重新请求', () async {
    final engine = _Engine()..fail = true;
    final cache = NovelChapterCache();
    final chapter = _chapter(2);

    await expectLater(
      cache.load(engine: engine, source: _source, ref: _ref, chapter: chapter),
      throwsStateError,
    );
    expect(cache.contains(chapter), isFalse);

    engine.fail = false;
    final content = await cache.load(
      engine: engine,
      source: _source,
      ref: _ref,
      chapter: chapter,
    );
    expect(content.title, '第2章');
    expect(engine.calls, 2);
  });

  test('超过字符预算淘汰最旧条目', () async {
    final engine = _Engine();
    final cache = NovelChapterCache(maxChars: 10);
    final a = _chapter(0);
    final b = _chapter(1);

    await cache.load(engine: engine, source: _source, ref: _ref, chapter: a);
    await cache.load(engine: engine, source: _source, ref: _ref, chapter: b);
    // 每章 4 个正文字符 + 3 字标题 = 7；两章 14 > 10，淘汰更旧的 a。
    expect(cache.contains(a), isFalse);
    expect(cache.contains(b), isTrue);
  });

  test('预取不抛异常，失败静默', () async {
    final engine = _Engine()..fail = true;
    final cache = NovelChapterCache();
    expect(
      () => cache.prefetch(
        engine: engine,
        source: _source,
        ref: _ref,
        chapter: _chapter(3),
      ),
      returnsNormally,
    );
    await Future<void>.delayed(Duration.zero);
  });
}
