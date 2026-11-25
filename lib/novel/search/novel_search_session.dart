/// 跨源在线搜索的会话状态机：限流并发、单源失败可重试、分页追加、可取消。
///
/// 只依赖 [NovelOnlineEngine] 的 `searchSource`，不碰 UI——页面订阅
/// [NovelSearchSession.onChanged] 后读 [NovelSearchSession.hits] 与各源状态。
/// 这样「选源 → 搜索 → 翻页 → 重试单源」的时序可以在纯 Dart 测试里钉住。
library;

import 'dart:async';

import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/engine/safe_timeout.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/search/novel_search_merge.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 一个源在一次搜索里的状态。
class NovelSourceSearchState {
  NovelSourceSearchState({required this.source});

  final NovelBookSource source;

  /// 已拿到的书（跨页累计，已按书地址去重）。
  final List<NovelSummary> books = <NovelSummary>[];

  /// 已成功请求的页码（0 = 还没跑）。
  int page = 0;

  bool loading = false;

  /// 最近一次错误；成功后清空。
  String? error;

  /// 该源是否已经翻到底（空页或没有新增）。
  bool exhausted = false;

  /// 最后一次请求耗时（毫秒）。
  int lastDurationMs = 0;

  bool get hasResult => books.isNotEmpty;
  bool get failed => error != null;
}

/// 一次在线搜索的会话。
///
/// 生命周期：页面 `_submit` 时新建（或复用后 [start]），页面 dispose 时
/// [cancel]；token 机制保证旧会话的迟到响应不污染新会话。
class NovelSearchSession {
  NovelSearchSession({
    required NovelOnlineEngine engine,
    this.concurrency = 6,
    this.sourceTimeout = const Duration(seconds: 15),
  }) : _engine = engine;

  final NovelOnlineEngine _engine;

  /// 同时跑几个源。
  final int concurrency;

  /// 单源单页超时（超时算该源失败，可重试）。
  final Duration sourceTimeout;

  /// 状态变更回调（页面 setState）。
  void Function()? onChanged;

  final List<NovelSourceSearchState> _states = <NovelSourceSearchState>[];

  String _keyword = '';
  int _token = 0;
  bool _running = false;
  bool _cancelled = false;

  /// 当前各源状态（只读视图，按选源顺序）。
  List<NovelSourceSearchState> get states =>
      List<NovelSourceSearchState>.unmodifiable(_states);

  bool get running => _running;
  bool get cancelled => _cancelled;
  String get keyword => _keyword;

  int get total => _states.length;
  int get done => _states.where((s) => s.page > 0 || s.failed).length;
  int get failureCount => _states.where((s) => s.failed).length;
  int get successCount => _states.where((s) => s.hasResult).length;

  /// 已跑到最新页且未失败的源数量（进度条分母用）。
  bool get allExhausted =>
      _states.every((s) => s.exhausted || s.failed) && !_running;

  /// 是否还有源可以继续翻页。
  bool get canLoadMore => _states.any((s) => !s.exhausted && !s.failed);

  /// 失败源（页面「重试失败源」按钮用）。
  List<NovelSourceSearchState> get failedStates =>
      _states.where((s) => s.failed).toList();

  /// 全部命中（跨源扁平化，供 [mergeNovelSearchHits] 合并）。
  List<NovelSearchHit> get hits => <NovelSearchHit>[
    for (final state in _states)
      for (final book in state.books)
        NovelSearchHit(source: state.source, book: book, page: state.page),
  ];

  /// 合并后的结果。
  List<NovelMergedBook> merged({
    NovelSearchSort sort = NovelSearchSort.relevance,
  }) => mergeNovelSearchHits(hits, sort: sort, keyword: _keyword);

  /// 开始一轮新搜索：重置全部源，从第 1 页并发跑。
  ///
  /// 已在跑的旧轮次立即失效（token 自增），迟到响应被丢弃。
  Future<void> start(List<NovelBookSource> sources, String keyword) async {
    final token = ++_token;
    _keyword = keyword;
    _cancelled = false;
    _states
      ..clear()
      ..addAll(<NovelSourceSearchState>[
        for (final source in sources) NovelSourceSearchState(source: source),
      ]);
    _running = true;
    _notify();
    await _runPages(token, page: 1, states: List.of(_states));
    if (token != _token) return;
    _running = false;
    _notify();
  }

  /// 追加下一页：只对「没失败、没到底」的源请求 page+1。
  Future<void> loadMore() async {
    if (_running) return;
    final token = _token;
    final targets = <NovelSourceSearchState>[
      for (final state in _states)
        if (!state.exhausted && !state.failed) state,
    ];
    if (targets.isEmpty) return;
    _running = true;
    _notify();
    await _runPages(token, page: null, states: targets);
    if (token != _token) return;
    _running = false;
    _notify();
  }

  /// 重试单源（从第 1 页重来，清掉该源的错误）。
  Future<void> retrySource(String sourceKey) async {
    final target = _states
        .where((state) => state.source.key == sourceKey)
        .firstOrNull;
    if (target == null || _running) return;
    final token = _token;
    target
      ..error = null
      ..exhausted = false
      ..page = 0
      ..books.clear();
    _running = true;
    _notify();
    await _runPages(token, page: 1, states: <NovelSourceSearchState>[target]);
    if (token != _token) return;
    _running = false;
    _notify();
  }

  /// 重试所有失败源。
  Future<void> retryFailed() async {
    final keys = <String>[for (final state in failedStates) state.source.key];
    if (keys.isEmpty || _running) return;
    final token = _token;
    final targets = <NovelSourceSearchState>[];
    for (final state in _states) {
      if (!keys.contains(state.source.key)) continue;
      state
        ..error = null
        ..exhausted = false
        ..page = 0
        ..books.clear();
      targets.add(state);
    }
    _running = true;
    _notify();
    await _runPages(token, page: 1, states: targets);
    if (token != _token) return;
    _running = false;
    _notify();
  }

  /// 取消：迟到响应全部丢弃，状态保持当前快照。
  void cancel() {
    _cancelled = true;
    _token++;
    _running = false;
  }

  /// 并发跑一轮：每个 worker 取一个状态，请求它的下一页（[page] 为 null
  /// 时用该状态的 `page + 1`）。
  Future<void> _runPages(
    int token, {
    required int? page,
    required List<NovelSourceSearchState> states,
  }) async {
    final queue = List<NovelSourceSearchState>.of(states);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (token != _token) return;
        final state = queue.removeAt(0);
        final targetPage = page ?? state.page + 1;
        state.loading = true;
        _notify();
        final stopwatch = Stopwatch()..start();
        try {
          final books = await withSafeTimeout(
            _engine.searchSource(state.source, _keyword, page: targetPage),
            sourceTimeout,
            label: state.source.name,
          );
          stopwatch.stop();
          if (token != _token) return;
          final known = <String>{for (final book in state.books) book.bookUrl};
          final fresh = <NovelSummary>[
            for (final book in books)
              if (book.type == 0 && known.add(book.bookUrl)) book,
          ];
          state
            ..page = targetPage
            ..lastDurationMs = stopwatch.elapsedMilliseconds
            ..error = null
            ..loading = false
            ..exhausted = books.isEmpty || fresh.isEmpty;
          state.books.addAll(fresh);
        } on Object catch (error) {
          stopwatch.stop();
          if (token != _token) return;
          state
            ..loading = false
            ..lastDurationMs = stopwatch.elapsedMilliseconds
            ..error = _readableError(error);
        }
        _notify();
      }
    }

    final workers = queue.length < concurrency ? queue.length : concurrency;
    await Future.wait(<Future<void>>[
      for (var i = 0; i < workers; i++) worker(),
    ]);
  }

  static String _readableError(Object error) {
    final text = '$error'.trim();
    if (text.isEmpty) return '未知错误';
    // 超时文案统一成「超时」，页面不必再判类型。
    if (error is TimeoutException) {
      return '超时（${error.duration?.inSeconds ?? 0}s）';
    }
    return text;
  }

  void _notify() {
    if (_cancelled) return;
    onChanged?.call();
  }
}
