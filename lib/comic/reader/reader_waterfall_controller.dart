// 跨章瀑布流控制器：在 [ReaderChapterFlow] 之上补全 "前后章节懒加载 / 跳章 /
// 预取"。纯 Dart（ChangeNotifier），不碰 Widget、不联网；I/O 全部走
// [ReaderChapterSource]。
//
// 对齐 Venera Next 的 WaterfallController，关键不变量：
// - 任何异步结果都要过三道闸：scope 未取消、[revision] 未变、章节 id 未漂移；
// - revision++（跳章）时取消全部在途 scope，迟到结果一律丢弃；
// - ensureAfter 防重入、跨空章继续填、失败锁存 afterError；
// - ensureBefore 一次只补一章并返回插入图片数（视图据此恢复滚动锚点）；
// - 章节 id 在 await 之前同步取，源切换后 id 漂移直接判为失效。
//
// 流索引只属于视图；控制器只负责章节段的增删与状态通知。

import 'package:flutter/foundation.dart';

import 'reader_chapter_source.dart';
import 'reader_flow.dart';

/// 瀑布流控制器：把 [source] 的章节按需拼进 [flow]。
class ReaderWaterfallController extends ChangeNotifier {
  ReaderWaterfallController({
    required this.source,
    required this.initialChapter,
    required this.initialChapterId,
    this.prefetchThreshold = 3,
  }) : assert(initialChapter > 0, '章节号 1 基'),
       assert(prefetchThreshold > 0, '预取阈值必须为正');

  final ReaderChapterSource source;

  /// 起始章（1 基）。
  final int initialChapter;

  /// 起始章的稳定 id（来自进度记录），[start] 用它构造首段。
  final String initialChapterId;

  /// 默认预取阈值（剩余图片少于该值就补章）。
  final int prefetchThreshold;

  final ReaderChapterFlow _flow = ReaderChapterFlow();
  final Set<ReaderLoadScope> _inFlight = <ReaderLoadScope>{};

  bool _loadingAfter = false;
  bool _loadingBefore = false;
  String? _afterError;
  int _revision = 0;
  bool _started = false;
  bool _disposed = false;

  // 加载代次：每次发起"向后/向前"加载时 ++，用来让旧调用的 finally 不误清
  // 新调用的 loading 标志（跳章会取消旧调用并自己接管标志）。
  int _afterLoadToken = 0;
  int _beforeLoadToken = 0;

  /// 当前段集合（升序）。
  ReaderChapterFlow get flow => _flow;

  bool get loadingAfter => _loadingAfter;
  bool get loadingBefore => _loadingBefore;

  /// 最近一次向后补章的错误；null 表示正常。UI 可用 [retryAfter] 重试。
  String? get afterError => _afterError;

  /// 每次显式导航（跳章 / 取消在途）递增；异步结果据此拒绝迟到插入。
  int get revision => _revision;

  /// 初始化：加载起始章，成功后 flow 只含这一段。
  /// 重复调用是空操作。
  Future<void> start() async {
    if (_disposed || _started) return;
    _started = true;
    final int revision = _revision;
    final ReaderLoadScope scope = _startScope();
    final int token = ++_afterLoadToken;
    final String sourceId = source.chapterId(initialChapter);
    _loadingAfter = true;
    _notify();
    try {
      final List<String> images = await source.load(initialChapter, scope);
      if (!_isCurrent(revision) || scope.isCancelled) return;
      if (source.chapterId(initialChapter) != sourceId) return;
      _flow.reset(
        ReaderChapterSegment(
          chapter: initialChapter,
          chapterId: initialChapterId,
          images: images,
        ),
      );
    } on Object catch (error) {
      if (!_isCurrent(revision) || scope.isCancelled) return;
      _afterError = '加载第 $initialChapter 章失败：$error';
    } finally {
      _endScope(scope);
      if (!_disposed && token == _afterLoadToken) {
        _loadingAfter = false;
        _notify();
      }
    }
  }

  /// 向后补章：填满阈值并跨空章，直到 [source] 的最大章。
  ///
  /// [current] 是视图当前可见的最后一个流索引；[threshold] 缺省用
  /// [prefetchThreshold]。正在加载或已锁存错误时直接返回。
  Future<void> ensureAfter({required int current, int? threshold}) async {
    if (_disposed || _loadingAfter || _flow.isEmpty) return;
    if (_afterError != null) return;
    final int limit = threshold ?? prefetchThreshold;
    final int token = ++_afterLoadToken;
    _loadingAfter = true;
    _notify();
    try {
      while (!_disposed &&
          _flow.shouldLoadAfter(
            current: current,
            threshold: limit,
            maxChapter: source.chapterCount,
          )) {
        final int chapter = _flow.lastChapter + 1;
        final int revision = _revision;
        // 章节 id 必须在 await 前取，源切换后 id 漂移即视为失效。
        final String sourceId = source.chapterId(chapter);
        final ReaderLoadScope scope = _startScope();
        List<String> images;
        try {
          images = await source.load(chapter, scope);
        } on Object catch (error) {
          _endScope(scope);
          if (!_isCurrent(revision) || scope.isCancelled) return;
          _afterError = '加载第 $chapter 章失败：$error';
          return;
        }
        _endScope(scope);
        if (!_isCurrent(revision) || scope.isCancelled) return;
        if (source.chapterId(chapter) != sourceId) return;

        final ReaderChapterSegment segment = ReaderChapterSegment(
          chapter: chapter,
          chapterId: sourceId,
          images: images,
        );
        final bool added = _flow.addAfter(segment);
        _notify();
        if (!added) return;
      }
    } finally {
      if (!_disposed && token == _afterLoadToken) {
        _loadingAfter = false;
        _notify();
      }
    }
  }

  /// 向前补章：每次只加载一章（[ReaderChapterFlow.firstChapter] - 1）。
  ///
  /// 返回插入的图片数，供视图做滚动锚点位移；失败静默返回 0（下次接近顶部
  /// 自然会重试），scope 取消同样返回 0。
  Future<int> ensureBefore({required int current, int? threshold}) async {
    if (_disposed || _loadingBefore || _flow.isEmpty) return 0;
    final int limit = threshold ?? prefetchThreshold;
    if (!_flow.shouldLoadBefore(current: current, threshold: limit)) return 0;
    final int chapter = _flow.firstChapter - 1;
    if (chapter < 1) return 0;

    final int revision = _revision;
    final String sourceId = source.chapterId(chapter);
    final ReaderLoadScope scope = _startScope();
    final int token = ++_beforeLoadToken;
    _loadingBefore = true;
    _notify();
    try {
      final List<String> images = await source.load(chapter, scope);
      if (!_isCurrent(revision) || scope.isCancelled) return 0;
      // id 在 await 期间漂移（源切换 / 章节重排）→ 不插，避免错位。
      if (source.chapterId(chapter) != sourceId) return 0;
      final ReaderChapterSegment segment = ReaderChapterSegment(
        chapter: chapter,
        chapterId: sourceId,
        images: images,
      );
      final int inserted = _flow.addBefore(segment);
      if (inserted > 0) _notify();
      return inserted;
    } on Object {
      // 向前补章失败保持静默：不锁存错误，靠近顶部时会自然重试。
      return 0;
    } finally {
      _endScope(scope);
      if (!_disposed && token == _beforeLoadToken) {
        _loadingBefore = false;
        _notify();
      }
    }
  }

  /// 清空 [afterError] 并重试向后补章（UI 的"点此重试"）。
  Future<void> retryAfter({required int current}) async {
    if (_disposed || _afterError == null) return;
    _afterError = null;
    _notify();
    await ensureAfter(current: current);
  }

  /// 显式跳章。目标章已在 flow 内时直接返回 true（不发请求，视图用现有段
  /// 定位即可）；否则加载成功后 flow 重置为单段。
  ///
  /// [toLastPage] 只由视图消费（跳到该章末页），控制器不解释它。
  ///
  /// 加载失败时：若旧流仍有效则 rethrow（让 UI 留在原处并提示），否则返回
  /// false。
  Future<bool> goToChapter(int chapter, {bool toLastPage = false}) async {
    if (_disposed) return false;
    RangeError.checkValueInInterval(chapter, 1, source.chapterCount, 'chapter');

    // 跳章是硬边界：先递增 revision 再取消旧 scope，迟到结果全部作废。
    _revision++;
    _cancelAllScopes();
    ++_afterLoadToken;
    ++_beforeLoadToken;
    _loadingAfter = false;
    _loadingBefore = false;
    _afterError = null;
    if (_flow.hasChapter(chapter)) {
      _notify();
      return true;
    }

    final int revision = _revision;
    final String sourceId = source.chapterId(chapter);
    final ReaderLoadScope scope = _startScope();
    final int token = ++_afterLoadToken;
    _loadingAfter = true;
    _notify();
    try {
      final List<String> images = await source.load(chapter, scope);
      if (!_isCurrent(revision) || scope.isCancelled) return false;
      if (source.chapterId(chapter) != sourceId) return false;
      _flow.reset(
        ReaderChapterSegment(
          chapter: chapter,
          chapterId: sourceId,
          images: images,
        ),
      );
      _notify();
      return true;
    } on Object {
      if (_isCurrent(revision) && !_flow.isEmpty) rethrow;
      return false;
    } finally {
      _endScope(scope);
      if (!_disposed && token == _afterLoadToken) {
        _loadingAfter = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // 取消全部在途请求；异步续体会因 _disposed 直接丢弃结果，不再 notify。
    _cancelAllScopes();
    super.dispose();
  }

  bool _isCurrent(int revision) => !_disposed && revision == _revision;

  ReaderLoadScope _startScope() {
    final ReaderLoadScope scope = ReaderLoadScope();
    _inFlight.add(scope);
    return scope;
  }

  void _endScope(ReaderLoadScope scope) {
    _inFlight.remove(scope);
  }

  void _cancelAllScopes() {
    for (final ReaderLoadScope scope in _inFlight) {
      scope.cancel();
    }
    _inFlight.clear();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
