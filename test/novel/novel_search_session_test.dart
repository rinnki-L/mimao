// 跨源搜索会话测试：限流并发、分页追加、单源失败重试、取消。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/search/novel_search_session.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

NovelBookSource _source(String name, {int weight = 0}) => NovelBookSource(
  key: NovelBookSource.keyFor('https://$name.example'),
  name: name,
  url: 'https://$name.example',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{
    'bookSourceName': name,
    'bookSourceUrl': 'https://$name.example',
    'searchUrl': '/s?q={{key}}',
    'weight': weight,
  },
);

class _PagedEngine implements NovelOnlineEngine {
  _PagedEngine({this.pagesPerSource = 2, this.failing = const <String>{}});

  final int pagesPerSource;
  final Set<String> failing;
  final List<String> calls = <String>[];
  Completer<void>? gate;

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    calls.add('${source.name}#$page');
    if (gate != null) await gate!.future;
    if (failing.contains(source.name)) {
      throw Exception('${source.name} 挂了');
    }
    if (page > pagesPerSource) return const <NovelSummary>[];
    return <NovelSummary>[
      NovelSummary(
        id: '${source.name}-$page',
        title: '${source.name} 第 $page 页',
        bookUrl: 'https://${source.name}/$page',
        sourceKey: source.key,
      ),
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

  @override
  void close() {}
}

/// 两个源都返回同一本书（不同源内地址），用于验证跨源合并。
class _SameBookEngine extends _PagedEngine {
  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    calls.add('${source.name}#$page');
    if (page > 1) return const <NovelSummary>[];
    return <NovelSummary>[
      NovelSummary(
        id: '${source.name}-1',
        title: '剑来',
        author: '烽火戏诸侯',
        bookUrl: 'https://${source.name}/book/1',
        sourceKey: source.key,
      ),
    ];
  }
}

void main() {
  test('并发上限生效，且每源只请求一次首页', () async {
    final engine = _PagedEngine()..gate = Completer<void>();
    final session = NovelSearchSession(engine: engine, concurrency: 2);
    final sources = <NovelBookSource>[
      for (final name in <String>['a', 'b', 'c', 'd']) _source(name),
    ];
    final future = session.start(sources, '剑来');
    await Future<void>.delayed(Duration.zero);
    // 门未放行时只有 2 个源在跑。
    expect(engine.calls, hasLength(2));
    engine.gate!.complete();
    await future;
    expect(engine.calls.toSet(), hasLength(4));
    expect(session.running, isFalse);
    expect(session.states.every((s) => s.page == 1), isTrue);
  });

  test('翻页追加并按书地址去重，空页标记到底', () async {
    final engine = _PagedEngine(pagesPerSource: 2);
    final session = NovelSearchSession(engine: engine);
    await session.start(<NovelBookSource>[_source('a')], '剑来');
    expect(session.hits, hasLength(1));
    expect(session.canLoadMore, isTrue);

    await session.loadMore();
    expect(session.hits, hasLength(2));
    expect(session.canLoadMore, isTrue);

    // 第 3 页空 → 到底。
    await session.loadMore();
    expect(session.states.single.exhausted, isTrue);
    expect(session.hits, hasLength(2));
    expect(session.canLoadMore, isFalse);
  });

  test('单源失败不影响其他源，可按源重试', () async {
    final engine = _PagedEngine(failing: <String>{'bad'});
    final session = NovelSearchSession(engine: engine);
    await session.start(<NovelBookSource>[
      _source('bad'),
      _source('good'),
    ], 'x');

    expect(session.failureCount, 1);
    expect(session.successCount, 1);
    expect(session.failedStates.single.source.name, 'bad');
    expect(session.failedStates.single.error, contains('挂了'));

    engine.failing.clear();
    await session.retryFailed();
    expect(session.failureCount, 0);
    expect(session.states.first.books, hasLength(1));
  });

  test('重试单源只重跑那一个源', () async {
    final engine = _PagedEngine(failing: <String>{'bad'});
    final session = NovelSearchSession(engine: engine);
    await session.start(<NovelBookSource>[
      _source('bad'),
      _source('good'),
    ], 'x');
    engine.calls.clear();
    engine.failing.clear();
    await session.retrySource(session.states.first.source.key);
    expect(engine.calls, <String>['bad#1']);
    expect(session.states.first.books, hasLength(1));
  });

  test('取消后迟到响应被丢弃', () async {
    final engine = _PagedEngine()..gate = Completer<void>();
    final session = NovelSearchSession(engine: engine);
    final future = session.start(<NovelBookSource>[_source('a')], 'x');
    await Future<void>.delayed(Duration.zero);
    session.cancel();
    engine.gate!.complete();
    await future;
    expect(session.cancelled, isTrue);
    expect(session.hits, isEmpty);
  });

  test('超时按失败记录并可读', () async {
    final engine = _PagedEngine()..gate = Completer<void>();
    final session = NovelSearchSession(
      engine: engine,
      sourceTimeout: const Duration(milliseconds: 30),
    );
    await session.start(<NovelBookSource>[_source('slow')], 'x');
    expect(session.failureCount, 1);
    expect(session.failedStates.single.error, contains('超时'));
    engine.gate!.complete();
  });

  test('合并结果按相关度排序并跨源合并同书', () async {
    final engine = _SameBookEngine();
    final session = NovelSearchSession(engine: engine);
    await session.start(<NovelBookSource>[_source('a'), _source('b')], '剑来');
    final merged = session.merged();
    expect(merged, hasLength(1));
    expect(merged.first.sourceCount, 2);
  });
}
