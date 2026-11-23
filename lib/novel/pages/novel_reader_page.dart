// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与小说其他页面同款说明。
/// 小说阅读器（沉浸式，对照「阅读（legado）」的界面与操作）。
///
/// 能力：
/// - 默认上下滚动，可切左右翻页；点中间显隐菜单，点左右翻页；
/// - 沉浸式全屏（Windows 隐藏标题栏/任务栏，Android 沉浸系统栏）；
/// - 顶部栏：缓存本章 / 刷新本章 / 换源 / 更多 + 当前书源名；
/// - 底部菜单：亮度滑杆、章节进度滑杆、书内搜索 / 自动翻页 / 目录 / 朗读 / 设置；
/// - 页脚：章节名 + 本章页码 + 全书百分比；
/// - 阅读设置：字号、Ttf 字体、背景预设/自定义/夜间、行距段距边距、翻页动画；
/// - 页内位置落模块 kv，历史库仍记章级进度（双记账不变）。
///
/// 路由参数：`bookId`、`title`、`author`、`sourceKey`、`bookUrl`、`chapterId`、
/// `chapterIndex`、`chapterUrl`、`chapterTitle`。缺目录时按 bookId 重新抓目录。
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_immersive.dart';
import 'package:mimao/novel/reader/novel_reader_chrome.dart';
import 'package:mimao/novel/reader/novel_reader_position.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_reader_settings_sheet.dart';
import 'package:mimao/novel/reader/novel_search_sheet.dart';
import 'package:mimao/novel/reader/novel_source_switch_sheet.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';
import 'package:mimao/novel/reader/novel_tts.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({
    super.key,
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
    this.stats,
    this.prefs,
    this.replaceRules,
    this.settingsStore,
  });

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

  /// 详情页已抓到的目录；有它时阅读器不再重复抓目录。
  final List<NovelChapter>? chapters;
  final NovelOnlineEngine? onlineEngine;
  final NovelSourceStorage? sourceStore;
  final NovelHistoryApi? history;
  final NovelStatsApi? stats;
  final NovelPrefsApi? prefs;

  /// 替换规则仓库；注入后正文与标题在展示前统一净化。
  final NovelReplaceRuleStorage? replaceRules;

  /// 阅读设置存储（测试注入内存实现；生产由 prefs 构造）。
  final NovelReaderSettingsStore? settingsStore;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  static const double _contentTopGap = 12;
  static const double _contentBottomGap = 44;
  static const double _footerHeight = 26;

  static bool get _isTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// 自动亮度需要系统亮度接口（Android 侧后续接入 screen_brightness）；
  /// 桌面端没有可靠接口，隐藏该按钮，亮度用遮罩滑杆。
  static bool get _supportsAutoBrightness => !kIsWeb && Platform.isAndroid;

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _scrollRatio = ValueNotifier<double>(0);
  final Stopwatch _session = Stopwatch();

  late final NovelReaderSettingsStore _settingsStore;
  late final NovelReaderPositionStore _positionStore;

  NovelReaderSettings _settings = const NovelReaderSettings();
  bool _settingsReady = false;

  NovelBookSource? _source;
  NovelDetail? _detail;
  NovelChapter? _chapter;
  NovelContent? _content;
  String? _loadError;
  bool _loadingDetail = true;
  bool _loadingContent = false;
  List<NovelReplaceRule> _replaceRules = const <NovelReplaceRule>[];
  Future<void> _replaceRulesReady = Future<void>.value();

  List<NovelTextPage> _pages = const <NovelTextPage>[];
  String _paginationKey = '';
  int _pageIndex = 0;
  int _pageDirection = 1;
  double? _pendingPageRatio;
  NovelReaderPosition? _pendingRestore;
  bool _pendingStartAtEnd = false;
  NovelReaderPosition? _savedPosition;
  NovelSummary? _historyOverride;

  bool _autoReading = false;
  Timer? _autoTimer;
  Timer? _saveTimer;
  Timer? _settingsTimer;
  bool _torndown = false;
  int _loadSeq = 0;
  bool _ensuringTts = false;

  NovelTtsEngine? _tts;
  bool _speaking = false;
  int _ttsParagraph = 0;

  @override
  void initState() {
    super.initState();
    _session.start();
    _settingsStore =
        widget.settingsStore ?? PrefsNovelReaderSettingsStore(widget.prefs);
    _positionStore = NovelReaderPositionStore(widget.prefs);
    _scroll.addListener(_onScroll);
    _replaceRulesReady = _loadReplaceRules();
    unawaited(_prepare());
    unawaited(NovelImmersive.enter());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _saveTimer?.cancel();
    _settingsTimer?.cancel();
    _flushReadingTime();
    _savePositionNow();
    _torndown = true;
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _scrollRatio.dispose();
    _chromeVisible.dispose();
    unawaited(_stopTts());
    unawaited(NovelImmersive.exit());
    super.dispose();
  }

  Future<void> _prepare() async {
    final loaded = await _settingsStore.load();
    final position = await _positionStore.load(widget.bookId);
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _savedPosition = position;
      _settingsReady = true;
    });
    await _bootstrap();
  }

  /// 读替换规则；失败不阻断阅读，按「没有规则」继续。
  Future<void> _loadReplaceRules() async {
    final store = widget.replaceRules;
    if (store == null) return;
    try {
      final rules = await store.loadAll();
      if (mounted) setState(() => _replaceRules = rules);
    } on Object {
      // 规则读坏了不该让正文打不开。
    }
  }

  /// 把替换规则作用到正文与标题上：`scopeTitle` / `scopeContent` 分别控制，
  /// 作用范围按书名 / 书源 key / 书源地址匹配（空范围 = 全局）。
  NovelContent _applyReplaceRules(NovelContent content) {
    if (_replaceRules.isEmpty) return content;
    final detail = _detail;
    final bookTitle = detail?.title ?? widget.title ?? '';
    final sourceKey = detail?.ref.sourceKey ?? widget.sourceKey ?? '';
    final bookUrl = detail?.ref.bookUrl ?? widget.bookUrl ?? '';
    final applicable = _replaceRules
        .where(
          (rule) =>
              rule.enabled &&
              rule.appliesToBook(
                bookTitle: bookTitle,
                sourceKey: sourceKey,
                bookUrl: bookUrl,
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

  Future<void> _bootstrap() async {
    final engine = widget.onlineEngine;
    final store = widget.sourceStore;
    final sourceKey = widget.sourceKey ?? '';
    if (engine == null || store == null || sourceKey.isEmpty) {
      setState(() {
        _loadingDetail = false;
        _loadError = '阅读器未接线（缺少书源引擎或书源信息）';
      });
      return;
    }
    final preloaded = widget.chapters;
    if (preloaded != null && preloaded.isNotEmpty) {
      final detail = NovelDetail(
        ref: NovelRef(
          id: widget.bookId,
          sourceKey: sourceKey,
          bookUrl: widget.bookUrl ?? widget.bookId,
        ),
        title: widget.title ?? '',
        coverUrl: widget.coverUrl ?? '',
        author: widget.author ?? '',
        chapters: preloaded,
      );
      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
      // 源仍需用于正文抓取；只靠 key 从仓库取一次。
      try {
        final sources = await store.loadAll();
        for (final candidate in sources) {
          if (candidate.key == sourceKey) {
            _source = candidate;
            break;
          }
        }
      } on Object {
        // 忽略：下面统一判空。
      }
      if (!mounted) return;
      if (_source == null) {
        setState(() => _loadError = '找不到书源（可能已被删除）');
        return;
      }
      final chapter = _pickChapter(detail.chapters);
      if (chapter == null) {
        setState(() => _loadError = '目录为空，无法开始阅读');
        return;
      }
      await _openChapter(chapter);
      return;
    }
    setState(() {
      _loadingDetail = true;
      _loadError = null;
    });
    try {
      final sources = await store.loadAll();
      NovelBookSource? source;
      for (final candidate in sources) {
        if (candidate.key == sourceKey) {
          source = candidate;
          break;
        }
      }
      if (source == null) {
        throw StateError('找不到书源（可能已被删除）');
      }
      final ref = NovelRef(
        id: widget.bookId,
        sourceKey: sourceKey,
        bookUrl: widget.bookUrl ?? widget.bookId,
      );
      final detail = await engine.bookDetail(
        source,
        ref,
        titleHint: widget.title,
        authorHint: widget.author,
      );
      if (!mounted) return;
      setState(() {
        _source = source;
        _detail = detail;
        _loadingDetail = false;
      });
      final chapter = _pickChapter(detail.chapters);
      if (chapter == null) {
        setState(() => _loadError = '目录为空，无法开始阅读');
        return;
      }
      await _openChapter(chapter);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _loadError = '$error';
      });
    }
  }

  NovelChapter? _pickChapter(List<NovelChapter> chapters) {
    if (chapters.isEmpty) return null;
    final id = widget.chapterId;
    if (id != null && id.isNotEmpty) {
      for (final chapter in chapters) {
        if (chapter.id == id || chapter.url == id) return chapter;
      }
    }
    final index = widget.chapterIndex;
    if (index != null && index >= 0 && index < chapters.length) {
      return chapters[index];
    }
    return chapters.first;
  }

  Future<void> _openChapter(
    NovelChapter chapter, {
    bool atEnd = false,
    bool refresh = false,
  }) async {
    final engine = widget.onlineEngine;
    final source = _source;
    final detail = _detail;
    if (engine == null || source == null || detail == null) return;
    final seq = ++_loadSeq;
    final reopening = _chapter != null && _chapter!.id == chapter.id;
    final resumeFrom = reopening ? _currentSavedPosition() : null;
    await _stopTts();
    _flushReadingTime();
    _savePositionNow();
    if (!mounted) return;
    setState(() {
      _chapter = chapter;
      _content = null;
      _loadingContent = true;
      _loadError = null;
      _pageIndex = 0;
      _pageDirection = 1;
      _paginationKey = '';
      _pages = const <NovelTextPage>[];
      _pendingPageRatio = null;
    });
    _scrollRatio.value = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      var content = refresh
          ? await _refreshContent(engine, source, detail.ref, chapter)
          : await engine.contentFor(source, detail.ref, chapter);
      // 规则可能还在读盘；等它落地再展示，避免首屏先出现未净化的正文。
      await _replaceRulesReady;
      if (!mounted || seq != _loadSeq) return;
      content = _applyReplaceRules(content);
      final saved = resumeFrom ?? _savedPosition;
      final canRestore =
          saved != null &&
          (resumeFrom != null ||
              saved.matches(
                chapterUrl: chapter.url,
                chapterId: chapter.id,
                chapterIndex: chapter.index,
              ));
      setState(() {
        _content = content;
        _loadingContent = false;
        _pendingRestore = canRestore ? saved : null;
        _pendingStartAtEnd = !canRestore && atEnd;
      });
      // 引擎的 chapter.index 是 0 起（对齐 legado），历史库存的"读到第几章"
      // 是 1 起且 0 表示无进度（novel_db.dart 的契约）。落库前 +1，否则第 1 章
      // （index=0）会被当成"没读"显示"读过"，第 N 章少显示一章。
      _session
        ..reset()
        ..start();
      // 先恢复页内位置，再写历史：历史库慢/失败不该把用户扔回章首。
      _schedulePositionRestore();
      try {
        await widget.history?.saveProgress(
          _historyOverride ?? detail.summary,
          chapter.index + 1,
          detail.chapters.length,
        );
      } on Object {
        // 历史写入失败不阻断阅读。
      }
    } on Object catch (error) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loadingContent = false;
        _loadError = '$error';
      });
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

  void _flushReadingTime() {
    if (!_session.isRunning) return;
    _session.stop();
    final elapsed = _session.elapsed;
    if (elapsed.inSeconds > 0) {
      unawaited(widget.stats?.addReadingTime(elapsed) ?? Future<void>.value());
    }
  }

  // ── 章节切换 ──────────────────────────────────────────────────────────
  NovelChapter? _neighborChapter(int delta) {
    final detail = _detail;
    final chapter = _chapter;
    if (detail == null || chapter == null) return null;
    var index = chapter.index + delta;
    while (index >= 0 && index < detail.chapters.length) {
      final candidate = detail.chapters[index];
      if (!candidate.isVolume) return candidate;
      index += delta;
    }
    return null;
  }

  Future<void> _nextChapter() async {
    final next = _neighborChapter(1);
    if (next != null) await _openChapter(next);
  }

  Future<void> _previousChapter({bool atEnd = false}) async {
    final previous = _neighborChapter(-1);
    if (previous != null) await _openChapter(previous, atEnd: atEnd);
  }

  // ── 排版与进度 ────────────────────────────────────────────────────────
  TextStyle _bodyStyle() {
    final family = _settings.fontFamily.isEmpty
        ? MimaoFonts.family
        : _settings.fontFamily;
    return TextStyle(
      fontFamily: family,
      fontWeight: MimaoFonts.regular,
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      color: novelReaderTextColor(_settings),
    );
  }

  TextStyle _titleStyle() => _bodyStyle().copyWith(
    fontSize: _settings.fontSize + 6,
    fontWeight: MimaoFonts.bold,
    height: 1.4,
  );

  String _paragraphText(int index) {
    final paragraphs = _content?.paragraphs ?? const <String>[];
    if (index < 0 || index >= paragraphs.length) return '';
    return '　　${paragraphs[index]}';
  }

  List<NovelTextPage> _pagesFor(BoxConstraints constraints, EdgeInsets insets) {
    final content = _content;
    if (content == null) {
      _pages = const <NovelTextPage>[];
      return _pages;
    }
    final double top = insets.top + _contentTopGap;
    final double bottom = insets.bottom + _contentBottomGap;
    final double width =
        (constraints.maxWidth - _settings.horizontalPadding * 2).clamp(
          80.0,
          double.infinity,
        );
    final double height = (constraints.maxHeight - top - bottom).clamp(
      80.0,
      double.infinity,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final key = <Object?>[
      _chapter?.id,
      content.title,
      content.paragraphs.length,
      width,
      height,
      _settings.fontSize,
      _settings.lineHeight,
      _settings.fontFamily,
      _settings.paragraphSpacing,
      _settings.horizontalPadding,
      scaler.scale(16),
    ].join('|');
    if (key == _paginationKey) return _pages;

    final pages = NovelPaginator(
      title: content.title.isEmpty ? (_chapter?.title ?? '') : content.title,
      paragraphs: content.paragraphs,
      bodyStyle: _bodyStyle(),
      titleStyle: _titleStyle(),
      maxWidth: width,
      maxHeight: height,
      paragraphSpacing: _settings.paragraphSpacing,
      titleSpacing: 18,
      textScaler: scaler,
    ).paginate();
    _paginationKey = key;
    _pages = pages;

    final ratio = _pendingPageRatio;
    if (ratio != null) {
      _pendingPageRatio = null;
      _pageIndex = (ratio * (pages.length - 1)).round().clamp(
        0,
        pages.length - 1,
      );
      if (_settings.pageMode == NovelPageMode.scroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final max = _scroll.position.maxScrollExtent;
          _scroll.jumpTo((ratio * max).clamp(0.0, max));
        });
      }
    } else if (_pageIndex >= pages.length) {
      _pageIndex = pages.length - 1;
    }
    return pages;
  }

  int _currentPage(int pageCount) {
    if (pageCount <= 1) return 1;
    if (_settings.pageMode == NovelPageMode.page) {
      return _pageIndex.clamp(0, pageCount - 1) + 1;
    }
    final page = (_scrollRatio.value * pageCount).floor() + 1;
    return page.clamp(1, pageCount);
  }

  /// 章内位置比例：滚动模式以滚动比例为准，翻页模式按页码比例。
  double _currentPageRatio() {
    final count = _pages.length;
    if (_settings.pageMode == NovelPageMode.page) {
      return count <= 1 ? 0 : _pageIndex / (count - 1);
    }
    return _scrollRatio.value;
  }

  void _scheduleSettingsSave() {
    _settingsTimer?.cancel();
    _settingsTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_settingsStore.save(_settings)),
    );
  }

  double _bookPercent(int page, int pageCount) {
    final chapters = _detail?.chapters.length ?? 0;
    final chapter = _chapter;
    if (chapters <= 0 || chapter == null) return 0;
    if (pageCount <= 0) {
      return ((chapter.index + 1) / chapters * 100).clamp(0.0, 100.0);
    }
    // 与 legado 一致：整书进度 = (章下标 + 当前页/本章页数) / 总章数。
    final value = (chapter.index + page / pageCount) / chapters * 100;
    final atLastPage = chapter.index >= chapters - 1 && page >= pageCount;
    final clamped = value.clamp(0.0, 100.0);
    // 还没读到最后一页时最多显示 99.9%，避免"没读完就 100%"。
    if (clamped >= 100 && !atLastPage) return 99.9;
    return clamped;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final max = position.maxScrollExtent;
    final ratio = max <= 0 ? 0.0 : (position.pixels / max).clamp(0.0, 1.0);
    if ((ratio - _scrollRatio.value).abs() >= 0.001) {
      _scrollRatio.value = ratio;
    }
    _scheduleSavePosition();
  }

  void _scheduleSavePosition() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _savePositionNow);
  }

  NovelReaderPosition? _currentSavedPosition() {
    final chapter = _chapter;
    if (chapter == null) return null;
    final pageCount = _pages.isEmpty ? 1 : _pages.length;
    return NovelReaderPosition(
      chapterUrl: chapter.url,
      chapterId: chapter.id,
      chapterIndex: chapter.index,
      page: _currentPage(pageCount),
      pageCount: pageCount,
      scrollRatio: _scrollRatio.value,
    );
  }

  void _savePositionNow() {
    final position = _currentSavedPosition();
    if (position == null || _torndown) return;
    _savedPosition = position;
    unawaited(_positionStore.save(widget.bookId, position));
  }

  void _schedulePositionRestore() {
    final restore = _pendingRestore;
    final startAtEnd = _pendingStartAtEnd;
    if (restore == null && !startAtEnd) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingRestore = null;
      _pendingStartAtEnd = false;
      final count = _pages.length;
      if (count == 0) return;
      if (_settings.pageMode == NovelPageMode.page) {
        final restored = restore == null
            ? count - 1
            : restore.pageCount <= 1
            ? 0
            : ((restore.page - 1) / (restore.pageCount - 1) * (count - 1))
                  .round();
        final index = restored.clamp(0, count - 1);
        setState(() {
          _pageDirection = 1;
          _pageIndex = index;
        });
      } else if (_scroll.hasClients) {
        final max = _scroll.position.maxScrollExtent;
        final ratio = restore != null
            ? restore.scrollRatio.clamp(0.0, 1.0)
            : 1.0;
        _scroll.jumpTo((ratio * max).clamp(0.0, max));
      }
    });
  }

  void _seekPage(int page) {
    final count = _pages.length;
    if (count <= 1) return;
    final index = (page - 1).clamp(0, count - 1);
    if (_settings.pageMode == NovelPageMode.page) {
      if (index == _pageIndex) return;
      setState(() {
        _pageDirection = index > _pageIndex ? 1 : -1;
        _pageIndex = index;
      });
    } else if (_scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      final target = count <= 1 ? 0.0 : index / (count - 1) * max;
      unawaited(
        _scroll.animateTo(
          target.clamp(0.0, max),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        ),
      );
    }
    _scheduleSavePosition();
  }

  void _turnPage(int direction) {
    if (!_settingsReady || _content == null) return;
    final pageCount = _pages.length;
    if (_settings.pageMode == NovelPageMode.page) {
      final next = _pageIndex + direction;
      if (next < 0) {
        unawaited(_previousChapter(atEnd: true));
        return;
      }
      if (next >= pageCount) {
        unawaited(_nextChapter());
        return;
      }
      setState(() {
        _pageDirection = direction;
        _pageIndex = next;
      });
      _scheduleSavePosition();
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target =
        position.pixels + direction * position.viewportDimension * 0.9;
    if (target < 0) {
      unawaited(_previousChapter(atEnd: true));
      return;
    }
    if (target > position.maxScrollExtent) {
      if (position.pixels >= position.maxScrollExtent - 2) {
        unawaited(_nextChapter());
        return;
      }
      unawaited(
        _scroll.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    unawaited(
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      ),
    );
  }

  void _toggleChrome() {
    _chromeVisible.value = !_chromeVisible.value;
  }

  void _handleEscape() {
    if (_chromeVisible.value) {
      _chromeVisible.value = false;
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ── 设置 ──────────────────────────────────────────────────────────────
  void _applySettings(NovelReaderSettings next) {
    final previous = _settings;
    final oldInterval = previous.autoPageSeconds;
    final ratio = _currentPageRatio();
    final modeChanged = next.pageMode != previous.pageMode;
    final layoutChanged =
        next.fontSize != previous.fontSize ||
        next.lineHeight != previous.lineHeight ||
        next.paragraphSpacing != previous.paragraphSpacing ||
        next.horizontalPadding != previous.horizontalPadding ||
        next.fontFamily != previous.fontFamily;
    setState(() {
      _settings = next;
      if (layoutChanged) _paginationKey = '';
      if (layoutChanged || modeChanged) _pendingPageRatio = ratio;
    });
    _scheduleSettingsSave();
    if (modeChanged && next.pageMode == NovelPageMode.scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo((ratio * max).clamp(0.0, max));
      });
    }
    if (_autoReading && next.autoPageSeconds != oldInterval) {
      _startAutoTimer();
    }
  }

  void _setBrightness(double value) {
    final next = _settings.copyWith(
      dimBrightness: value.round(),
      // 手动拖亮度即退出「跟随系统」。
      autoBrightness: false,
    );
    if (next.dimBrightness == _settings.dimBrightness &&
        !_settings.autoBrightness) {
      return;
    }
    setState(() => _settings = next);
    _settingsTimer?.cancel();
    _settingsTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_settingsStore.save(_settings)),
    );
  }

  int _dimBeforeAuto = 100;

  void _toggleAutoBrightness() {
    final turningOn = !_settings.autoBrightness;
    if (turningOn) _dimBeforeAuto = _settings.dimBrightness;
    final next = _settings.copyWith(
      autoBrightness: turningOn,
      // 跟随系统 = 阅读遮罩不压暗，亮度交给系统；关掉后恢复原值。
      dimBrightness: turningOn ? 100 : _dimBeforeAuto,
    );
    setState(() => _settings = next);
    unawaited(_settingsStore.save(next));
  }

  // ── 自动翻页 ──────────────────────────────────────────────────────────
  void _pauseAutoForSheet() {
    if (!_autoReading) return;
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void _resumeAutoFromSheet() {
    if (_autoReading && _autoTimer == null) _startAutoTimer();
  }

  void _toggleAutoReading() {
    if (_autoReading) {
      _stopAutoReading();
      return;
    }
    if (_content == null) {
      _showSnack('正文还没加载完，暂时不能自动翻页');
      return;
    }
    setState(() => _autoReading = true);
    _startAutoTimer();
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(Duration(seconds: _settings.autoPageSeconds), (
      _,
    ) {
      if (!mounted || !_autoReading) return;
      _turnPage(1);
    });
  }

  void _stopAutoReading() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (_autoReading && mounted) setState(() => _autoReading = false);
  }

  // ── 朗读 ──────────────────────────────────────────────────────────────
  Future<NovelTtsEngine?> _ensureTts() async {
    if (_isTest) return null;
    final existing = _tts;
    if (existing != null) return existing;
    final engine = createNovelTtsEngine();
    if (engine == null) return null;
    try {
      await engine.configure();
      _tts = engine;
      return engine;
    } on Object {
      await engine.stop();
      return null;
    }
  }

  Future<void> _toggleTts() async {
    if (_speaking) {
      await _stopTts();
      return;
    }
    if (_ensuringTts) return;
    final content = _content;
    if (content == null) return;
    _ensuringTts = true;
    final tts = await _ensureTts();
    _ensuringTts = false;
    if (!mounted) return;
    if (tts == null) {
      _showSnack('当前平台暂不支持朗读');
      return;
    }
    setState(() => _speaking = true);
    _ttsParagraph = _firstParagraphOnPage();
    await _speakParagraphs(tts, content);
  }

  int _firstParagraphOnPage() {
    if (_pages.isEmpty) return 0;
    final index = (_currentPage(_pages.length) - 1).clamp(0, _pages.length - 1);
    for (final slice in _pages[index].slices) {
      if (!slice.isTitle) return slice.paragraph;
    }
    return 0;
  }

  Future<void> _speakParagraphs(
    NovelTtsEngine tts,
    NovelContent content,
  ) async {
    for (var i = _ttsParagraph; i < content.paragraphs.length; i++) {
      if (!_speaking || !mounted) return;
      _ttsParagraph = i;
      try {
        await tts.speak(content.paragraphs[i]);
      } on Object {
        await _stopTts();
        if (mounted) _showSnack('朗读失败，已停止');
        return;
      }
    }
    await _stopTts();
  }

  Future<void> _stopTts() async {
    if (!_speaking) return;
    _speaking = false;
    try {
      await _tts?.stop();
    } on Object {
      // 停止失败不阻塞切章/退出。
    }
    if (mounted) setState(() {});
  }

  // ── 面板入口 ──────────────────────────────────────────────────────────
  Future<void> _openSettings() async {
    _pauseAutoForSheet();
    _chromeVisible.value = false;
    final info = NovelReaderBookInfo(
      bookTitle: _detail?.title ?? widget.title ?? '',
      author: _detail?.author ?? widget.author ?? '',
      sourceName: _source?.name ?? '',
      chapterTitle: _chapter?.title ?? '',
      chapterIndex: (_chapter?.index ?? 0) + 1,
      chapterCount: _detail?.chapters.length ?? 0,
      page: _currentPage(_pages.length),
      pageCount: _pages.isEmpty ? 1 : _pages.length,
      percent: _bookPercent(_currentPage(_pages.length), _pages.length),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
      builder: (sheetContext) => _sheetTheme(
        Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            MediaQuery.paddingOf(sheetContext).bottom + 12,
          ),
          child: NovelReaderSettingsSheet(
            initial: _settings,
            info: info,
            onChanged: _applySettings,
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
    }
  }

  Future<void> _openCatalog() async {
    _pauseAutoForSheet();
    final detail = _detail;
    if (detail == null) return;
    _chromeVisible.value = false;
    final chapters = <({String title, bool isVolume, bool isVip})>[
      for (final chapter in detail.chapters)
        (
          title: chapter.title,
          isVolume: chapter.isVolume,
          isVip: chapter.isVip,
        ),
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheetThemeData().colorScheme.surfaceContainerLow,
      showDragHandle: false,
      builder: (sheetContext) => _sheetTheme(
        NovelCatalogSheet(
          chapters: chapters,
          currentIndex: _chapter?.index ?? 0,
          settings: _settings,
          onPick: (index) => Navigator.of(sheetContext).pop(index),
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
    }
    if (picked != null && mounted && picked < detail.chapters.length) {
      final target = detail.chapters[picked];
      if (!target.isVolume) await _openChapter(target);
    }
  }

  Future<void> _openSearch() async {
    _pauseAutoForSheet();
    final engine = widget.onlineEngine;
    final source = _source;
    final detail = _detail;
    if (engine == null || source == null || detail == null) return;
    _chromeVisible.value = false;
    final titles = <String>[
      for (final chapter in detail.chapters) chapter.title,
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheetThemeData().colorScheme.surfaceContainerLow,
      showDragHandle: false,
      builder: (sheetContext) => _sheetTheme(
        NovelSearchSheet(
          chapterTitles: titles,
          currentChapterIndex: _chapter?.index ?? 0,
          loadChapter: (index) async {
            if (index < 0 || index >= detail.chapters.length) {
              return const <String>[];
            }
            final chapter = detail.chapters[index];
            if (chapter.isVolume) return const <String>[];
            final content = await engine.contentFor(
              source,
              detail.ref,
              chapter,
            );
            return content.paragraphs;
          },
          onPick: (chapterIndex, paragraph) {
            // 搜索面板自己 pop 回阅读页，这里不能再 pop 一次。
            unawaited(_jumpToParagraph(chapterIndex, paragraph));
          },
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
    }
  }

  Future<void> _jumpToParagraph(int chapterIndex, int paragraph) async {
    final detail = _detail;
    if (detail == null ||
        chapterIndex < 0 ||
        chapterIndex >= detail.chapters.length) {
      return;
    }
    final chapter = detail.chapters[chapterIndex];
    if (_chapter?.index != chapterIndex) {
      await _openChapter(chapter);
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _pages.indexWhere(
        (page) => page.slices.any(
          (slice) => !slice.isTitle && slice.paragraph >= paragraph,
        ),
      );
      if (index >= 0) _seekPage(index + 1);
    });
  }

  Future<void> _openSourceSwitch() async {
    _pauseAutoForSheet();
    final engine = widget.onlineEngine;
    final store = widget.sourceStore;
    final detail = _detail;
    if (engine == null || store == null || detail == null) return;
    _chromeVisible.value = false;
    List<NovelBookSource> sources;
    try {
      sources = await store.loadAll();
    } on Object catch (error) {
      if (mounted) {
        _chromeVisible.value = true;
        _resumeAutoFromSheet();
        _showSnack('读取书源失败：$error');
      }
      return;
    }
    if (!mounted) return;
    final hit = await showModalBottomSheet<NovelSourceHit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheetThemeData().colorScheme.surfaceContainerLow,
      showDragHandle: false,
      builder: (sheetContext) => _sheetTheme(
        NovelSourceSwitchSheet(
          title: detail.title,
          author: detail.author,
          currentSourceKey: _source?.key ?? '',
          sources: sources,
          engine: engine,
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
    }
    if (hit == null || !mounted) return;
    await _switchSource(hit.source, hit.book);
  }

  Future<void> _switchSource(NovelBookSource source, NovelSummary book) async {
    final engine = widget.onlineEngine;
    if (engine == null) return;
    final oldChapter = _chapter;
    _savePositionNow();
    _flushReadingTime();
    await _stopTts();
    setState(() {
      _loadingDetail = true;
      _loadError = null;
    });
    try {
      final ref = NovelRef(
        id: book.id,
        sourceKey: source.key,
        bookUrl: book.bookUrl.isEmpty ? book.id : book.bookUrl,
      );
      final detail = await engine.bookDetail(
        source,
        ref,
        titleHint: book.title,
        authorHint: book.author,
      );
      if (!mounted) return;
      final targetIndex = _matchChapterIndex(detail.chapters, oldChapter);
      if (detail.chapters.isEmpty) {
        throw StateError('新书源目录为空');
      }
      final target = detail.chapters[targetIndex];
      // 保持同一本书的 history 行（widget.bookId），只更新源信息；
      // 这样书架/时间线不会因为换源多出一条重复记录。
      _historyOverride = NovelSummary(
        id: widget.bookId,
        title: detail.title,
        coverUrl: detail.coverUrl,
        author: detail.author,
        sourceKey: source.key,
        bookUrl: ref.bookUrl,
        intro: detail.intro,
        kind: detail.kind,
        latestChapter: detail.latestChapter,
        wordCount: detail.wordCount,
      );
      setState(() {
        _source = source;
        _detail = detail;
        _chapter = null;
        _content = null;
        _loadingDetail = false;
      });
      await _openChapter(target);
      if (mounted) _showSnack('已切换到「${source.name}」');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _loadError = '$error';
      });
      _showSnack('换源失败：$error');
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
    // 标题对不上时按旧下标兜底，但不能落在卷名行上。
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

  // ── 缓存 / 更多 ───────────────────────────────────────────────────────
  Future<void> _downloadCurrentChapter() async {
    final engine = widget.onlineEngine;
    final source = _source;
    final detail = _detail;
    final chapter = _chapter;
    if (engine == null || source == null || detail == null || chapter == null) {
      return;
    }
    try {
      await engine.contentFor(source, detail.ref, chapter);
      _showSnack('已缓存本章');
    } on Object catch (error) {
      _showSnack('缓存失败：$error');
    }
  }

  Future<void> _refreshCurrentChapter() async {
    final chapter = _chapter;
    if (chapter == null) return;
    await _openChapter(chapter, refresh: true);
  }

  Future<void> _cacheWholeBook() async {
    final engine = widget.onlineEngine;
    final source = _source;
    final detail = _detail;
    if (engine == null || source == null || detail == null) return;
    final chapters = <NovelChapter>[
      for (final chapter in detail.chapters)
        if (!chapter.isVolume) chapter,
    ];
    if (chapters.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('缓存全本'),
        content: Text('共 ${chapters.length} 章，将逐章抓取并写入本地缓存。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始缓存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    var cancelled = false;
    final done = ValueNotifier<int>(0);
    final failed = ValueNotifier<int>(0);
    final navigator = Navigator.of(context);
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('正在缓存全书'),
          content: ValueListenableBuilder<int>(
            valueListenable: done,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                LinearProgressIndicator(
                  value: chapters.isEmpty ? 0 : value / chapters.length,
                  minHeight: 4,
                ),
                const SizedBox(height: 12),
                Text('$value / ${chapters.length} 章'),
                ValueListenableBuilder<int>(
                  valueListenable: failed,
                  builder: (_, count, ___) => count == 0
                      ? const SizedBox.shrink()
                      : Text('失败 $count 章'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('novel-cache-all-stop'),
              onPressed: () => cancelled = true,
              child: const Text('停止'),
            ),
          ],
        ),
      ).then((_) => dialogOpen = false),
    );

    for (final chapter in chapters) {
      if (cancelled || !mounted) break;
      try {
        await engine
            .contentFor(source, detail.ref, chapter)
            .timeout(const Duration(seconds: 20));
      } on Object {
        failed.value++;
      }
      done.value++;
    }
    if (!mounted) return;
    // 用户可能用系统返回键关了进度框；只有它还在栈顶时才 pop。
    if (dialogOpen) navigator.pop();
    _showSnack(
      '缓存完成：${done.value} 章${failed.value == 0 ? '' : '，失败 ${failed.value} 章'}',
    );
  }

  Future<void> _openMore() async {
    _pauseAutoForSheet();
    _chromeVisible.value = false;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _sheetThemeData().colorScheme.surfaceContainerLow,
      showDragHandle: false,
      builder: (sheetContext) => _sheetTheme(
        SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                key: const Key('novel-more-cache-all'),
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('缓存全本'),
                subtitle: const Text('逐章抓取正文写入本地缓存'),
                onTap: () => Navigator.of(sheetContext).pop('cache'),
              ),
              ListTile(
                key: const Key('novel-more-info'),
                leading: const Icon(Icons.info_outline),
                title: const Text('书籍信息'),
                onTap: () => Navigator.of(sheetContext).pop('info'),
              ),
              ListTile(
                key: const Key('novel-more-settings'),
                leading: const Icon(Icons.tune),
                title: const Text('阅读设置'),
                onTap: () => Navigator.of(sheetContext).pop('settings'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
    }
    switch (picked) {
      case 'cache':
        await _cacheWholeBook();
      case 'info':
        await _showBookInfo();
      case 'settings':
        await _openSettings();
    }
  }

  Future<void> _showBookInfo() async {
    final detail = _detail;
    if (detail == null) return;
    final page = _currentPage(_pages.isEmpty ? 1 : _pages.length);
    final pageCount = _pages.isEmpty ? 1 : _pages.length;
    final rows = <(String, String)>[
      ('书名', detail.title),
      ('作者', detail.author.isEmpty ? '—' : detail.author),
      ('书源', _source?.name ?? '—'),
      ('章节', '${(_chapter?.index ?? 0) + 1} / ${detail.chapters.length}'),
      ('本章页码', '$page / $pageCount'),
      ('全书进度', '${_bookPercent(page, pageCount).toStringAsFixed(1)}%'),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('书籍信息'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 76,
                        child: Text(
                          row.$1,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(row.$2, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 阅读页内浮层跟随阅读背景明暗：深色画布上不弹浅色面板。
  ///
  /// 主题里的 TextTheme 是「黑色基线」（见 lib/core/theme.dart），深色背景上
  /// 直接复用会把标题/说明压成深灰；这里显式换成 onSurface。
  ThemeData _sheetThemeData() {
    final base = buildMimaoTheme(
      seedColor: Theme.of(context).colorScheme.primary,
      brightness: _settings.darkBackground ? Brightness.dark : Brightness.light,
    );
    final scheme = base.colorScheme;
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }

  Widget _sheetTheme(Widget child) =>
      Theme(data: _sheetThemeData(), child: child);

  // ── 构建 ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final background = novelReaderBackgroundColor(_settings);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _turnPage(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _turnPage(1),
        const SingleActivator(LogicalKeyboardKey.space): _toggleAutoReading,
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: background,
          body: !_settingsReady
              ? Center(
                  child: CircularProgressIndicator(
                    color: novelReaderTextColor(_settings),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final pages = _pagesFor(constraints, insets);
                    final pageCount = pages.isEmpty ? 1 : pages.length;
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _buildContent(insets, pages),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: const Color(0xFF000000).withValues(
                                alpha: 1 - _settings.dimBrightness / 100,
                              ),
                            ),
                          ),
                        ),
                        if (_settings.eyeProtection)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(color: Color(0x1AFFB74D)),
                            ),
                          ),
                        Positioned.fill(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                flex: 3,
                                child: GestureDetector(
                                  key: const Key('novel-reader-tap-prev'),
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => _turnPage(-1),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: GestureDetector(
                                  key: const Key('novel-reader-tap-center'),
                                  behavior: HitTestBehavior.translucent,
                                  onTap: _toggleChrome,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: GestureDetector(
                                  key: const Key('novel-reader-tap-next'),
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => _turnPage(1),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_settings.showFooter)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    background.withValues(alpha: 0),
                                    background.withValues(alpha: 0.92),
                                    background,
                                  ],
                                  stops: const <double>[0, 0.55, 1],
                                ),
                              ),
                              child: ValueListenableBuilder<double>(
                                valueListenable: _scrollRatio,
                                builder: (context, _, __) {
                                  final page = _currentPage(pageCount);
                                  return NovelReaderFooter(
                                    settings: _settings,
                                    chapterTitle:
                                        _chapter?.title ??
                                        widget.chapterTitle ??
                                        '',
                                    bookTitle:
                                        _detail?.title ?? widget.title ?? '',
                                    page: page,
                                    pageCount: pageCount,
                                    percent: _bookPercent(page, pageCount),
                                  );
                                },
                              ),
                            ),
                          ),
                        _buildTopBar(),
                        _buildBottomPanel(pageCount),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildContent(EdgeInsets insets, List<NovelTextPage> pages) {
    if (_loadingDetail) {
      return _centeredMessage('正在加载目录…');
    }
    if (_content == null) {
      if (_loadError != null) {
        return _centeredMessage(
          _loadError!,
          actionLabel: '重试',
          onAction: () {
            if (_chapter == null) {
              unawaited(_bootstrap());
            } else {
              unawaited(_openChapter(_chapter!));
            }
          },
        );
      }
      return _centeredMessage(_loadingContent ? '正在加载正文…' : '暂无正文');
    }
    return _settings.pageMode == NovelPageMode.page
        ? _buildPageMode(insets, pages)
        : _buildScrollMode(insets);
  }

  Widget _buildScrollMode(EdgeInsets insets) {
    final content = _content!;
    final body = _bodyStyle();
    final title = _titleStyle();
    final chapterTitle = content.title.isEmpty
        ? (_chapter?.title ?? '')
        : content.title;
    final paragraphs = content.paragraphs;
    return SelectionArea(
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          _scheduleSavePosition();
          return false;
        },
        child: ListView.builder(
          key: const Key('novel-reader-scroll'),
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            _settings.horizontalPadding,
            insets.top + _contentTopGap,
            _settings.horizontalPadding,
            insets.bottom + _contentBottomGap + 16,
          ),
          itemCount: paragraphs.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(chapterTitle, style: title),
              );
            }
            final paragraph = index - 1;
            if (paragraph < paragraphs.length) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: paragraph == paragraphs.length - 1
                      ? 0
                      : _settings.paragraphSpacing,
                ),
                child: Text(_paragraphText(paragraph), style: body),
              );
            }
            return _buildChapterEnd();
          },
        ),
      ),
    );
  }

  Widget _buildChapterEnd() {
    final hasNext = _neighborChapter(1) != null;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Column(
        children: <Widget>[
          TextButton.icon(
            key: const Key('novel-reader-next-chapter'),
            onPressed: hasNext ? () => unawaited(_nextChapter()) : null,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(hasNext ? '下一章' : '已是最后一章'),
          ),
          const SizedBox(height: 6),
          Text(
            '点击屏幕中间可呼出菜单，点左右两侧翻页',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: novelReaderSecondaryColor(_settings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageMode(EdgeInsets insets, List<NovelTextPage> pages) {
    if (pages.isEmpty) return _centeredMessage('正在排版…');
    final index = _pageIndex.clamp(0, pages.length - 1);
    final duration = _settings.pageAnimation
        ? Duration(milliseconds: _settings.pageAnimationMs)
        : Duration.zero;
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (event.scrollDelta.dy > 0) {
          _turnPage(1);
        } else if (event.scrollDelta.dy < 0) {
          _turnPage(-1);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 220) {
            _turnPage(-1);
          } else if (velocity < -220) {
            _turnPage(1);
          }
        },
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: Offset(_pageDirection.toDouble() * 0.12, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<String>('page-${_chapter?.id}-$index'),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _settings.horizontalPadding,
                  insets.top + _contentTopGap,
                  _settings.horizontalPadding,
                  insets.bottom + _contentBottomGap,
                ),
                child: _buildPageBody(pages[index]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageBody(NovelTextPage page) {
    final content = _content;
    if (content == null) return const SizedBox.shrink();
    final body = _bodyStyle();
    final titleStyle = _titleStyle();
    final chapterTitle = content.title.isEmpty
        ? (_chapter?.title ?? '')
        : content.title;
    final children = <Widget>[];
    var afterTitle = false;
    int? previousParagraph;
    for (final slice in page.slices) {
      if (slice.isTitle) {
        final start = slice.start.clamp(0, chapterTitle.length);
        final end = slice.end.clamp(start, chapterTitle.length);
        if (end > start) {
          children.add(
            Text(chapterTitle.substring(start, end), style: titleStyle),
          );
        }
        afterTitle = true;
        continue;
      }
      final full = _paragraphText(slice.paragraph);
      final start = slice.start.clamp(0, full.length);
      final end = slice.end.clamp(start, full.length);
      if (afterTitle) {
        children.add(const SizedBox(height: 18));
        afterTitle = false;
      } else if (previousParagraph != null &&
          previousParagraph != slice.paragraph) {
        children.add(SizedBox(height: _settings.paragraphSpacing));
      }
      if (end > start) {
        children.add(Text(full.substring(start, end), style: body));
      }
      previousParagraph = slice.paragraph;
    }
    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _centeredMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final text = novelReaderTextColor(_settings);
    final secondary = novelReaderSecondaryColor(_settings);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: secondary),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 16),
              TextButton.icon(
                key: const Key('novel-reader-retry'),
                onPressed: onAction,
                icon: Icon(Icons.refresh, size: 18, color: text),
                label: Text(actionLabel, style: TextStyle(color: text)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, child) => AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.05),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: IgnorePointer(ignoring: !visible, child: child),
        ),
        child: NovelReaderTopBar(
          settings: _settings,
          bookTitle: _detail?.title ?? widget.title ?? '',
          chapterTitle: _chapter?.title ?? widget.chapterTitle ?? '',
          sourceName: _source?.name ?? '',
          onBack: () => Navigator.of(context).maybePop(),
          onDownload: () => unawaited(_downloadCurrentChapter()),
          onRefresh: () => unawaited(_refreshCurrentChapter()),
          onSwitchSource: () => unawaited(_openSourceSwitch()),
          onMore: () => unawaited(_openMore()),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(int pageCount) {
    final bottom = _settings.showFooter
        ? _footerHeight + MediaQuery.paddingOf(context).bottom
        : 8 + MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom,
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, child) => AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.1),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: IgnorePointer(ignoring: !visible, child: child),
        ),
        child: ValueListenableBuilder<double>(
          valueListenable: _scrollRatio,
          builder: (context, _, __) => NovelReaderBottomPanel(
            settings: _settings,
            brightness: _settings.dimBrightness.toDouble(),
            onBrightnessChanged: _setBrightness,
            showAutoBrightness: _supportsAutoBrightness,
            autoBrightness: _settings.autoBrightness,
            onToggleAutoBrightness: _toggleAutoBrightness,
            page: _currentPage(pageCount),
            pageCount: pageCount,
            onSeekPage: _seekPage,
            onPrevChapter: () => unawaited(_previousChapter()),
            onNextChapter: () => unawaited(_nextChapter()),
            onSearch: () => unawaited(_openSearch()),
            onToggleAutoPage: _toggleAutoReading,
            onCatalog: () => unawaited(_openCatalog()),
            onTts: () => unawaited(_toggleTts()),
            onSettings: () => unawaited(_openSettings()),
            autoReading: _autoReading,
            speaking: _speaking,
          ),
        ),
      ),
    );
  }
}
