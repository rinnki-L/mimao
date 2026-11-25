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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/dict/novel_dict_rule.dart'
    show normalizeNovelDictWord;
import 'package:mimao/novel/dict/novel_dict_service.dart'
    show NovelDictLookup, NovelDictRuleStorage;
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_bookmarks_page.dart';
import 'package:mimao/novel/pages/novel_content_edit_page.dart';
import 'package:mimao/novel/pages/novel_dict_page.dart' show showNovelDictSheet;
import 'package:mimao/novel/pages/novel_highlight_rules_page.dart';
import 'package:mimao/novel/pages/novel_replace_editor_page.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_content_override_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rule_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rules.dart';
import 'package:mimao/novel/reader/novel_immersive.dart';
import 'package:mimao/novel/reader/novel_keyboard_assist.dart';
import 'package:mimao/novel/reader/novel_keyboard_hint_bar.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_menu_actions.dart';
import 'package:mimao/novel/reader/novel_platform.dart';
import 'package:mimao/novel/reader/novel_reader_chrome.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';
import 'package:mimao/novel/reader/novel_reading_clock.dart';
import 'package:mimao/novel/reader/novel_reader_fonts.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/reader/novel_reader_settings_sheet.dart';
import 'package:mimao/novel/reader/novel_search_sheet.dart';
import 'package:mimao/novel/reader/novel_selection_menu.dart';
import 'package:mimao/novel/reader/novel_source_switch_sheet.dart';
import 'package:mimao/novel/reader/novel_text_pagination.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/pages/novel_import_book_page.dart';
import 'package:mimao/novel/reader/novel_tts.dart';
import 'package:mimao/novel/reader/novel_tts_cache.dart';
import 'package:mimao/novel/reader/novel_tts_export.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';
import 'package:path/path.dart' as p;

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
    this.highlightRules,
    this.contentOverrides,
    this.settingsStore,
    this.bookmarks,
    this.dictRules,
    this.dictLookup,
    this.keyboardStore,
    this.initialLocator,
    this.ttsEngine,
    this.ttsCache,
    this.readingClock,
    this.localBooks,
    this.txtRules,
    this.localFileGate,
    this.initialTtsRate,
    this.initialTtsSleepTimer,
    this.platform,
  });

  final String bookId;
  final String? title;

  /// 本地书门面：文件被移动/删除时，「重新定位文件」要靠它把书指到新路径。
  /// 在线书不需要（null 即不显示该入口）。
  final NovelLocalBookStorage? localBooks;

  /// TXT 目录规则仓库：重新定位后若换了文件版本，重扫目录时用同一套规则。
  final NovelTxtRuleStorage? txtRules;

  /// 本地书文件选择缝；null 时导入页用 file_picker 生产实现。
  final NovelLocalFileGate? localFileGate;

  /// 验收/截图用：打开阅读器即套用的朗读语速与睡眠定时；生产调用不传。
  final double? initialTtsRate;
  final Duration? initialTtsSleepTimer;

  /// 平台能力（亮度/常亮/系统栏/方向/音量键）；null = 按运行环境自动解析。
  /// 测试注入 FakeNovelPlatform 断言调用序列。
  final NovelPlatform? platform;
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

  /// 高亮规则仓库；注入后正文按规则叠加颜色/装饰（不改排版）。
  final NovelHighlightRuleStorage? highlightRules;

  /// 单章本地覆盖仓库；注入后阅读器提供「正文编辑」。
  final NovelContentOverrideStorage? contentOverrides;

  /// 阅读设置存储（测试注入内存实现；生产由 prefs 构造）。
  final NovelReaderSettingsStore? settingsStore;

  /// 书签/划线门面；null 时阅读器不给书签入口。
  final NovelBookmarkApi? bookmarks;

  /// 词典规则仓库 + 查询服务；两者都注入时选区菜单才有「词典」。
  final NovelDictRuleStorage? dictRules;
  final NovelDictLookup? dictLookup;

  /// 键盘键位存储；null 时由 [prefs] 现建（测试可注入内存实现）。
  final NovelKeyboardAssistStore? keyboardStore;

  /// 从书签列表直接打开时带进来的落点；首章据此选章并跳过续读位置。
  final NovelLocator? initialLocator;

  /// 朗读后端注入缝；测试注入 fake，生产按平台自动创建。
  final NovelTtsEngine? ttsEngine;

  /// 朗读音频缓存（L2）；null = 不缓存。
  final NovelTtsCache? ttsCache;

  /// 阅读计时器；null = 真实 [Stopwatch]。测试注入可控实现来断言时长归属。
  final NovelReadingClock? readingClock;

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

  /// 自动亮度需要系统亮度接口；桌面端没有可靠接口，隐藏该按钮，亮度用遮罩滑杆。
  bool get _supportsAutoBrightness => _platform.supportsScreenBrightness;

  /// 桌面端才有实体键盘提示浮层的意义（手机一般不看）。
  static bool get _keyboardHintsSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 平台能力：生产按运行环境解析（桌面/测试拿到 no-op），测试可注入 fake。
  late final NovelPlatform _platform =
      widget.platform ??
      resolveNovelPlatform(
        volumeHooks: NovelVolumeHooks(
          onTurn: _onVolumeTurn,
          onInput: _onVolumeInput,
          onError: _onVolumeError,
        ),
      );

  /// 已下发到平台的状态快照，用来只对变化项发调用（每次 notify 都会 sync）。
  bool _appliedBrightnessKnown = false;
  double? _appliedBrightness;
  bool? _appliedKeepAwake;
  bool? _appliedHideStatusBar;
  bool? _appliedHideNavigationBar;
  NovelScreenOrientation? _appliedOrientation;
  bool? _appliedVolumeKeys;

  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'novel-reader');
  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _scrollRatio = ValueNotifier<double>(0);
  late final NovelReadingClock _session =
      widget.readingClock ?? StopwatchNovelReadingClock();
  final Map<int, GlobalKey> _paragraphKeys = <int, GlobalKey>{};

  late final NovelReaderController _controller;

  int _lastEpoch = -1;
  bool _restoreScheduled = false;

  bool _autoReading = false;
  Timer? _autoTimer;
  bool _appPaused = false;

  int? _highlightParagraph;
  Timer? _highlightTimer;

  /// 朗读跟随：上一段/上一状态，用于只在「段变了 / 刚开始读」时滚动一次，
  /// 避免每帧 notify 都把用户手动滚走的视口拽回来。
  int _lastTtsParagraph = -1;
  NovelTtsPlaybackState _lastTtsState = NovelTtsPlaybackState.idle;

  /// 导出朗读音频的进行/取消状态（同一时间只允许一个导出）。
  bool _exporting = false;
  bool _exportCancelled = false;

  /// 划线点击识别器：按 marking id 复用，切章/退出时统一 dispose。
  final Map<int, TapGestureRecognizer> _markingTaps =
      <int, TapGestureRecognizer>{};

  /// 每段的选区探针：SelectionArea 只暴露工具栏锚点（选中矩形可能塌缩成
  /// 一个点），拿不到真实字符区间；在每段 Text 外包一层 SelectionListener，
  /// 就能直接读到「这一段选中了 [start, end)」。
  ///
  /// 每个探针**自己**持有 notifier（不能按段号复用：ListView 回收/重建时
  /// 新旧两个 SelectionListener 可能短暂同时挂同一 notifier，Flutter 会断言）。
  final Map<Object, ({int paragraph, SelectionListenerNotifier notifier})>
  _selectionProbes =
      <Object, ({int paragraph, SelectionListenerNotifier notifier})>{};
  List<NovelMarking> _markingSnapshot = const <NovelMarking>[];

  /// 一次下拉只触发一次加/删书签，避免回弹期间连发。
  bool _swipeBookmarkFired = false;

  /// 键盘辅助：优先用注入的存储，否则按模块 kv 现建（测试可注入内存实现）。
  late final NovelKeyboardAssistStore _keyboardStore =
      widget.keyboardStore ?? NovelKeyboardAssistStore(widget.prefs);
  NovelKeyboardConfig _keyboardConfig = NovelKeyboardConfig.defaults;

  @override
  void initState() {
    super.initState();
    unawaited(
      _keyboardStore.load().then((config) {
        if (!mounted) return;
        setState(() => _keyboardConfig = config);
      }),
    );
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
      highlightRules: widget.highlightRules,
      contentOverrides: widget.contentOverrides,
      settingsStore: widget.settingsStore,
      bookmarks: widget.bookmarks,
      initialLocator: widget.initialLocator,
      ttsEngine: widget.ttsEngine,
      ttsCache: widget.ttsCache,
    );
    _controller.onTtsError = (error) {
      // 朗读中断不只弹 SnackBar：错误也进日志，便于排查后端（SAPI/音色/
      // 音频设备）问题。
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'mimao/novel/tts',
          context: ErrorDescription('朗读中断'),
        ),
      );
      if (!mounted) return;
      _showSnack('朗读中断：$error');
    };
    _controller.onTtsSleepTimerFired = () {
      if (!mounted) return;
      _showSnack('睡眠定时已到，朗读已停止');
    };
    _controller.addListener(_onControllerChanged);
    _scroll.addListener(_onScroll);
    // 首章正文还没回来就退出时，按路由参数里的章先归属（章号 0 起 → 1 起）。
    final initialChapterIndex = widget.chapterIndex;
    if (initialChapterIndex != null) {
      _readTarget = NovelReadTarget(
        bookId: widget.bookId,
        bookTitle: widget.title ?? '',
        chapterIndex: initialChapterIndex + 1,
        chapterName: widget.chapterTitle ?? '',
      );
    }
    _session.start();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      _controller.init().then((_) {
        if (!mounted) return;
        final rate = widget.initialTtsRate;
        if (rate != null) {
          _controller.applySettings(
            _controller.settings.copyWith(ttsRate: rate),
          );
        }
        final sleep = widget.initialTtsSleepTimer;
        if (sleep != null) _controller.setTtsSleepTimer(sleep);
      }),
    );
    // 导入字体要在首帧前尽量注册好；失败也不阻塞阅读（回退系统字体）。
    unawaited(NovelFontRegistry.instance.loadAll());
    // 系统栏先按「两根都隐藏」进（= 改造前的 immersiveSticky 观感），
    // 设置读盘完成后 _syncPlatformState 再按用户的独立开关纠正；
    // 不等设置能避免打开阅读页时闪一下系统栏。
    _appliedHideStatusBar = true;
    _appliedHideNavigationBar = true;
    unawaited(
      _platform.applySystemBars(hideStatusBar: true, hideNavigationBar: true),
    );
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
    _disposeMarkingTaps();
    _selectionProbes.clear();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _scrollRatio.dispose();
    _chromeVisible.dispose();
    _focus.dispose();
    unawaited(NovelImmersive.exit());
    // 还原亮度 / 常亮 / 系统栏 / 方向，并释放音量键租约。
    unawaited(_platform.dispose());
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
        unawaited(_controller.stopTts());
        // 进后台先放掉常亮，免得在后台还替用户挡休眠。
        unawaited(_platform.setKeepAwake(false));
      case AppLifecycleState.resumed:
        _appPaused = false;
        _session.start();
        if (_autoReading) _startAutoTimer();
        _syncPlatformState();
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
      // 换章时先把上一章已读时长结掉，再重置计时；否则章与章之间的时间会被
      // reset() 静默丢弃（旧实现只在退页面/切后台才 flush）。首章没有上一段
      // 可结，跳过。结算用的是 [_readTarget]（上一章），不是此刻的
      // `_controller.chapter`（已经指向新章）。
      if (_lastEpoch >= 0) _flushReadingTime();
      _lastEpoch = epoch;
      _readTarget = _targetFromController();
      _paragraphKeys.clear();
      _disposeMarkingTaps();
      _session
        ..reset()
        ..start();
      _highlightParagraph = null;
      // 朗读自己续章时不停读；用户手动换章（目录/上一章/换源）才停。
      if (!_controller.ttsAdvancingChapter) {
        unawaited(_controller.stopTts());
      }
      _lastTtsParagraph = _controller.ttsParagraph;
    }
    _markingSnapshot = List<NovelMarking>.of(_controller.chapterMarkings);
    setState(() {});
    final ttsState = _controller.ttsState;
    final ttsParagraph = _controller.ttsParagraph;
    final startedOrResumed =
        ttsState == NovelTtsPlaybackState.speaking &&
        _lastTtsState != NovelTtsPlaybackState.speaking;
    if (ttsState == NovelTtsPlaybackState.speaking &&
        (ttsParagraph != _lastTtsParagraph || startedOrResumed)) {
      _lastTtsParagraph = ttsParagraph;
      _followTtsParagraph(ttsParagraph);
    }
    _lastTtsState = ttsState;
    // 设置 / 朗读状态一变就重新对账平台状态（只对差异项发调用）。
    _syncPlatformState();
    if (!_restoreScheduled) {
      _restoreScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScheduled = false;
        if (mounted) _handleScrollRestore(resetToTop: changed);
      });
    }
  }

  // ── 平台能力（亮度 / 常亮 / 系统栏 / 方向 / 音量键） ─────────────────────
  /// 把「设置 + 当前阅读状态」折算成期望的平台状态，只对变化项下发调用。
  ///
  /// 由控制器通知（设置落盘 / 朗读状态）、自动翻页开关与回到前台驱动；
  /// 重复调用是安全的（内部与上次已下发的快照对比）。
  void _syncPlatformState() {
    if (!mounted || !_controller.settingsReady) return;
    final settings = _controller.settings;

    // 亮度：跟随系统（autoBrightness）或滑杆拉满 = 交还系统，其余按百分比真调。
    final brightness =
        !_platform.supportsScreenBrightness ||
            settings.autoBrightness ||
            settings.dimBrightness >= 100
        ? null
        : settings.dimBrightness / 100;
    if (!_appliedBrightnessKnown || brightness != _appliedBrightness) {
      _appliedBrightnessKnown = true;
      _appliedBrightness = brightness;
      unawaited(_platform.setBrightness(brightness));
    }

    final keepAwake =
        _platform.supportsKeepAwake &&
        settings.keepAwakeOnAutoPage &&
        (_autoReading || _controller.ttsSpeaking);
    if (keepAwake != _appliedKeepAwake) {
      _appliedKeepAwake = keepAwake;
      unawaited(_platform.setKeepAwake(keepAwake));
    }

    if (_platform.supportsSystemBars &&
        (settings.hideStatusBar != _appliedHideStatusBar ||
            settings.hideNavigationBar != _appliedHideNavigationBar)) {
      _appliedHideStatusBar = settings.hideStatusBar;
      _appliedHideNavigationBar = settings.hideNavigationBar;
      unawaited(
        _platform.applySystemBars(
          hideStatusBar: settings.hideStatusBar,
          hideNavigationBar: settings.hideNavigationBar,
        ),
      );
    }

    if (_platform.supportsOrientation &&
        settings.screenOrientation != _appliedOrientation) {
      _appliedOrientation = settings.screenOrientation;
      unawaited(_platform.setOrientation(settings.screenOrientation));
    }

    final volumeKeys = _platform.supportsVolumeKeys && settings.volumeKeys;
    if (volumeKeys != _appliedVolumeKeys) {
      _appliedVolumeKeys = volumeKeys;
      unawaited(_platform.setVolumeKeysEnabled(volumeKeys));
    }
  }

  /// 音量键：上 = 下一页、下 = 上一页（与点击区 / 方向键同一套语义）。
  void _onVolumeTurn(int direction) {
    if (!mounted) return;
    _turnPage(direction);
  }

  /// 音量键也重置自动翻页计时：刚手动翻过，别立刻又自动翻一次。
  void _onVolumeInput(bool forward) {
    if (_autoReading) _startAutoTimer();
  }

  void _onVolumeError(Object error, StackTrace stack) {
    // 音量键失效只影响翻页，不打断阅读；进日志便于排查原生侧。
    debugPrint('音量键翻页失败：$error');
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
    // 刷新本章时旧段落的 Element 可能已 deactivate；ensureVisible 会对它做
    // ancestor 查找并抛「deactivated widget」，所以先确认还挂在树上。
    if (target != null && target.mounted) {
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
      if (built == null || !built.mounted) return;
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

  /// 朗读跟随：把视口带到正在读的段落。
  ///
  /// 翻页模式直接对齐页码；滚动模式优先在当前已构建的段落上做
  /// ensureVisible（对齐到视口上部 1/3，前后文都留一点），没构建就退回
  /// 按段落比例粗定位。只在段落变化 / 开始朗读时调用，不跟每一帧。
  void _followTtsParagraph(int paragraph) {
    final content = _controller.content;
    if (content == null ||
        paragraph < 0 ||
        paragraph >= content.paragraphs.length) {
      return;
    }
    if (_controller.settings.pageMode == NovelPageMode.page) {
      if (_controller.syncPageToParagraph(paragraph)) setState(() {});
      return;
    }
    if (!_scroll.hasClients) return;
    final target = _paragraphKey(paragraph).currentContext;
    if (target != null && target.mounted) {
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: 0.3,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    _jumpToParagraph(paragraph);
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

  /// 本段计时归属的章节：换章前先按它结算，再把计时重置到新章。
  ///
  /// 不能在结算时读 `_controller.chapter`——`_applyContent` 先把 chapter 换成
  /// 新章、再 bump epoch、再 notify，等到这里已经指向新章了，那样每段时长都会
  /// 记到「下一章」头上。
  NovelReadTarget? _readTarget;

  Future<void> _flushReadingTime() async {
    if (!_session.isRunning) return;
    _session.stop();
    final elapsed = _session.elapsed;
    if (elapsed.inSeconds <= 0) return;
    try {
      await widget.stats?.addReadingTime(elapsed, target: _readTarget);
    } on Object {
      // 统计失败不影响阅读。
    }
  }

  /// 从控制器当前章重建归属（章号 +1 转成历史/统计的 1 起口径）。
  NovelReadTarget? _targetFromController() {
    final chapter = _controller.chapter;
    if (chapter == null) return null;
    return NovelReadTarget(
      bookId: widget.bookId,
      bookTitle:
          _controller.historyOverride?.title ??
          _controller.detail?.title ??
          widget.title ??
          '',
      chapterIndex: chapter.index + 1,
      chapterName: chapter.title,
    );
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

  /// 手动翻页：朗读开着时按设置暂停或跟随。
  ///
  /// - 默认「暂停」：避免朗读还在上一页、眼睛已经翻到下一页；
  /// - 「跟随」：把朗读位置挪到新页第一段，声音跟着视线走。
  void _turnPage(int direction, {bool manual = true}) {
    final settings = _controller.settings;
    final follow =
        manual &&
        _controller.ttsActive &&
        settings.ttsTurnPagePolicy == NovelTtsTurnPolicy.follow;
    if (manual && _controller.ttsActive && !follow) {
      _controller.pauseTts();
    }
    _turnPageCore(direction);
    if (follow) {
      if (settings.pageMode == NovelPageMode.page) {
        _controller.seekTtsToParagraph(_firstParagraphOnPage());
      } else {
        // 滚动模式的翻页是 240ms 动画；等视口落定再取「可见段」，
        // 否则会按旧视口把朗读拽回上一屏。
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 260), () {
            if (!mounted) return;
            _controller.seekTtsToParagraph(_visibleParagraph());
          }),
        );
      }
    }
  }

  void _turnPageCore(int direction) {
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
    bool selectionMenu = false,
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
        // 滚动模式挂自定义选区菜单；翻页模式保留系统菜单（翻页没有稳定的
        // 段落命中上下文，强上自定义菜单会破坏点按/翻页手势）。
        if (!selectable) return layer;
        return SelectionArea(
          contextMenuBuilder: selectionMenu ? _buildSelectionMenu : null,
          child: layer,
        );
      },
    );
  }

  /// 选区菜单：复制 / 划线 / 笔记 / 搜索。
  Widget _buildSelectionMenu(
    BuildContext context,
    SelectableRegionState state,
  ) {
    final range = _selectionRangeFromListeners();
    void dismiss() {
      state.hideToolbar();
      state.clearSelection();
    }

    String selectedText() =>
        range?.textFrom(
          _controller.paragraphText,
          indentLength: _controller.settings.indent.length,
        ) ??
        '';

    return buildNovelSelectionMenu(
      context: context,
      anchors: state.contextMenuAnchors,
      actions: NovelSelectionActions(
        canMark: range?.isSingleParagraph == true,
        onCopy: () {
          final text = selectedText();
          dismiss();
          unawaited(_copySelection(text));
        },
        onMark: () {
          final picked = range;
          dismiss();
          if (picked != null) {
            unawaited(_markSelection(picked, withNote: false));
          }
        },
        onNote: () {
          final picked = range;
          dismiss();
          if (picked != null) unawaited(_markSelection(picked, withNote: true));
        },
        onSearch: () {
          final text = selectedText().trim();
          dismiss();
          if (text.isNotEmpty) unawaited(_openSearch(initialQuery: text));
        },
        onDict: widget.dictRules == null || widget.dictLookup == null
            ? null
            : () {
                final text = selectedText().trim();
                dismiss();
                if (text.isNotEmpty) unawaited(_openDict(text));
              },
      ),
    );
  }

  /// 从每段的 [SelectionListener] 汇总选区。
  ///
  /// 只取「有实际选中内容」的段：同一段内 start<end；跨段时取最早一段的
  /// start 与最晚一段的 end。偏移减去段首缩进，与划线/书签锚点同口径。
  NovelTextSelectionRange? _selectionRangeFromListeners() {
    ({int paragraph, int offset})? start;
    ({int paragraph, int offset})? end;
    final indent = _controller.settings.indent.length;
    for (final entry in _selectionProbes.values) {
      final notifier = entry.notifier;
      if (!notifier.registered) continue;
      final range = notifier.selection.range;
      if (range == null) continue;
      final length = _controller.paragraphLength(entry.paragraph);
      final begin = (range.startOffset - indent).clamp(0, length);
      final finish = (range.endOffset - indent).clamp(0, length);
      if (finish <= begin) continue;
      if (start == null ||
          entry.paragraph < start.paragraph ||
          (entry.paragraph == start.paragraph && begin < start.offset)) {
        start = (paragraph: entry.paragraph, offset: begin);
      }
      if (end == null ||
          entry.paragraph > end.paragraph ||
          (entry.paragraph == end.paragraph && finish > end.offset)) {
        end = (paragraph: entry.paragraph, offset: finish);
      }
    }
    if (start == null || end == null) return null;
    final range = NovelTextSelectionRange(
      startParagraph: start.paragraph,
      startOffset: start.offset,
      endParagraph: end.paragraph,
      endOffset: end.offset,
    );
    return range.isValid ? range : null;
  }

  /// 给一段正文套上选区探针；探针进出时登记/注销自己的 notifier。
  /// 正在朗读的段落加一层底色（暂停时保留，表示「停在哪儿」）。
  ///
  /// [keySuffix] 用于翻页模式：同一段可能被切成多个 slice，键不能重复。
  Widget _withTtsHighlight(
    int paragraph,
    Widget child, {
    String keySuffix = '',
  }) {
    if (!_controller.ttsActive || _controller.ttsParagraph != paragraph) {
      return child;
    }
    // 阅读画布可能是深底也可能是浅底，而 ColorScheme 跟的是 app 主题，
    // 不跟阅读背景：深底用固定浅紫提亮、浅底用固定深紫压暗，两层都
    // 保证看得见（与播放页遮罩同属「覆盖在阅读画布上」的例外场景）。
    final color = _controller.settings.darkBackground
        ? const Color(0xFFB39DDB).withValues(alpha: 0.30)
        : const Color(0xFF6750A4).withValues(alpha: 0.16);
    return Container(
      key: Key('novel-tts-current-$paragraph$keySuffix'),
      decoration: BoxDecoration(color: color, borderRadius: MimaoShapes.sm),
      child: child,
    );
  }

  Widget _withSelectionListener(int paragraph, Widget child) {
    return _NovelSelectionProbe(
      paragraph: paragraph,
      onRegister: (token, notifier) =>
          _selectionProbes[token] = (paragraph: paragraph, notifier: notifier),
      onUnregister: (token) => _selectionProbes.remove(token),
      child: child,
    );
  }

  Future<void> _copySelection(String text) async {
    if (text.isEmpty) {
      _showSnack('没有可复制的文字');
      return;
    }
    await copyNovelSelection(text);
    _showSnack('已复制');
    _refocusReader();
  }

  /// 选区 → 划线/笔记。跨段（多段）选择在菜单里已置灰，这里再兜一次底。
  Future<void> _markSelection(
    NovelTextSelectionRange range, {
    required bool withNote,
  }) async {
    if (!range.isSingleParagraph) {
      _showSnack('跨段选择暂不支持划线，可以分段划或先复制');
      return;
    }
    final excerpt = range.textFrom(
      _controller.paragraphText,
      indentLength: _controller.settings.indent.length,
    );
    var style = _controller.lastMarkingStyle;
    var note = '';
    if (withNote) {
      final result = await showNovelMarkingEditor(
        context,
        excerpt: excerpt,
        initialStyle: style,
        theme: _sheetThemeData(),
      );
      if (result == null || !mounted) return;
      style = result.style;
      note = result.note;
    }
    final marking = await _controller.addMarking(
      paragraph: range.startParagraph,
      startOffset: range.startOffset,
      endOffset: range.endOffset,
      style: style,
      note: note,
    );
    if (!mounted) return;
    if (marking == null) {
      _showSnack('划线没保存成功；这段文字可能已被替换规则改动，刷新本章后再试');
      return;
    }
    _showSnack(withNote || note.isNotEmpty ? '笔记已保存' : '已划线，点划线可加备注');
    _refocusReader();
  }

  /// 点击已有划线：编辑样式/备注，或删除。
  Future<void> _openMarkingEditor(NovelMarking marking) async {
    final raw = _controller.paragraphText(marking.paragraph);
    final indent = _controller.settings.indent.length;
    final start = (marking.startOffset + indent).clamp(0, raw.length);
    final end = (marking.endOffset + indent).clamp(start, raw.length);
    final result = await showNovelMarkingEditor(
      context,
      excerpt: raw.substring(start, end),
      initialStyle: marking.style,
      initialNote: marking.note,
      editing: true,
      theme: _sheetThemeData(),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      final removed = await _controller.removeMarkingItem(marking);
      if (mounted) _showSnack(removed ? '已删除划线' : '删除失败，刷新本章后再试');
      return;
    }
    final updated = await _controller.updateMarking(
      marking,
      style: result.style,
      note: result.note,
    );
    if (mounted) {
      _showSnack(updated == null ? '划线保存失败' : '划线已更新');
    }
  }

  TapGestureRecognizer _markingTapFor(NovelMarking marking) {
    return _markingTaps.putIfAbsent(
      marking.id,
      () => TapGestureRecognizer()..onTap = () => _onMarkingTap(marking.id),
    );
  }

  void _onMarkingTap(int id) {
    for (final marking in _markingSnapshot) {
      if (marking.id == id) {
        unawaited(_openMarkingEditor(marking));
        return;
      }
    }
  }

  void _disposeMarkingTaps() {
    for (final recognizer in _markingTaps.values) {
      recognizer.dispose();
    }
    _markingTaps.clear();
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
  void addBookmark() => unawaited(_toggleBookmark());

  /// 加/删书签：同一段落位置再点即删。滚动模式用当前可见段，翻页模式用
  /// 当前页第一段——两者都是「用户正在看的那句话」的段索引。
  Future<void> _toggleBookmark({int? paragraph}) async {
    if (!_controller.bookmarksReady) {
      _showSnack('书签库还没接上，暂时不能加书签');
      return;
    }
    if (_controller.content == null) {
      _showSnack('正文还没加载完，稍后再试');
      return;
    }
    final target =
        paragraph ??
        (_controller.settings.pageMode == NovelPageMode.page
            ? _firstParagraphOnPage()
            : _visibleParagraph());
    final result = await _controller.toggleBookmarkAt(paragraph: target);
    if (!mounted) return;
    if (result == null) {
      _showSnack('书签操作失败，请重试');
      return;
    }
    _showSnack(result.removed ? '已删除这一处的书签' : '已加书签');
  }

  /// 本地书文件被移动/删除后的「重新定位」：进导入页的重新定位模式，
  /// 选好新文件后把这本书指过去，回来重新加载当前章（进度/书签都保留）。
  Future<void> _relocateLocalFile() async {
    final bookId = _controller.bookId;
    if (bookId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/import-book'),
        builder: (_) => NovelImportBookPage(
          localBooks: widget.localBooks,
          rules: widget.txtRules,
          fileGate: widget.localFileGate,
          relocateBookId: bookId,
        ),
      ),
    );
    if (!mounted) return;
    // 重新定位可能换了文件版本，重读目录并重开当前章。
    await _controller.retry();
  }

  /// 全书书签列表：pickMode 下点一条回本页，在同一个控制器里跳转。
  Future<void> _openBookmarks() async {
    if (!_controller.bookmarksReady) {
      _showSnack('书签库还没接上');
      return;
    }
    _pauseAutoForSheet();
    _chromeVisible.value = false;
    final picked = await Navigator.of(context).push<NovelBookmark>(
      MaterialPageRoute<NovelBookmark>(
        settings: const RouteSettings(name: 'novel/bookmarks'),
        builder: (_) => NovelBookmarksPage(
          bookmarks: widget.bookmarks,
          bookId: _controller.bookId,
          bookTitle: _controller.bookTitleNow,
          pickMode: true,
        ),
      ),
    );
    if (!mounted) return;
    _chromeVisible.value = true;
    _resumeAutoFromSheet();
    _refocusReader();
    if (picked != null) await _jumpToBookmark(picked);
  }

  Future<void> _jumpToBookmark(NovelBookmark bookmark) async {
    final ok = await _controller.jumpToBookmark(bookmark);
    if (!mounted) return;
    if (!ok) {
      _showSnack('这条书签在当前目录里找不到对应章节，可到书签列表删除后重新加');
      return;
    }
    if (bookmark.unresolved) {
      _showSnack('已按章标题重新定位；如果位置不对，可删除后重新加');
    }
    // 从书签回来先把菜单收掉：顶栏浮在正文上，跳转后第一段会被压住，
    // 用户看到的起点就不像「回到那句话」了。
    _chromeVisible.value = false;
    _highlightTimer?.cancel();
    setState(() => _highlightParagraph = bookmark.paragraph);
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightParagraph = null);
    });
  }

  @override
  void openContentEdit() => unawaited(_openContentEdit());

  @override
  void toggleReplace() => unawaited(_openReplaceRules());

  /// 正文编辑：把当前章正文交给编辑页，保存后控制器直接换成本地覆盖。
  Future<void> _openContentEdit() async {
    if (!_controller.contentOverrideReady) {
      _showSnack('正文编辑服务未启用，重启应用后再试');
      return;
    }
    if (_controller.content == null) {
      _showSnack('正文还没加载完，稍后再试');
      return;
    }
    _pauseAutoForSheet();
    _chromeVisible.value = false;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: 'novel/content-edit'),
        builder: (_) => NovelContentEditPage(controller: _controller),
      ),
    );
    if (!mounted) return;
    _chromeVisible.value = true;
    _resumeAutoFromSheet();
    _refocusReader();
    if (changed == true) _showSnack('已保存本地覆盖；下次打开这一章优先用它');
  }

  /// 替换规则面板：带当前书上下文与一段样例正文，保存后当前章按新规则重算。
  Future<void> _openReplaceRules() async {
    final store = widget.replaceRules;
    if (store == null) {
      _showSnack('替换规则仓库未启用，重启应用后再试');
      return;
    }
    _pauseAutoForSheet();
    _chromeVisible.value = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/replace-editor'),
        builder: (_) => NovelReplaceEditorPage(
          store: store,
          bookId: _controller.bookId,
          bookTitle: _controller.bookTitleNow,
          sourceKey: _controller.sourceKey ?? '',
          bookUrl: _controller.bookUrlNow,
          sampleText:
              _controller.rawContent?.paragraphs.join('\n') ??
              _controller.content?.paragraphs.join('\n') ??
              '',
          onHighlightRules: widget.highlightRules == null
              ? null
              : () => _openHighlightRules(),
        ),
      ),
    );
    if (!mounted) return;
    _chromeVisible.value = true;
    _resumeAutoFromSheet();
    _refocusReader();
    await _controller.reloadReplaceRules();
  }

  Future<void> _openHighlightRules() async {
    final store = widget.highlightRules;
    if (store == null) {
      _showSnack('高亮规则服务未启用，重启应用后再试');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/highlight-rules'),
        builder: (_) => NovelHighlightRulesPage(
          store: store,
          bookId: _controller.bookId,
          bookTitle: _controller.bookTitleNow,
        ),
      ),
    );
    if (!mounted) return;
    await _controller.reloadHighlightRules();
  }

  @override
  void syncProgress() => _showSnack('WebDAV 同步还没接到阅读页，暂时不能手动同步');

  void _handleEscape() {
    if (_chromeVisible.value) {
      _chromeVisible.value = false;
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// 实际生效的快捷键表：保留键（Home/End/Esc）固定，其余来自键盘辅助配置。
  ///
  /// 与改造前的差别只有「可配置」：默认配置就是原来那组方向键/翻页键/空格，
  /// 所以不动设置时行为不变。
  Map<ShortcutActivator, VoidCallback> _shortcutBindings() {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.home): () => _scrollToEdge(0),
      const SingleActivator(LogicalKeyboardKey.end): () => _scrollToEdge(1),
      const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
    };
    for (final binding in normalizedNovelKeyboardBindings(
      _keyboardConfig.bindings,
    )) {
      final activator = novelShortcutFor(binding.keys);
      if (activator == null) continue;
      bindings[activator] = () => dispatchClickAction(binding.action, this);
    }
    return bindings;
  }

  void _refocusReader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  // ── 设置 ──────────────────────────────────────────────────────────────
  /// 设置面板回调。[scope] 由面板的「只改这本 / 改全局」开关给出，
  /// 默认全局（与上游一致）。
  void _applySettings(
    NovelReaderSettings next, {
    NovelSettingsScope scope = NovelSettingsScope.global,
  }) {
    final oldInterval = _controller.settings.autoPageSeconds;
    _controller.applySettings(next, scope: scope);
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
    _syncPlatformState();
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(
      Duration(seconds: _controller.settings.autoPageSeconds),
      (_) {
        if (!mounted || !_autoReading || _appPaused) return;
        _turnPage(1, manual: false);
      },
    );
  }

  void _stopAutoReading() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (_autoReading && mounted) setState(() => _autoReading = false);
    _syncPlatformState();
  }

  // ── 朗读 ──────────────────────────────────────────────────────────────
  Future<void> _toggleTts() async {
    switch (_controller.ttsState) {
      case NovelTtsPlaybackState.speaking:
        _controller.pauseTts();
      case NovelTtsPlaybackState.paused:
        _controller.resumeTts();
      case NovelTtsPlaybackState.idle:
        if (_controller.content == null) {
          _showSnack('正文还没加载完，暂时不能朗读');
          return;
        }
        final ok = await _controller.startTts(
          fromParagraph: _firstParagraphOnPage(),
        );
        if (!ok && mounted) _showSnack('当前平台暂不支持朗读');
    }
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

  Future<void> _stopTts() => _controller.stopTts();

  /// 导出当前章/全书朗读音频：选目录 → 进度对话框可取消 → 完成提示路径。
  Future<void> _exportAudio({required bool wholeBook}) async {
    if (_exporting) return;
    final content = _controller.content;
    final detail = _controller.detail;
    if (content == null || detail == null) {
      _showSnack('正文和目录还没加载完，暂时不能导出');
      return;
    }
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: wholeBook ? '选择全书朗读音频的保存目录' : '选择本章朗读音频的保存目录',
    );
    if (!mounted || directory == null || directory.trim().isEmpty) return;
    final bookTitle = _exportFileSafe(
      detail.title.isEmpty ? (widget.title ?? '朗读') : detail.title,
    );
    final chapterTitle = _exportFileSafe(_controller.chapter?.title ?? '本章');
    final outputPath = p.join(
      directory,
      wholeBook ? '$bookTitle-全书.wav' : '$bookTitle-$chapterTitle.wav',
    );
    final total = wholeBook
        ? detail.chapters.where((chapter) => !chapter.isVolume).length
        : 1;
    _exporting = true;
    _exportCancelled = false;
    final progress = ValueNotifier<int>(0);
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(wholeBook ? '导出全书音频' : '导出本章音频'),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                LinearProgressIndicator(
                  value: total <= 0 ? null : (done / total).clamp(0.0, 1.0),
                ),
                const SizedBox(height: 12),
                Text('已合成 $done / $total 章'),
                const SizedBox(height: 6),
                Text(
                  outputPath,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('novel-tts-export-cancel'),
              onPressed: () {
                _exportCancelled = true;
                dialogOpen = false;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
    try {
      final result = await _controller.exportTtsAudio(
        outputPath: outputPath,
        wholeBook: wholeBook,
        onProgress: (done, _) => progress.value = done,
        isCancelled: () => _exportCancelled,
      );
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        _showSnack('已导出 ${result.paragraphs} 段：${result.path}');
      }
    } on NovelTtsExportCancelled {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) _showSnack('已取消导出');
    } on Object catch (error) {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) _showSnack('导出失败：$error');
    } finally {
      progress.dispose();
      _exporting = false;
      _exportCancelled = false;
    }
  }

  String _exportFileSafe(String raw) =>
      raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

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
            hasBookOverride: _controller.hasBookOverride,
            onChanged: _applySettings,
            onClearBookOverride: _controller.clearBookOverride,
            loadTtsVoices: _controller.availableTtsVoices,
            ttsSleepDeadline: _controller.ttsSleepDeadline,
            onTtsSleepTimerChanged: _controller.setTtsSleepTimer,
            loadTtsCacheStats: _controller.ttsCacheStats,
            onClearTtsCache: _controller.clearTtsCache,
            onExportChapterAudio: () => _exportAudio(wholeBook: false),
            onExportBookAudio: () => _exportAudio(wholeBook: true),
            platform: _platform,
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
          bookmarkedChapterIndexes: _controller.bookmarkedChapters,
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

  /// 选词 → 查词典：面板自己加载规则，改完词典页的规则下一次查词就生效。
  Future<void> _openDict(String text) async {
    final store = widget.dictRules;
    final lookup = widget.dictLookup;
    final word = normalizeNovelDictWord(text);
    if (store == null || lookup == null) {
      _showSnack('词典没有接入，暂时查不了');
      return;
    }
    if (word.isEmpty) {
      _showSnack('没选中可查的文字');
      return;
    }
    _pauseAutoForSheet();
    _chromeVisible.value = false;
    await showNovelDictSheet(
      context,
      word: word,
      store: store,
      lookup: lookup,
      theme: _sheetThemeData(),
    );
    if (!mounted) return;
    _chromeVisible.value = true;
    _resumeAutoFromSheet();
    _refocusReader();
  }

  Future<void> _openSearch({String initialQuery = ''}) async {
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
          initialQuery: initialQuery,
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
                key: const Key('novel-more-add-bookmark'),
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('加书签 / 删书签'),
                subtitle: const Text('存下当前段落；同一位置再点即删'),
                onTap: _controller.bookmarksReady
                    ? () => Navigator.of(sheetContext).pop('bookmark')
                    : null,
              ),
              ListTile(
                key: const Key('novel-more-bookmarks'),
                leading: const Icon(Icons.bookmark_border),
                title: const Text('全书书签'),
                subtitle: const Text('按章节查看、点按跳回'),
                onTap: () => Navigator.of(sheetContext).pop('bookmarks'),
              ),
              ListTile(
                key: const Key('novel-more-edit-content'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('正文编辑'),
                subtitle: Text(
                  _controller.chapterIsLocalOverride
                      ? '当前章是本地覆盖，可继续修改或恢复原样'
                      : '修改这一章正文，保存后下次打开优先用本地版',
                ),
                onTap: _controller.contentOverrideReady
                    ? () => Navigator.of(sheetContext).pop('contentEdit')
                    : null,
              ),
              ListTile(
                key: const Key('novel-more-replace'),
                leading: const Icon(Icons.find_replace),
                title: const Text('替换规则'),
                subtitle: const Text('新建/编辑规则，用样例正文实时预览'),
                onTap: widget.replaceRules == null
                    ? null
                    : () => Navigator.of(sheetContext).pop('replace'),
              ),
              ListTile(
                key: const Key('novel-more-highlight'),
                leading: const Icon(Icons.border_color_outlined),
                title: const Text('高亮规则'),
                subtitle: const Text('按正则给正文上色，可只对本书生效'),
                onTap: widget.highlightRules == null
                    ? null
                    : () => Navigator.of(sheetContext).pop('highlight'),
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
      case 'bookmark':
        await _toggleBookmark();
      case 'bookmarks':
        await _openBookmarks();
      case 'contentEdit':
        await _openContentEdit();
      case 'replace':
        await _openReplaceRules();
      case 'highlight':
        await _openHighlightRules();
      case 'info':
        await _showBookInfo();
      case 'settings':
        await _openSettings();
    }
  }

  /// 「更多动作」面板：底栏 / 浮动行按「每行几个 × 几行」放不下的动作收在这里。
  ///
  /// 只列真正被挤出去的那批，不是把三处菜单栏的全部动作再列一遍——
  /// 否则这个入口就变成「第二份底栏」，跟「放不下才出现」的语义不符。
  Future<void> _openMoreActions() async {
    final contextSnapshot = _menuActionContext;
    final settings = _controller.settings;
    final defs = <NovelMenuActionDef>[];
    void collectOverflow(List<NovelMenuButtonItem> items) {
      final actions = resolveNovelMenuActions(
        items: items,
        context: contextSnapshot,
      );
      final layout = layoutNovelMenuRows(
        actions: actions,
        itemsPerRow: settings.menuIconItemsPerRow,
        rowCount: settings.menuIconRowCount,
        showMore: true,
      );
      for (final def in layout.overflow) {
        if (!defs.any((existing) => existing.id == def.id)) defs.add(def);
      }
    }

    collectOverflow(settings.bottomBarMenu);
    collectOverflow(settings.floatingBarMenu);
    _pauseAutoForSheet();
    _chromeVisible.value = false;
    final picked = await showModalBottomSheet<NovelMenuActionDef>(
      context: context,
      backgroundColor: _sheetThemeData().colorScheme.surfaceContainerLow,
      showDragHandle: false,
      builder: (sheetContext) => _sheetTheme(
        SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (defs.isEmpty)
                ListTile(
                  key: const Key('novel-more-actions-empty'),
                  leading: const Icon(Icons.info_outline),
                  title: const Text('没有放不下的动作'),
                  subtitle: const Text(
                    '底栏与浮动行的动作都直接显示着；想收起来就去「阅读设置 → 菜单」把每行个数调小',
                  ),
                )
              else
                for (final def in defs)
                  ListTile(
                    key: Key('novel-more-action-${def.id}'),
                    leading: Icon(def.icon),
                    title: Text(def.label),
                    onTap: () => Navigator.of(sheetContext).pop(def),
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
    if (picked != null) _menuActionTap(picked)?.call();
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
      if (_controller.chapterIsLocalOverride) ('正文', '本地覆盖（更多 → 正文编辑可修改或恢复原样）'),
      if (_controller.sourceWarning != null)
        ('书源提示', _controller.sourceWarning!),
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
      bindings: _shortcutBindings(),
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
                        // Android 走真亮度（窗口亮度已经压暗）时不再叠遮罩，
                        // 否则等于双重压暗，且遮罩会把面板一起变灰。桌面端保留
                        // 遮罩滑杆（没有可靠的系统亮度接口）。
                        if (!_platform.usesRealBrightness)
                          Positioned.fill(
                            key: const Key('novel-reader-dim-overlay'),
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
                        if (_keyboardConfig.showHints &&
                            _keyboardHintsSupported)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: IgnorePointer(
                              child: NovelKeyboardHintBar(
                                bindings: _keyboardConfig.bindings,
                                foreground: novelReaderTextColor(settings),
                                muted: novelReaderSecondaryColor(settings),
                                background: background,
                              ),
                            ),
                          ),
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
      if (_controller.localFileMissingPath != null) {
        // 本地书文件被移动/删除：重试同一个路径没有意义，只给「重新定位」。
        return _centeredMessage(
          '${_controller.loadError}\n\n'
          '把文件放回原处，或重新选择它的新位置'
          '——阅读进度、书签与划线都会保留。',
          actionLabel: '重新定位文件',
          actionIcon: Icons.drive_file_move_outline,
          actionKey: const Key('novel-reader-relocate'),
          onAction: () => unawaited(_relocateLocalFile()),
        );
      }
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
      selectionMenu: true,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification) {
            _swipeBookmarkFired = false;
          }
          if (notification is ScrollEndNotification) {
            unawaited(_controller.savePositionNow());
          }
          // 顶部继续下滑加/删书签（默认关）：一次下拉只触发一次。
          if (_controller.settings.swipeDownBookmark &&
              notification is OverscrollNotification &&
              notification.overscroll < 0 &&
              !_swipeBookmarkFired) {
            _swipeBookmarkFired = true;
            unawaited(_toggleBookmark(paragraph: _visibleParagraph()));
          }
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
                  child: _withSelectionListener(
                    paragraph,
                    _withTtsHighlight(
                      paragraph,
                      _highlightParagraph == paragraph
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
                                paragraph: paragraph,
                              ),
                            )
                          : _buildBodyText(
                              _controller.paragraphText(paragraph),
                              style: body,
                              paragraph: paragraph,
                            ),
                    ),
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

  /// 正文文字：有划线/高亮就按区间切成 TextSpan（只加颜色/装饰/字重，
  /// 不改字号行高）；否则维持原来的普通 [Text] / 下划线渲染。
  ///
  /// [paragraph] 是这一段在章节里的下标，[sliceStart] 是这段文字在整段
  /// （含缩进）里的起点——翻页模式传切片起点，滚动模式恒为 0。
  Widget _buildBodyText(
    String text, {
    required TextStyle style,
    int? paragraph,
    int sliceStart = 0,
    bool highlight = false,
  }) {
    final settings = _controller.settings;
    final background = highlight
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
        : null;
    final markings = paragraph == null
        ? const <NovelMarking>[]
        : _controller.markingsOfParagraph(paragraph);
    final highlightSpans = paragraph == null
        ? const <NovelHighlightSpan>[]
        : matchNovelHighlights(
            _controller.paragraphText(paragraph),
            _controller.highlightRulesForBook,
            bookId: _controller.bookId,
            dark: settings.darkBackground,
          );
    if (markings.isNotEmpty || highlightSpans.isNotEmpty) {
      return _buildRichBodyText(
        text,
        style: style,
        markings: markings,
        highlights: highlightSpans,
        sliceStart: sliceStart,
        background: background,
      );
    }
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

  /// 高亮 + 划线合并渲染：按所有区间端点切段，每段分别套高亮样式与划线样式。
  ///
  /// 划线（用户手选）优先于高亮（规则）：同一段文字既被高亮命中又被划线时，
  /// 以划线的背景/装饰为准，避免规则把用户的标记盖掉。
  Widget _buildRichBodyText(
    String text, {
    required TextStyle style,
    required List<NovelMarking> markings,
    required List<NovelHighlightSpan> highlights,
    required int sliceStart,
    Color? background,
  }) {
    final indent = _controller.settings.indent.length;
    final boundaries = <int>{0, text.length};
    void addRange(int start, int end) {
      final localStart = (start - sliceStart).clamp(0, text.length);
      final localEnd = (end - sliceStart).clamp(0, text.length);
      if (localEnd <= localStart) return;
      boundaries
        ..add(localStart)
        ..add(localEnd);
    }

    for (final span in highlights) {
      addRange(span.start, span.end);
    }
    for (final marking in markings) {
      addRange(marking.startOffset + indent, marking.endOffset + indent);
    }
    final offsets = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < offsets.length - 1; i++) {
      final start = offsets[i];
      final end = offsets[i + 1];
      if (end <= start) continue;
      final global = sliceStart + start;
      var segmentStyle = style;
      final hit = highlightSpanAt(highlights, global);
      if (hit != null) {
        segmentStyle = segmentStyle.copyWith(
          color: hit.style.foreground,
          backgroundColor: hit.style.background,
          fontWeight: hit.style.bold ? MimaoFonts.bold : null,
          decoration: hit.style.underline ? TextDecoration.underline : null,
          decorationColor: hit.style.underline ? hit.style.foreground : null,
        );
      }
      NovelMarking? cover;
      for (final marking in markings.reversed) {
        final markStart = marking.startOffset + indent;
        final markEnd = marking.endOffset + indent;
        if (global >= markStart && global < markEnd) {
          cover = marking;
          break;
        }
      }
      TapGestureRecognizer? recognizer;
      if (cover != null) {
        segmentStyle = _markingTextStyle(segmentStyle, cover.style);
        recognizer = _markingTapFor(cover);
      }
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: segmentStyle,
          recognizer: recognizer,
        ),
      );
    }
    // 自定义下划线（NovelUnderlinedText）画不了区间样式；这里退回系统下划线，
    // 保证高亮命中时至少还有下划线，行高/字号不变。
    final baseStyle =
        _controller.settings.underlineStyle == NovelUnderlineStyle.none
        ? style
        : style.copyWith(decoration: TextDecoration.underline);
    return Text.rich(
      TextSpan(
        style: background == null
            ? baseStyle
            : baseStyle.copyWith(backgroundColor: background),
        children: spans,
      ),
      textAlign: _controller.bodyTextAlign,
      textHeightBehavior: _controller.textHeightBehavior,
    );
  }

  /// 划线只改装饰，不碰 fontSize/fontFamily/height：行高与未划线时完全一致。
  TextStyle _markingTextStyle(TextStyle base, NovelMarkingStyle marking) {
    final color = Color(marking.colorArgb);
    switch (marking.decoration) {
      case NovelMarkingDecoration.background:
        return base.copyWith(backgroundColor: color);
      case NovelMarkingDecoration.underline:
        return base.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: Color(marking.colorArgb | 0xFF000000),
          decorationThickness: 1.5,
        );
      case NovelMarkingDecoration.wavy:
        return base.copyWith(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: Color(marking.colorArgb | 0xFF000000),
          decorationThickness: 1.2,
        );
    }
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
          _withTtsHighlight(
            slice.paragraph,
            keySuffix: '$column-$start',
            _buildBodyText(
              substring,
              style: body,
              paragraph: slice.paragraph,
              sliceStart: start,
              highlight: _highlightParagraph == slice.paragraph,
            ),
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
              if (_controller.localFileMissingPath != null)
                TextButton(
                  key: const Key('novel-reader-chapter-relocate'),
                  onPressed: () => unawaited(_relocateLocalFile()),
                  child: const Text('重新定位文件'),
                )
              else
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
    IconData actionIcon = Icons.refresh,
    Key? actionKey,
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
                key: actionKey ?? const Key('novel-reader-retry'),
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18, color: text),
                label: Text(actionLabel, style: TextStyle(color: text)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 注册表里每个动作的可用性上下文：只跟这本书的类型与已落地能力有关。
  NovelMenuActionContext get _menuActionContext => NovelMenuActionContext(
    hasOnlineSource:
        _controller.source != null || (widget.sourceKey ?? '').isNotEmpty,
    // 书签库接上后加书签/书签列表按钮自动可用，用户不用重配菜单。
    bookmarkReady: _controller.bookmarksReady,
    contentEditReady: _controller.contentOverrideReady,
    replaceReady: widget.replaceRules != null,
    syncReady: false,
  );

  /// 菜单动作 → 页面方法。注册表只管「长什么样 + 能不能用」，
  /// 副作用入口集中在这里，别处不再各写一套 switch。
  ///
  /// 注意 [novelMenuActionSettings] 虽然在注册表里挂着
  /// [NovelClickAction.menu]（九宫格里的「菜单」是显隐浮层），
  /// 但菜单栏上的「阅读设置」必须打开设置面板——两者语义不同，
  /// 所以这里先按 id 特判，再落到点击区分发器。
  VoidCallback? _menuActionTap(NovelMenuActionDef def) {
    switch (def.id) {
      case novelMenuActionTts:
        // 菜单按钮开着时是「停止朗读」语义（图标/提示已换），不是暂停；
        // 暂停/继续留给点击区与快捷动作。
        return _controller.ttsActive
            ? () => unawaited(_stopTts())
            : () => unawaited(_toggleTts());
      case novelMenuActionSettings:
        return () => unawaited(_openSettings());
      case novelMenuActionDownload:
        return () => unawaited(_downloadCurrentChapter());
      case novelMenuActionRefresh:
        return () => unawaited(_refreshCurrentChapter());
      case novelMenuActionSwitchSource:
        return () => unawaited(_openSourceSwitch());
      case novelMenuActionMore:
        return () => unawaited(_openMore());
      case novelMenuActionMorePanel:
        return () => unawaited(_openMoreActions());
      case novelMenuActionBookmarkList:
        return () => unawaited(_openBookmarks());
    }
    final click = def.clickAction;
    if (click == null) return null;
    // 点击区动作复用同一个分发器：未实现/不可用的动作返回 false 不执行。
    if (!click.available) return null;
    return () => dispatchClickAction(click, this);
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
          onTap: _menuActionTap,
          actionContext: _menuActionContext,
        ),
      ),
    );
  }

  /// 浮动图标行：贴在底栏上方，配置为空时不占位。
  Widget _buildFloatingBar() {
    final settings = _controller.settings;
    if (settings.floatingBarMenu.every((item) => !item.enabled)) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerRight,
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, child) => AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.1),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: IgnorePointer(ignoring: !visible, child: child),
        ),
        child: NovelReaderFloatingBar(
          settings: settings,
          onTap: _menuActionTap,
          actionContext: _menuActionContext,
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
      // 浮动行与底栏同处一个纵向栈：浮动行在上、底栏在下，
      // 底栏高度随行数/图标文字变化时不会互相压住。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildFloatingBar(),
          ValueListenableBuilder<bool>(
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
                onTap: _menuActionTap,
                actionContext: _menuActionContext,
                autoReading: _autoReading,
                speaking: _controller.ttsActive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一段正文的选区探针：自己持有 [SelectionListenerNotifier]，
/// 挂载时登记进阅读页、卸载时注销，避免 ListView 回收重建期间
/// 同一个 notifier 被两个 SelectionListener 同时注册。
class _NovelSelectionProbe extends StatefulWidget {
  const _NovelSelectionProbe({
    required this.paragraph,
    required this.onRegister,
    required this.onUnregister,
    required this.child,
  });

  final int paragraph;
  final void Function(Object token, SelectionListenerNotifier notifier)
  onRegister;
  final void Function(Object token) onUnregister;
  final Widget child;

  @override
  State<_NovelSelectionProbe> createState() => _NovelSelectionProbeState();
}

class _NovelSelectionProbeState extends State<_NovelSelectionProbe> {
  final SelectionListenerNotifier _notifier = SelectionListenerNotifier();

  @override
  void initState() {
    super.initState();
    widget.onRegister(_notifier, _notifier);
  }

  @override
  void dispose() {
    widget.onUnregister(_notifier);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionListener(selectionNotifier: _notifier, child: widget.child);
  }
}
