// 沉浸式漫画阅读页：阅读器的"真正实现"，对照 Venera Next 的体验。
//
// 与历史 [ComicReaderPage](reader_page.dart) 分开：那个是最小可运行版本，
// 被 868 行 widget/controller 测试锁定；本页是新体验，接入后由集成层改走这里。
//
// 能力（全部 Flutter 原生，不引第三方图片/滚动库）：
// - 七种阅读模式（翻页左/右/上、连续左/右/上、跨章瀑布），见 reader_view_mode.dart；
// - 沉浸式工具栏：点中间显隐顶/底栏，桌面 hover 反馈；
// - 手势：左右/上下热区翻页、双击缩放、长按放大、双指捏合（InteractiveViewer）；
// - 跨章瀑布流：接近章尾自动接下一章、上滚回上一章、插章锚点恢复；
// - 阅读设置面板实时生效（模式/方向/亮度/预取/动画/自动翻页间隔等）；
// - 每张图经 ReaderImageCache.loadRequest 取字节（防盗链头 + 重试 + 两级缓存）；
// - 加载 / 空 / 错误三态齐全，进度跟随真实章节/页。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';

import 'reader_cache.dart';
import 'reader_chapter_source.dart';
import 'reader_comments.dart';
import 'reader_comments_sheet.dart';
import 'reader_diagnostics.dart';
import 'reader_diagnostics_sheet.dart';
import 'reader_image_size.dart';
import 'reader_immersive_controller.dart';
import 'reader_immersive_viewport.dart';
import 'reader_layout_detect.dart';
import 'reader_models.dart';
import 'reader_progress.dart';
import 'reader_settings.dart';
import 'reader_settings_panel.dart';
import 'reader_view_mode.dart';
import 'reader_volume_keys.dart';
import 'reader_waterfall_controller.dart';

/// 沉浸式阅读页对外接口。
class ImmersiveReaderPage extends StatefulWidget {
  const ImmersiveReaderPage({
    super.key,
    required this.title,
    required this.source,
    required this.imageCache,
    required this.settingsStore,
    this.recorder,
    this.initialChapter = 1,
    this.initialPage = 1,
    this.chapterTitles = const <String>[],
    this.commentSource,
  });

  final String title;

  /// 章节数据源（懒加载：只按章号取图片地址，不预先整本拉取）。
  final ReaderChapterSource source;

  final ReaderImageCache imageCache;
  final ReaderSettingsStore settingsStore;
  final ProgressRecorder? recorder;

  /// 起始章节（1 基）与章内页（1 基），由历史进度恢复；无历史时为 1。
  final int initialChapter;
  final int initialPage;

  /// 章节标题（1 基章号 - 1 索引），用于章节目录与进度文案；可为空。
  final List<String> chapterTitles;

  /// 章节评论源；null 时不显示评论入口。
  final NovelCommentSource? commentSource;

  @override
  State<ImmersiveReaderPage> createState() => _ImmersiveReaderPageState();
}

class _ImmersiveReaderPageState extends State<ImmersiveReaderPage>
    with WidgetsBindingObserver {
  late ReaderSettings _settings;
  late ImmersiveReaderController _reading;
  late ReaderWaterfallController _waterfall;
  bool _settingsReady = false;

  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(true);
  final ReaderViewportController _viewport = ReaderViewportController();
  bool _menuLocked = false;
  Timer? _autoReadTimer;
  bool _autoReading = false;
  bool _fullscreen = false;
  bool _appActive = true;
  DateTime _lastInteraction = DateTime.fromMillisecondsSinceEpoch(0);

  /// 自动版式判断结果：只影响本次打开，不改保存的默认模式。
  ReaderViewMode? _autoMode;
  int _autoModeGeneration = 0;
  final ReaderImageSizeCache _detectSizes = ReaderImageSizeCache();
  late final ReaderDiagnostics _diagnostics = ReaderDiagnostics();
  late final ReaderVolumeController _volume = ReaderVolumeController(
    nextPage: () {
      if (_effectiveSettings.mode.isGallery) {
        unawaited(_viewport.turnGalleryPage(1));
      } else {
        unawaited(_viewport.scrollViewport(1));
      }
      return true;
    },
    previousPage: () {
      if (_effectiveSettings.mode.isGallery) {
        unawaited(_viewport.turnGalleryPage(-1));
      } else {
        unawaited(_viewport.scrollViewport(-1));
      }
      return true;
    },
    nextChapter: () => unawaited(_runChapterAction(_reading.nextChapter)),
    previousChapter: () =>
        unawaited(_runChapterAction(_reading.previousChapter)),
    onError: (error, stack) {
      // 音量键失败只影响翻页，不打断阅读；进日志便于排查。
      debugPrint('音量键翻页失败：$error');
    },
    onInput: (_) => _noteInteraction(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _waterfall = ReaderWaterfallController(
      source: widget.source,
      initialChapter: widget.initialChapter,
      initialChapterId: widget.source.chapterId(widget.initialChapter),
    );
    _reading = ImmersiveReaderController(
      waterfall: _waterfall,
      recorder: widget.recorder,
      chapterTitles: widget.chapterTitles,
      initialPage: widget.initialPage,
    );
    _waterfall.addListener(_onWaterfallChanged);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final loaded = await widget.settingsStore.load();
    _settings = loaded.copyWith(mode: loaded.mode);
    _reading.updateSettings(_effectiveSettings);
    if (!mounted) return;
    setState(() => _settingsReady = true);
    await _waterfall.start();
    if (mounted && _settings.autoLayout) unawaited(_detectLayout());
    await _syncVolumeKeys();
  }

  ReaderSettings get _effectiveSettings =>
      _autoMode == null ? _settings : _settings.copyWith(mode: _autoMode);

  void _onWaterfallChanged() {
    // 瀑布流段变化时：非瀑布模式下保持单章；瀑布模式下视图自然重建。
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoReadTimer?.cancel();
    if (_fullscreen && _supportsFullscreen) unawaited(_restoreFullscreen());
    _waterfall.removeListener(_onWaterfallChanged);
    _waterfall.dispose();
    _reading.dispose();
    _chromeVisible.dispose();
    _detectSizes.clear();
    _diagnostics.dispose();
    unawaited(_volume.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    if (!active) {
      // 切后台时把最后一次滚动位置补写掉，自动阅读下一拍自然停住。
      unawaited(_reading.flushProgress());
      _diagnostics.stop(ReaderDiagnosticStop.background);
      // 后台不该继续吃音量键（那是系统音量）。
      unawaited(_volume.setEnabled(false));
    } else {
      unawaited(_syncVolumeKeys());
    }
  }

  Future<void> _restoreFullscreen() async {
    try {
      await windowManager.setFullScreen(false);
    } on Object {
      // 退出阅读器时恢复失败不阻塞返回；下次进入按窗口当前状态显示。
    }
  }

  void _applySettings(ReaderSettings next) {
    final intervalChanged =
        next.autoReadingInterval != _settings.autoReadingInterval;
    final wasAuto = _settings.autoLayout;
    // 用户手动选了别的模式（或关掉自动）→ 以用户选择为准，取消本次自动结果。
    if (!next.autoLayout || (_autoMode != null && next.mode != _autoMode)) {
      _autoMode = null;
      _autoModeGeneration++;
    }
    if (!wasAuto && next.autoLayout) unawaited(_detectLayout());
    if (next.volumeKeys != _settings.volumeKeys) unawaited(_syncVolumeKeys());
    final autoMode = _autoMode;
    // 自动版式只是本次打开的内存覆盖：面板改其它项时，落盘仍写用户原来的
    // 默认模式，不把检测结果偷偷变成默认。
    final stored = autoMode != null && next.mode == autoMode
        ? next.copyWith(mode: _settings.mode)
        : next;
    setState(() => _settings = stored);
    _reading.updateSettings(_effectiveSettings);
    unawaited(widget.settingsStore.save(stored));
    if (_autoReading && intervalChanged) _startAutoReading();
  }

  void _toggleChrome() {
    if (_menuLocked) return;
    _chromeVisible.value = !_chromeVisible.value;
  }

  Future<void> _openSettingsSheet() async {
    final wasVisible = _chromeVisible.value;
    if (!_menuLocked) _chromeVisible.value = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReaderSettingsPanel(
        initial: _effectiveSettings,
        onChanged: _applySettings,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
    // 锁菜单时不能把面板藏掉后又不还原，否则解锁按钮也看不见。
    if (mounted && wasVisible) _chromeVisible.value = true;
  }

  /// Android 上按设置申请/撤销音量键监听；其它平台是空操作。
  Future<void> _syncVolumeKeys() async {
    if (!supportsVolumeKeys) return;
    try {
      await _volume.setEnabled(_settings.volumeKeys);
    } on Object catch (error) {
      // 拿不到音量键不影响阅读：静默降级，用户仍可用点击/滚轮。
      debugPrint('音量键监听不可用：$error');
    }
  }

  /// 打开当前章评论；源不支持时不显示入口，所以这里不再判空。
  Future<void> _openComments() async {
    final source = widget.commentSource;
    if (source == null) return;
    final position = _reading.position;
    if (position.chapterId.isEmpty) {
      _showSnack('当前章节没有稳定 id，无法加载评论');
      return;
    }
    _chromeVisible.value = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ReaderCommentsSheet(
          comicId: widget.title,
          episodeId: position.chapterId,
          source: source,
          chapterTitle: _reading.chapterTitle,
        ),
      ),
    );
  }

  Future<void> _openDiagnostics() async {
    _diagnostics.stop(ReaderDiagnosticStop.review);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ReaderDiagnosticsSheet(
          diagnostics: _diagnostics,
          mode: _effectiveSettings.mode,
          appVersion: kReaderDiagnosticsAppVersion,
          refreshRate: View.of(context).display.refreshRate,
        ),
      ),
    );
  }

  Future<void> _showContextMenu(TapDownDetails details) async {
    if (!_supportsFullscreen) return; // 桌面右键菜单；触屏长按仍用于缩放
    final position = details.globalPosition;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'settings', child: Text('阅读设置')),
        const PopupMenuItem<String>(value: 'chapters', child: Text('章节目录')),
        const PopupMenuItem<String>(value: 'save', child: Text('保存当前图片')),
        PopupMenuItem<String>(
          value: 'fullscreen',
          child: Text(_fullscreen ? '退出全屏' : '全屏'),
        ),
        PopupMenuItem<String>(
          value: 'auto',
          child: Text(_autoReading ? '停止自动阅读' : '自动阅读'),
        ),
        const PopupMenuItem<String>(value: 'comments', child: Text('章节评论')),
        const PopupMenuItem<String>(value: 'diagnostics', child: Text('阅读诊断')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'settings':
        await _openSettingsSheet();
      case 'chapters':
        await _openChapterMenu();
      case 'save':
        await _saveCurrentImage();
      case 'fullscreen':
        await _toggleFullscreen();
      case 'auto':
        _toggleAutoReading();
      case 'comments':
        await _openComments();
      case 'diagnostics':
        await _openDiagnostics();
    }
  }

  bool get _supportsFullscreen =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _toggleFullscreen() async {
    if (!_supportsFullscreen) return;
    final next = !_fullscreen;
    try {
      await windowManager.setFullScreen(next);
      if (mounted) setState(() => _fullscreen = next);
    } on Object {
      // 窗口管理器未初始化/平台不支持：保持当前窗口状态即可。
    }
  }

  void _toggleAutoReading() {
    if (_autoReading) {
      _stopAutoReading();
      return;
    }
    setState(() => _autoReading = true);
    _startAutoReading();
  }

  void _startAutoReading() {
    _autoReadTimer?.cancel();
    _chromeVisible.value = false;
    final seconds = _settings.autoReadingInterval;
    _autoReadTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted || !_appActive) return;
      // 菜单栏被唤出时视为暂停，用户看完/关掉菜单后继续。
      if (_chromeVisible.value) return;
      // 手指/滚轮刚动过：这一拍不推进（真正的"暂停"感）。
      if (DateTime.now().difference(_lastInteraction) <
          const Duration(milliseconds: 900)) {
        return;
      }
      // 当前图还没就绪：等下一拍，别把空白页翻过去。
      if (!_viewport.currentImageReady) return;
      if (_viewport.atEnd) {
        _stopAutoReading();
        return;
      }
      if (_effectiveSettings.mode.isGallery) {
        unawaited(_viewport.turnGalleryPage(1));
      } else {
        unawaited(_viewport.scrollViewport(1));
      }
    });
  }

  void _stopAutoReading() {
    _autoReadTimer?.cancel();
    _autoReadTimer = null;
    if (mounted && _autoReading) setState(() => _autoReading = false);
  }

  void _noteInteraction() {
    _lastInteraction = DateTime.now();
  }

  Future<void> _turnByKeyboard(int direction) async {
    _lastInteraction = DateTime.now();
    if (_effectiveSettings.mode.isGallery) {
      await _viewport.turnGalleryPage(direction);
    } else {
      await _viewport.scrollViewport(direction);
    }
  }

  Future<void> _openChapterMenu() async {
    final chapters = widget.chapterTitles;
    if (chapters.isEmpty) return;
    final current = _reading.currentChapter;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '章节目录',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    final number = index + 1;
                    final selected = number == current;
                    return ListTile(
                      selected: selected,
                      leading: Text('$number'),
                      title: Text(chapters[index]),
                      onTap: () => Navigator.of(context).pop(number),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await _runChapterAction(() => _reading.goToChapter(picked));
    }
  }

  Future<void> _runChapterAction(Future<bool> Function() action) async {
    final ok = await action();
    if (!mounted) return;
    final message = _reading.message;
    if (message != null) {
      _showSnack(message);
    } else if (!ok) {
      _showSnack('没有可去的章节');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// 采样当前章第 2~7 张，按宽高比推荐条漫/页漫。
  ///
  /// 700ms 内出结果就切；超时先用默认模式打开，后台采样完成后仍可切换。
  /// 只改本次打开的内存模式，不覆盖保存的默认模式。
  Future<void> _detectLayout() async {
    final generation = ++_autoModeGeneration;
    final segment = _waterfall.flow.segmentOf(_waterfall.initialChapter);
    if (segment == null || segment.length < 5) return;
    final candidates = <ImageRequest>[
      for (var i = 1; i < segment.length && i < 7; i++) segment.images[i],
    ];
    if (candidates.length < 4) return;

    final sizes = <Size>[];
    Future<List<Size>> sample() async {
      for (var i = 0; i < candidates.length; i += 2) {
        if (!mounted || generation != _autoModeGeneration) break;
        final measured = await Future.wait(
          candidates.skip(i).take(2).map(_measureRequest),
        );
        sizes.addAll(measured.whereType<Size>());
      }
      return sizes;
    }

    final sampling = sample().timeout(
      const Duration(seconds: 8),
      onTimeout: () => sizes,
    );
    final result = await Future.any<Object?>(<Future<Object?>>[
      sampling,
      Future<void>.delayed(const Duration(milliseconds: 700)),
    ]);
    if (!mounted) return;
    if (result is List<Size>) {
      _applyDetectedLayout(result, generation);
    } else {
      // 先按默认模式打开；后台采样完成后再补一次判断。
      unawaited(
        sampling.then((late) => _applyDetectedLayout(late, generation)),
      );
    }
  }

  Future<Size?> _measureRequest(ImageRequest request) async {
    try {
      final bytes = await widget.imageCache.loadRequest(request);
      return await _detectSizes.measure(request, bytes);
    } on Object {
      return null;
    }
  }

  void _applyDetectedLayout(List<Size> sizes, int generation) {
    if (!mounted ||
        generation != _autoModeGeneration ||
        !_settings.autoLayout) {
      return;
    }
    final mode = detectReaderModeFromSizes(sizes);
    if (mode == null || mode == _effectiveSettings.mode) return;
    setState(() => _autoMode = mode);
    _reading.updateSettings(_effectiveSettings);
    _showSnack('已按图片版式切换为「${mode.label}」');
  }

  /// 保存当前显示的第一张图（翻页模式一屏多图时取左上/第一张）。
  Future<void> _saveCurrentImage() async {
    final current = await _viewport.currentImage();
    if (!mounted) return;
    if (current == null) {
      _showSnack('当前图片还没加载完成');
      return;
    }
    final (bytes, url) = current;
    final extension = _imageExtension(url);
    final position = _reading.position;
    final fileName = _safeFileName(
      '${widget.title}_${_reading.chapterTitle}_${position.page}',
    );
    try {
      final uri = await FilePicker.saveFile(
        fileName: '$fileName.$extension',
        bytes: bytes,
        mimeType: _mimeType(extension),
        dialogTitle: '保存图片',
      );
      if (!mounted || uri == null) return;
      final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
      _showSnack('已保存：$path');
    } on Object catch (error) {
      if (mounted) _showSnack('保存失败：$error');
    }
  }

  String _imageExtension(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase();
    for (final extension in const <String>[
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
      'bmp',
      'avif',
    ]) {
      if (path != null && path.endsWith('.$extension')) return extension;
    }
    return 'jpg';
  }

  String _mimeType(String extension) => switch (extension) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'avif' => 'image/avif',
    _ => 'image/jpeg',
  };

  String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: !_settingsReady
          ? const Center(child: CircularProgressIndicator())
          : CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                    unawaited(_turnByKeyboard(1)),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    unawaited(_turnByKeyboard(1)),
                const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                    unawaited(_turnByKeyboard(-1)),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    unawaited(_turnByKeyboard(-1)),
                const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                    unawaited(_turnByKeyboard(1)),
                const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                    unawaited(_turnByKeyboard(-1)),
                const SingleActivator(LogicalKeyboardKey.space): () =>
                    unawaited(_turnByKeyboard(1)),
                const SingleActivator(LogicalKeyboardKey.f11): () =>
                    unawaited(_toggleFullscreen()),
              },
              child: Focus(
                autofocus: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) =>
                      unawaited(_showContextMenu(details)),
                  child: Listener(
                    onPointerDown: (_) => _noteInteraction(),
                    onPointerSignal: (_) => _noteInteraction(),
                    child: AnimatedBuilder(
                      animation: _waterfall,
                      builder: (context, _) {
                        return AnimatedBuilder(
                          animation: _reading,
                          builder: (context, __) => Stack(
                            fit: StackFit.expand,
                            children: [
                              ReaderViewport(
                                settings: _effectiveSettings,
                                reading: _reading,
                                waterfall: _waterfall,
                                cache: widget.imageCache,
                                onTapCenter: _toggleChrome,
                                chapterTitles: widget.chapterTitles,
                                viewportController: _viewport,
                                diagnostics: _diagnostics,
                              ),
                              // 阅读亮度遮罩（不压暗时透明、不吃事件）。
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: Colors.black.withValues(
                                      alpha: 1 - _settings.dimBrightness / 100,
                                    ),
                                  ),
                                ),
                              ),
                              if (_settings.showPageNumber)
                                _buildPageBadge(theme),
                              _buildTopBar(theme),
                              _buildBottomBar(theme),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPageBadge(ThemeData theme) {
    final pos = _reading.position;
    return Positioned(
      left: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.85,
              ),
              borderRadius: MimaoShapes.sm,
            ),
            child: Text(
              '${_reading.chapterTitle} · ${pos.displayPage}/${pos.displayPageCount}',
              style: theme.textTheme.labelMedium,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _chromeVisible,
      builder: (context, visible, _) => AnimatedPositioned(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        top: visible ? 0 : -80,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.96),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    key: const Key('reader-back'),
                    tooltip: '返回',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('reader-lock-menu'),
                    tooltip: _menuLocked ? '解锁菜单' : '锁定菜单',
                    icon: Icon(
                      _menuLocked ? Icons.lock : Icons.lock_open_outlined,
                    ),
                    onPressed: () => setState(() => _menuLocked = !_menuLocked),
                  ),
                  if (_supportsFullscreen)
                    IconButton(
                      key: const Key('reader-fullscreen'),
                      tooltip: _fullscreen ? '退出全屏 (F11)' : '全屏 (F11)',
                      icon: Icon(
                        _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      ),
                      onPressed: () => unawaited(_toggleFullscreen()),
                    ),
                  IconButton(
                    key: const Key('reader-save-image'),
                    tooltip: '保存当前图片',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => unawaited(_saveCurrentImage()),
                  ),
                  IconButton(
                    key: const Key('reader-settings'),
                    tooltip: '阅读设置',
                    icon: const Icon(Icons.tune),
                    onPressed: () => unawaited(_openSettingsSheet()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _chromeVisible,
      builder: (context, visible, _) => AnimatedPositioned(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        bottom: visible ? 0 : -120,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.96),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          key: const Key('reader-prev-chapter'),
                          tooltip: '上一章',
                          icon: const Icon(Icons.keyboard_double_arrow_left),
                          onPressed: () => unawaited(
                            _runChapterAction(_reading.previousChapter),
                          ),
                        ),
                        IconButton(
                          key: const Key('reader-chapter-menu'),
                          tooltip: '章节目录',
                          icon: const Icon(Icons.list_alt),
                          onPressed: _openChapterMenu,
                        ),
                        IconButton(
                          key: const Key('reader-auto'),
                          tooltip: _autoReading ? '停止自动阅读' : '自动阅读',
                          icon: Icon(
                            _autoReading
                                ? Icons.pause_circle
                                : Icons.play_circle_outline,
                          ),
                          onPressed: _toggleAutoReading,
                        ),
                        IconButton(
                          key: const Key('reader-next-chapter'),
                          tooltip: '下一章',
                          icon: const Icon(Icons.keyboard_double_arrow_right),
                          onPressed: () => unawaited(
                            _runChapterAction(_reading.nextChapter),
                          ),
                        ),
                      ],
                    ),
                    _buildProgressSlider(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSlider(ThemeData theme) {
    final pos = _reading.position;
    final max = pos.displayPageCount < 1 ? 1 : pos.displayPageCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text('${pos.displayPage}'),
          Expanded(
            child: Slider(
              key: const Key('reader-progress-slider'),
              value: pos.displayPage.clamp(1, max).toDouble(),
              min: 1,
              max: max.toDouble(),
              divisions: max <= 1 ? 1 : max - 1,
              onChanged: (value) =>
                  unawaited(_reading.goToDisplayPage(value.round())),
            ),
          ),
          Text('$max'),
        ],
      ),
    );
  }
}
