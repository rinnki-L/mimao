// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与小说其他页面同款说明。
/// 小说阅读器（沉浸式，对照「阅读（legado）」的界面与操作）。
///
/// 能力：
/// - 默认上下滚动，可切左右翻页；点中间显隐菜单，点左右翻页；
/// - 沉浸式全屏（Windows 隐藏标题栏/任务栏，Android 沉浸系统栏）；
/// - 顶部栏：缓存本章 / 刷新本章 / 换源 / 更多 + 当前书源名；
/// - 底部菜单：亮度滑杆、章节进度滑杆、书内搜索 / 自动翻页 / 目录 / 朗读 / 设置；
/// - 页脚：章节名 + 本章页码 + 全书百分比（滚动模式只显示百分比）；
/// - 阅读设置：字号、Ttf 字体、背景预设/自定义/夜间、行距段距边距、翻页动画；
/// - 章内位置落模块 kv（含字符偏移 locator），历史库仍记章级进度（双记账不变）；
/// - 相邻章预取 + 会话内 LRU：换章不白屏，加载失败保留当前正文；
/// - 分页在帧后调度，不再每帧在 build 里同步排版。
///
/// 路由参数：`bookId`、`title`、`author`、`sourceKey`、`bookUrl`、`chapterId`、
/// `chapterIndex`、`chapterUrl`、`chapterTitle`。缺目录时按 bookId 重新抓目录。
library;

import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_immersive.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_reader_chrome.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';
import 'package:mimao/novel/reader/novel_reader_fonts.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_reader_settings_sheet.dart';
import 'package:mimao/novel/reader/novel_search_sheet.dart';
import 'package:mimao/novel/reader/novel_source_switch_sheet.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';
import 'package:mimao/novel/reader/novel_tts.dart';
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

class _NovelReaderPageState extends State<NovelReaderPage>
    with WidgetsBindingObserver
    implements NovelClickActionHandler {
  static const double _contentTopGap = 12;
  static const double _contentBottomGap = 44;
  static const double _footerHeight = 26;

  /// 双栏列间距：分页与渲染必须用同一个值，否则列宽对不上会多折行。
  static const double _twoColumnGap = 32;

  NovelReaderSettings get _settings => _controller.settings;

  /// 页眉占用的高度（关闭时为 0），分页可用高度要扣掉。
  double get _headerBandHeight =>
      _settings.showHeader ? _settings.headerFontSize * 1.7 + 8 : 0;

  /// 页脚条实际高度（随独立字号增长，最小沿用旧 26）。
  double get _footerBandHeight => _settings.showFooter
      ? math.max(_footerHeight, _settings.footerFontSize * 1.5 + 16)
      : 0;

  static bool get _isTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// 自动亮度需要系统亮度接口（Android 侧后续接入 screen_brightness）；
  /// 桌面端没有可靠接口，隐藏该按钮，亮度用遮罩滑杆。
  static bool get _supportsAutoBrightness => !kIsWeb && Platform.isAndroid;

  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'novel-reader');
  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _scrollRatio = ValueNotifier<double>(0);
  final Stopwatch _session = Stopwatch();
  final Map<int, GlobalKey> _paragraphKeys = <int, GlobalKey>{};

  late final NovelReaderController _controller;

  int _lastEpoch = -1;
  bool _restoreScheduled = false;

  bool _autoReading = false;
  Timer? _autoTimer;
  bool _appPaused = false;

  NovelTtsEngine? _tts;
  bool _speaking = false;
  bool _ensuringTts = false;
  int _ttsParagraph = 0;

  int? _highlightParagraph;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _controller = NovelReaderController(
      bookId: widget.bookId,
      title: widget.title,
      author: widget.author,
      sourceKey: widget.sourceKey,
      bookUrl: widget.bookUrl,
      chapterId: widget.chapterId,
      chapterIndex: widget.chapterIndex,
      chapterUrl: widget.chapterUrl,
      chapterTitle: widget.chapterTitle,
      coverUrl: widget.coverUrl,
      chapters: widget.chapters,
      onlineEngine: widget.onlineEngine,
      sourceStore: widget.sourceStore,
      history: widget.history,
      prefs: widget.prefs,
      replaceRules: widget.replaceRules,
      settingsStore: widget.settingsStore,
    );
    _controller.addListener(_onControllerChanged);
    _scroll.addListener(_onScroll);
    _session.start();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.init());
    // 导入字体要在首帧前尽量注册好；失败也不阻塞阅读（回退系统字体）。
    unawaited(NovelFontRegistry.instance.loadAll());
    unawaited(NovelImmersive.enter());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTimer?.cancel();
    _highlightTimer?.cancel();
    _flushReadingTime();
    unawaited(_controller.savePositionNow());
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _scrollRatio.dispose();
    _chromeVisible.dispose();
    _focus.dispose();
    unawaited(_stopTts());
    unawaited(NovelImmersive.exit());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appPaused = true;
        _autoTimer?.cancel();
        _autoTimer = null;
        _flushReadingTime();
        unawaited(_stopTts());
      case AppLifecycleState.resumed:
        _appPaused = false;
        _session.start();
        if (_autoReading) _startAutoTimer();
      case AppLifecycleState.inactive:
        // 桌面上切换窗口会频繁出现 inactive，不当作后台。
        break;
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final epoch = _controller.contentEpoch;
    final changed = epoch != _lastEpoch;
    if (changed) {
      // 换章时先把本章已读时长结掉，再重置计时；否则章与章之间的时间会被
      // reset() 静默丢弃（旧实现只在退页面/切后台才 flush）。首章没有上一段
      // 可结，跳过。
      if (_lastEpoch >= 0) _flushReadingTime();
      _lastEpoch = epoch;
      _paragraphKeys.clear();
      _session
        ..reset()
        ..start();
      _highlightParagraph = null;
      unawaited(_stopTts());
    }
    setState(() {});
    if (!_restoreScheduled) {
      _restoreScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScheduled = false;
        if (mounted) _handleScrollRestore(resetToTop: changed);
      });
    }
  }

  /// 滚动模式的落位：新章先回顶，再按 locator / 比例 / atEnd 还原。
  /// 翻页模式的落位在控制器排版完成时直接算好 pageIndex。
  void _handleScrollRestore({required bool resetToTop}) {
    if (_controller.settings.pageMode != NovelPageMode.scroll) return;
    if (!_scroll.hasClients) return;
    if (resetToTop) _scroll.jumpTo(0);
    final restore = _controller.takeScrollRestore();
    if (restore == null) return;
    if (restore.atEnd) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      return;
    }
    final position = restore.position;
    if (position == null) return;
    final locator = position.locator;
    if (locator != null &&
        !locator.isTitle &&
        locator.chapterIndex == (_controller.chapter?.index ?? -1)) {
      _jumpToParagraph(locator.paragraph, locator.charOffset);
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(
      (position.scrollRatio.clamp(0.0, 1.0) * max).clamp(0.0, max),
    );
  }

  GlobalKey _paragraphKey(int paragraph) =>
      _paragraphKeys.putIfAbsent(paragraph, GlobalKey.new);

  void _jumpToParagraph(int paragraph, [int charOffset = 0]) {
    final key = _paragraphKey(paragraph);
    final target = key.currentContext;
    if (target != null) {
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    // 段落还没被 ListView 构建：先按段落比例粗定位，再在下一帧精确定位。
    if (_scroll.hasClients) {
      final total = _controller.content?.paragraphs.length ?? 1;
      final max = _scroll.position.maxScrollExtent;
      final ratio = total <= 1 ? 0.0 : paragraph / total;
      _scroll.jumpTo((ratio * max).clamp(0.0, max));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final built = key.currentContext;
      if (built == null) return;
      unawaited(
        Scrollable.ensureVisible(
          built,
          alignment: 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  int _visibleParagraph() {
    final top =
        MediaQuery.paddingOf(context).top +
        _contentTopGap +
        _headerBandHeight +
        12;
    var result = 0;
    for (final entry in _paragraphKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= top && entry.key >= result) result = entry.key;
    }
    return result;
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
    _controller.onScroll(
      ratio,
      visibleParagraph: _controller.settings.pageMode == NovelPageMode.scroll
          ? _visibleParagraph()
          : null,
    );
  }

  Future<void> _flushReadingTime() async {
    if (!_session.isRunning) return;
    _session.stop();
    final elapsed = _session.elapsed;
    if (elapsed.inSeconds <= 0) return;
    try {
      await widget.stats?.addReadingTime(elapsed);
    } on Object {
      // 统计失败不影响阅读。
    }
  }

  // ── 章节切换 ──────────────────────────────────────────────────────────
  Future<void> _nextChapter() => _controller.nextChapter();

  Future<void> _previousChapter({bool atEnd = false}) =>
      _controller.previousChapter(atEnd: atEnd);

  /// 双栏时分屏：标题页独占一屏，其余两列一屏；单栏时一页一屏。
  List<List<int>> _spreads(List<NovelTextPage> pages) {
    if (_controller.layoutColumns != 2 || pages.isEmpty) {
      return <List<int>>[
        for (var i = 0; i < pages.length; i++) <int>[i],
      ];
    }
    final result = <List<int>>[];
    var i = 0;
    while (i < pages.length) {
      if (pages[i].hasTitle) {
        result.add(<int>[i]);
        i += 1;
      } else {
        result.add(<int>[i, if (i + 1 < pages.length) i + 1]);
        i += 2;
      }
    }
    return result;
  }

  int _spreadIndexFor(List<List<int>> spreads, int pageIndex) {
    for (var i = 0; i < spreads.length; i++) {
      if (spreads[i].contains(pageIndex)) return i;
    }
    return spreads.isEmpty ? 0 : pageIndex.clamp(0, spreads.length - 1);
  }

  /// 屏幕上的页码/页数（双栏时按「屏」而不是按「列」计）。
  int _displayPageCount(int rawPageCount) {
    if (_controller.layoutColumns != 2) return rawPageCount;
    final pages = _controller.pages;
    if (pages.isEmpty) return rawPageCount;
    return _spreads(pages).length;
  }

  int _displayPage(int rawPageCount) {
    if (_controller.layoutColumns != 2) {
      return _controller.currentPage(rawPageCount);
    }
    final pages = _controller.pages;
    if (pages.isEmpty) return 1;
    final spreads = _spreads(pages);
    return _spreadIndexFor(spreads, _controller.pageIndex) + 1;
  }

  void _seekDisplayPage(int page) {
    if (_controller.layoutColumns != 2) {
      _controller.seekPage(page);
      return;
    }
    final pages = _controller.pages;
    if (pages.isEmpty) return;
    final spreads = _spreads(pages);
    final index = (page - 1).clamp(0, spreads.length - 1);
    _controller.setPageIndex(spreads[index].first);
  }

  void _turnPage(int direction) {
    final settings = _controller.settings;
    if (!_controller.settingsReady || _controller.content == null) return;
    if (settings.pageMode == NovelPageMode.page) {
      final pages = _controller.pages;
      if (pages.isEmpty) return;
      if (_controller.layoutColumns == 2) {
        final spreads = _spreads(pages);
        final current = _spreadIndexFor(spreads, _controller.pageIndex);
        final next = current + direction;
        if (next < 0) {
          unawaited(_previousChapter(atEnd: true));
          return;
        }
        if (next >= spreads.length) {
          unawaited(_nextChapter());
          return;
        }
        _controller.setPageIndex(spreads[next].first, direction: direction);
        unawaited(_controller.savePositionNow());
        return;
      }
      final next = _controller.pageIndex + direction;
      if (next < 0) {
        unawaited(_previousChapter(atEnd: true));
        return;
      }
      if (next >= pages.length) {
        unawaited(_nextChapter());
        return;
      }
      _controller.setPageIndex(next, direction: direction);
      unawaited(_controller.savePositionNow());
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

  void _scrollToEdge(double ratio) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    unawaited(
      _scroll.animateTo(
        (ratio * max).clamp(0.0, max),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      ),
    );
  }

  void _toggleChrome() {
    _chromeVisible.value = !_chromeVisible.value;
  }

  /// 正文手势外壳：点按九宫格 / 长按 / 双击都挂在这里。
  ///
  /// 注意两点（都是回归过的坑）：
  /// - 不能盖一层全屏热区：手势必须在正文子树里，章末按钮、选中文字才抢得到；
  /// - 长按默认（[NovelLongPressAction.selectText]）不注册 `onLongPressStart`，
  ///   否则会和 [SelectionArea] 抢手势；配置成别的动作时才接管。
  /// - 双击默认「无」时不注册 `onDoubleTap`，否则单击要多等一个双击超时才响应。
  Widget _buildGestureLayer({
    required Widget child,
    required bool selectable,
    GestureDragEndCallback? onHorizontalDragEnd,
  }) {
    final settings = _controller.settings;
    final takesLongPress =
        settings.longPressAction != NovelLongPressAction.selectText;
    final takesDoubleTap =
        settings.doubleTapAction != NovelDoubleTapAction.none;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // 横滑与点按放同一个 GestureDetector：竞技场里拖拽赢了就取消点按，
        // 两者不会同时触发（旧实现也是这么叠的，行为不变）。
        final layer = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapAt(details, size),
          onLongPressStart: takesLongPress ? _handleLongPressAt : null,
          onDoubleTap: takesDoubleTap ? _handleDoubleTap : null,
          onHorizontalDragEnd: onHorizontalDragEnd,
          child: child,
        );
        // SelectionArea 在更外层：手势层比它深，点按/长按才归我们；
        // 默认选文时长按不注册，手势仍落回 SelectionArea。
        return selectable ? SelectionArea(child: layer) : layer;
      },
    );
  }

  /// 点按分区挂在正文手势上，而不是盖一层全屏热区。
  ///
  /// 旧实现的热区在正文之上，会把章末「下一章」按钮和选文长按一起吃掉；
  /// 现在由正文自己识别 3×3 九宫格，按钮等更深的手势优先。
  /// 每格动作来自设置（[NovelReaderSettings.clickZones]），默认只开中间一行：
  /// 左 = 上一页、中 = 菜单、右 = 下一页，上/下两行无动作。
  void _handleTapAt(TapUpDetails details, Size size) {
    if (!_controller.settingsReady) return;
    final zone = clickZoneAt(
      details.localPosition.dx,
      details.localPosition.dy,
      size.width,
      size.height,
    );
    dispatchClickAction(_controller.settings.clickZoneAction(zone), this);
  }

  /// 长按：只有配置成非「选文」时才接管，否则不注册手势，
  /// 让 [SelectionArea] 自己处理（回归：选文长按仍可用）。
  void _handleLongPressAt(LongPressStartDetails details) {
    if (!_controller.settingsReady) return;
    dispatchLongPressAction(_controller.settings.longPressAction, this);
  }

  void _handleDoubleTap() {
    if (!_controller.settingsReady) return;
    dispatchDoubleTapAction(_controller.settings.doubleTapAction, this);
  }

  // ── 点击动作执行器（NovelClickActionHandler） ─────────────────────────
  @override
  void openMenu() => _toggleChrome();

  @override
  void turnPreviousPage() => _turnPage(-1);

  @override
  void turnNextPage() => _turnPage(1);

  @override
  void openPreviousChapter() => unawaited(_previousChapter());

  @override
  void openNextChapter() => unawaited(_nextChapter());

  @override
  void toggleTts() => unawaited(_toggleTts());

  @override
  void toggleAutoPage() => _toggleAutoReading();

  @override
  void openCatalog() => unawaited(_openCatalog());

  @override
  void openSearch() => unawaited(_openSearch());

  // 下面四个动作在枚举里标了 requires，分发器不会调到；留实现只为接口完整，
  // 万一以后放开开关也有明确落点（不是静默无效）。
  @override
  void addBookmark() => _showSnack('书签功能还没做完，暂时不能从点击区添加');

  @override
  void openContentEdit() => _showSnack('正文编辑还没做完，暂时不能从点击区进入');

  @override
  void toggleReplace() => _showSnack('替换规则面板还没做完，暂时不能从点击区打开');

  @override
  void syncProgress() => _showSnack('WebDAV 同步还没接到阅读页，暂时不能手动同步');

  void _handleEscape() {
    if (_chromeVisible.value) {
      _chromeVisible.value = false;
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _refocusReader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  // ── 设置 ──────────────────────────────────────────────────────────────
  void _applySettings(NovelReaderSettings next) {
    final oldInterval = _controller.settings.autoPageSeconds;
    _controller.applySettings(next);
    if (_autoReading && next.autoPageSeconds != oldInterval) {
      _startAutoTimer();
    }
  }

  void _setBrightness(double value) {
    final current = _controller.settings;
    final next = current.copyWith(
      dimBrightness: value.round(),
      // 手动拖亮度即退出「跟随系统」。
      autoBrightness: false,
    );
    if (next.dimBrightness == current.dimBrightness &&
        !current.autoBrightness) {
      return;
    }
    _controller.applySettings(next);
  }

  int _dimBeforeAuto = 100;

  void _toggleAutoBrightness() {
    final current = _controller.settings;
    final turningOn = !current.autoBrightness;
    if (turningOn) _dimBeforeAuto = current.dimBrightness;
    _controller.applySettings(
      current.copyWith(
        autoBrightness: turningOn,
        dimBrightness: turningOn ? 100 : _dimBeforeAuto,
      ),
    );
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
    if (_controller.content == null) {
      _showSnack('正文还没加载完，暂时不能自动翻页');
      return;
    }
    setState(() => _autoReading = true);
    _startAutoTimer();
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(
      Duration(seconds: _controller.settings.autoPageSeconds),
      (_) {
        if (!mounted || !_autoReading || _appPaused) return;
        _turnPage(1);
      },
    );
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
    final content = _controller.content;
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
    if (_controller.settings.pageMode == NovelPageMode.page) {
      final pages = _controller.pages;
      if (pages.isEmpty) return 0;
      final index = _controller.pageIndex.clamp(0, pages.length - 1);
      for (final slice in pages[index].slices) {
        if (!slice.isTitle) return slice.paragraph;
      }
      return 0;
    }
    return _visibleParagraph();
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
    final rawPageCount = _controller.pages.isEmpty
        ? 1
        : _controller.pages.length;
    final pageCount = _displayPageCount(rawPageCount);
    final pageMode = _controller.settings.pageMode == NovelPageMode.page;
    final page = _displayPage(rawPageCount);
    final info = NovelReaderBookInfo(
      bookTitle: _controller.detail?.title ?? widget.title ?? '',
      author: _controller.detail?.author ?? widget.author ?? '',
      sourceName: _controller.source?.name ?? '',
      chapterTitle: _controller.chapter?.title ?? '',
      chapterIndex: (_controller.chapter?.index ?? 0) + 1,
      chapterCount: _controller.detail?.chapters.length ?? 0,
      page: page,
      pageCount: pageCount,
      percent: _controller.bookPercent(
        page: pageMode ? page : null,
        pageCount: pageMode ? pageCount : null,
      ),
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
            initial: _controller.settings,
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
      _refocusReader();
    }
  }

  Future<void> _openCatalog() async {
    _pauseAutoForSheet();
    final detail = _controller.detail;
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
          currentIndex: _controller.chapter?.index ?? 0,
          settings: _controller.settings,
          onPick: (index) => Navigator.of(sheetContext).pop(index),
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
      _refocusReader();
    }
    if (picked != null && mounted && picked < detail.chapters.length) {
      final target = detail.chapters[picked];
      if (!target.isVolume) await _controller.openChapter(target);
    }
  }

  Future<void> _openSearch() async {
    _pauseAutoForSheet();
    final engine = widget.onlineEngine;
    final source = _controller.source;
    final detail = _controller.detail;
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
          currentChapterIndex: _controller.chapter?.index ?? 0,
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
            unawaited(_jumpToHit(chapterIndex, paragraph, 0, titles));
          },
          onPickHit: (hit) {
            unawaited(
              _jumpToHit(
                hit.chapterIndex,
                hit.paragraph,
                hit.charOffset,
                titles,
              ),
            );
          },
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
      _refocusReader();
    }
  }

  Future<void> _jumpToHit(
    int chapterIndex,
    int paragraph,
    int charOffset,
    List<String> titles,
  ) async {
    final detail = _controller.detail;
    if (detail == null ||
        chapterIndex < 0 ||
        chapterIndex >= detail.chapters.length) {
      return;
    }
    final chapter = detail.chapters[chapterIndex];
    if (chapter.isVolume) return;
    await _controller.jumpToLocator(
      NovelLocator(
        chapterIndex: chapterIndex,
        paragraph: paragraph,
        charOffset: charOffset,
        sourceKey: detail.ref.sourceKey,
      ),
    );
    if (!mounted) return;
    // 跨章跳转时正文 epoch 会变，等高亮要放在跳转之后，否则会被清掉。
    _highlightTimer?.cancel();
    setState(() => _highlightParagraph = paragraph);
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightParagraph = null);
    });
  }

  Future<void> _openSourceSwitch() async {
    _pauseAutoForSheet();
    final engine = widget.onlineEngine;
    final store = widget.sourceStore;
    final detail = _controller.detail;
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
          currentSourceKey: _controller.source?.key ?? '',
          sources: sources,
          engine: engine,
        ),
      ),
    );
    if (mounted) {
      _chromeVisible.value = true;
      _resumeAutoFromSheet();
      _refocusReader();
    }
    if (hit == null || !mounted) return;
    try {
      await _controller.switchSource(hit.source, hit.book);
      if (mounted) _showSnack('已切换到「${hit.source.name}」');
    } on Object catch (error) {
      if (mounted) _showSnack('换源失败：$error');
    }
  }

  // ── 缓存 / 更多 ───────────────────────────────────────────────────────
  Future<void> _downloadCurrentChapter() async {
    final engine = widget.onlineEngine;
    final source = _controller.source;
    final detail = _controller.detail;
    final chapter = _controller.chapter;
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
    final chapter = _controller.chapter;
    if (chapter == null) return;
    await _controller.refreshCurrentChapter();
  }

  Future<void> _cacheWholeBook() async {
    final engine = widget.onlineEngine;
    final source = _controller.source;
    final detail = _controller.detail;
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
      _refocusReader();
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
    final detail = _controller.detail;
    if (detail == null) return;
    final rawPageCount = _controller.pages.isEmpty
        ? 1
        : _controller.pages.length;
    final pageCount = _displayPageCount(rawPageCount);
    final pageMode = _controller.settings.pageMode == NovelPageMode.page;
    final page = _displayPage(rawPageCount);
    final rows = <(String, String)>[
      ('书名', detail.title),
      ('作者', detail.author.isEmpty ? '—' : detail.author),
      ('书源', _controller.source?.name ?? '—'),
      (
        '章节',
        '${(_controller.chapter?.index ?? 0) + 1} / ${detail.chapters.length}',
      ),
      if (pageMode) ('本章页码', '$page / $pageCount'),
      (
        '全书进度',
        '${_controller.bookPercent(page: pageMode ? page : null, pageCount: pageMode ? pageCount : null).toStringAsFixed(1)}%',
      ),
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
    _refocusReader();
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
      brightness: _controller.settings.darkBackground
          ? Brightness.dark
          : Brightness.light,
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
    final settings = _controller.settings;
    final background = novelReaderBackgroundColor(settings);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _turnPage(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _turnPage(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _turnPage(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _turnPage(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _turnPage(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _turnPage(1),
        const SingleActivator(LogicalKeyboardKey.home): () => _scrollToEdge(0),
        const SingleActivator(LogicalKeyboardKey.end): () => _scrollToEdge(1),
        const SingleActivator(LogicalKeyboardKey.space): _toggleAutoReading,
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: background,
          body: !_controller.settingsReady
              ? Center(
                  child: CircularProgressIndicator(
                    color: novelReaderTextColor(settings),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width =
                        (constraints.maxWidth - settings.horizontalPadding * 2)
                            .clamp(80.0, double.infinity);
                    final height =
                        (constraints.maxHeight -
                                insets.top -
                                _contentTopGap -
                                _headerBandHeight -
                                insets.bottom -
                                math.max(_contentBottomGap, _footerBandHeight))
                            .clamp(80.0, double.infinity);
                    _controller.updateLayout(
                      width: width,
                      height: height,
                      textScaler: MediaQuery.textScalerOf(context),
                      viewportWidth: constraints.maxWidth,
                      landscape:
                          MediaQuery.orientationOf(context) ==
                          Orientation.landscape,
                    );
                    final pages = _controller.pages;
                    final pageCount = pages.isEmpty ? 1 : pages.length;
                    final displayPageCount = _displayPageCount(pageCount);
                    final displayPage = _displayPage(pageCount);
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (settings.backgroundImagePath != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: settings.backgroundImageOpacity / 100,
                                child: Image.file(
                                  File(settings.backgroundImagePath!),
                                  fit: novelBackgroundBoxFit(
                                    settings.backgroundImageFit,
                                  ),
                                  alignment: novelBackgroundAlignment(
                                    settings.backgroundImageAlign,
                                  ),
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        if (settings.backgroundTexture !=
                            NovelBackgroundTexture.none)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: NovelBackgroundTexturePainter(
                                  texture: settings.backgroundTexture,
                                  color: novelReaderTextColor(settings),
                                ),
                              ),
                            ),
                          ),
                        _buildContent(insets, pages),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: const Color(0xFF000000).withValues(
                                alpha: 1 - settings.dimBrightness / 100,
                              ),
                            ),
                          ),
                        ),
                        if (settings.eyeProtection)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(color: Color(0x1AFFB74D)),
                            ),
                          ),
                        if (_controller.content != null &&
                            (_controller.pendingChapter != null ||
                                (_controller.loadingContent &&
                                    _controller.content != null))) ...<Widget>[
                          _buildChapterLoading(insets),
                        ] else if (_controller.content != null &&
                            _controller.loadError != null) ...<Widget>[
                          _buildChapterLoadError(insets),
                        ],
                        if (settings.showFooter)
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
                                  final pageMode =
                                      settings.pageMode == NovelPageMode.page;
                                  final page = displayPage;
                                  return NovelReaderFooter(
                                    settings: settings,
                                    chapterTitle: _controller.displayTitle(
                                      _controller.chapter?.title ??
                                          widget.chapterTitle ??
                                          '',
                                    ),
                                    bookTitle:
                                        _controller.detail?.title ??
                                        widget.title ??
                                        '',
                                    page: pageMode ? page : null,
                                    pageCount: pageMode
                                        ? displayPageCount
                                        : null,
                                    percent: _controller.bookPercent(
                                      page: pageMode ? page : null,
                                      pageCount: pageMode
                                          ? displayPageCount
                                          : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        if (settings.showHeader)
                          Positioned(
                            top: insets.top,
                            left: 0,
                            right: 0,
                            // 菜单展开时顶部栏占着这块，页眉让位，收起后再出现。
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _chromeVisible,
                              builder: (context, visible, child) =>
                                  AnimatedOpacity(
                                    opacity: visible ? 0 : 1,
                                    duration: const Duration(milliseconds: 160),
                                    child: child,
                                  ),
                              child: IgnorePointer(
                                child: NovelReaderHeader(
                                  settings: settings,
                                  chapterTitle: _controller.displayTitle(
                                    _controller.chapter?.title ??
                                        widget.chapterTitle ??
                                        '',
                                  ),
                                  bookTitle:
                                      _controller.detail?.title ??
                                      widget.title ??
                                      '',
                                  page: settings.pageMode == NovelPageMode.page
                                      ? displayPage
                                      : null,
                                  pageCount:
                                      settings.pageMode == NovelPageMode.page
                                      ? displayPageCount
                                      : null,
                                  percent: _controller.bookPercent(
                                    page:
                                        settings.pageMode == NovelPageMode.page
                                        ? displayPage
                                        : null,
                                    pageCount:
                                        settings.pageMode == NovelPageMode.page
                                        ? displayPageCount
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        _buildTopBar(),
                        _buildBottomPanel(displayPageCount),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildContent(EdgeInsets insets, List<NovelTextPage> pages) {
    if (_controller.loadingDetail) {
      return _centeredMessage('正在加载目录…');
    }
    if (_controller.content == null) {
      if (_controller.loadError != null) {
        return _centeredMessage(
          _controller.loadError!,
          actionLabel: '重试',
          onAction: () => unawaited(_controller.retry()),
        );
      }
      return _centeredMessage(_controller.loadingContent ? '正在加载正文…' : '暂无正文');
    }
    if (_controller.settings.pageMode == NovelPageMode.page) {
      if (pages.isEmpty) {
        return _centeredMessage(_controller.paginating ? '正在排版…' : '暂无正文');
      }
      return _buildPageMode(insets, pages);
    }
    return _buildScrollMode(insets);
  }

  Widget _buildScrollMode(EdgeInsets insets) {
    final content = _controller.content!;
    final body = _controller.bodyStyle();
    final title = _controller.titleStyle();
    final chapterTitle = _controller.displayTitle(
      content.title.isEmpty
          ? (_controller.chapter?.title ?? '')
          : content.title,
    );
    final paragraphs = content.paragraphs;
    final showTitle = chapterTitle.isNotEmpty;
    return _buildGestureLayer(
      selectable: true,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          unawaited(_controller.savePositionNow());
          return false;
        },
        child: ListView.builder(
          key: const Key('novel-reader-scroll'),
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            _controller.settings.horizontalPadding,
            insets.top + _contentTopGap + _headerBandHeight,
            _controller.settings.horizontalPadding,
            insets.bottom + math.max(_contentBottomGap, _footerBandHeight) + 16,
          ),
          itemCount: paragraphs.length + (showTitle ? 2 : 1),
          itemBuilder: (context, index) {
            if (showTitle && index == 0) {
              return Padding(
                padding: EdgeInsets.only(
                  top: _controller.settings.titleTopSpacing,
                  bottom: _controller.settings.titleBottomSpacing,
                ),
                child: _buildTitleWidget(
                  chapterTitle,
                  style: title,
                  align: _controller.titleTextAlign,
                ),
              );
            }
            final paragraph = index - (showTitle ? 1 : 0);
            if (paragraph < paragraphs.length) {
              return KeyedSubtree(
                key: _paragraphKey(paragraph),
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: paragraph == paragraphs.length - 1
                        ? 0
                        : _controller.settings.paragraphSpacing,
                  ),
                  child: _highlightParagraph == paragraph
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.18),
                            borderRadius: MimaoShapes.sm,
                          ),
                          child: _buildBodyText(
                            _controller.paragraphText(paragraph),
                            style: body,
                          ),
                        )
                      : _buildBodyText(
                          _controller.paragraphText(paragraph),
                          style: body,
                        ),
                ),
              );
            }
            return _buildChapterEnd();
          },
        ),
      ),
    );
  }

  /// 正文文字：开了下划线就走 [NovelUnderlinedText]（按行画、可延伸），
  /// 否则仍是普通 [Text]，两者行高一致（bodyStyle 不含 decoration）。
  Widget _buildBodyText(
    String text, {
    required TextStyle style,
    bool highlight = false,
  }) {
    final settings = _controller.settings;
    final background = highlight
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
        : null;
    if (settings.underlineStyle == NovelUnderlineStyle.none) {
      return Text(
        text,
        style: highlight ? style.copyWith(backgroundColor: background) : style,
        textAlign: _controller.bodyTextAlign,
        textHeightBehavior: _controller.textHeightBehavior,
      );
    }
    return NovelUnderlinedText(
      text: text,
      style: style,
      textAlign: _controller.bodyTextAlign,
      textHeightBehavior: _controller.textHeightBehavior,
      underlineStyle: settings.underlineStyle,
      thickness: settings.underlineThickness,
      spacing: settings.underlineSpacing,
      extend: settings.underlineExtend,
      backgroundColor: background,
    );
  }

  /// 章节标题：分段开启时「主标题 + 分隔符 + 副标题（缩小）」。
  Widget _buildTitleWidget(
    String title, {
    required TextStyle style,
    required TextAlign align,
  }) {
    final settings = _controller.settings;
    if (!settings.titleSegment) {
      return Text(title, style: style, textAlign: align);
    }
    final parts = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 1) {
      return Text(title, style: style, textAlign: align);
    }
    final tailStyle = style.copyWith(
      fontSize: style.fontSize == null
          ? null
          : style.fontSize! * settings.titleSegmentScale,
    );
    final spans = <InlineSpan>[TextSpan(text: parts.first, style: style)];
    for (var i = 1; i < parts.length; i++) {
      if (settings.titleSegmentDivider.isNotEmpty) {
        spans.add(
          TextSpan(text: settings.titleSegmentDivider, style: tailStyle),
        );
      }
      spans.add(TextSpan(text: parts[i], style: tailStyle));
    }
    return Text.rich(TextSpan(children: spans), textAlign: align);
  }

  Widget _buildChapterEnd() {
    final hasNext = _controller.hasNext;
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
              color: novelReaderSecondaryColor(_controller.settings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageMode(EdgeInsets insets, List<NovelTextPage> pages) {
    if (pages.isEmpty) return const SizedBox.shrink();
    final settings = _controller.settings;
    final spreads = _spreads(pages);
    final spreadIndex = _spreadIndexFor(spreads, _controller.pageIndex);
    final spread = spreads[spreadIndex];
    // 尊重系统「减少动态效果」：开了就一律无动画，哪怕设置里选了别的风格。
    final animationsOff = MediaQuery.disableAnimationsOf(context);
    final style = animationsOff
        ? NovelPageAnimStyle.none
        : settings.effectivePageAnimStyle;
    final duration = style == NovelPageAnimStyle.none
        ? Duration.zero
        : Duration(milliseconds: settings.pageAnimationMs);
    final page = KeyedSubtree(
      key: ValueKey<String>('spread-${_controller.chapter?.id}-$spreadIndex'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          settings.horizontalPadding,
          insets.top + _contentTopGap + _headerBandHeight,
          settings.horizontalPadding,
          insets.bottom + math.max(_contentBottomGap, _footerBandHeight),
        ),
        child: spread.length <= 1
            ? _buildPageBody(pages[spread[0]])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: _buildPageBody(pages[spread[0]])),
                  // 列间距必须与分页时的 columnGap 一致：这里少给宽度，
                  // 每列实际可用宽就比测量时窄，正文会多折一行把页撑破。
                  const SizedBox(width: _twoColumnGap),
                  Expanded(child: _buildPageBody(pages[spread[1]], column: 1)),
                ],
              ),
      ),
    );
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (event.scrollDelta.dy > 0) {
          _turnPage(1);
        } else if (event.scrollDelta.dy < 0) {
          _turnPage(-1);
        }
      },
      child: _buildGestureLayer(
        selectable: true,
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
            layoutBuilder: _pageSwitchLayoutBuilder(style),
            transitionBuilder: (child, animation) =>
                _pageTransition(style, child, animation),
            child: page,
          ),
        ),
      ),
    );
  }

  /// 翻页动画的层叠方式：覆盖/滚动类需要「新页盖住旧页」，其余并排堆叠。
  Widget Function(Widget?, List<Widget>) _pageSwitchLayoutBuilder(
    NovelPageAnimStyle style,
  ) {
    return (currentChild, previousChildren) => Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 覆盖/滚动/视差：旧页在下、新页在上，才能"压过去"。
        if (style == NovelPageAnimStyle.cover ||
            style == NovelPageAnimStyle.scroll ||
            style == NovelPageAnimStyle.parallax) ...<Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ] else ...<Widget>[
          if (currentChild != null) currentChild,
          ...previousChildren,
        ],
      ],
    );
  }

  /// 六种翻页过渡（卷曲/仿真翻页不做，设置里也不出现）。
  ///
  /// AnimatedSwitcher 的 `transitionBuilder` 只在建条目时调一次，之后条目被
  /// 缓存进 `_outgoingWidgets`，所以「这是入场帧还是退场帧」不能在这里读——
  /// 必须在 [AnimatedBuilder] 的 builder 里按 `animation.status` 实时判断，
  /// 否则旧页也会按入场方向动（覆盖/滚动类就变成两页同向滑）。
  ///
  /// 方向取自 [_controller.pageDirection]：`dir > 0` = 向后翻（新页从右侧进）。
  Widget _pageTransition(
    NovelPageAnimStyle style,
    Widget child,
    Animation<double> animation,
  ) {
    if (style == NovelPageAnimStyle.none) return child;
    final dir = _controller.pageDirection.toDouble();
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, inner) {
        final leaving = animation.status == AnimationStatus.reverse;
        final t = animation.value.clamp(0.0, 1.0);
        // 入场：从 dir 侧滑向 0；退场：从 0 滑向 -dir 侧。
        final sign = leaving ? -dir : dir;
        Widget translate(double fraction) => FractionalTranslation(
          translation: Offset(sign * fraction * (1 - t), 0),
          child: inner,
        );
        switch (style) {
          case NovelPageAnimStyle.none:
            return inner!;
          case NovelPageAnimStyle.fade:
            return Opacity(opacity: t, child: inner);
          case NovelPageAnimStyle.slide:
            return Opacity(
              opacity: t,
              child: FractionalTranslation(
                translation: Offset(sign * 0.12 * (1 - t), 0),
                child: inner,
              ),
            );
          case NovelPageAnimStyle.cover:
            // 新页整幅压过去，旧页原地不动。
            if (leaving) return inner!;
            return FractionalTranslation(
              translation: Offset(dir * (1 - t), 0),
              child: inner,
            );
          case NovelPageAnimStyle.scroll:
            // 新页整幅进、旧页退三分之一，叠出「纸在滑」的错位。
            return translate(leaving ? 0.35 : 1);
          case NovelPageAnimStyle.parallax:
            // 新页整幅进、旧页反向缓移（视差）。
            return translate(leaving ? 0.16 : 1);
        }
      },
    );
  }

  Widget _buildPageBody(NovelTextPage page, {int column = 0}) {
    final content = _controller.content;
    if (content == null) return const SizedBox.shrink();
    final body = _controller.bodyStyle();
    final titleStyle = _controller.titleStyle();
    final rawTitle = content.title.isEmpty
        ? (_controller.chapter?.title ?? '')
        : content.title;
    final chapterTitle = _controller.displayTitle(rawTitle);
    final children = <Widget>[];
    var afterTitle = false;
    int? previousParagraph;
    for (final slice in page.slices) {
      if (slice.isTitle) {
        final start = slice.start.clamp(0, chapterTitle.length);
        final end = slice.end.clamp(start, chapterTitle.length);
        if (end > start) {
          final isWholeTitle = start == 0 && end == chapterTitle.length;
          children.add(
            isWholeTitle
                ? _buildTitleWidget(
                    chapterTitle,
                    style: titleStyle,
                    align: _controller.titleTextAlign,
                  )
                : Text(
                    chapterTitle.substring(start, end),
                    style: titleStyle,
                    textAlign: _controller.titleTextAlign,
                  ),
          );
        }
        afterTitle = true;
        continue;
      }
      final full = _controller.paragraphText(slice.paragraph);
      final start = slice.start.clamp(0, full.length);
      final end = slice.end.clamp(start, full.length);
      if (afterTitle) {
        children.add(SizedBox(height: _controller.settings.titleBottomSpacing));
        afterTitle = false;
      } else if (previousParagraph != null &&
          previousParagraph != slice.paragraph) {
        children.add(SizedBox(height: _controller.settings.paragraphSpacing));
      }
      if (end > start) {
        final substring = full.substring(start, end);
        children.add(
          _buildBodyText(
            substring,
            style: body,
            highlight: _highlightParagraph == slice.paragraph,
          ),
        );
      }
      previousParagraph = slice.paragraph;
    }
    return ClipRect(
      key: Key('novel-reader-page-body${column == 0 ? '' : '-$column'}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// 换章加载条：正文还在，只在底部提示，不再整屏替换。
  Widget _buildChapterLoading(EdgeInsets insets) {
    final settings = _controller.settings;
    final target = _controller.pendingChapter;
    return Positioned(
      left: 16,
      right: 16,
      bottom:
          (settings.showFooter ? _footerBandHeight : 8) + insets.bottom + 16,
      child: IgnorePointer(
        child: Material(
          key: const Key('novel-reader-chapter-loading'),
          color: novelReaderPanelColor(settings),
          shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 8),
                Text(
                  target == null ? '正在刷新本章…' : '正在加载「${target.title}」…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: novelReaderSecondaryColor(settings),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChapterLoadError(EdgeInsets insets) {
    final settings = _controller.settings;
    return Positioned(
      left: 16,
      right: 16,
      bottom:
          (settings.showFooter ? _footerBandHeight : 8) + insets.bottom + 16,
      child: Material(
        color: novelReaderPanelColor(settings),
        shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '章节加载失败，当前页仍是上一章',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: novelReaderSecondaryColor(settings),
                  ),
                ),
              ),
              TextButton(
                key: const Key('novel-reader-chapter-retry'),
                onPressed: () => unawaited(_controller.retry()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centeredMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final text = novelReaderTextColor(_controller.settings);
    final secondary = novelReaderSecondaryColor(_controller.settings);
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
          settings: _controller.settings,
          bookTitle: _controller.detail?.title ?? widget.title ?? '',
          chapterTitle: _controller.chapter?.title ?? widget.chapterTitle ?? '',
          sourceName: _controller.source?.name ?? '',
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
    final settings = _controller.settings;
    final pageMode = settings.pageMode == NovelPageMode.page;
    final bottom = settings.showFooter
        ? _footerBandHeight + MediaQuery.paddingOf(context).bottom
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
          builder: (context, ratio, __) => NovelReaderBottomPanel(
            settings: settings,
            brightness: settings.dimBrightness.toDouble(),
            onBrightnessChanged: _setBrightness,
            showAutoBrightness: _supportsAutoBrightness,
            autoBrightness: settings.autoBrightness,
            onToggleAutoBrightness: _toggleAutoBrightness,
            page: pageMode ? _displayPage(pageCount) : 1,
            pageCount: pageMode ? pageCount : 1,
            onSeekPage: _seekDisplayPage,
            scrollMode: !pageMode,
            progress: ratio,
            onSeekProgress: (value) {
              if (!_scroll.hasClients) return;
              final max = _scroll.position.maxScrollExtent;
              unawaited(
                _scroll.animateTo(
                  (value * max).clamp(0.0, max),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                ),
              );
            },
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
