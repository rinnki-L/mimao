// 阅读器控制器：把「书 / 章 / 正文 / 排版 / 位置 / 预取」从页面 State 里拆出来。
//
// 页面只负责画和交互；状态变更都走这里，便于单测和后续接 legado 的
// 阅读菜单/点击区/书签。行为对照：
// - 章级进度仍写 novel_history（chapterIndex 1 起）；
// - 章内位置写模块 kv，新增字符偏移 locator；
// - 正文缓存分两层：引擎的落盘 NovelCache（跨会话）+ 本控制器的相邻章 LRU
//   （会话内，换章不白屏）。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mimao/core/theme.dart' show MimaoFonts;
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_chapter_cache.dart';
import 'package:mimao/novel/reader/novel_layout_service.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_reader_position.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

/// 滚动模式恢复位置时给页面的一次性请求。
class NovelScrollRestore {
  const NovelScrollRestore(this.position, {this.atEnd = false});

  final NovelReaderPosition? position;
  final bool atEnd;
}

class NovelReaderController extends ChangeNotifier {
  NovelReaderController({
    required this.bookId,
    this.title,
    this.author,
    this.sourceKey,
    this.bookUrl,
    this.chapterId,
    this.chapterIndex,
    this.chapterUrl,
    this.chapterTitle,
    this.coverUrl,
    this.chapters,
    this.onlineEngine,
    this.sourceStore,
    this.history,
    this.prefs,
    this.replaceRules,
    NovelReaderSettingsStore? settingsStore,
    NovelLayoutService? layoutService,
    NovelChapterCache? chapterCache,
  }) : settingsStore = settingsStore ?? PrefsNovelReaderSettingsStore(prefs),
       layoutService = layoutService ?? NovelLayoutService(),
       chapterCache = chapterCache ?? NovelChapterCache();

  final String bookId;
  final String? title;
  final String? author;
  final String? sourceKey;
  final String? bookUrl;
  final String? chapterId;
  final int? chapterIndex;
  final String? chapterUrl;
  final String? chapterTitle;
  final String? coverUrl;
  final List<NovelChapter>? chapters;
  final NovelOnlineEngine? onlineEngine;
  final NovelSourceStorage? sourceStore;
  final NovelHistoryApi? history;
  final NovelPrefsApi? prefs;
  final NovelReplaceRuleStorage? replaceRules;

  final NovelReaderSettingsStore settingsStore;
  final NovelLayoutService layoutService;
  final NovelChapterCache chapterCache;
  late final NovelReaderPositionStore positionStore = NovelReaderPositionStore(
    prefs,
  );

  NovelReaderSettings settings = const NovelReaderSettings();
  bool settingsReady = false;

  NovelBookSource? source;
  NovelDetail? detail;
  NovelChapter? chapter;
  NovelContent? content;

  /// 正在切换、但还没拿到正文的下一章；非空时正文区仍显示上一章。
  NovelChapter? pendingChapter;

  String? loadError;
  bool loadingDetail = true;
  bool loadingContent = false;
  bool paginating = false;

  List<NovelTextPage> pages = const <NovelTextPage>[];
  int pageIndex = 0;
  int pageDirection = 1;

  /// 正文换过一次就 +1；页面据此重置滚动位置。
  int contentEpoch = 0;

  NovelReaderPosition? savedPosition;
  double scrollRatio = 0;

  NovelSummary? historyOverride;
  List<NovelReplaceRule> replaceRules_ = const <NovelReplaceRule>[];

  NovelReaderPosition? _pendingRestore;
  bool _pendingStartAtEnd = false;
  double? _pendingScrollRatio;
  NovelLocator? _pendingJumpLocator;
  NovelLocator? _pendingLocator;
  int _scrollParagraph = 0;

  String _layoutKey = '';
  String _requestedKey = '';

  Future<void> _replaceRulesReady = Future<void>.value();
  Timer? _settingsTimer;
  Timer? _saveTimer;
  bool _disposed = false;
  int _loadSeq = 0;

  bool get disposed => _disposed;

  String get _sourceKeyNow =>
      detail?.ref.sourceKey ?? source?.key ?? sourceKey ?? '';

  bool get hasPrevious => neighborChapter(-1) != null;
  bool get hasNext => neighborChapter(1) != null;

  NovelChapter? neighborChapter(int delta) {
    final current = detail;
    final selected = chapter;
    if (current == null || selected == null) return null;
    var index = selected.index + delta;
    while (index >= 0 && index < current.chapters.length) {
      final candidate = current.chapters[index];
      if (!candidate.isVolume) return candidate;
      index += delta;
    }
    return null;
  }

  Future<void> init() async {
    final loaded = await settingsStore.load();
    final position = await positionStore.load(
      bookId,
      sourceKey: sourceKey ?? '',
    );
    if (_disposed) return;
    settings = loaded;
    savedPosition = position;
    settingsReady = true;
    _replaceRulesReady = _loadReplaceRules();
    notifyListeners();
    await bootstrap();
  }

  Future<void> _loadReplaceRules() async {
    final store = replaceRules;
    if (store == null) return;
    try {
      final rules = await store.loadAll();
      if (_disposed) return;
      replaceRules_ = rules;
      notifyListeners();
    } on Object {
      // 规则读坏了不该让正文打不开。
    }
  }

  NovelContent applyContentReplaceRules(NovelContent content) {
    if (replaceRules_.isEmpty) return content;
    final bookTitle = detail?.title ?? title ?? '';
    final bookSourceKey = _sourceKeyNow;
    final bookUrlNow = detail?.ref.bookUrl ?? bookUrl ?? '';
    final applicable = replaceRules_
        .where(
          (rule) =>
              rule.enabled &&
              rule.appliesToBook(
                bookTitle: bookTitle,
                sourceKey: bookSourceKey,
                bookUrl: bookUrlNow,
              ),
        )
        .toList();
    if (applicable.isEmpty) return content;
    final titleRules = applicable.where((rule) => rule.scopeTitle).toList();
    final contentRules = applicable.where((rule) => rule.scopeContent).toList();
    return NovelContent(
      chapterId: content.chapterId,
      title: titleRules.isEmpty
          ? content.title
          : applyReplaceRules(content.title, titleRules),
      paragraphs: contentRules.isEmpty
          ? content.paragraphs
          : <String>[
              for (final paragraph in content.paragraphs)
                applyReplaceRules(paragraph, contentRules),
            ],
    );
  }

  Future<void> bootstrap() async {
    final engine = onlineEngine;
    final store = sourceStore;
    final key = sourceKey ?? '';
    if (engine == null || store == null || key.isEmpty) {
      loadingDetail = false;
      loadError = '阅读器未接线（缺少书源引擎或书源信息）';
      notifyListeners();
      return;
    }

    final seq = ++_loadSeq;
    final preloaded = chapters;
    if (preloaded != null && preloaded.isNotEmpty) {
      final preview = NovelDetail(
        ref: NovelRef(id: bookId, sourceKey: key, bookUrl: bookUrl ?? bookId),
        title: title ?? '',
        coverUrl: coverUrl ?? '',
        author: author ?? '',
        chapters: preloaded,
      );
      detail = preview;
      loadingDetail = false;
      notifyListeners();
      try {
        final sources = await store.loadAll();
        if (_disposed || seq != _loadSeq) return;
        for (final candidate in sources) {
          if (candidate.key == key) {
            source = candidate;
            break;
          }
        }
      } on Object {
        // 下面统一判空。
      }
      if (_disposed || seq != _loadSeq) return;
      if (source == null) {
        loadError = '找不到书源（可能已被删除）';
        notifyListeners();
        return;
      }
      final target = _pickChapter(preloaded);
      if (target == null) {
        loadError = '目录为空，无法开始阅读';
        notifyListeners();
        return;
      }
      await openChapter(target);
      return;
    }

    loadingDetail = true;
    loadError = null;
    notifyListeners();
    try {
      final sources = await store.loadAll();
      if (_disposed || seq != _loadSeq) return;
      NovelBookSource? found;
      for (final candidate in sources) {
        if (candidate.key == key) {
          found = candidate;
          break;
        }
      }
      if (found == null) {
        throw StateError('找不到书源（可能已被删除）');
      }
      final ref = NovelRef(
        id: bookId,
        sourceKey: key,
        bookUrl: bookUrl ?? bookId,
      );
      final loaded = await engine.bookDetail(
        found,
        ref,
        titleHint: title,
        authorHint: author,
      );
      if (_disposed || seq != _loadSeq) return;
      source = found;
      detail = loaded;
      loadingDetail = false;
      notifyListeners();
      final target = _pickChapter(loaded.chapters);
      if (target == null) {
        loadError = '目录为空，无法开始阅读';
        notifyListeners();
        return;
      }
      await openChapter(target);
    } on Object catch (error) {
      if (_disposed || seq != _loadSeq) return;
      loadingDetail = false;
      loadError = '$error';
      notifyListeners();
    }
  }

  NovelChapter? _pickChapter(List<NovelChapter> chapters) {
    if (chapters.isEmpty) return null;
    final wanted = chapterId;
    if (wanted != null && wanted.isNotEmpty) {
      for (final item in chapters) {
        if (item.id == wanted || item.url == wanted) return item;
      }
    }
    final index = chapterIndex;
    if (index != null && index >= 0 && index < chapters.length) {
      return chapters[index];
    }
    return chapters.first;
  }

  Future<void> openChapter(
    NovelChapter target, {
    bool atEnd = false,
    bool refresh = false,
  }) async {
    final engine = onlineEngine;
    final currentDetail = detail;
    final currentSource = source;
    if (engine == null || currentDetail == null || currentSource == null) {
      return;
    }

    final seq = ++_loadSeq;
    final reopening = chapter != null && chapter!.id == target.id;
    final resumeFrom = reopening ? currentSavedPosition() : null;
    final hadContent = content != null;
    await savePositionNow();
    if (_disposed) return;

    loadError = null;
    loadingContent = true;
    if (hadContent) {
      // 关键：不立刻清空正文，先把目标章记下来，页面继续显示上一章。
      pendingChapter = target;
      notifyListeners();
    } else {
      pendingChapter = null;
      chapter = target;
      content = null;
      pages = const <NovelTextPage>[];
      pageIndex = 0;
      _layoutKey = '';
      _requestedKey = '';
      notifyListeners();
    }

    try {
      NovelContent raw;
      if (refresh) {
        raw = await _refreshContent(
          engine,
          currentSource,
          currentDetail.ref,
          target,
        );
        chapterCache.put(target, raw);
      } else {
        raw = await chapterCache.load(
          engine: engine,
          source: currentSource,
          ref: currentDetail.ref,
          chapter: target,
        );
      }
      // 规则可能还在读盘；等它落地再展示，避免首屏先出现未净化的正文。
      await _replaceRulesReady;
      if (_disposed || seq != _loadSeq) return;
      final cleaned = applyContentReplaceRules(raw);
      _applyContent(
        target,
        cleaned,
        atEnd: atEnd,
        resumeFrom: resumeFrom,
        reopening: reopening,
      );
    } on Object catch (error) {
      if (_disposed || seq != _loadSeq) return;
      loadingContent = false;
      pendingChapter = null;
      if (content != null) {
        // 保留当前正文；页面上给一条可重试的提示，而不是整屏错误。
        loadError = '$error';
        notifyListeners();
      } else {
        loadError = '$error';
        notifyListeners();
      }
    }
  }

  Future<NovelContent> _refreshContent(
    NovelOnlineEngine engine,
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) {
    if (engine is NovelContentRefresh) {
      return (engine as NovelContentRefresh).refreshContent(
        source,
        ref,
        chapter,
      );
    }
    return engine.contentFor(source, ref, chapter);
  }

  void _applyContent(
    NovelChapter target,
    NovelContent next, {
    required bool atEnd,
    required bool reopening,
    NovelReaderPosition? resumeFrom,
  }) {
    chapter = target;
    content = next;
    pendingChapter = null;
    loadingContent = false;
    loadError = null;
    pageDirection = 1;
    contentEpoch++;

    NovelReaderPosition? saved = resumeFrom ?? savedPosition;
    final jump = _pendingJumpLocator;
    if (jump != null) {
      if (jump.chapterIndex == target.index &&
          (jump.sourceKey.isEmpty ||
              jump.sourceKey == (detail?.ref.sourceKey ?? ''))) {
        saved = NovelReaderPosition(
          chapterUrl: target.url,
          chapterId: target.id,
          chapterIndex: target.index,
          page: 1,
          pageCount: 1,
          locator: jump,
        );
      }
      _pendingJumpLocator = null;
    }
    final canRestore =
        saved != null &&
        (resumeFrom != null ||
            jump != null ||
            saved.matches(
              chapterUrl: target.url,
              chapterId: target.id,
              chapterIndex: target.index,
            ));
    _pendingRestore = canRestore ? saved : null;
    _pendingStartAtEnd = !canRestore && atEnd;
    _pendingLocator = null;
    _pendingScrollRatio = null;
    pages = const <NovelTextPage>[];
    _layoutKey = '';
    _requestedKey = '';
    pageIndex = 0;
    notifyListeners();

    _settlePageRestore();
    _reportProgress(target);
    _prefetchNeighbors(target);
  }

  void _reportProgress(NovelChapter target) {
    final currentDetail = detail;
    if (currentDetail == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await history?.saveProgress(
            historyOverride ?? currentDetail.summary,
            target.index + 1,
            currentDetail.chapters.length,
          );
        } on Object {
          // 历史写入失败不阻断阅读。
        }
      }),
    );
  }

  void _prefetchNeighbors(NovelChapter target) {
    // 串行预取，别一次并发三章把书源打限流：先下一章，再下下章/上一章。
    unawaited(_runPrefetch(target));
  }

  Future<void> _runPrefetch(NovelChapter target) async {
    final engine = onlineEngine;
    final currentDetail = detail;
    final currentSource = source;
    if (engine == null || currentDetail == null || currentSource == null) {
      return;
    }
    for (final delta in <int>[1, 2, -1]) {
      if (_disposed || chapter?.index != target.index) return;
      final neighbor = _neighborFrom(target, delta);
      if (neighbor == null) continue;
      try {
        await chapterCache.load(
          engine: engine,
          source: currentSource,
          ref: currentDetail.ref,
          chapter: neighbor,
        );
      } on Object {
        // 预取失败静默；真正翻到该章时会再请求一次并给错误态。
      }
    }
  }

  NovelChapter? _neighborFrom(NovelChapter from, int delta) {
    final currentDetail = detail;
    if (currentDetail == null) return null;
    var index = from.index + delta;
    while (index >= 0 && index < currentDetail.chapters.length) {
      final candidate = currentDetail.chapters[index];
      if (!candidate.isVolume) return candidate;
      index += delta;
    }
    return null;
  }

  Future<void> nextChapter() async {
    final next = neighborChapter(1);
    if (next != null) await openChapter(next);
  }

  Future<void> previousChapter({bool atEnd = false}) async {
    final previous = neighborChapter(-1);
    if (previous != null) await openChapter(previous, atEnd: atEnd);
  }

  Future<void> retry() async {
    final target = chapter;
    if (target == null) {
      await bootstrap();
    } else {
      await openChapter(target);
    }
  }

  Future<void> refreshCurrentChapter() async {
    final target = chapter;
    if (target != null) await openChapter(target, refresh: true);
  }

  TextStyle bodyStyle() {
    final family = settings.fontFamily.isEmpty
        ? MimaoFonts.family
        : settings.fontFamily;
    return TextStyle(
      fontFamily: family,
      fontWeight: MimaoFonts.regular,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      color: Color(settings.textColorArgb),
    );
  }

  TextStyle titleStyle() => bodyStyle().copyWith(
    fontSize: settings.fontSize + 6,
    fontWeight: MimaoFonts.bold,
    height: 1.4,
  );

  String paragraphText(int index) {
    final paragraphs = content?.paragraphs ?? const <String>[];
    if (index < 0 || index >= paragraphs.length) return '';
    return '　　${paragraphs[index]}';
  }

  /// 页面在 LayoutBuilder 里调用；只登记尺寸，真正排版在帧后。
  void updateLayout({
    required double width,
    required double height,
    required TextScaler textScaler,
  }) {
    final current = content;
    if (current == null) return;
    if (settings.pageMode == NovelPageMode.scroll) {
      if (pages.isNotEmpty || paginating) {
        pages = const <NovelTextPage>[];
        paginating = false;
        _layoutKey = '';
        _requestedKey = '';
      }
      return;
    }
    if (width <= 0 || height <= 0) return;

    final key = <Object?>[
      chapter?.id,
      current.title,
      current.paragraphs.length,
      width,
      height,
      settings.fontSize,
      settings.lineHeight,
      settings.fontFamily,
      settings.paragraphSpacing,
      settings.horizontalPadding,
      textScaler.scale(16),
    ].join('|');
    if (key == _layoutKey && pages.isNotEmpty) return;
    if (key == _requestedKey) return;

    _requestedKey = key;
    paginating = true;
    layoutService.schedule(
      NovelLayoutRequest(
        key: key,
        title: current.title.isEmpty ? (chapter?.title ?? '') : current.title,
        paragraphs: current.paragraphs,
        bodyStyle: bodyStyle(),
        titleStyle: titleStyle(),
        maxWidth: width,
        maxHeight: height,
        paragraphSpacing: settings.paragraphSpacing,
        titleSpacing: 18,
        textScaler: textScaler,
      ),
      onReady: (readyKey, readyPages) {
        if (_disposed || readyKey != _requestedKey) return;
        _layoutKey = readyKey;
        _requestedKey = '';
        pages = readyPages;
        paginating = false;
        _settlePageRestore();
        notifyListeners();
      },
      immediate: pages.isEmpty,
    );
  }

  /// 翻页模式：按 pending locator / 比例 / atEnd 还原页码。
  /// 滚动模式由页面消费 [takeScrollRestore]。
  void _settlePageRestore() {
    if (settings.pageMode != NovelPageMode.page) return;
    if (pages.isEmpty) return;
    final restore = _pendingRestore;
    final locator = restore?.locator ?? _pendingLocator;
    int index = -1;
    if (locator != null && locator.chapterIndex == (chapter?.index ?? -1)) {
      index = pageIndexForLocator(pages, locator);
    }
    if (index < 0 && restore != null && restore.pageCount > 1) {
      index =
          ((restore.page - 1) / (restore.pageCount - 1) * (pages.length - 1))
              .round();
    }
    if (index < 0 && _pendingPageRatioForRestore != null) {
      index = (_pendingPageRatioForRestore! * (pages.length - 1)).round();
    }
    if (index < 0 && _pendingStartAtEnd) {
      index = pages.length - 1;
    }
    if (index >= 0) {
      pageIndex = index.clamp(0, pages.length - 1);
      _pendingRestore = null;
      _pendingStartAtEnd = false;
      _pendingLocator = null;
      _pendingPageRatioForRestore = null;
    } else if (pageIndex >= pages.length) {
      pageIndex = pages.length - 1;
    }
  }

  void applySettings(NovelReaderSettings next) {
    final previous = settings;
    final ratio = currentPageRatio();
    final locator = currentLocator();
    final modeChanged = next.pageMode != previous.pageMode;
    final layoutChanged =
        next.fontSize != previous.fontSize ||
        next.lineHeight != previous.lineHeight ||
        next.paragraphSpacing != previous.paragraphSpacing ||
        next.horizontalPadding != previous.horizontalPadding ||
        next.fontFamily != previous.fontFamily;

    settings = next;
    if (layoutChanged || modeChanged) {
      _pendingPageRatioForRestore = ratio;
      _pendingLocator = locator;
      _layoutKey = '';
      _requestedKey = '';
      if (next.pageMode == NovelPageMode.scroll) {
        pages = const <NovelTextPage>[];
        paginating = false;
        _pendingScrollRatio = ratio;
      }
    }
    _scheduleSettingsSave();
    notifyListeners();
  }

  double? _pendingPageRatioForRestore;

  double get pendingPageRatio => _pendingPageRatioForRestore ?? 0;

  void _scheduleSettingsSave() {
    _settingsTimer?.cancel();
    _settingsTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(settingsStore.save(settings)),
    );
  }

  void setPageIndex(int value, {int? direction}) {
    if (pages.isEmpty) return;
    final clamped = value.clamp(0, pages.length - 1);
    if (clamped == pageIndex) return;
    pageDirection = direction ?? (clamped > pageIndex ? 1 : -1);
    pageIndex = clamped;
    _scheduleSavePosition();
    notifyListeners();
  }

  void seekPage(int page) {
    if (pages.isEmpty) return;
    setPageIndex(page - 1);
  }

  int currentPage([int? pageCount]) {
    final count = pageCount ?? pages.length;
    if (count <= 1) return 1;
    if (settings.pageMode == NovelPageMode.page) {
      return pageIndex.clamp(0, count - 1) + 1;
    }
    return (scrollRatio * count).floor().clamp(0, count - 1) + 1;
  }

  double currentPageRatio() {
    if (settings.pageMode == NovelPageMode.page) {
      final count = pages.length;
      return count <= 1 ? 0 : pageIndex / (count - 1);
    }
    return scrollRatio;
  }

  /// 当前屏第一段的绝对位置；滚动模式用页面回写的可见段。
  NovelLocator currentLocator() {
    final current = chapter;
    if (current == null) {
      return NovelLocator(chapterIndex: 0, sourceKey: _sourceKeyNow);
    }
    if (settings.pageMode == NovelPageMode.page && pages.isNotEmpty) {
      return locatorForPage(
        pages,
        pageIndex,
        chapterIndex: current.index,
        sourceKey: _sourceKeyNow,
      );
    }
    return NovelLocator(
      chapterIndex: current.index,
      paragraph: _scrollParagraph.clamp(0, 1 << 30),
      sourceKey: _sourceKeyNow,
    );
  }

  void onScroll(double ratio, {int? visibleParagraph}) {
    scrollRatio = ratio.clamp(0.0, 1.0);
    if (visibleParagraph != null) _scrollParagraph = visibleParagraph;
    _scheduleSavePosition();
  }

  NovelReaderPosition? currentSavedPosition() {
    final current = chapter;
    if (current == null) return null;
    final count = pages.isEmpty ? 1 : pages.length;
    return NovelReaderPosition(
      chapterUrl: current.url,
      chapterId: current.id,
      chapterIndex: current.index,
      page: currentPage(count),
      pageCount: count,
      scrollRatio: scrollRatio,
      locator: currentLocator(),
    );
  }

  Future<void> savePositionNow() async {
    final position = currentSavedPosition();
    if (position == null || _disposed) return;
    savedPosition = position;
    try {
      await positionStore.save(bookId, position, sourceKey: _sourceKeyNow);
    } on Object {
      // 写失败不影响本次阅读。
    }
  }

  void _scheduleSavePosition() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(savePositionNow()),
    );
  }

  /// 滚动模式消费一次性恢复请求（打开章节 / 跳到搜索命中 / 换回滚动）。
  NovelScrollRestore? takeScrollRestore() {
    if (settings.pageMode != NovelPageMode.scroll) return null;
    final restore = _pendingRestore;
    final atEnd = _pendingStartAtEnd;
    final ratio = _pendingScrollRatio;
    _pendingRestore = null;
    _pendingStartAtEnd = false;
    _pendingScrollRatio = null;
    _pendingLocator = null;
    if (restore == null && !atEnd && ratio == null) return null;
    if (restore != null || atEnd) {
      return NovelScrollRestore(restore, atEnd: atEnd);
    }
    return NovelScrollRestore(
      NovelReaderPosition(
        chapterUrl: chapter?.url ?? '',
        chapterId: chapter?.id ?? '',
        chapterIndex: chapter?.index ?? 0,
        scrollRatio: ratio ?? 0,
      ),
    );
  }

  /// 跳到指定绝对位置；跨章时先开章，落位由 pending restore 完成。
  Future<void> jumpToLocator(NovelLocator locator) async {
    final currentDetail = detail;
    if (currentDetail == null ||
        locator.chapterIndex < 0 ||
        locator.chapterIndex >= currentDetail.chapters.length) {
      return;
    }
    final target = currentDetail.chapters[locator.chapterIndex];
    if (target.isVolume) return;
    if (chapter?.index != locator.chapterIndex) {
      _pendingJumpLocator = locator;
      await openChapter(target);
      return;
    }
    _pendingRestore = NovelReaderPosition(
      chapterUrl: target.url,
      chapterId: target.id,
      chapterIndex: target.index,
      page: 1,
      pageCount: 1,
      locator: locator,
    );
    if (settings.pageMode == NovelPageMode.page) {
      _settlePageRestore();
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  double bookPercent({int? page, int? pageCount}) {
    final currentDetail = detail;
    final current = chapter;
    final chaptersCount = currentDetail?.chapters.length ?? 0;
    if (chaptersCount <= 0 || current == null) return 0;
    final fraction = settings.pageMode == NovelPageMode.page
        ? (page != null && pageCount != null && pageCount > 0
              ? page / pageCount
              : 0.0)
        : scrollRatio;
    final value = (current.index + fraction) / chaptersCount * 100;
    final atLastPage =
        current.index >= chaptersCount - 1 &&
        (settings.pageMode != NovelPageMode.page ||
            (page ?? 0) >= (pageCount ?? 1));
    final clamped = value.clamp(0.0, 100.0);
    if (clamped >= 100 && !atLastPage) return 99.9;
    return clamped;
  }

  Future<void> switchSource(
    NovelBookSource nextSource,
    NovelSummary book,
  ) async {
    final engine = onlineEngine;
    if (engine == null) return;
    final oldChapter = chapter;
    await savePositionNow();
    loadingDetail = true;
    loadError = null;
    notifyListeners();
    try {
      final ref = NovelRef(
        id: book.id,
        sourceKey: nextSource.key,
        bookUrl: book.bookUrl.isEmpty ? book.id : book.bookUrl,
      );
      final loaded = await engine.bookDetail(
        nextSource,
        ref,
        titleHint: book.title,
        authorHint: book.author,
      );
      if (_disposed) return;
      if (loaded.chapters.isEmpty) {
        throw StateError('新书源目录为空');
      }
      final targetIndex = _matchChapterIndex(loaded.chapters, oldChapter);
      final target = loaded.chapters[targetIndex];
      // 保持同一本书的 history 行（bookId），只更新源信息。
      historyOverride = NovelSummary(
        id: bookId,
        title: loaded.title,
        coverUrl: loaded.coverUrl,
        author: loaded.author,
        sourceKey: nextSource.key,
        bookUrl: ref.bookUrl,
        intro: loaded.intro,
        kind: loaded.kind,
        latestChapter: loaded.latestChapter,
        wordCount: loaded.wordCount,
      );
      source = nextSource;
      detail = loaded;
      chapter = null;
      content = null;
      pendingChapter = null;
      pages = const <NovelTextPage>[];
      loadingDetail = false;
      notifyListeners();
      await openChapter(target);
    } on Object catch (error) {
      if (_disposed) return;
      loadingDetail = false;
      loadError = '$error';
      notifyListeners();
      rethrow;
    }
  }

  int _matchChapterIndex(
    List<NovelChapter> chapters,
    NovelChapter? oldChapter,
  ) {
    if (chapters.isEmpty) return 0;
    if (oldChapter == null) return 0;
    final target = _normalizeTitle(oldChapter.title);
    if (target.isNotEmpty) {
      for (var i = 0; i < chapters.length; i++) {
        if (!chapters[i].isVolume &&
            _normalizeTitle(chapters[i].title) == target) {
          return i;
        }
      }
    }
    final start = oldChapter.index.clamp(0, chapters.length - 1);
    if (!chapters[start].isVolume) return start;
    for (var offset = 1; offset < chapters.length; offset++) {
      final forward = start + offset;
      if (forward < chapters.length && !chapters[forward].isVolume) {
        return forward;
      }
      final backward = start - offset;
      if (backward >= 0 && !chapters[backward].isVolume) return backward;
    }
    return start;
  }

  String _normalizeTitle(String value) => value
      .replaceAll(RegExp(r'[\s《》「」『』（）()\[\]【】\-—_·,，。.!！?？:：;；]'), '')
      .toLowerCase();

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _settingsTimer?.cancel();
    layoutService.cancel();
    chapterCache.clear();
    super.dispose();
  }
}
