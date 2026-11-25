// 阅读器控制器：把「书 / 章 / 正文 / 排版 / 位置 / 预取」从页面 State 里拆出来。
//
// 页面只负责画和交互；状态变更都走这里，便于单测和后续接 legado 的
// 阅读菜单/点击区/书签。行为对照：
// - 章级进度仍写 novel_history（chapterIndex 1 起）；
// - 章内位置写模块 kv，新增字符偏移 locator；
// - 正文缓存分两层：引擎的落盘 NovelCache（跨会话）+ 本控制器的相邻章 LRU
//   （会话内，换章不白屏）。

import 'dart:async';
import 'dart:io' show Directory;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mimao/core/theme.dart' show MimaoFonts;
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';
import 'package:mimao/novel/reader/novel_chapter_cache.dart';
import 'package:mimao/novel/reader/novel_content_override_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rule_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rules.dart';
import 'package:mimao/novel/reader/novel_layout_service.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_reader_position.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_chinese_convert.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';
import 'package:mimao/novel/reader/novel_tts.dart';
import 'package:mimao/novel/reader/novel_tts_cache.dart';
import 'package:mimao/novel/reader/novel_tts_export.dart';
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
    this.highlightRules,
    this.contentOverrides,
    this.bookmarks,
    this.initialLocator,
    this.ttsEngine,
    this.ttsCache,
    NovelReaderSettingsStore? settingsStore,
    NovelLayoutService? layoutService,
    NovelChapterCache? chapterCache,
  }) : settingsStore = settingsStore ?? PrefsNovelReaderSettingsStore(prefs),
       bookStore = NovelBookSettingsStore(prefs),
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

  /// 高亮规则仓库；null 时正文不做高亮（测试/无数据层场景）。
  final NovelHighlightRuleStorage? highlightRules;

  /// 单章本地覆盖仓库；null 时「正文编辑」不可用。
  final NovelContentOverrideStorage? contentOverrides;

  /// 书签/划线门面；null 时阅读器不给入口（测试或无数据层场景）。
  final NovelBookmarkApi? bookmarks;

  /// 从书签列表打开时指定的落点（优先于续读位置）。
  final NovelLocator? initialLocator;

  /// 朗读后端注入缝；null 时按平台创建（测试不注入即不朗读）。
  final NovelTtsEngine? ttsEngine;

  /// 朗读音频缓存（L2）；null = 只读不缓存（测试/无数据层）。
  final NovelTtsCache? ttsCache;

  final NovelReaderSettingsStore settingsStore;
  final NovelBookSettingsStore bookStore;
  final NovelLayoutService layoutService;
  final NovelChapterCache chapterCache;
  late final NovelReaderPositionStore positionStore = NovelReaderPositionStore(
    prefs,
  );

  /// 全局设置（跨书共用，落 [NovelReaderSettingsStore]）。
  NovelReaderSettings globalSettings = const NovelReaderSettings();

  /// 本书的差异覆盖（只含与全局不同的字段，落 [NovelBookSettingsStore]）。
  Map<String, Object?> bookOverride = const <String, Object?>{};

  /// 当前生效的设置 = 每书覆盖叠加在全局之上（每书 > 全局 > 默认）。
  NovelReaderSettings settings = const NovelReaderSettings();
  bool settingsReady = false;

  NovelBookSource? source;
  NovelDetail? detail;
  NovelChapter? chapter;
  NovelContent? content;

  /// 净化前的原始正文（正文编辑/替换预览用）：编辑器拿它当样例，
  /// 免得把已替换过的文本再套一次规则（预览出现 `【【艾琳娜】】`）。
  NovelContent? rawContent;

  /// 正在切换、但还没拿到正文的下一章；非空时正文区仍显示上一章。
  NovelChapter? pendingChapter;

  String? loadError;
  bool loadingDetail = true;
  bool loadingContent = false;
  bool paginating = false;

  List<NovelTextPage> pages = const <NovelTextPage>[];
  int pageIndex = 0;
  int pageDirection = 1;

  /// 最近一次排版用的列数（1/2）；页面据此决定是否并排两列。
  int layoutColumns = 1;

  /// 正文换过一次就 +1；页面据此重置滚动位置。
  int contentEpoch = 0;

  NovelReaderPosition? savedPosition;
  double scrollRatio = 0;

  NovelSummary? historyOverride;
  List<NovelReplaceRule> replaceRules_ = const <NovelReplaceRule>[];
  List<NovelHighlightRule> highlightRules_ = const <NovelHighlightRule>[];

  /// 当前章用的是本地覆盖（正文编辑过）；页面据此显示「本地覆盖」提示。
  bool chapterIsLocalOverride = false;

  /// 高亮/内容覆盖仓库是否已就绪（菜单动作可用性用）。
  bool get highlightRulesReady => highlightRules != null;
  bool get contentOverrideReady => contentOverrides != null;

  /// 当前书源最近一次非致命警告（引擎实现 [NovelEngineWarnings] 时才有）。
  String? get sourceWarning {
    final engine = onlineEngine;
    if (engine is NovelEngineWarnings) {
      return (engine as NovelEngineWarnings).warningFor(_sourceKeyNow);
    }
    return null;
  }

  /// 当前章的书签与划线（渲染层直接读，切章后重载）。
  List<NovelBookmark> chapterBookmarks = const <NovelBookmark>[];
  List<NovelMarking> chapterMarkings = const <NovelMarking>[];

  /// 全书有书签的章下标（目录角标）。
  Set<int> bookmarkedChapters = const <int>{};

  /// 最近一次选用的划线样式（同一次阅读里连划复用，不每次重选）。
  NovelMarkingStyle lastMarkingStyle = NovelMarkingStyle.yellow;

  /// 最近一次换源重定位结果；阅读页可据此提示「N 条无法定位」。
  NovelRelocateResult? lastRelocateResult;

  NovelReaderPosition? _pendingRestore;
  bool _pendingStartAtEnd = false;
  double? _pendingScrollRatio;
  NovelLocator? _pendingJumpLocator;
  NovelLocator? _pendingLocator;
  int _scrollParagraph = 0;

  String _layoutKey = '';
  String _requestedKey = '';

  Future<void> _replaceRulesReady = Future<void>.value();
  Future<void> _highlightRulesReady = Future<void>.value();
  Timer? _settingsTimer;
  Timer? _saveTimer;
  bool _disposed = false;
  int _loadSeq = 0;

  // ── 朗读运行时状态（不落库：睡眠定时/暂停是本次会话的事） ─────────────
  NovelTtsPlayer? _ttsPlayer;
  NovelTtsEngine? _ownedTtsEngine;
  NovelTtsEngine? _cachedTtsEngine;
  bool _ttsEngineReady = false;

  /// 控制器自己发起的续章加载；页面据此区分「朗读换章」与「用户换章」。
  bool _ttsAdvancingChapter = false;
  Timer? _ttsSleepTimer;

  /// 睡眠定时到点时间；null = 未设。UI 据此倒计时。
  DateTime? ttsSleepDeadline;

  /// 朗读出错（后端故障）时通知页面；页面只提示，不吞掉错误。
  void Function(Object error)? onTtsError;

  /// 睡眠定时到点：控制器已停读，页面负责提示。
  void Function()? onTtsSleepTimerFired;

  bool get ttsAdvancingChapter => _ttsAdvancingChapter;

  NovelTtsPlaybackState get ttsState =>
      _ttsPlayer?.state ?? NovelTtsPlaybackState.idle;

  bool get ttsActive => ttsState != NovelTtsPlaybackState.idle;

  bool get ttsSpeaking => ttsState == NovelTtsPlaybackState.speaking;

  bool get ttsPaused => ttsState == NovelTtsPlaybackState.paused;

  int get ttsParagraph => _ttsPlayer?.paragraph ?? 0;

  bool get disposed => _disposed;

  String get _sourceKeyNow =>
      detail?.ref.sourceKey ?? source?.key ?? sourceKey ?? '';

  String get bookTitleNow => detail?.title ?? title ?? '';

  String get bookAuthorNow => detail?.author ?? author ?? '';

  String get bookUrlNow => detail?.ref.bookUrl ?? bookUrl ?? '';

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
    // 书签列表带进来的落点先排上：bootstrap 选章/应用正文时都会用到。
    if (initialLocator != null) _pendingJumpLocator = initialLocator;
    final loaded = await settingsStore.load();
    final override = await bookStore.load(bookId);
    final position = await positionStore.load(
      bookId,
      sourceKey: sourceKey ?? '',
    );
    if (_disposed) return;
    globalSettings = loaded;
    bookOverride = override;
    settings = mergeNovelBookOverride(loaded, override);
    savedPosition = position;
    settingsReady = true;
    _replaceRulesReady = _loadReplaceRules();
    _highlightRulesReady = _loadHighlightRules();
    notifyListeners();
    await bootstrap();
  }

  Future<void> _loadHighlightRules() async {
    final store = highlightRules;
    if (store == null) return;
    try {
      final rules = await store.loadAll();
      if (_disposed) return;
      highlightRules_ = rules;
      notifyListeners();
    } on Object {
      // 高亮规则读坏了不该让正文打不开；正文照常显示，只是没高亮。
    }
  }

  /// 当前书生效的高亮规则（全局 + 本书）。
  List<NovelHighlightRule> get highlightRulesForBook => <NovelHighlightRule>[
    for (final rule in highlightRules_)
      if (rule.enabled && rule.appliesToBook(bookId)) rule,
  ];

  /// 重新读一遍高亮规则（高亮管理页保存后调用）。
  Future<void> reloadHighlightRules() async {
    _highlightRulesReady = _loadHighlightRules();
    await _highlightRulesReady;
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

  /// 重新读一遍替换规则（编辑页保存后调用），并让当前章按新规则重算。
  Future<void> reloadReplaceRules() async {
    _replaceRulesReady = _loadReplaceRules();
    await _replaceRulesReady;
    final target = chapter;
    if (target != null) await openChapter(target);
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
      loadError = key.isEmpty
          ? '这本书没有关联书源，无法加载正文。返回书架从书源重新添加。'
          : '书源引擎未启用，无法加载正文。重启应用后再试。';
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
      unawaited(_relocateBookmarks());
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
      unawaited(_relocateBookmarks());
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
    // 从书签列表进来：优先打开书签所在的章，而不是第一章/上次进度。
    final locatorIndex = _pendingJumpLocator?.chapterIndex;
    if (locatorIndex != null &&
        locatorIndex >= 0 &&
        locatorIndex < chapters.length &&
        !chapters[locatorIndex].isVolume) {
      return chapters[locatorIndex];
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
      await _highlightRulesReady;
      if (_disposed || seq != _loadSeq) return;
      // 本地覆盖优先于网络/缓存正文：正文编辑保存后再次打开就用这一版。
      // 覆盖是「用户亲手改过的最终文本」，不再叠加替换规则（否则
      // 像 `(\d+)章 → 第$1章` 这种规则会对改过的正文再套一层）。
      NovelContent? local;
      final overrides = contentOverrides;
      if (overrides != null) {
        try {
          local = await overrides.load(
            bookId: bookId,
            sourceKey: _sourceKeyNow,
            chapterKey: novelChapterOverrideKey(target),
          );
        } on Object {
          // 覆盖读坏了退回原正文，不让整章打不开。
        }
      }
      if (_disposed || seq != _loadSeq) return;
      rawContent = local ?? raw;
      final cleaned = local ?? applyContentReplaceRules(raw);
      chapterIsLocalOverride = local != null;
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
    var jump = _pendingJumpLocator;
    if (jump != null) {
      // 书签/搜索命中的段落可能因为版本差异越界：落到末尾段，偏移清零，
      // 不因为一个旧锚点把整次跳转丢掉。
      final lastParagraph = next.paragraphs.isEmpty
          ? 0
          : next.paragraphs.length - 1;
      if (jump.paragraph > lastParagraph) {
        jump = jump.copyWith(paragraph: lastParagraph, charOffset: 0);
      } else if (jump.paragraph >= 0) {
        final length = next.paragraphs[jump.paragraph].length;
        if (jump.charOffset > length) {
          jump = jump.copyWith(charOffset: length);
        }
      }
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
    unawaited(_reloadBookmarkState());
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

  /// 保存当前章的本地覆盖并立即重新展示；返回是否保存成功。
  ///
  /// [paragraphs] 是编辑后的最终段落（不含段首缩进）；空正文拒绝保存，
  /// 避免一次误删把整章变成空白。
  // ── 朗读 ────────────────────────────────────────────────────────────────

  /// 创建/复用后端。测试环境且未注入时返回 null（页面提示不支持）。
  Future<NovelTtsEngine?> ensureTtsEngine() async {
    final injected = ttsEngine;
    if (injected != null) {
      if (!_ttsEngineReady) {
        try {
          await injected.configure();
        } on Object {
          return null;
        }
        _ttsEngineReady = true;
      }
      return _withCache(injected);
    }
    final owned = _ownedTtsEngine;
    if (owned != null) return _withCache(owned);
    final created = createNovelTtsEngine();
    if (created == null) return null;
    try {
      await created.configure();
    } on Object {
      return null;
    }
    _ownedTtsEngine = created;
    return _withCache(created);
  }

  /// 系统可用音色；引擎不可用时返回空表（UI 回落到「自动」）。
  Future<List<NovelTtsVoice>> availableTtsVoices() async {
    final engine = await ensureTtsEngine();
    if (engine == null) return const <NovelTtsVoice>[];
    return engine.voices();
  }

  /// 缓存统计（设置面板展示）；没有缓存服务返回 null。
  Future<NovelTtsCacheStats?> ttsCacheStats() async => await ttsCache?.stats();

  /// 清空朗读缓存；返回删掉的段数。
  Future<int> clearTtsCache() async => await ttsCache?.clear() ?? 0;

  /// 有缓存服务且后端能「合成到文件 + 播文件」时套缓存装饰器。
  NovelTtsEngine _withCache(NovelTtsEngine engine) {
    final cache = ttsCache;
    if (cache == null ||
        !engine.supportsFileOutput ||
        !engine.supportsFilePlayback) {
      return engine;
    }
    return _cachedTtsEngine ??= CachedNovelTtsEngine(
      inner: engine,
      cache: cache,
    );
  }

  /// 开始朗读；[fromParagraph] 缺省从本章第一段。返回 false = 当前平台无后端。
  Future<bool> startTts({int? fromParagraph}) async {
    if (ttsActive) return true;
    final current = content;
    if (current == null || current.paragraphs.isEmpty) return false;
    final engine = await ensureTtsEngine();
    if (engine == null || _disposed) return false;
    final player = NovelTtsPlayer(
      engine: engine,
      runtime: () => NovelTtsRuntime(
        rate: settings.ttsRate,
        voice: settings.ttsVoice,
        paragraphPauseMs: settings.ttsParagraphPauseMs,
        autoNextChapter: settings.ttsAutoNextChapter,
      ),
      loadNextChapter: _loadNextChapterForTts,
      cacheKey: ttsCache == null
          ? null
          : (paragraph) => novelTtsCacheKey(
              bookId: bookId,
              chapterKey: (chapter?.id.isNotEmpty ?? false)
                  ? chapter!.id
                  : (chapter?.url ?? ''),
              paragraph: paragraph,
              voice: settings.ttsVoice,
              rate: settings.ttsRate,
            ),
      onParagraphChanged: (_) {
        if (!_disposed) notifyListeners();
      },
      onStateChanged: (state) {
        if (state == NovelTtsPlaybackState.idle) _cancelTtsSleepTimer();
        if (!_disposed) notifyListeners();
      },
      onError: (error) {
        onTtsError?.call(error);
        if (!_disposed) notifyListeners();
      },
    );
    _ttsPlayer = player;
    notifyListeners();
    await player.start(_ttsParagraphs(), from: fromParagraph ?? 0);
    return true;
  }

  /// 朗读中 → 暂停；暂停中 → 继续；没开 → 从头开始。
  Future<void> toggleTts() async {
    switch (ttsState) {
      case NovelTtsPlaybackState.idle:
        await startTts();
      case NovelTtsPlaybackState.speaking:
        pauseTts();
      case NovelTtsPlaybackState.paused:
        resumeTts();
    }
  }

  void pauseTts() {
    final player = _ttsPlayer;
    if (player == null || !player.isSpeaking) return;
    player.pause();
    notifyListeners();
  }

  void resumeTts() {
    final player = _ttsPlayer;
    if (player == null || player.state != NovelTtsPlaybackState.paused) {
      return;
    }
    player.resume();
    notifyListeners();
  }

  /// 停止朗读并清理睡眠定时。
  Future<void> stopTts() async {
    final player = _ttsPlayer;
    _ttsPlayer = null;
    _cancelTtsSleepTimer();
    await player?.stop();
    if (!_disposed) notifyListeners();
  }

  /// 手动翻页「跟随」：把朗读位置挪到指定段。
  void seekTtsToParagraph(int paragraph) {
    final player = _ttsPlayer;
    if (player == null || !player.isActive) return;
    player.seek(paragraph);
  }

  /// 设置/清除睡眠定时；null 或非正数 = 关闭。
  void setTtsSleepTimer(Duration? duration) {
    _ttsSleepTimer?.cancel();
    _ttsSleepTimer = null;
    if (duration == null || duration <= Duration.zero) {
      ttsSleepDeadline = null;
      notifyListeners();
      return;
    }
    final deadline = DateTime.now().add(duration);
    ttsSleepDeadline = deadline;
    _ttsSleepTimer = Timer(duration, () {
      if (_disposed) return;
      _ttsSleepTimer = null;
      ttsSleepDeadline = null;
      final player = _ttsPlayer;
      _ttsPlayer = null;
      unawaited(player?.stop());
      onTtsSleepTimerFired?.call();
      notifyListeners();
    });
    notifyListeners();
  }

  void _cancelTtsSleepTimer() {
    _ttsSleepTimer?.cancel();
    _ttsSleepTimer = null;
    ttsSleepDeadline = null;
  }

  /// 章末续章：读下一章并返回它的段落。null = 没有下一章或加载失败。
  Future<List<String>?> _loadNextChapterForTts() async {
    if (!settings.ttsAutoNextChapter) return null;
    final next = neighborChapter(1);
    if (next == null) return null;
    _ttsAdvancingChapter = true;
    try {
      await openChapter(next);
    } finally {
      _ttsAdvancingChapter = false;
    }
    if (_disposed || loadError != null) return null;
    final current = content;
    if (current == null || current.paragraphs.isEmpty) return null;
    return _ttsParagraphs();
  }

  /// 当前章的朗读文本（简繁转换后，不含段首缩进——缩进是排版，不该念出来）。
  List<String> _ttsParagraphs() {
    final current = content;
    if (current == null) return const <String>[];
    return <String>[
      for (final paragraph in current.paragraphs) _convert(paragraph),
    ];
  }

  /// 导出朗读音频（L2）：[wholeBook] 为 true 时逐章拉正文，否则只导当前章。
  ///
  /// 合成走独立临时目录，成功拼成 wav 后删除临时文件；取消/失败时连同
  /// 半成品目标文件一起清掉。返回已写入的段数与字节数。
  Future<NovelTtsExportResult> exportTtsAudio({
    required String outputPath,
    required bool wholeBook,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (ttsActive) await stopTts();
    final engine = await ensureTtsEngine();
    if (engine == null) {
      throw StateError('当前平台不支持导出朗读音频');
    }
    if (!engine.supportsFileOutput) {
      throw StateError('当前语音后端不支持合成到文件');
    }
    final work = await Directory.systemTemp.createTemp('mimao_tts_export_');
    try {
      final total = wholeBook
          ? (detail?.chapters.where((chapter) => !chapter.isVolume).length ?? 1)
          : 1;
      return await NovelTtsExporter(engine: engine, workDirectory: work).export(
        outputPath: outputPath,
        chapters: wholeBook
            ? _exportWholeBookStream()
            : _exportCurrentChapterStream(),
        rate: settings.ttsRate,
        voice: settings.ttsVoice,
        totalChapters: total,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      try {
        await work.delete(recursive: true);
      } on Object {
        // 临时目录清不掉不阻塞导出结果。
      }
    }
  }

  Stream<List<String>> _exportCurrentChapterStream() async* {
    final paragraphs = _ttsParagraphs();
    if (paragraphs.isEmpty) return;
    final target = chapter;
    final title = target == null ? '' : _convert(target.title);
    yield <String>[if (title.trim().isNotEmpty) title, ...paragraphs];
  }

  Stream<List<String>> _exportWholeBookStream() async* {
    final currentDetail = detail;
    final engine = onlineEngine;
    final currentSource = source;
    if (currentDetail == null || engine == null || currentSource == null) {
      throw StateError('这本书没有可导出的在线目录');
    }
    for (final target in currentDetail.chapters) {
      if (target.isVolume) continue;
      NovelContent raw;
      try {
        raw = await chapterCache.load(
          engine: engine,
          source: currentSource,
          ref: currentDetail.ref,
          chapter: target,
        );
      } on Object catch (error) {
        throw StateError('第 ${target.index + 1} 章加载失败：$error');
      }
      final cleaned = applyContentReplaceRules(raw);
      final title = _convert(target.title);
      final paragraphs = <String>[
        if (title.trim().isNotEmpty) title,
        for (final paragraph in cleaned.paragraphs) _convert(paragraph),
      ].where((paragraph) => paragraph.trim().isNotEmpty).toList();
      if (paragraphs.isNotEmpty) yield paragraphs;
    }
  }

  /// 段落落在哪一页（翻页模式）；未排版或找不到返回 null。
  int? pageIndexForParagraph(int paragraph) {
    for (var i = 0; i < pages.length; i++) {
      for (final slice in pages[i].slices) {
        if (!slice.isTitle && slice.paragraph == paragraph) return i;
      }
    }
    return null;
  }

  /// 翻页模式跟随朗读：把 pageIndex 对齐到目标段所在页。返回是否翻页。
  bool syncPageToParagraph(int paragraph) {
    final index = pageIndexForParagraph(paragraph);
    if (index == null || index == pageIndex) return false;
    setPageIndex(index);
    return true;
  }

  Future<bool> saveChapterOverride(
    List<String> paragraphs, {
    String? title,
  }) async {
    final storage = contentOverrides;
    final target = chapter;
    if (storage == null || target == null) return false;
    final cleaned = <String>[
      for (final paragraph in paragraphs)
        if (paragraph.trim().isNotEmpty) paragraph,
    ];
    if (cleaned.isEmpty) return false;
    try {
      await storage.save(
        bookId: bookId,
        sourceKey: _sourceKeyNow,
        chapterKey: novelChapterOverrideKey(target),
        chapterTitle: target.title,
        title: title ?? content?.title ?? '',
        paragraphs: cleaned,
      );
    } on Object {
      return false;
    }
    await openChapter(target);
    return true;
  }

  /// 删除当前章的本地覆盖并恢复网络/缓存正文。
  Future<bool> restoreChapterOverride() async {
    final storage = contentOverrides;
    final target = chapter;
    if (storage == null || target == null) return false;
    try {
      await storage.remove(
        bookId: bookId,
        sourceKey: _sourceKeyNow,
        chapterKey: novelChapterOverrideKey(target),
      );
    } on Object {
      return false;
    }
    chapterIsLocalOverride = false;
    await openChapter(target);
    return true;
  }

  /// 当前章是否存在本地覆盖（编辑页显示「恢复原样」用）。
  Future<bool> hasChapterOverride() async {
    final storage = contentOverrides;
    final target = chapter;
    if (storage == null || target == null) return false;
    try {
      return await storage.has(
        bookId: bookId,
        sourceKey: _sourceKeyNow,
        chapterKey: novelChapterOverrideKey(target),
      );
    } on Object {
      return false;
    }
  }

  /// 读覆盖状态；仓库读失败返回 null，页面据此显示「错误 + 重试」。
  ///
  /// 与 [hasChapterOverride] 分开：后者把读失败当「没有覆盖」，会静默藏掉
  /// 本地库故障；正文编辑页需要把失败显式告诉用户。
  Future<bool?> readChapterOverrideState() async {
    final storage = contentOverrides;
    final target = chapter;
    if (storage == null || target == null) return null;
    try {
      return await storage.has(
        bookId: bookId,
        sourceKey: _sourceKeyNow,
        chapterKey: novelChapterOverrideKey(target),
      );
    } on Object {
      return null;
    }
  }

  /// 正文样式：字体、字距、加粗/斜体、阴影。
  ///
  /// 下划线不在这里：`TextStyle.decoration` 只能贴着字形画、也拿不到行边界，
  /// 画不出「延伸到整行宽度」和可调间距。下划线由渲染层的
  /// `NovelUnderlinedText` 按 `computeLineMetrics()` 逐行绘制，分页测量与渲染
  /// 都用这个不含 decoration 的样式，两边行高一致。
  TextStyle bodyStyle() {
    final family = settings.fontFamily.isEmpty
        ? MimaoFonts.family
        : settings.fontFamily;
    return TextStyle(
      fontFamily: family,
      fontWeight: settings.textBold ? MimaoFonts.bold : MimaoFonts.regular,
      fontStyle: settings.textItalic ? FontStyle.italic : FontStyle.normal,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      letterSpacing: settings.letterSpacing,
      color: Color(settings.textColorArgb),
      decoration: TextDecoration.none,
      shadows: _textShadows(),
    );
  }

  List<Shadow>? _textShadows() {
    if (settings.shadowRadius <= 0) return null;
    final color = settings.shadowColorArgb;
    return <Shadow>[
      Shadow(
        offset: Offset(settings.shadowOffsetX, settings.shadowOffsetY),
        blurRadius: settings.shadowRadius,
        color: color != null
            ? Color(color)
            : Color(settings.textColorArgb).withValues(alpha: 0.45),
      ),
    ];
  }

  /// 正文是否启用下划线（渲染层据此换用 `NovelUnderlinedText`）。
  bool get hasUnderline => settings.underlineStyle != NovelUnderlineStyle.none;

  TextStyle titleStyle() => bodyStyle().copyWith(
    fontSize: settings.effectiveTitleFontSize.clamp(
      NovelReaderSettings.minFontSize,
      NovelReaderSettings.maxFontSize + 20,
    ),
    fontWeight: MimaoFonts.bold,
    fontStyle: FontStyle.normal,
    height: 1.4,
    decoration: TextDecoration.none,
    decorationStyle: null,
    decorationThickness: null,
    letterSpacing: settings.letterSpacing / 2,
  );

  /// 行距是否含行内留白：false 时只拉开行与行之间，不往首末行上下加高。
  TextHeightBehavior get textHeightBehavior => TextHeightBehavior(
    applyHeightToFirstAscent: settings.lineHeightIncludesPadding,
    applyHeightToLastDescent: settings.lineHeightIncludesPadding,
  );

  TextAlign get bodyTextAlign =>
      settings.textAlignJustify ? TextAlign.justify : TextAlign.start;

  TextAlign get titleTextAlign => settings.titleMode == NovelTitleMode.center
      ? TextAlign.center
      : TextAlign.start;

  /// 正文段落（含缩进与简繁转换）；分页与渲染共用，保证切片偏移一致。
  String paragraphText(int index) {
    final paragraphs = content?.paragraphs ?? const <String>[];
    if (index < 0 || index >= paragraphs.length) return '';
    return '${settings.indent}${_convert(paragraphs[index])}';
  }

  /// 章节标题的展示文本（简繁转换；隐藏模式返回空串）。
  String displayTitle(String raw) {
    if (settings.titleMode == NovelTitleMode.hide) return '';
    return _convert(raw);
  }

  String _convert(String text) =>
      convertNovelChinese(text, settings.chineseConvert);

  /// 页面在 LayoutBuilder 里调用；只登记尺寸，真正排版在帧后。
  void updateLayout({
    required double width,
    required double height,
    required TextScaler textScaler,
    double? viewportWidth,
    bool landscape = true,
  }) {
    final current = content;
    if (current == null) return;
    if (settings.pageMode == NovelPageMode.scroll) {
      layoutColumns = 1;
      if (pages.isNotEmpty || paginating) {
        pages = const <NovelTextPage>[];
        paginating = false;
        _layoutKey = '';
        _requestedKey = '';
      }
      return;
    }
    if (width <= 0 || height <= 0) return;

    // 双栏：窗口 ≥1100 且横向时按两列排版；页面层再把相邻两列并排。
    final columns =
        settings.twoColumn &&
            (viewportWidth ?? (width + settings.horizontalPadding * 2)) >=
                1100 &&
            landscape
        ? 2
        : 1;
    layoutColumns = columns;

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
      settings.textAlignJustify,
      settings.letterSpacing,
      settings.textBold,
      settings.textItalic,
      settings.indentCount,
      settings.lineHeightIncludesPadding,
      settings.titleMode,
      settings.titleSize,
      settings.titleSizeRelative,
      settings.titleTopSpacing,
      settings.titleBottomSpacing,
      settings.chineseConvert,
      columns,
      textScaler.scale(16),
    ].join('|');
    if (key == _layoutKey && pages.isNotEmpty) return;
    if (key == _requestedKey) return;

    _requestedKey = key;
    paginating = true;
    final rawTitle = current.title.isEmpty
        ? (chapter?.title ?? '')
        : current.title;
    final title = displayTitle(rawTitle);
    final paragraphs = <String>[
      for (final paragraph in current.paragraphs) _convert(paragraph),
    ];
    layoutService.schedule(
      NovelLayoutRequest(
        key: key,
        title: title,
        paragraphs: paragraphs,
        bodyStyle: bodyStyle(),
        titleStyle: titleStyle(),
        maxWidth: width,
        maxHeight: height,
        paragraphSpacing: settings.paragraphSpacing,
        titleSpacing: settings.titleBottomSpacing,
        titleTopSpacing: settings.titleTopSpacing,
        indent: settings.indent,
        textScaler: textScaler,
        bodyTextAlign: bodyTextAlign,
        titleTextAlign: titleTextAlign,
        textHeightBehavior: textHeightBehavior,
        kinsoku: true,
        columns: columns,
        columnGap: 32,
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

  /// 应用一次设置修改。
  ///
  /// [scope] 默认 [NovelSettingsScope.global]（与上游一致）：改的是全局设置，
  /// 本书的覆盖字段若与这次改动冲突，按「每书 > 全局」保留每书的值。
  /// [NovelSettingsScope.book] 时只把「与全局不同的字段」写进本书覆盖，
  /// 全局设置一个字都不动——以后改全局，这本书的差异仍然有效。
  void applySettings(
    NovelReaderSettings next, {
    NovelSettingsScope scope = NovelSettingsScope.global,
  }) {
    final previous = settings;
    final ratio = currentPageRatio();
    final locator = currentLocator();
    final modeChanged = next.pageMode != previous.pageMode;
    final layoutChanged =
        next.fontSize != previous.fontSize ||
        next.lineHeight != previous.lineHeight ||
        next.paragraphSpacing != previous.paragraphSpacing ||
        next.horizontalPadding != previous.horizontalPadding ||
        next.fontFamily != previous.fontFamily ||
        next.textAlignJustify != previous.textAlignJustify ||
        next.letterSpacing != previous.letterSpacing ||
        next.textBold != previous.textBold ||
        next.textItalic != previous.textItalic ||
        next.indentCount != previous.indentCount ||
        next.lineHeightIncludesPadding != previous.lineHeightIncludesPadding ||
        next.titleMode != previous.titleMode ||
        next.titleSize != previous.titleSize ||
        next.titleSizeRelative != previous.titleSizeRelative ||
        next.titleTopSpacing != previous.titleTopSpacing ||
        next.titleBottomSpacing != previous.titleBottomSpacing ||
        next.chineseConvert != previous.chineseConvert ||
        next.twoColumn != previous.twoColumn;

    switch (scope) {
      case NovelSettingsScope.global:
        // 只把「这次真正被改动的字段」写进全局：面板展示的是叠加后的
        // 生效值，若整份当新全局，本书的覆盖值会泄漏进全局。
        final delta = diffNovelReaderSettingsAllFields(previous, next);
        globalSettings = applyNovelReaderSettingsJson(globalSettings, delta);
        settings = mergeNovelBookOverride(globalSettings, bookOverride);
      case NovelSettingsScope.book:
        // 每书覆盖只认白名单字段（背景/字体/翻页/动画/点击区）。菜单外观、
        // 按钮配置这类不在白名单的改动**不能静默丢掉**——用户点了开关却
        // 什么都没发生比"改不了"更糟。这里把差异拆两半：白名单进覆盖，
        // 其余落全局（菜单布局本来就是全局概念）。
        final allDiff = diffNovelReaderSettingsAllFields(previous, next);
        final scoped = diffNovelReaderSettings(globalSettings, next);
        bookOverride = scoped;
        final rest = <String, Object?>{
          for (final entry in allDiff.entries)
            if (!novelBookOverrideFields.contains(entry.key))
              entry.key: entry.value,
        };
        if (rest.isNotEmpty) {
          globalSettings = applyNovelReaderSettingsJson(globalSettings, rest);
        }
        settings = mergeNovelBookOverride(globalSettings, bookOverride);
    }

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
    _scheduleSettingsSave(scope);
    notifyListeners();
  }

  /// 清掉本书覆盖，回到纯全局设置。
  void clearBookOverride() {
    if (bookOverride.isEmpty) return;
    final ratio = currentPageRatio();
    final locator = currentLocator();
    bookOverride = const <String, Object?>{};
    final next = globalSettings;
    final modeChanged = next.pageMode != settings.pageMode;
    settings = next;
    if (modeChanged || true) {
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
    _scheduleBookSave();
    notifyListeners();
  }

  bool get hasBookOverride => bookOverride.isNotEmpty;

  double? _pendingPageRatioForRestore;

  double get pendingPageRatio => _pendingPageRatioForRestore ?? 0;

  /// 落盘：全局与每书覆盖各写各的键。
  ///
  /// 不能按 [scope] 决定要不要写全局——「只改这本」下改了菜单外观这类
  /// 非可覆盖字段时，[globalSettings] 也变了（见 applySettings 里的拆分），
  /// 只写覆盖会让那次改动在重启后消失。这里一律两份都写：
  /// 覆盖为空时 bookStore.save 本身就是清空，成本可忽略。
  void _scheduleSettingsSave(NovelSettingsScope scope) {
    _settingsTimer?.cancel();
    _settingsTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(settingsStore.save(globalSettings));
      unawaited(bookStore.save(bookId, bookOverride));
    });
  }

  void _scheduleBookSave() {
    _settingsTimer?.cancel();
    _settingsTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(bookStore.save(bookId, bookOverride)),
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

  // ── 书签 / 划线 ────────────────────────────────────────────────────────
  bool get bookmarksReady => bookmarks != null;

  /// 当前章正文（不含段首缩进）的字符长度；划线区间校验用。
  int paragraphLength(int paragraph) =>
      math.max(0, paragraphText(paragraph).length - settings.indent.length);

  List<NovelMarking> markingsOfParagraph(int paragraph) => <NovelMarking>[
    for (final marking in chapterMarkings)
      if (marking.paragraph == paragraph) marking,
  ];

  /// 本书全部书签（阅读器里的「全书书签」列表用）。
  Future<List<NovelBookmark>> loadBookBookmarks() async {
    final api = bookmarks;
    if (api == null) return const <NovelBookmark>[];
    try {
      return await api.bookmarksForBook(bookId);
    } on Object {
      return const <NovelBookmark>[];
    }
  }

  /// 换源后按章标题 + 段落下标尽力重定位；失败标 unresolved（不删行）。
  Future<void> _relocateBookmarks() async {
    final api = bookmarks;
    final currentDetail = detail;
    if (api == null || currentDetail == null) return;
    try {
      final result = await api.relocateBookmarks(
        bookId,
        currentDetail.chapters,
        sourceKey: _sourceKeyNow,
      );
      await api.relocateMarkings(
        bookId,
        currentDetail.chapters,
        sourceKey: _sourceKeyNow,
      );
      if (_disposed) return;
      lastRelocateResult = result;
      notifyListeners();
      await _reloadBookmarkState();
    } on Object {
      // 重定位失败不该让正文打不开；下次开书再试。
    }
  }

  Future<void> _reloadBookmarkState() async {
    final api = bookmarks;
    final current = chapter;
    if (api == null || current == null) return;
    try {
      final all = await api.bookmarksForBook(bookId);
      final markings = await api.markingsForChapter(
        bookId,
        current.index,
        sourceKey: _sourceKeyNow,
      );
      final chapterSet = await api.bookmarkedChapterIndexes(
        bookId,
        sourceKey: _sourceKeyNow,
      );
      if (_disposed) return;
      final currentKey = _sourceKeyNow;
      chapterBookmarks = <NovelBookmark>[
        for (final bookmark in all)
          if (bookmark.chapterIndex == current.index &&
              (bookmark.sourceKey.isEmpty || bookmark.sourceKey == currentKey))
            bookmark,
      ];
      chapterMarkings = markings;
      bookmarkedChapters = chapterSet;
      notifyListeners();
    } on Object {
      // 读失败保留上一份快照，阅读继续。
    }
  }

  /// 加/删书签（同一位置再点即删）。返回 null 表示书签库没接上或没有正文。
  Future<NovelBookmarkToggleResult?> toggleBookmarkAt({
    int? paragraph,
    int charOffset = 0,
  }) async {
    final api = bookmarks;
    final current = chapter;
    final contentNow = content;
    if (api == null || current == null || contentNow == null) return null;
    final last = contentNow.paragraphs.isEmpty
        ? 0
        : contentNow.paragraphs.length - 1;
    final targetParagraph = (paragraph ?? _scrollParagraph).clamp(0, last);
    final raw = contentNow.paragraphs[targetParagraph];
    final excerpt = raw.trim();
    try {
      final result = await api.toggleBookmark(
        anchor: NovelTextAnchor(
          bookId: bookId,
          sourceKey: _sourceKeyNow,
          chapterIndex: current.index,
          paragraph: targetParagraph,
          charOffset: charOffset,
        ),
        chapterName: current.title,
        bookTitle: bookTitleNow,
        bookAuthor: bookAuthorNow,
        bookUrl: bookUrlNow,
        excerpt: excerpt.length > 80 ? excerpt.substring(0, 80) : excerpt,
      );
      await _reloadBookmarkState();
      return result;
    } on Object {
      return null;
    }
  }

  Future<bool> removeBookmarkItem(NovelBookmark bookmark) async {
    final api = bookmarks;
    if (api == null) return false;
    try {
      final removed = await api.removeBookmark(bookmark.id);
      if (removed) await _reloadBookmarkState();
      return removed;
    } on Object {
      return false;
    }
  }

  /// 跳到一条书签：章下标失效或标了 unresolved 时先按章标题在现目录里找，
  /// 仍找不到返回 false（调用方提示「无法定位，可在书签列表删除」）。
  Future<bool> jumpToBookmark(NovelBookmark bookmark) async {
    final currentDetail = detail;
    if (currentDetail == null) return false;
    var index = bookmark.chapterIndex;
    final invalid =
        bookmark.unresolved ||
        index < 0 ||
        index >= currentDetail.chapters.length ||
        currentDetail.chapters[index].isVolume;
    if (invalid) {
      index = _chapterIndexByTitle(bookmark.chapterName);
    }
    if (index < 0 || index >= currentDetail.chapters.length) return false;
    final target = currentDetail.chapters[index];
    if (target.isVolume) return false;
    await jumpToLocator(
      NovelLocator(
        chapterIndex: index,
        paragraph: bookmark.paragraph,
        charOffset: bookmark.charOffset,
        sourceKey: _sourceKeyNow,
      ),
    );
    return true;
  }

  int _chapterIndexByTitle(String title) {
    final currentDetail = detail;
    if (currentDetail == null) return -1;
    final key = normalizeNovelChapterTitle(title);
    if (key.isEmpty) return -1;
    for (var i = 0; i < currentDetail.chapters.length; i++) {
      final chapter = currentDetail.chapters[i];
      if (chapter.isVolume) continue;
      if (normalizeNovelChapterTitle(chapter.title) == key) return i;
    }
    return -1;
  }

  /// 新建划线；区间越界在这里按当前段落长度 clamp，非法返回 null。
  Future<NovelMarking?> addMarking({
    required int paragraph,
    required int startOffset,
    required int endOffset,
    NovelMarkingStyle? style,
    String note = '',
  }) async {
    final api = bookmarks;
    final current = chapter;
    final contentNow = content;
    if (api == null || current == null || contentNow == null) return null;
    final last = contentNow.paragraphs.isEmpty
        ? 0
        : contentNow.paragraphs.length - 1;
    final targetParagraph = paragraph.clamp(0, last);
    final chosen = style ?? lastMarkingStyle;
    try {
      final marking = await api.addMarking(
        anchor: NovelTextAnchor(
          bookId: bookId,
          sourceKey: _sourceKeyNow,
          chapterIndex: current.index,
          paragraph: targetParagraph,
          charOffset: startOffset,
        ),
        endOffset: endOffset,
        style: chosen,
        note: note,
        chapterName: current.title,
        bookTitle: bookTitleNow,
        bookAuthor: bookAuthorNow,
        bookUrl: bookUrlNow,
        paragraphLength: paragraphLength(targetParagraph),
      );
      if (marking != null) {
        lastMarkingStyle = chosen;
        await _reloadBookmarkState();
      }
      return marking;
    } on Object {
      return null;
    }
  }

  Future<NovelMarking?> updateMarking(
    NovelMarking marking, {
    NovelMarkingStyle? style,
    String? note,
  }) async {
    final api = bookmarks;
    if (api == null) return null;
    try {
      final updated = await api.updateMarking(
        marking.id,
        style: style,
        note: note,
        paragraphLength: paragraphLength(marking.paragraph),
      );
      if (updated != null) await _reloadBookmarkState();
      return updated;
    } on Object {
      return null;
    }
  }

  Future<bool> removeMarkingItem(NovelMarking marking) async {
    final api = bookmarks;
    if (api == null) return false;
    try {
      final removed = await api.removeMarking(marking.id);
      if (removed) await _reloadBookmarkState();
      return removed;
    } on Object {
      return false;
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
      // 换源后目录可能重排：书签/笔记按「章标题 + 段落」尽力找回原位置。
      unawaited(_relocateBookmarks());
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
    _ttsSleepTimer?.cancel();
    _ttsSleepTimer = null;
    final player = _ttsPlayer;
    _ttsPlayer = null;
    unawaited(player?.stop());
    unawaited(_ownedTtsEngine?.stop());
    layoutService.cancel();
    chapterCache.clear();
    super.dispose();
  }
}
