// 书源校验/调试会话测试：四步结果结构、动作分发、取消、追踪事件。
//
// 用 fake 引擎覆盖（不碰网络/QuickJS）；真实引擎链路由 legado_engine_test 覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/debug/novel_engine_trace.dart';
import 'package:mimao/novel/debug/novel_source_debugger.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

final NovelBookSource _source = NovelBookSource(
  key: 'k1',
  name: '测试源',
  url: 'https://s.example',
  type: 0,
  enabled: true,
  raw: const <String, dynamic>{
    'bookSourceName': '测试源',
    'bookSourceUrl': 'https://s.example',
    'searchUrl': '/s?q={{key}}',
  },
);

final NovelSummary _book = NovelSummary(
  id: 'k1::https://s.example/1',
  title: '测试书',
  author: '作者',
  sourceKey: 'k1',
  bookUrl: 'https://s.example/1',
);

final NovelDetail _detail = NovelDetail(
  ref: _book.ref,
  title: '测试书',
  author: '作者',
  intro: '简介文字',
  chapters: const <NovelChapter>[
    NovelChapter(id: 'c1', title: '第一章', index: 0, url: 'https://s.example/1'),
    NovelChapter(id: 'c2', title: '第二章', index: 1, url: 'https://s.example/2'),
  ],
);

/// 可控的 fake 引擎：每个阶段可单独配置失败 / 空结果，并记录调用。
class _FakeEngine implements NovelOnlineEngine, NovelEngineTraceable {
  _FakeEngine({
    this.searchBooks,
    this.detail,
    this.contentParagraphs,
    this.searchError,
    this.detailError,
    this.contentError,
  });

  List<NovelSummary>? searchBooks;
  NovelDetail? detail;
  List<String>? contentParagraphs;
  String? searchError;
  String? detailError;
  String? contentError;

  final List<String> calls = <String>[];
  NovelTraceSink? sink;
  final List<String> phases = <String>[];

  @override
  void attachTrace(NovelTraceSink? value) => sink = value;

  @override
  void beginTracePhase(String phase) {
    phases.add(phase);
    sink?.add(NovelTraceEvent(kind: NovelTraceKind.phase, label: phase));
  }

  void _emitHttp(String url, String body) {
    sink?.add(
      NovelTraceEvent(kind: NovelTraceKind.http, label: url, detail: body),
    );
  }

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    calls.add('search:$keyword');
    if (searchError != null) throw Exception(searchError);
    final books = searchBooks ?? <NovelSummary>[_book];
    _emitHttp('https://s.example/s?q=$keyword', '<html>搜索结果</html>');
    return books;
  }

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async {
    calls.add('detail:${ref.id}');
    if (detailError != null) throw Exception(detailError);
    _emitHttp(ref.bookUrl, '<html>详情页</html>');
    return detail ?? _detail;
  }

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async {
    calls.add('content:${chapter.title}');
    if (contentError != null) throw Exception(contentError);
    _emitHttp(chapter.url, '<html>正文页</html>');
    return NovelContent(
      chapterId: chapter.id,
      title: chapter.title,
      paragraphs: contentParagraphs ?? <String>['第一段正文', '第二段正文'],
    );
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
  void close() {}
}

void main() {
  group('完整校验链', () {
    test('四步全通过，给出每步耗时与结果摘要', () async {
      final engine = _FakeEngine();
      final result = await NovelSourceDebugger(engine: engine).verify(_source);

      expect(result.passed, isTrue);
      expect(result.steps.map((s) => s.name), <String>['搜索', '详情', '目录', '正文']);
      expect(result.steps.every((s) => s.isOk), isTrue);
      expect(result.steps.first.summary, contains('1 本'));
      expect(result.steps[2].summary, contains('2 章'));
      expect(result.steps.last.summary, contains('2 段'));
      expect(result.headline, contains('全部通过'));
      expect(result.cancelled, isFalse);
    });

    test('搜索空结果 → 搜索失败并停止，后续步骤不执行', () async {
      final engine = _FakeEngine(searchBooks: const <NovelSummary>[]);
      final result = await NovelSourceDebugger(engine: engine).verify(_source);

      expect(result.passed, isFalse);
      expect(result.steps, hasLength(1));
      expect(result.steps.single.name, '搜索');
      expect(result.steps.single.error, contains('0 本书'));
      expect(result.headline, contains('搜索失败'));
      expect(engine.calls.where((c) => c.startsWith('detail')), isEmpty);
    });

    test('详情失败 → 报可读错误，目录/正文不再跑', () async {
      final engine = _FakeEngine(detailError: '详情页 403');
      final result = await NovelSourceDebugger(engine: engine).verify(_source);
      expect(result.steps.map((s) => s.name), <String>['搜索', '详情']);
      expect(result.firstFailure?.error, contains('403'));
      expect(engine.calls.any((c) => c.startsWith('content')), isFalse);
    });

    test('目录 0 章 → 目录失败，正文不跑', () async {
      final engine = _FakeEngine(
        detail: NovelDetail(ref: _book.ref, title: '测试书'),
      );
      final result = await NovelSourceDebugger(engine: engine).verify(_source);
      expect(result.steps.map((s) => s.name), <String>['搜索', '详情', '目录']);
      expect(result.firstFailure?.error, contains('目录 0 章'));
    });

    test('正文 0 段 → 正文失败，错误提示规则失效', () async {
      final engine = _FakeEngine(contentParagraphs: const <String>[]);
      final result = await NovelSourceDebugger(engine: engine).verify(_source);
      expect(result.firstFailure?.name, '正文');
      expect(result.firstFailure?.error, contains('正文 0 段'));
    });

    test('已取消 → 剩余步骤标 cancelled，已完成的保留', () async {
      final engine = _FakeEngine();
      final cancellation = NovelDebugCancellation();
      final debugger = NovelSourceDebugger(engine: engine);
      // 在搜索后取消：用一个在 detail 前触发的引擎包装。
      final future = debugger.verify(_source, cancellation: cancellation);
      cancellation.cancel();
      final result = await future;
      expect(result.cancelled, isTrue);
      expect(result.headline, contains('已取消'));
      expect(
        result.steps.where((s) => s.status == NovelVerifyStatus.cancelled),
        isNotEmpty,
      );
    });

    test('给已有搜索结果时跳过搜索步，仍跑详情/目录/正文', () async {
      final engine = _FakeEngine();
      final result = await NovelSourceDebugger(
        engine: engine,
      ).verify(_source, preferredBook: _book);
      expect(result.steps.first.status, NovelVerifyStatus.skipped);
      expect(engine.calls.any((c) => c.startsWith('search')), isFalse);
      expect(result.passed, isTrue);
    });

    test('追踪事件：HTTP 原始响应、阶段分隔都进 sink', () async {
      final engine = _FakeEngine();
      final sink = NovelMemoryTraceSink();
      await NovelSourceDebugger(engine: engine).verify(_source, sink: sink);

      expect(
        sink.events.where((e) => e.kind == NovelTraceKind.phase),
        isNotEmpty,
      );
      expect(
        sink.events.where((e) => e.kind == NovelTraceKind.http),
        isNotEmpty,
      );
      expect(sink.lastHttpBody, isNotNull);
      // 跑完必须摘掉 sink，避免影响正常阅读。
      expect(engine.sink, isNull);
    });

    test('结果可序列化成 JSON（dev 通道用）', () async {
      final engine = _FakeEngine();
      final result = await NovelSourceDebugger(engine: engine).verify(_source);
      final json = result.toJson();
      expect(json['passed'], isTrue);
      expect(json['steps'], isA<List<Object?>>());
      expect((json['steps']! as List<Object?>).length, 4);
    });
  });

  group('单动作调试', () {
    test('搜索动作只跑搜索，带回原始 HTML 与结果摘要', () async {
      final engine = _FakeEngine();
      final run = await NovelSourceDebugger(
        engine: engine,
      ).debug(source: _source, action: NovelDebugAction.search, keyword: '剑来');

      expect(run.isOk, isTrue);
      expect(run.summary, contains('1 本'));
      expect(run.rawHtml, contains('搜索结果'));
      expect(run.rawUrl, contains('q=剑来'));
      expect(engine.calls.where((c) => c.startsWith('detail')), isEmpty);
      expect(engine.sink, isNull);
    });

    test('详情/目录/正文动作在没带书时先搜一次拿第一本', () async {
      final engine = _FakeEngine();
      final run = await NovelSourceDebugger(
        engine: engine,
      ).debug(source: _source, action: NovelDebugAction.toc);
      expect(run.isOk, isTrue);
      expect(run.summary, '2 章');
      expect(engine.calls.first, startsWith('search:'));
      expect(run.events.any((e) => e.label == '解析结果'), isTrue);
    });

    test('正文动作可指定章节', () async {
      final engine = _FakeEngine();
      final run = await NovelSourceDebugger(engine: engine).debug(
        source: _source,
        action: NovelDebugAction.content,
        book: _book,
        chapter: _detail.chapters[1],
      );
      expect(run.isOk, isTrue);
      expect(engine.calls, contains('content:第二章'));
    });

    test('失败动作返回可读错误 + 错误事件（含堆栈）', () async {
      final engine = _FakeEngine(searchError: '连接超时');
      final run = await NovelSourceDebugger(
        engine: engine,
      ).debug(source: _source, action: NovelDebugAction.search);
      expect(run.isOk, isFalse);
      expect(run.error, contains('连接超时'));
      expect(run.events.any((e) => e.kind == NovelTraceKind.error), isTrue);
    });

    test('没有目录时正文动作给出可操作错误', () async {
      final engine = _FakeEngine(
        detail: NovelDetail(ref: _book.ref, title: '测试书'),
      );
      final run = await NovelSourceDebugger(
        engine: engine,
      ).debug(source: _source, action: NovelDebugAction.content, book: _book);
      expect(run.isOk, isFalse);
      expect(run.error, contains('目录 0 章'));
    });

    test('调试结果 JSON 含动作、耗时、原始 HTML 长度与 JS 日志', () async {
      final engine = _FakeEngine();
      final run = await NovelSourceDebugger(
        engine: engine,
      ).debug(source: _source, action: NovelDebugAction.search);
      final json = run.toJson();
      expect(json['action'], 'search');
      expect(json['ok'], isTrue);
      expect(json['rawHtmlLength'], isA<int>());
      expect(json['jsLogs'], isA<List<Object?>>());
    });
  });

  group('追踪 sink', () {
    test('内存 sink 截断超长详情并计数', () {
      final sink = NovelMemoryTraceSink(maxDetailChars: 20);
      sink.add(
        NovelTraceEvent(
          kind: NovelTraceKind.http,
          label: 'u',
          detail: 'x' * 100,
        ),
      );
      expect(sink.truncated, 1);
      expect(sink.events.single.detail, contains('已截断'));
    });

    test('内存 sink 超上限丢弃最旧事件', () {
      final sink = NovelMemoryTraceSink(maxEvents: 3);
      for (var i = 0; i < 5; i++) {
        sink.add(NovelTraceEvent(kind: NovelTraceKind.rule, label: '$i'));
      }
      expect(sink.events.map((e) => e.label), <String>['2', '3', '4']);
    });

    test('jsLogs / errors 过滤正确', () {
      final sink = NovelMemoryTraceSink();
      sink.add(
        NovelTraceEvent(kind: NovelTraceKind.js, label: 'j', detail: 'a'),
      );
      sink.add(NovelTraceEvent(kind: NovelTraceKind.error, label: 'e'));
      expect(sink.jsLogs, <String>['a']);
      expect(sink.errors, hasLength(1));
    });
  });
}
