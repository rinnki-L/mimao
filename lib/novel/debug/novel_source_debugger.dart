/// 书源校验与调试：在**同一个**引擎实例上跑「搜索 → 详情 → 目录 → 正文」，
/// 逐步记录耗时、结果摘要与追踪事件，支持取消。
///
/// 设计要点：
/// - 只调 [NovelOnlineEngine] 的公开方法，不复制解析逻辑；调试跑的就是阅读
///   时跑的那条流水线。
/// - 引擎实现了 [NovelEngineTraceable] 时挂上追踪 sink，拿到 HTTP 原始响应、
///   规则执行结果、JS 日志；不实现也能跑（只是没有细节）。
/// - 取消粒度是「步骤之间」：单条 HTTP 无法协作中断，面板文案照实说。
/// - 纯 Dart（除引擎本身），可单测：注入 fake 引擎验证结果结构。
library;

import 'dart:async';

import 'package:mimao/novel/debug/novel_engine_trace.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/engine/safe_timeout.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 调试动作。
enum NovelDebugAction {
  search('搜索', '用关键词搜一次列表'),
  detail('详情', '抓详情页字段（书名/作者/简介/封面）'),
  toc('目录', '抓章节目录'),
  content('正文', '抓指定章节的正文');

  const NovelDebugAction(this.label, this.description);

  final String label;
  final String description;
}

/// 一步的执行结果。
enum NovelVerifyStatus { ok, failed, skipped, cancelled }

class NovelVerifyStep {
  const NovelVerifyStep({
    required this.name,
    required this.status,
    this.durationMs = 0,
    this.summary = '',
    this.error = '',
    this.detail = '',
  });

  /// 步骤名：搜索 / 详情 / 目录 / 正文。
  final String name;
  final NovelVerifyStatus status;
  final int durationMs;

  /// 结果摘要（「12 本书」「目录 348 章，第一章…」）。
  final String summary;

  /// 可读错误（堆栈在 [detail]）。
  final String error;

  /// 附加细节（错误堆栈 / 示例数据）。
  final String detail;

  bool get isOk => status == NovelVerifyStatus.ok;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'status': status.name,
    'durationMs': durationMs,
    if (summary.isNotEmpty) 'summary': summary,
    if (error.isNotEmpty) 'error': error,
    if (detail.isNotEmpty) 'detail': detail,
  };
}

/// 一次校验的完整结果。
class NovelVerifyResult {
  const NovelVerifyResult({
    required this.sourceName,
    required this.sourceKey,
    required this.steps,
    required this.startedAt,
    this.cancelled = false,
  });

  final String sourceName;
  final String sourceKey;
  final List<NovelVerifyStep> steps;
  final DateTime startedAt;
  final bool cancelled;

  /// 全部跑通（没有 failed）。
  bool get passed =>
      !cancelled &&
      steps.every((step) => step.status != NovelVerifyStatus.failed);

  /// 总耗时（各步之和）。
  int get totalMs => steps.fold<int>(0, (sum, step) => sum + step.durationMs);

  /// 第一个失败的步骤（UI 高亮用）。
  NovelVerifyStep? get firstFailure => steps
      .where((step) => step.status == NovelVerifyStatus.failed)
      .firstOrNull;

  /// 一句话结论：「全部通过（1.2s）」/「正文失败：…」。
  String get headline {
    if (cancelled) return '已取消（已完成的步骤保留）';
    final failure = firstFailure;
    if (failure != null) return '${failure.name}失败：${failure.error}';
    return '全部通过（${(totalMs / 1000).toStringAsFixed(1)}s）';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceName': sourceName,
    'sourceKey': sourceKey,
    'passed': passed,
    'cancelled': cancelled,
    'totalMs': totalMs,
    'headline': headline,
    'steps': <Object?>[for (final step in steps) step.toJson()],
  };
}

/// 校验/调试会话。
///
/// 一个会话对应一条书源的一次跑动；同一实例可重复 [verify] / [debug]，每次
/// 都重挂追踪 sink 并在结束时摘掉（不影响正常阅读）。
class NovelSourceDebugger {
  NovelSourceDebugger({
    required NovelOnlineEngine engine,
    this.stepTimeout = const Duration(seconds: 30),
  }) : _engine = engine;

  final NovelOnlineEngine _engine;

  /// 单步超时（校验链每一步、单动作调试都用它）。
  final Duration stepTimeout;

  /// 跑完整校验链：搜索 → 详情 → 目录 → 正文。
  ///
  /// [keyword] 为空时用书源名（多数源能搜到自己）；[preferredBook] 允许直接
  /// 指定一本书跳过搜索（从搜索结果点「校验」时用）。
  Future<NovelVerifyResult> verify(
    NovelBookSource source, {
    String keyword = '',
    NovelSummary? preferredBook,
    NovelDebugCancellation? cancellation,
    NovelTraceSink? sink,
  }) async {
    final startedAt = DateTime.now();
    final steps = <NovelVerifyStep>[];
    final trace = _attach(sink);

    Future<NovelVerifyStep> run(
      String name,
      Future<String> Function() body,
    ) async {
      if (cancellation?.isCancelled == true) {
        return NovelVerifyStep(
          name: name,
          status: NovelVerifyStatus.cancelled,
          summary: '取消后未执行',
        );
      }
      _beginPhase(name);
      final stopwatch = Stopwatch()..start();
      try {
        final summary = await withSafeTimeout(body(), stepTimeout, label: name);
        stopwatch.stop();
        return NovelVerifyStep(
          name: name,
          status: NovelVerifyStatus.ok,
          durationMs: stopwatch.elapsedMilliseconds,
          summary: summary,
        );
      } on TimeoutException {
        stopwatch.stop();
        return NovelVerifyStep(
          name: name,
          status: NovelVerifyStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          error: '超时（${stepTimeout.inSeconds}s）',
        );
      } on Object catch (error, stack) {
        stopwatch.stop();
        return NovelVerifyStep(
          name: name,
          status: NovelVerifyStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          error: _readable(error),
          detail: '$stack',
        );
      }
    }

    // 1. 搜索
    NovelSummary? book = preferredBook;
    if (book != null) {
      steps.add(
        NovelVerifyStep(
          name: '搜索',
          status: NovelVerifyStatus.skipped,
          summary: '用已有结果：${book.title}',
        ),
      );
    } else {
      final step = await run('搜索', () async {
        final books = await _engine.searchSource(
          source,
          keyword.trim().isEmpty ? source.name : keyword.trim(),
        );
        if (books.isEmpty) {
          throw _VerifyEmpty('搜索返回 0 本书（关键词「$keyword」）');
        }
        book = books.first;
        return '${books.length} 本 · 首本「${books.first.title}」'
            '${books.first.author.isEmpty ? '' : ' / ${books.first.author}'}';
      });
      steps.add(step);
      if (!step.isOk) {
        return _finish(source, steps, startedAt, trace, cancellation);
      }
    }

    final target = book;
    if (target == null) {
      return _finish(source, steps, startedAt, trace, cancellation);
    }
    final ref = target.ref;

    // 2+3. 详情 + 目录（引擎一次调用同时返回两者；失败归到「详情」）
    NovelDetail? detail;
    final detailStep = await run('详情', () async {
      final value = await _engine.bookDetail(
        source,
        ref,
        titleHint: target.title,
        authorHint: target.author,
      );
      detail = value;
      final filled = <String>[
        if (value.title.isNotEmpty) '书名',
        if (value.author.isNotEmpty) '作者',
        if (value.intro.isNotEmpty) '简介',
        if (value.coverUrl.isNotEmpty) '封面',
        if (value.wordCount.isNotEmpty) '字数',
      ];
      return '「${value.title}」· 解析到 ${filled.length}/5 个字段'
          '${filled.isEmpty ? '' : '（${filled.join('/')}）'}';
    });
    steps.add(detailStep);
    if (!detailStep.isOk) {
      return _finish(source, steps, startedAt, trace, cancellation);
    }
    final loaded = detail;
    if (loaded == null) {
      return _finish(source, steps, startedAt, trace, cancellation);
    }

    final tocStep = await run('目录', () async {
      final chapters = loaded.chapters;
      if (chapters.isEmpty) {
        throw const _VerifyEmpty('目录 0 章（chapterList 规则可能失效）');
      }
      final first = chapters.first.title;
      final last = chapters.last.title;
      return '${chapters.length} 章 · 首「$first」尾「$last」';
    });
    steps.add(tocStep);
    if (!tocStep.isOk) {
      return _finish(source, steps, startedAt, trace, cancellation);
    }

    // 4. 正文（第一章；VIP 章会跳过说明）
    final chapter = loaded.chapters.first;
    final contentStep = await run('正文', () async {
      final content = await _engine.contentFor(source, loaded.ref, chapter);
      if (content.paragraphs.isEmpty) {
        throw const _VerifyEmpty('正文 0 段（content 规则可能失效，或需要登录）');
      }
      final firstLine = content.paragraphs.first;
      final preview = firstLine.length <= 40
          ? firstLine
          : '${firstLine.substring(0, 40)}…';
      return '${content.paragraphs.length} 段 · $preview';
    });
    steps.add(contentStep);
    return _finish(source, steps, startedAt, trace, cancellation);
  }

  /// 单动作调试：只跑用户选的那一步，返回追踪 sink 供面板展示链路。
  ///
  /// [book] / [chapter] 由面板从校验结果或搜索结果里带入；缺失时搜索动作
  /// 之外的动作会给出可读错误（而不是空跑）。
  Future<NovelDebugRun> debug({
    required NovelBookSource source,
    required NovelDebugAction action,
    String keyword = '',
    NovelSummary? book,
    NovelChapter? chapter,
    NovelDebugCancellation? cancellation,
  }) async {
    final sink = NovelMemoryTraceSink();
    final trace = _attach(sink);
    final stopwatch = Stopwatch()..start();
    _beginPhase(action.label);
    String summary = '';
    String? error;
    try {
      if (cancellation?.isCancelled == true) {
        throw const NovelDebugCancelled();
      }
      summary = await withSafeTimeout(
        switch (action) {
          NovelDebugAction.search => _debugSearch(source, keyword, sink),
          NovelDebugAction.detail => _debugDetail(source, book, sink),
          NovelDebugAction.toc => _debugToc(source, book, sink),
          NovelDebugAction.content => _debugContent(
            source,
            book,
            chapter,
            sink,
          ),
        },
        stepTimeout,
        label: action.label,
      );
    } on TimeoutException {
      error = '超时（${stepTimeout.inSeconds}s）';
    } on NovelDebugCancelled {
      error = '已取消';
    } on Object catch (e, stack) {
      error = _readable(e);
      sink.add(
        NovelTraceEvent(
          kind: NovelTraceKind.error,
          label: action.label,
          detail: '$stack',
        ),
      );
    } finally {
      stopwatch.stop();
      trace();
    }
    return NovelDebugRun(
      action: action,
      summary: summary,
      error: error,
      durationMs: stopwatch.elapsedMilliseconds,
      events: sink.events,
      rawHtml: sink.lastHttpBody ?? '',
      rawUrl: sink.lastHttpUrl ?? '',
      jsLogs: sink.jsLogs,
      truncated: sink.truncated > 0,
    );
  }

  Future<String> _debugSearch(
    NovelBookSource source,
    String keyword,
    NovelMemoryTraceSink sink,
  ) async {
    final books = await _engine.searchSource(
      source,
      keyword.trim().isEmpty ? source.name : keyword.trim(),
    );
    sink.add(
      NovelTraceEvent(
        kind: NovelTraceKind.phase,
        label: '解析结果',
        detail: books.isEmpty
            ? '0 本'
            : '${books.length} 本\n'
                  '${books.take(5).map((book) => '· ${book.title} / ${book.author} → ${book.bookUrl}').join('\n')}',
      ),
    );
    return books.isEmpty
        ? '0 本（检查 searchUrl 与 bookList 规则）'
        : '${books.length} 本';
  }

  Future<String> _debugDetail(
    NovelBookSource source,
    NovelSummary? book,
    NovelMemoryTraceSink sink,
  ) async {
    final target = book ?? await _firstBook(source);
    final detail = await _engine.bookDetail(
      source,
      target.ref,
      titleHint: target.title,
      authorHint: target.author,
    );
    sink.add(
      NovelTraceEvent(
        kind: NovelTraceKind.phase,
        label: '解析结果',
        detail:
            '书名：${detail.title}\n'
            '作者：${detail.author}\n'
            '简介：${detail.intro.length} 字\n'
            '封面：${detail.coverUrl}\n'
            '字数：${detail.wordCount}\n'
            '目录：${detail.chapters.length} 章',
      ),
    );
    return '「${detail.title}」· ${detail.chapters.length} 章';
  }

  Future<String> _debugToc(
    NovelBookSource source,
    NovelSummary? book,
    NovelMemoryTraceSink sink,
  ) async {
    final target = book ?? await _firstBook(source);
    final detail = await _engine.bookDetail(
      source,
      target.ref,
      titleHint: target.title,
      authorHint: target.author,
    );
    final chapters = detail.chapters;
    sink.add(
      NovelTraceEvent(
        kind: NovelTraceKind.phase,
        label: '解析结果',
        detail: chapters.isEmpty
            ? '0 章'
            : '${chapters.length} 章\n'
                  '${chapters.take(5).map((c) => '· [${c.index}] ${c.title} → ${c.url}').join('\n')}'
                  '${chapters.length > 5 ? '\n…' : ''}',
      ),
    );
    return chapters.isEmpty ? '0 章' : '${chapters.length} 章';
  }

  Future<String> _debugContent(
    NovelBookSource source,
    NovelSummary? book,
    NovelChapter? chapter,
    NovelMemoryTraceSink sink,
  ) async {
    final target = book ?? await _firstBook(source);
    final detail = await _engine.bookDetail(
      source,
      target.ref,
      titleHint: target.title,
      authorHint: target.author,
    );
    final picked =
        chapter ?? (detail.chapters.isEmpty ? null : detail.chapters.first);
    if (picked == null) {
      throw const _VerifyEmpty('目录 0 章，无法抓正文');
    }
    final content = await _engine.contentFor(source, detail.ref, picked);
    sink.add(
      NovelTraceEvent(
        kind: NovelTraceKind.phase,
        label: '解析结果',
        detail:
            '章节：${content.title}\n'
            '段落：${content.paragraphs.length}\n\n'
            '${content.paragraphs.take(5).join('\n')}',
      ),
    );
    return '${content.paragraphs.length} 段';
  }

  /// 详情/目录/正文动作没带书时，先搜一次拿第一本（与校验链一致）。
  Future<NovelSummary> _firstBook(NovelBookSource source) async {
    final books = await _engine.searchSource(source, source.name);
    if (books.isEmpty) {
      throw const _VerifyEmpty('搜索返回 0 本书，先在「搜索」动作里确认列表规则');
    }
    return books.first;
  }

  void _beginPhase(String name) {
    final engine = _engine;
    if (engine is NovelEngineTraceable) {
      (engine as NovelEngineTraceable).beginTracePhase(name);
    }
  }

  /// 挂上追踪 sink，返回摘除函数（必须调用，否则正常阅读也会被记录）。
  void Function() _attach(NovelTraceSink? sink) {
    final engine = _engine;
    if (sink == null || engine is! NovelEngineTraceable) return () {};
    final traceable = engine as NovelEngineTraceable;
    traceable.attachTrace(sink);
    return () => traceable.attachTrace(null);
  }

  NovelVerifyResult _finish(
    NovelBookSource source,
    List<NovelVerifyStep> steps,
    DateTime startedAt,
    void Function() detach,
    NovelDebugCancellation? cancellation,
  ) {
    detach();
    return NovelVerifyResult(
      sourceName: source.name,
      sourceKey: source.key,
      steps: List<NovelVerifyStep>.unmodifiable(steps),
      startedAt: startedAt,
      cancelled: cancellation?.isCancelled == true,
    );
  }

  static String _readable(Object error) {
    final text = '$error'.trim();
    if (text.isEmpty) return '未知错误';
    return text;
  }
}

/// 单动作调试的结果。
class NovelDebugRun {
  const NovelDebugRun({
    required this.action,
    required this.summary,
    required this.durationMs,
    required this.events,
    required this.rawHtml,
    required this.rawUrl,
    required this.jsLogs,
    this.error,
    this.truncated = false,
  });

  final NovelDebugAction action;
  final String summary;
  final String? error;
  final int durationMs;
  final List<NovelTraceEvent> events;

  /// 最近一次 HTTP 的原始响应体（「原始 HTML」页签）。
  final String rawHtml;
  final String rawUrl;

  /// JS 控制台输出（`java.log`）。
  final List<String> jsLogs;

  /// 响应体是否因超长被截断。
  final bool truncated;

  bool get isOk => error == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'action': action.name,
    'ok': isOk,
    if (error != null) 'error': error,
    'durationMs': durationMs,
    'summary': summary,
    'rawUrl': rawUrl,
    'rawHtmlLength': rawHtml.length,
    'jsLogs': jsLogs,
    'events': <Object?>[for (final event in events) event.toJson()],
  };
}

/// 校验链里「规则跑通但结果是空」——与异常区分开，文案更具体。
class _VerifyEmpty implements Exception {
  const _VerifyEmpty(this.message);

  final String message;

  @override
  String toString() => message;
}
