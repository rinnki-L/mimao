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

import 'package:flutter/material.dart';

import '../../core/theme.dart';

import 'reader_cache.dart';
import 'reader_chapter_source.dart';
import 'reader_immersive_controller.dart';
import 'reader_immersive_viewport.dart';
import 'reader_progress.dart';
import 'reader_settings.dart';
import 'reader_settings_panel.dart';
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

  @override
  State<ImmersiveReaderPage> createState() => _ImmersiveReaderPageState();
}

class _ImmersiveReaderPageState extends State<ImmersiveReaderPage> {
  late ReaderSettings _settings;
  late ImmersiveReaderController _reading;
  late ReaderWaterfallController _waterfall;
  bool _settingsReady = false;

  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(true);
  bool _menuLocked = false;
  Timer? _autoReadTimer;
  bool _autoReading = false;

  @override
  void initState() {
    super.initState();
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
    _reading.updateSettings(_settings);
    if (!mounted) return;
    setState(() => _settingsReady = true);
    await _waterfall.start();
  }

  void _onWaterfallChanged() {
    // 瀑布流段变化时：非瀑布模式下保持单章；瀑布模式下视图自然重建。
  }

  @override
  void dispose() {
    _autoReadTimer?.cancel();
    _waterfall.removeListener(_onWaterfallChanged);
    _waterfall.dispose();
    _reading.dispose();
    _chromeVisible.dispose();
    super.dispose();
  }

  void _applySettings(ReaderSettings next) {
    setState(() => _settings = next);
    _reading.updateSettings(next);
    unawaited(widget.settingsStore.save(next));
  }

  void _toggleChrome() {
    if (_menuLocked) return;
    _chromeVisible.value = !_chromeVisible.value;
  }

  void _toggleAutoReading() {
    setState(() => _autoReading = !_autoReading);
    if (_autoReading) {
      _startAutoReading();
    } else {
      _autoReadTimer?.cancel();
      _autoReadTimer = null;
    }
  }

  void _startAutoReading() {
    _autoReadTimer?.cancel();
    final seconds = _settings.autoReadingInterval;
    _autoReadTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (_settings.mode.isGallery) {
        unawaited(_reading.turnPage(1));
      } else {
        unawaited(_reading.scrollByViewport(1));
      }
    });
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
      await _waterfall.goToChapter(picked);
      await _reading.syncToFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: !_settingsReady
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _waterfall,
              builder: (context, _) {
                return AnimatedBuilder(
                  animation: _reading,
                  builder: (context, __) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ReaderViewport(
                        settings: _settings,
                        reading: _reading,
                        waterfall: _waterfall,
                        cache: widget.imageCache,
                        onTapCenter: _toggleChrome,
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
                      if (_settings.showPageNumber) _buildPageBadge(theme),
                      _buildTopBar(theme),
                      _buildBottomBar(theme),
                    ],
                  ),
                );
              },
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
              '${_reading.chapterTitle} · ${pos.page}/${pos.pageCount}',
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
                  IconButton(
                    key: const Key('reader-settings'),
                    tooltip: '阅读设置',
                    icon: const Icon(Icons.tune),
                    onPressed: () {
                      _chromeVisible.value = false;
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ReaderSettingsPanel(
                          initial: _settings,
                          onChanged: _applySettings,
                        ),
                      );
                    },
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
                          onPressed: () =>
                              unawaited(_reading.previousChapter()),
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
                          onPressed: () => unawaited(_reading.nextChapter()),
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
    final max = pos.pageCount < 1 ? 1 : pos.pageCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text('${pos.page}'),
          Expanded(
            child: Slider(
              key: const Key('reader-progress-slider'),
              value: pos.page.clamp(1, max).toDouble(),
              min: 1,
              max: max.toDouble(),
              divisions: max <= 1 ? 1 : max - 1,
              onChanged: (value) => unawaited(_reading.goToPage(value.round())),
            ),
          ),
          Text('$max'),
        ],
      ),
    );
  }
}
