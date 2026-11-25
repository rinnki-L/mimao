// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读设置面板（对照截图「阅读界面」）：字号 / Tt 字体 / 背景预设与自定义 /
// 翻页动画 / 全局·菜单·信息·更多 四个页签。
//
// 面板只持有设置的本地副本，每次修改经 [onChanged] 抛出完整快照，阅读页据此
// 立即重建并落盘；面板自身不读盘。

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'novel_click_actions.dart';
import 'novel_menu_actions.dart';
import 'novel_reader_chrome.dart';
import 'novel_reader_fonts.dart';
import 'novel_reader_settings.dart';
import 'novel_tts.dart';
import 'novel_tts_cache.dart';

/// 「信息」页签展示的只读书籍信息。
class NovelReaderBookInfo {
  const NovelReaderBookInfo({
    this.bookTitle = '',
    this.author = '',
    this.sourceName = '',
    this.chapterTitle = '',
    this.chapterIndex = 0,
    this.chapterCount = 0,
    this.page = 1,
    this.pageCount = 1,
    this.percent = 0,
  });

  final String bookTitle;
  final String author;
  final String sourceName;
  final String chapterTitle;
  final int chapterIndex;
  final int chapterCount;
  final int page;
  final int pageCount;
  final double percent;
}

enum _SettingsTab { global, typography, menu, info, more }

const Map<_SettingsTab, String> _tabLabels = <_SettingsTab, String>{
  _SettingsTab.global: '全局',
  _SettingsTab.typography: '排版',
  _SettingsTab.menu: '菜单',
  _SettingsTab.info: '信息',
  _SettingsTab.more: '更多',
};

/// 设置项搜索索引的一条：文案 + 所属页签 + 额外关键词。
///
/// 搜索只做「找到并跳过去」，不复制控件——同一个设置在面板里仍只有一处
/// 实现，索引只登记它的名字，避免两份真相漂移。
class _SettingsSearchEntry {
  const _SettingsSearchEntry(
    this.title,
    this.tab, {
    this.keywords = const <String>[],
  });

  final String title;
  final _SettingsTab tab;
  final List<String> keywords;

  bool matches(String query) {
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    for (final keyword in keywords) {
      if (keyword.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// 可搜索的设置项清单（覆盖五个页签里的主要条目）。
const List<_SettingsSearchEntry> _settingsSearchIndex = <_SettingsSearchEntry>[
  _SettingsSearchEntry('字号', _SettingsTab.global, keywords: <String>['字体大小']),
  _SettingsSearchEntry(
    '字体',
    _SettingsTab.global,
    keywords: <String>['Tt', 'font'],
  ),
  _SettingsSearchEntry(
    '背景',
    _SettingsTab.global,
    keywords: <String>['底色', '背景色'],
  ),
  _SettingsSearchEntry(
    '背景图',
    _SettingsTab.global,
    keywords: <String>['图片', '铺放'],
  ),
  _SettingsSearchEntry(
    '背景纹理',
    _SettingsTab.global,
    keywords: <String>['网格', '斜纹'],
  ),
  _SettingsSearchEntry('护眼模式', _SettingsTab.global, keywords: <String>['滤光']),
  _SettingsSearchEntry('翻页动画', _SettingsTab.global, keywords: <String>['过渡']),
  _SettingsSearchEntry(
    '翻页动画风格',
    _SettingsTab.menu,
    keywords: <String>['淡入淡出', '滑动', '视差'],
  ),
  _SettingsSearchEntry('正文加粗', _SettingsTab.typography),
  _SettingsSearchEntry('正文斜体', _SettingsTab.typography),
  _SettingsSearchEntry('两端对齐', _SettingsTab.typography),
  _SettingsSearchEntry('行距包含行内留白', _SettingsTab.typography),
  _SettingsSearchEntry('字距', _SettingsTab.typography),
  _SettingsSearchEntry('段首缩进', _SettingsTab.typography),
  _SettingsSearchEntry('简繁转换', _SettingsTab.typography),
  _SettingsSearchEntry('标题', _SettingsTab.typography),
  _SettingsSearchEntry('标题分段', _SettingsTab.typography),
  _SettingsSearchEntry('文字阴影', _SettingsTab.typography),
  _SettingsSearchEntry('下划线', _SettingsTab.typography),
  _SettingsSearchEntry('双栏分页', _SettingsTab.typography),
  _SettingsSearchEntry('显示页脚', _SettingsTab.menu),
  _SettingsSearchEntry('翻页过渡动画', _SettingsTab.menu),
  _SettingsSearchEntry('点击区', _SettingsTab.menu, keywords: <String>['九宫格']),
  _SettingsSearchEntry('长按', _SettingsTab.menu),
  _SettingsSearchEntry('双击', _SettingsTab.menu),
  _SettingsSearchEntry(
    '下滑加书签',
    _SettingsTab.menu,
    keywords: <String>['手势', '书签'],
  ),
  _SettingsSearchEntry('图标每行个数', _SettingsTab.menu),
  _SettingsSearchEntry('菜单行数', _SettingsTab.menu),
  _SettingsSearchEntry('底栏圆角', _SettingsTab.menu, keywords: <String>['圆角']),
  _SettingsSearchEntry('图标文字', _SettingsTab.menu),
  _SettingsSearchEntry('紧凑标题栏', _SettingsTab.menu, keywords: <String>['顶栏']),
  _SettingsSearchEntry('顶栏按钮', _SettingsTab.menu, keywords: <String>['自定义']),
  _SettingsSearchEntry('底栏按钮', _SettingsTab.menu, keywords: <String>['自定义']),
  _SettingsSearchEntry('浮动按钮', _SettingsTab.menu, keywords: <String>['自定义']),
  _SettingsSearchEntry('页眉页脚', _SettingsTab.info),
  _SettingsSearchEntry('自动翻页间隔', _SettingsTab.more, keywords: <String>['速度']),
  _SettingsSearchEntry(
    '朗读语速',
    _SettingsTab.more,
    keywords: <String>['tts', '速度'],
  ),
  _SettingsSearchEntry(
    '朗读音色',
    _SettingsTab.more,
    keywords: <String>['声音', 'voice'],
  ),
  _SettingsSearchEntry(
    '段间停顿',
    _SettingsTab.more,
    keywords: <String>['朗读', '间隔'],
  ),
  _SettingsSearchEntry(
    '自动续章',
    _SettingsTab.more,
    keywords: <String>['朗读', '下一章'],
  ),
  _SettingsSearchEntry(
    '手动翻页行为',
    _SettingsTab.more,
    keywords: <String>['朗读', '暂停', '跟随'],
  ),
  _SettingsSearchEntry(
    '睡眠定时',
    _SettingsTab.more,
    keywords: <String>['朗读', '定时停止'],
  ),
  _SettingsSearchEntry('行距', _SettingsTab.more),
  _SettingsSearchEntry('段距', _SettingsTab.more),
  _SettingsSearchEntry('左右边距', _SettingsTab.more, keywords: <String>['留白']),
  _SettingsSearchEntry('阅读亮度', _SettingsTab.more, keywords: <String>['亮度']),
  _SettingsSearchEntry('恢复默认设置', _SettingsTab.more, keywords: <String>['重置']),
];

class NovelReaderSettingsSheet extends StatefulWidget {
  const NovelReaderSettingsSheet({
    super.key,
    required this.initial,
    required this.info,
    required this.onChanged,
    required this.onClose,
    this.hasBookOverride = false,
    this.onClearBookOverride,
    this.loadTtsVoices,
    this.ttsSleepDeadline,
    this.onTtsSleepTimerChanged,
    this.loadTtsCacheStats,
    this.onClearTtsCache,
    this.onExportChapterAudio,
    this.onExportBookAudio,
  });

  final NovelReaderSettings initial;
  final NovelReaderBookInfo info;

  /// [scope] 由面板的「只改这本」开关给出，默认改全局。
  final void Function(NovelReaderSettings settings, {NovelSettingsScope scope})
  onChanged;
  final VoidCallback onClose;

  /// 这本书是否已有独立设置（有则在头部提示，可一键清掉）。
  final bool hasBookOverride;

  final VoidCallback? onClearBookOverride;

  /// 读取系统音色；null 表示当前环境没有朗读后端（只显示「自动」）。
  final Future<List<NovelTtsVoice>> Function()? loadTtsVoices;

  /// 睡眠定时到点时间；null = 未设。
  final DateTime? ttsSleepDeadline;

  /// 用户改睡眠定时（null = 关闭）；由阅读页写到控制器。
  final ValueChanged<Duration?>? onTtsSleepTimerChanged;

  /// 朗读缓存占用；null 表示没有缓存服务（不显示缓存行）。
  final Future<NovelTtsCacheStats?> Function()? loadTtsCacheStats;

  /// 清理朗读缓存；返回删掉的段数。
  final Future<int> Function()? onClearTtsCache;

  /// 导出当前章 / 全书朗读音频（由阅读页选目录、跑进度、提示结果）。
  final Future<void> Function()? onExportChapterAudio;
  final Future<void> Function()? onExportBookAudio;

  @override
  State<NovelReaderSettingsSheet> createState() =>
      _NovelReaderSettingsSheetState();
}

class _NovelReaderSettingsSheetState extends State<NovelReaderSettingsSheet> {
  late NovelReaderSettings _settings = widget.initial;
  _SettingsTab _tab = _SettingsTab.global;
  List<NovelFontFile> _importedFonts = const <NovelFontFile>[];
  late final TextEditingController _dividerController;

  /// 朗读：系统音色表 + 睡眠定时倒计时。
  List<NovelTtsVoice> _ttsVoices = const <NovelTtsVoice>[];
  bool _loadingTtsVoices = false;
  DateTime? _sleepDeadline;
  Timer? _sleepTicker;
  NovelTtsCacheStats? _ttsCacheStats;
  bool _loadingTtsCache = false;

  /// 搜索框与当前关键词；非空时正文区换成搜索结果列表。
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// 「只改这本」开关；默认关（改全局，与上游一致）。
  bool _bookOnly = false;

  /// 页签共用同一个滚动区：不重置的话切到短页签会停在半空中（甚至滚过头
  /// 看到空白），切到长页签又像是"跳过了顶部"。
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _dividerController = TextEditingController(
      text: widget.initial.titleSegmentDivider,
    );
    unawaited(_loadImportedFonts());
    _sleepDeadline = widget.ttsSleepDeadline;
    if (_sleepDeadline != null) _startSleepTicker();
    if (widget.loadTtsVoices != null) unawaited(_loadTtsVoices());
    if (widget.loadTtsCacheStats != null) unawaited(_loadTtsCacheStats());
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    _dividerController.dispose();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _selectTab(_SettingsTab tab) {
    setState(() {
      _tab = tab;
      // 从搜索结果跳过来时把搜索清掉，否则用户会以为页签没切换。
      _query = '';
      _searchController.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _loadImportedFonts() async {
    final fonts = await NovelFontRegistry.instance.list();
    if (!mounted) return;
    setState(() => _importedFonts = fonts);
  }

  // ── 朗读辅助 ─────────────────────────────────────────────────────────
  Future<void> _loadTtsVoices() async {
    final loader = widget.loadTtsVoices;
    if (loader == null || _loadingTtsVoices || _ttsVoices.isNotEmpty) return;
    setState(() => _loadingTtsVoices = true);
    try {
      final voices = await loader();
      if (mounted) setState(() => _ttsVoices = voices);
    } on Object {
      // 音色读不到不影响其它朗读设置。
    } finally {
      if (mounted) setState(() => _loadingTtsVoices = false);
    }
  }

  void _startSleepTicker() {
    _sleepTicker?.cancel();
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_sleepDeadline == null) {
        _sleepTicker?.cancel();
        _sleepTicker = null;
      }
      setState(() {});
    });
  }

  void _setSleepTimer(Duration? duration) {
    setState(() {
      _sleepDeadline = duration == null ? null : DateTime.now().add(duration);
    });
    widget.onTtsSleepTimerChanged?.call(duration);
    if (duration == null) {
      _sleepTicker?.cancel();
      _sleepTicker = null;
    } else {
      _startSleepTicker();
    }
  }

  Duration _sleepRemaining() {
    final deadline = _sleepDeadline;
    if (deadline == null) return Duration.zero;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _sleepLabel() {
    final remaining = _sleepRemaining();
    final seconds = remaining.inSeconds;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTtsCacheStats() async {
    final loader = widget.loadTtsCacheStats;
    if (loader == null) return;
    setState(() => _loadingTtsCache = true);
    try {
      final stats = await loader();
      if (mounted) setState(() => _ttsCacheStats = stats);
    } on Object {
      // 缓存统计失败不挡朗读设置。
    } finally {
      if (mounted) setState(() => _loadingTtsCache = false);
    }
  }

  Future<void> _clearTtsCache() async {
    final clear = widget.onClearTtsCache;
    if (clear == null) return;
    setState(() => _loadingTtsCache = true);
    try {
      final removed = await clear();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已清理 $removed 段朗读缓存')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理缓存失败：$error')));
    } finally {
      if (mounted) {
        await _loadTtsCacheStats();
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _apply(NovelReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(
      next,
      scope: _bookOnly ? NovelSettingsScope.book : NovelSettingsScope.global,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 面板随当前阅读背景明暗实时切换：切到羊皮纸/纯白时不能还弹深色面板。
    final base = Theme.of(context);
    final themed = buildMimaoTheme(
      seedColor: base.colorScheme.primary,
      brightness: _settings.darkBackground ? Brightness.dark : Brightness.light,
    );
    final scheme = themed.colorScheme;
    return Theme(
      data: themed.copyWith(
        textTheme: themed.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
      ),
      child: Builder(builder: _buildSheet),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.xl),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: <Widget>[
                IconButton(
                  key: const Key('novel-settings-back'),
                  tooltip: '返回阅读',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: 4),
                Text(
                  '阅读界面',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: MimaoFonts.bold,
                  ),
                ),
                const Spacer(),
                _buildScopeToggle(context),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: _buildSearchField(context),
          ),
          if (widget.hasBookOverride && _query.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: _buildBookOverrideHint(context),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.topCenter,
                child: _query.isEmpty
                    ? switch (_tab) {
                        _SettingsTab.global => _buildGlobal(context),
                        _SettingsTab.typography => _buildTypography(context),
                        _SettingsTab.menu => _buildMenu(context),
                        _SettingsTab.info => _buildInfo(context),
                        _SettingsTab.more => _buildMore(context),
                      }
                    : _buildSearchResults(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _buildTabs(context),
          ),
        ],
      ),
    );
  }

  /// 「只改这本 / 改全局」切换。默认全局；开着时只有可覆盖字段落本书。
  ///
  /// 每书覆盖刻意只收「背景 / 字体 / 翻页 / 动画 / 点击区」五项
  /// （见 [novelBookOverrideFields]）；菜单外观、按钮配置这类全局项
  /// 即使在「只改这本」下也写全局——在 Tooltip 里说清楚，别让用户以为
  /// 点了个开关却什么都没发生。
  Widget _buildScopeToggle(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: _bookOnly
          ? '只改这本：背景 / 字体 / 翻页方式 / 动画 / 点击区；菜单外观、按钮配置与朗读设置仍改全局'
          : '正在改全局设置；点一下改成只改这本书',
      child: InkWell(
        key: const Key('novel-settings-scope'),
        onTap: () => setState(() => _bookOnly = !_bookOnly),
        borderRadius: MimaoShapes.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _bookOnly
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: MimaoShapes.pill,
            border: Border.all(
              color: _bookOnly ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                _bookOnly ? Icons.book_outlined : Icons.public,
                size: 16,
                color: _bookOnly
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                _bookOnly ? '只改这本' : '改全局',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _bookOnly
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      key: const Key('novel-settings-search'),
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索设置项',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                key: const Key('novel-settings-search-clear'),
                tooltip: '清空搜索',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
      ),
      onChanged: (value) => setState(() => _query = value.trim()),
    );
  }

  /// 本书有独立设置时的提示条：说明「为什么和别的书不一样」并给出一键清掉。
  Widget _buildBookOverrideHint(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: MimaoShapes.md,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.bookmark_added_outlined,
              size: 18,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '这本书有独立设置，只存了与全局不同的项',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              key: const Key('novel-settings-clear-book-override'),
              onPressed: widget.onClearBookOverride,
              child: const Text('跟随全局'),
            ),
          ],
        ),
      ),
    );
  }

  /// 跨页签的搜索结果：命中标题高亮，点一条跳到对应页签。
  Widget _buildSearchResults(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hits = <_SettingsSearchEntry>[
      for (final entry in _settingsSearchIndex)
        if (entry.matches(_query)) entry,
    ];
    if (hits.isEmpty) {
      return Padding(
        key: const Key('novel-settings-search-empty'),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
        child: Column(
          children: <Widget>[
            Icon(Icons.search_off, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              '没有匹配「$_query」的设置项',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '试试点数、背景、翻页、菜单、亮度这类关键词；'
              '清空搜索框回到当前页签。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      key: const Key('novel-settings-search-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '找到 ${hits.length} 项',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final hit in hits)
          ListTile(
            key: Key('novel-settings-search-hit-${hit.title}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: _highlighted(hit.title, _query, theme, scheme),
            trailing: Text(
              _tabLabels[hit.tab]!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            onTap: () => _selectTab(hit.tab),
          ),
      ],
    );
  }

  /// 把命中片段包成主色加粗，让用户一眼看到为什么这条被搜出来。
  Widget _highlighted(
    String text,
    String query,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final index = text.toLowerCase().indexOf(query.toLowerCase());
    if (query.isEmpty || index < 0) {
      return Text(text, style: theme.textTheme.bodyMedium);
    }
    final end = index + query.length;
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          if (index > 0) TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, end),
            style: TextStyle(
              color: scheme.primary,
              fontWeight: MimaoFonts.bold,
            ),
          ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
      style: theme.textTheme.bodyMedium,
    );
  }

  // ── 全局 ──────────────────────────────────────────────────────────────
  Widget _buildGlobal(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _card(
          child: Row(
            children: <Widget>[
              Text('字号', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    _stepButton(
                      key: 'novel-settings-font-minus',
                      icon: Icons.remove,
                      onTap: () => _apply(
                        _settings.copyWith(fontSize: _settings.fontSize - 1),
                      ),
                    ),
                    Container(
                      width: 52,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: MimaoShapes.sm,
                      ),
                      child: Text(
                        '${_settings.fontSize.round()}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    _stepButton(
                      key: 'novel-settings-font-plus',
                      icon: Icons.add,
                      onTap: () => _apply(
                        _settings.copyWith(fontSize: _settings.fontSize + 1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _squareButton(
                key: 'novel-settings-font-family',
                tooltip: '字体',
                onTap: _pickFont,
                child: Text(
                  'Tт',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: text,
                    fontWeight: MimaoFonts.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        _card(child: _buildBackground(context)),
        _card(child: _buildPageAnimation(context)),
      ],
    );
  }

  Widget _buildBackground(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _settings.background;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('背景', style: theme.textTheme.bodyMedium),
            const SizedBox(width: 8),
            Text(
              '长按自定义',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            IconButton(
              key: const Key('novel-settings-eye-protection'),
              tooltip: '护眼模式',
              visualDensity: VisualDensity.compact,
              color: _settings.eyeProtection ? theme.colorScheme.primary : null,
              icon: const Icon(Icons.visibility_outlined, size: 20),
              onPressed: () => _apply(
                _settings.copyWith(eyeProtection: !_settings.eyeProtection),
              ),
            ),
            IconButton(
              key: const Key('novel-settings-background-night'),
              tooltip: _settings.darkBackground ? '日间模式' : '夜间模式',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.dark_mode_outlined, size: 20),
              onPressed: () => _apply(
                _settings.useBackground(_settings.darkBackground ? 3 : 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 86,
          child: ListView(
            key: const Key('novel-settings-background-presets'),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              _backgroundTile(
                key: 'novel-settings-custom-color',
                tooltip: '自定义背景色',
                color: theme.colorScheme.surfaceContainerHighest,
                selected: _settings.customBackgroundArgb != null,
                child: Icon(
                  Icons.grid_view,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onTap: _pickCustomColor,
                onLongPress: _pickCustomColor,
              ),
              const SizedBox(width: 8),
              for (var i = 0; i < novelReaderBackgrounds.length; i++) ...[
                _backgroundTile(
                  key: 'novel-settings-background-$i',
                  tooltip: novelReaderBackgrounds[i].name,
                  color: Color(novelReaderBackgrounds[i].argb),
                  selected:
                      _settings.customBackgroundArgb == null &&
                      _settings.backgroundIndex == i,
                  onTap: () => _apply(_settings.useBackground(i)),
                  onLongPress: _pickCustomColor,
                ),
                const SizedBox(width: 8),
              ],
              _backgroundTile(
                key: 'novel-settings-background-more',
                tooltip: '更多背景色',
                color: theme.colorScheme.surfaceContainerHighest,
                selected: false,
                child: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onTap: _pickCustomColor,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          selected.name,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 18),
        _buildBackgroundImage(context),
        const SizedBox(height: 4),
        _buildBackgroundTexture(context),
      ],
    );
  }

  Widget _buildBackgroundImage(BuildContext context) {
    final theme = Theme.of(context);
    final path = _settings.backgroundImagePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('背景图', style: theme.textTheme.bodyMedium),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path == null ? '未选择（点右侧选择本地图片）' : '已选择本地图片',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('novel-settings-background-image'),
              onPressed: _pickBackgroundImage,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(path == null ? '选择' : '更换'),
            ),
            if (path != null)
              IconButton(
                key: const Key('novel-settings-background-image-clear'),
                tooltip: '移除背景图',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    _apply(_settings.copyWith(clearBackgroundImage: true)),
              ),
          ],
        ),
        if (path != null) ...<Widget>[
          _enumDropdownRow<NovelBackgroundFit>(
            key: 'novel-settings-background-image-fit',
            title: '铺放',
            value: _settings.backgroundImageFit,
            values: NovelBackgroundFit.values,
            labelOf: (value) => value.label,
            onChanged: (value) =>
                _apply(_settings.copyWith(backgroundImageFit: value)),
          ),
          _enumDropdownRow<NovelBackgroundAlign>(
            key: 'novel-settings-background-image-align',
            title: '对齐（九宫格）',
            value: _settings.backgroundImageAlign,
            values: NovelBackgroundAlign.values,
            labelOf: (value) => value.label,
            onChanged: (value) =>
                _apply(_settings.copyWith(backgroundImageAlign: value)),
          ),
          _sliderRow(
            context,
            key: 'novel-settings-background-image-opacity',
            title: '图片透明度',
            valueLabel: '${_settings.backgroundImageOpacity}%',
            value: _settings.backgroundImageOpacity.toDouble(),
            min: NovelReaderSettings.minBackgroundImageOpacity.toDouble(),
            max: NovelReaderSettings.maxBackgroundImageOpacity.toDouble(),
            divisions: 20,
            onChanged: (value) => _apply(
              _settings.copyWith(backgroundImageOpacity: value.round()),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBackgroundTexture(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text('背景纹理', style: theme.textTheme.bodyMedium),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<NovelBackgroundTexture>(
              key: const Key('novel-settings-background-texture'),
              isExpanded: true,
              value: _settings.backgroundTexture,
              items: <DropdownMenuItem<NovelBackgroundTexture>>[
                for (final texture in NovelBackgroundTexture.values)
                  DropdownMenuItem<NovelBackgroundTexture>(
                    value: texture,
                    child: Text(texture.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _apply(_settings.copyWith(backgroundTexture: value));
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageAnimation(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SegmentedButton<NovelPageMode>(
            key: const Key('novel-settings-page-mode'),
            showSelectedIcon: false,
            segments: const <ButtonSegment<NovelPageMode>>[
              ButtonSegment<NovelPageMode>(
                value: NovelPageMode.page,
                label: Text('翻页动画'),
              ),
              ButtonSegment<NovelPageMode>(
                value: NovelPageMode.scroll,
                label: Text('滚动'),
              ),
            ],
            selected: <NovelPageMode>{_settings.pageMode},
            onSelectionChanged: (selection) =>
                _apply(_settings.copyWith(pageMode: selection.first)),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const Key('novel-settings-animation-speed'),
          tooltip: '翻页动画速度',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.speed, size: 20),
          onPressed: _pickAnimationSpeed,
        ),
        IconButton(
          key: const Key('novel-settings-margins'),
          tooltip: '页边距',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.crop_free, size: 20),
          onPressed: _pickMargins,
        ),
      ],
    );
  }

  // ── 排版 ──────────────────────────────────────────────────────────────
  Widget _buildTypography(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                key: const Key('novel-settings-bold'),
                contentPadding: EdgeInsets.zero,
                title: const Text('正文加粗'),
                value: _settings.textBold,
                onChanged: (value) =>
                    _apply(_settings.copyWith(textBold: value)),
              ),
              SwitchListTile(
                key: const Key('novel-settings-italic'),
                contentPadding: EdgeInsets.zero,
                title: const Text('正文斜体'),
                value: _settings.textItalic,
                onChanged: (value) =>
                    _apply(_settings.copyWith(textItalic: value)),
              ),
              SwitchListTile(
                key: const Key('novel-settings-justify'),
                contentPadding: EdgeInsets.zero,
                title: const Text('两端对齐'),
                subtitle: const Text('中文段落左右两边都对齐'),
                value: _settings.textAlignJustify,
                onChanged: (value) =>
                    _apply(_settings.copyWith(textAlignJustify: value)),
              ),
              SwitchListTile(
                key: const Key('novel-settings-line-height-padding'),
                contentPadding: EdgeInsets.zero,
                title: const Text('行距包含行内留白'),
                subtitle: const Text('关闭后行距只拉开行与行之间'),
                value: _settings.lineHeightIncludesPadding,
                onChanged: (value) => _apply(
                  _settings.copyWith(lineHeightIncludesPadding: value),
                ),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-letter-spacing',
                title: '字距',
                valueLabel: _settings.letterSpacing.toStringAsFixed(1),
                value: _settings.letterSpacing,
                min: NovelReaderSettings.minLetterSpacing,
                max: NovelReaderSettings.maxLetterSpacing,
                divisions: 40,
                onChanged: (value) =>
                    _apply(_settings.copyWith(letterSpacing: value)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-indent',
                title: '段首缩进',
                valueLabel: '${_settings.indentCount} 字',
                value: _settings.indentCount.toDouble(),
                min: NovelReaderSettings.minIndentCount.toDouble(),
                max: NovelReaderSettings.maxIndentCount.toDouble(),
                divisions:
                    NovelReaderSettings.maxIndentCount -
                    NovelReaderSettings.minIndentCount,
                onChanged: (value) =>
                    _apply(_settings.copyWith(indentCount: value.round())),
              ),
              _enumDropdownRow<NovelChineseConvert>(
                key: 'novel-settings-chinese-convert',
                title: '简繁转换',
                value: _settings.chineseConvert,
                values: NovelChineseConvert.values,
                labelOf: (value) => value.label,
                onChanged: (value) =>
                    _apply(_settings.copyWith(chineseConvert: value)),
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('标题', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<NovelTitleMode>(
                key: const Key('novel-settings-title-mode'),
                showSelectedIcon: false,
                segments: <ButtonSegment<NovelTitleMode>>[
                  for (final mode in NovelTitleMode.values)
                    ButtonSegment<NovelTitleMode>(
                      value: mode,
                      label: Text(mode.label),
                    ),
                ],
                selected: <NovelTitleMode>{_settings.titleMode},
                onSelectionChanged: (selection) =>
                    _apply(_settings.copyWith(titleMode: selection.first)),
              ),
              SwitchListTile(
                key: const Key('novel-settings-title-relative'),
                contentPadding: EdgeInsets.zero,
                title: const Text('标题字号相对正文'),
                subtitle: const Text('关闭后按绝对字号渲染'),
                value: _settings.titleSizeRelative,
                onChanged: (value) =>
                    _apply(_settings.copyWith(titleSizeRelative: value)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-title-size',
                title: _settings.titleSizeRelative ? '标题字号偏移' : '标题字号',
                valueLabel: _settings.titleSizeRelative
                    ? '+${_settings.titleSize.round()}'
                    : '${_settings.titleSize.round()}',
                value: _settings.titleSize,
                min: NovelReaderSettings.minTitleSize,
                max: _settings.titleSizeRelative
                    ? NovelReaderSettings.maxTitleSizeRelative
                    : NovelReaderSettings.maxTitleSizeAbsolute,
                divisions: _settings.titleSizeRelative ? 40 : 59,
                onChanged: (value) =>
                    _apply(_settings.copyWith(titleSize: value)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-title-top',
                title: '标题上留白',
                valueLabel: '${_settings.titleTopSpacing.round()}',
                value: _settings.titleTopSpacing,
                min: NovelReaderSettings.minTitleSpacing,
                max: NovelReaderSettings.maxTitleSpacing,
                divisions: 24,
                onChanged: (value) =>
                    _apply(_settings.copyWith(titleTopSpacing: value)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-title-bottom',
                title: '标题下留白',
                valueLabel: '${_settings.titleBottomSpacing.round()}',
                value: _settings.titleBottomSpacing,
                min: NovelReaderSettings.minTitleSpacing,
                max: NovelReaderSettings.maxTitleSpacing,
                divisions: 24,
                onChanged: (value) =>
                    _apply(_settings.copyWith(titleBottomSpacing: value)),
              ),
              SwitchListTile(
                key: const Key('novel-settings-title-segment'),
                contentPadding: EdgeInsets.zero,
                title: const Text('标题分段'),
                subtitle: const Text('按空白把「第X章 标题」拆成主标题与副标题'),
                value: _settings.titleSegment,
                onChanged: (value) =>
                    _apply(_settings.copyWith(titleSegment: value)),
              ),
              if (_settings.titleSegment) ...<Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 88,
                      child: Text('分隔符', style: theme.textTheme.bodyMedium),
                    ),
                    Expanded(
                      child: TextField(
                        key: const Key('novel-settings-title-divider'),
                        controller: _dividerController,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '如 ·',
                        ),
                        onChanged: (value) => _apply(
                          _settings.copyWith(titleSegmentDivider: value),
                        ),
                      ),
                    ),
                  ],
                ),
                _sliderRow(
                  context,
                  key: 'novel-settings-title-segment-scale',
                  title: '副标题缩放',
                  valueLabel: _settings.titleSegmentScale.toStringAsFixed(1),
                  value: _settings.titleSegmentScale,
                  min: NovelReaderSettings.minTitleSegmentScale,
                  max: NovelReaderSettings.maxTitleSegmentScale,
                  divisions: 14,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(titleSegmentScale: value)),
                ),
              ],
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('文字装饰', style: theme.textTheme.titleSmall),
              SwitchListTile(
                key: const Key('novel-settings-shadow'),
                contentPadding: EdgeInsets.zero,
                title: const Text('文字阴影'),
                value: _settings.shadowRadius > 0,
                onChanged: (value) =>
                    _apply(_settings.copyWith(shadowRadius: value ? 4 : 0)),
              ),
              if (_settings.shadowRadius > 0) ...<Widget>[
                _sliderRow(
                  context,
                  key: 'novel-settings-shadow-radius',
                  title: '阴影半径',
                  valueLabel: _settings.shadowRadius.toStringAsFixed(1),
                  value: _settings.shadowRadius,
                  min: 0.5,
                  max: NovelReaderSettings.maxShadowRadius,
                  divisions: 31,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(shadowRadius: value)),
                ),
                _sliderRow(
                  context,
                  key: 'novel-settings-shadow-dx',
                  title: '阴影水平偏移',
                  valueLabel: _settings.shadowOffsetX.toStringAsFixed(0),
                  value: _settings.shadowOffsetX,
                  min: NovelReaderSettings.minShadowOffset,
                  max: NovelReaderSettings.maxShadowOffset,
                  divisions: 16,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(shadowOffsetX: value)),
                ),
                _sliderRow(
                  context,
                  key: 'novel-settings-shadow-dy',
                  title: '阴影垂直偏移',
                  valueLabel: _settings.shadowOffsetY.toStringAsFixed(0),
                  value: _settings.shadowOffsetY,
                  min: NovelReaderSettings.minShadowOffset,
                  max: NovelReaderSettings.maxShadowOffset,
                  divisions: 16,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(shadowOffsetY: value)),
                ),
                _buildShadowColorRow(context),
              ],
              _enumDropdownRow<NovelUnderlineStyle>(
                key: 'novel-settings-underline',
                title: '下划线',
                value: _settings.underlineStyle,
                values: NovelUnderlineStyle.values,
                labelOf: (value) => value.label,
                onChanged: (value) =>
                    _apply(_settings.copyWith(underlineStyle: value)),
              ),
              if (_settings.underlineStyle !=
                  NovelUnderlineStyle.none) ...<Widget>[
                _sliderRow(
                  context,
                  key: 'novel-settings-underline-thickness',
                  title: '下划线粗细',
                  valueLabel: _settings.underlineThickness.toStringAsFixed(1),
                  value: _settings.underlineThickness,
                  min: NovelReaderSettings.minUnderlineThickness,
                  max: NovelReaderSettings.maxUnderlineThickness,
                  divisions: 14,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(underlineThickness: value)),
                ),
                _sliderRow(
                  context,
                  key: 'novel-settings-underline-spacing',
                  title: '下划线间距',
                  valueLabel: _settings.underlineSpacing.toStringAsFixed(1),
                  value: _settings.underlineSpacing,
                  min: NovelReaderSettings.minUnderlineSpacing,
                  max: NovelReaderSettings.maxUnderlineSpacing,
                  divisions: 16,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(underlineSpacing: value)),
                ),
                SwitchListTile(
                  key: const Key('novel-settings-underline-extend'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('下划线延伸'),
                  subtitle: const Text('延伸到段尾空白'),
                  value: _settings.underlineExtend,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(underlineExtend: value)),
                ),
              ],
            ],
          ),
        ),
        _card(
          child: SwitchListTile(
            key: const Key('novel-settings-two-column'),
            contentPadding: EdgeInsets.zero,
            title: const Text('双栏分页'),
            subtitle: const Text('窗口 ≥1100 且横向时生效；标题页不拆'),
            value: _settings.twoColumn,
            onChanged: (value) => _apply(_settings.copyWith(twoColumn: value)),
          ),
        ),
      ],
    );
  }

  Widget _buildShadowColorRow(BuildContext context) {
    final theme = Theme.of(context);
    const palette = <(String, int?)>[
      ('跟随文字', null),
      ('黑', 0xFF000000),
      ('白', 0xFFFFFFFF),
      ('深灰', 0xFF333333),
      ('强调色', null), // 占位，见下方特判
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text('阴影颜色', style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (var i = 0; i < palette.length; i++)
                  InkWell(
                    key: Key('novel-settings-shadow-color-$i'),
                    borderRadius: MimaoShapes.sm,
                    onTap: () => _apply(
                      palette[i].$2 == null && i != palette.length - 1
                          ? _settings.copyWith(clearShadowColor: true)
                          : _applyShadowColor(
                              i == palette.length - 1
                                  ? theme.colorScheme.primary
                                  : Color(palette[i].$2!),
                            ),
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? theme.colorScheme.surfaceContainerHighest
                            : i == palette.length - 1
                            ? theme.colorScheme.primary
                            : Color(palette[i].$2!),
                        borderRadius: MimaoShapes.sm,
                        border: Border.all(
                          color: _shadowColorSelected(i, theme)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: _shadowColorSelected(i, theme) ? 2 : 1,
                        ),
                      ),
                      child: i == 0
                          ? Icon(
                              Icons.text_fields,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _shadowColorSelected(int index, ThemeData theme) {
    final color = _settings.shadowColorArgb;
    if (index == 0) return color == null;
    if (index == 4) {
      return color == theme.colorScheme.primary.toARGB32();
    }
    const values = <int>[0, 0xFF000000, 0xFFFFFFFF, 0xFF333333];
    return index < values.length && color == values[index];
  }

  NovelReaderSettings _applyShadowColor(Color color) =>
      _settings.copyWith(shadowColorArgb: color.toARGB32());

  // ── 菜单 ──────────────────────────────────────────────────────────────
  Widget _buildMenu(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildMenuAppearance(context),
        _buildMenuBarEditor(context, NovelMenuBar.titleBar),
        _buildMenuBarEditor(context, NovelMenuBar.bottomBar),
        _buildMenuBarEditor(context, NovelMenuBar.floatingBar),
        _card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                key: const Key('novel-settings-show-footer'),
                contentPadding: EdgeInsets.zero,
                title: const Text('显示页脚'),
                subtitle: const Text('章节名、本章页码与全书进度'),
                value: _settings.showFooter,
                onChanged: (value) =>
                    _apply(_settings.copyWith(showFooter: value)),
              ),
              SwitchListTile(
                key: const Key('novel-settings-page-transition'),
                contentPadding: EdgeInsets.zero,
                title: const Text('翻页过渡动画'),
                subtitle: const Text('关掉后左右翻页直接换页，不播放过渡'),
                value: _settings.pageAnimation,
                onChanged: (value) =>
                    _apply(_settings.copyWith(pageAnimation: value)),
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('翻页动画风格', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                _settings.pageAnimation
                    ? '左右翻页时新页怎么进场'
                    : '「翻页过渡动画」已关闭，下面选什么都不生效',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              // 风格用下拉而不是 SegmentedButton：六项在窄窗口里挤不下。
              DropdownButtonHideUnderline(
                child: DropdownButton<NovelPageAnimStyle>(
                  key: const Key('novel-settings-page-anim-style'),
                  isExpanded: true,
                  value: _settings.pageAnimStyle,
                  items: <DropdownMenuItem<NovelPageAnimStyle>>[
                    for (final style in NovelPageAnimStyle.values)
                      DropdownMenuItem<NovelPageAnimStyle>(
                        value: style,
                        child: Text(style.label),
                      ),
                  ],
                  onChanged: _settings.pageAnimation
                      ? (picked) {
                          if (picked != null) {
                            _apply(_settings.copyWith(pageAnimStyle: picked));
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('点击与手势', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              ListTile(
                key: const Key('novel-settings-click-zones'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.grid_view),
                title: const Text('点击区（九宫格）'),
                subtitle: Text(_clickZonesSummary()),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openClickZones,
              ),
              const Divider(height: 14),
              _enumDropdownRow<NovelLongPressAction>(
                key: 'novel-settings-long-press',
                title: '长按',
                value: _settings.longPressAction,
                values: NovelLongPressAction.values,
                labelOf: (value) => value.label,
                onChanged: (value) =>
                    _apply(_settings.copyWith(longPressAction: value)),
              ),
              _enumDropdownRow<NovelDoubleTapAction>(
                key: 'novel-settings-double-tap',
                title: '双击',
                value: _settings.doubleTapAction,
                values: NovelDoubleTapAction.values,
                labelOf: (value) => value.label,
                onChanged: (value) =>
                    _apply(_settings.copyWith(doubleTapAction: value)),
              ),
              SwitchListTile(
                key: const Key('novel-settings-swipe-bookmark'),
                contentPadding: EdgeInsets.zero,
                title: const Text('下滑加书签'),
                subtitle: const Text('在正文顶部继续下滑时加/删书签；默认关，避免与回弹抢手势'),
                value: _settings.swipeDownBookmark,
                onChanged: (value) =>
                    _apply(_settings.copyWith(swipeDownBookmark: value)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 菜单外观：每行几个、几行、底栏圆角、图标文字、紧凑标题栏。
  Widget _buildMenuAppearance(BuildContext context) {
    final theme = Theme.of(context);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('菜单外观', style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            '底栏与浮动行共用「每行几个 / 几行」；顶栏最多 '
            '$novelTitleBarMaxActions 个按钮',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _sliderRow(
            context,
            key: 'novel-settings-menu-items-per-row',
            title: '图标每行个数',
            valueLabel: '${_settings.menuIconItemsPerRow}',
            value: _settings.menuIconItemsPerRow.toDouble(),
            min: NovelReaderSettings.minMenuIconItemsPerRow.toDouble(),
            max: NovelReaderSettings.maxMenuIconItemsPerRow.toDouble(),
            divisions:
                NovelReaderSettings.maxMenuIconItemsPerRow -
                NovelReaderSettings.minMenuIconItemsPerRow,
            onChanged: (value) =>
                _apply(_settings.copyWith(menuIconItemsPerRow: value.round())),
          ),
          _sliderRow(
            context,
            key: 'novel-settings-menu-row-count',
            title: '菜单行数',
            valueLabel: '${_settings.menuIconRowCount} 行',
            value: _settings.menuIconRowCount.toDouble(),
            min: NovelReaderSettings.minMenuIconRowCount.toDouble(),
            max: NovelReaderSettings.maxMenuIconRowCount.toDouble(),
            divisions:
                NovelReaderSettings.maxMenuIconRowCount -
                NovelReaderSettings.minMenuIconRowCount,
            onChanged: (value) =>
                _apply(_settings.copyWith(menuIconRowCount: value.round())),
          ),
          _sliderRow(
            context,
            key: 'novel-settings-menu-bottom-radius',
            title: '底栏圆角',
            valueLabel: '${_settings.menuBottomRadius}',
            value: _settings.menuBottomRadius.toDouble(),
            min: NovelReaderSettings.minMenuBottomRadius.toDouble(),
            max: NovelReaderSettings.maxMenuBottomRadius.toDouble(),
            divisions:
                NovelReaderSettings.maxMenuBottomRadius -
                NovelReaderSettings.minMenuBottomRadius,
            onChanged: (value) =>
                _apply(_settings.copyWith(menuBottomRadius: value.round())),
          ),
          SwitchListTile(
            key: const Key('novel-settings-menu-icon-text'),
            contentPadding: EdgeInsets.zero,
            title: const Text('图标显示文字'),
            subtitle: const Text('关掉后只留图标，靠长按/悬停看名字'),
            value: _settings.menuShowIconText,
            onChanged: (value) =>
                _apply(_settings.copyWith(menuShowIconText: value)),
          ),
          SwitchListTile(
            key: const Key('novel-settings-title-bar-compact'),
            contentPadding: EdgeInsets.zero,
            title: const Text('紧凑标题栏'),
            subtitle: const Text('顶栏只留「更多」，书名独占一行'),
            value: _settings.titleBarCompact,
            onChanged: (value) =>
                _apply(_settings.copyWith(titleBarCompact: value)),
          ),
        ],
      ),
    );
  }

  /// 一处菜单栏的按钮编辑器：勾选启用 + 上下移动调顺序。
  ///
  /// 顶栏/底栏/浮动行各存一份配置，互不影响；顺序就是渲染顺序。
  Widget _buildMenuBarEditor(BuildContext context, NovelMenuBar bar) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = _settings.menuBarItems(bar);
    final title = switch (bar) {
      NovelMenuBar.titleBar => '顶栏按钮',
      NovelMenuBar.bottomBar => '底栏按钮',
      NovelMenuBar.floatingBar => '浮动按钮',
    };
    final hint = switch (bar) {
      NovelMenuBar.titleBar => '最多显示 $novelTitleBarMaxActions 个；紧凑标题栏下只留「更多」',
      NovelMenuBar.bottomBar => '底栏滑杆下面的功能键',
      NovelMenuBar.floatingBar => '浮在底栏上方的一排，默认空',
    };
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              TextButton(
                key: Key('novel-settings-menu-reset-${bar.name}'),
                onPressed: () => _resetMenuBar(bar),
                child: const Text('恢复默认'),
              ),
            ],
          ),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              key: Key('novel-settings-menu-empty-${bar.name}'),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                bar == NovelMenuBar.floatingBar
                    ? '还没有浮动按钮；勾选下面的动作把它放到这一行'
                    : '这一行没有按钮；勾选下面的动作把它加回来',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (var i = 0; i < items.length; i++)
            _menuBarRow(bar, items, i, theme, scheme),
          const Divider(height: 16),
          Text(
            '添加动作',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: <Widget>[
              for (final def in novelMenuActionDefs)
                if (!items.any((item) => item.id == def.id))
                  ActionChip(
                    key: Key('novel-settings-menu-add-${bar.name}-${def.id}'),
                    avatar: Icon(def.icon, size: 16),
                    label: Text(def.label),
                    onPressed: () => _addMenuBarItem(bar, def.id),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _menuBarRow(
    NovelMenuBar bar,
    List<NovelMenuButtonItem> items,
    int index,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final item = items[index];
    final def = novelMenuActionById(item.id);
    final label = def?.label ?? item.id;
    return Padding(
      key: Key('novel-settings-menu-row-${bar.name}-${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          Checkbox(
            key: Key('novel-settings-menu-toggle-${bar.name}-${item.id}'),
            value: item.enabled,
            onChanged: (value) =>
                _setMenuBarItem(bar, index, item.copyWith(enabled: value)),
          ),
          Icon(
            def?.icon ?? Icons.help_outline,
            size: 18,
            color: scheme.onSurface,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: item.enabled
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            key: Key('novel-settings-menu-up-${bar.name}-${item.id}'),
            tooltip: '上移',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: index == 0
                ? null
                : () => _moveMenuBarItem(bar, index, -1),
          ),
          IconButton(
            key: Key('novel-settings-menu-down-${bar.name}-${item.id}'),
            tooltip: '下移',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: index == items.length - 1
                ? null
                : () => _moveMenuBarItem(bar, index, 1),
          ),
          IconButton(
            key: Key('novel-settings-menu-remove-${bar.name}-${item.id}'),
            tooltip: '移除',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            onPressed: () => _removeMenuBarItem(bar, index),
          ),
        ],
      ),
    );
  }

  void _setMenuBarItem(NovelMenuBar bar, int index, NovelMenuButtonItem item) {
    final items = List<NovelMenuButtonItem>.from(_settings.menuBarItems(bar));
    if (index < 0 || index >= items.length) return;
    items[index] = item;
    _apply(_settings.withMenuBar(bar, items));
  }

  void _moveMenuBarItem(NovelMenuBar bar, int index, int delta) {
    final items = List<NovelMenuButtonItem>.from(_settings.menuBarItems(bar));
    final target = index + delta;
    if (target < 0 || target >= items.length) return;
    final moved = items.removeAt(index);
    items.insert(target, moved);
    _apply(_settings.withMenuBar(bar, items));
  }

  void _removeMenuBarItem(NovelMenuBar bar, int index) {
    final items = List<NovelMenuButtonItem>.from(_settings.menuBarItems(bar));
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    _apply(_settings.withMenuBar(bar, items));
  }

  void _addMenuBarItem(NovelMenuBar bar, String id) {
    final items = List<NovelMenuButtonItem>.from(_settings.menuBarItems(bar));
    if (items.any((item) => item.id == id)) return;
    items.add(NovelMenuButtonItem(id));
    _apply(_settings.withMenuBar(bar, items));
  }

  void _resetMenuBar(NovelMenuBar bar) {
    final defaults = switch (bar) {
      NovelMenuBar.titleBar => novelDefaultTitleBarMenu,
      NovelMenuBar.bottomBar => novelDefaultBottomBarMenu,
      NovelMenuBar.floatingBar => novelDefaultFloatingMenu,
    };
    _apply(
      _settings.withMenuBar(bar, List<NovelMenuButtonItem>.from(defaults)),
    );
  }

  /// 九宫格摘要：只列非「无动作」的格子，一眼看出配了哪几格。
  String _clickZonesSummary() {
    final zones = _settings.clickZones;
    final parts = <String>[];
    for (final zone in NovelClickZone.values) {
      final action = zones[zone.index];
      if (action != NovelClickAction.none) {
        parts.add('${zone.label}=${action.label}');
      }
    }
    return parts.isEmpty ? '九格都没有动作' : parts.join(' · ');
  }

  Future<void> _openClickZones() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      builder: (sheetContext) => Theme(
        data: Theme.of(context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            MediaQuery.paddingOf(sheetContext).bottom + 12,
          ),
          child: NovelClickZoneSheet(
            settings: _settings,
            onChanged: _apply,
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  // ── 信息 ──────────────────────────────────────────────────────────────
  Widget _buildInfo(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final rows = <(String, String)>[
      ('书名', info.bookTitle),
      ('作者', info.author.isEmpty ? '—' : info.author),
      ('书源', info.sourceName.isEmpty ? '—' : info.sourceName),
      ('当前章节', info.chapterTitle),
      ('章节序号', '${info.chapterIndex} / ${info.chapterCount}'),
      ('本章页码', '${info.page} / ${info.pageCount}'),
      ('全书进度', '${info.percent.toStringAsFixed(1)}%'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('页脚三槽', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              _chromeSlotRow(
                key: 'novel-settings-footer-left',
                title: '页脚左槽',
                slots: _settings.footerSlots,
                index: 0,
                onChanged: (slots) =>
                    _apply(_settings.copyWith(footerSlots: slots)),
              ),
              _chromeSlotRow(
                key: 'novel-settings-footer-center',
                title: '页脚中槽',
                slots: _settings.footerSlots,
                index: 1,
                onChanged: (slots) =>
                    _apply(_settings.copyWith(footerSlots: slots)),
              ),
              _chromeSlotRow(
                key: 'novel-settings-footer-right',
                title: '页脚右槽',
                slots: _settings.footerSlots,
                index: 2,
                onChanged: (slots) =>
                    _apply(_settings.copyWith(footerSlots: slots)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-footer-font-size',
                title: '页脚字号',
                valueLabel: _settings.footerFontSize.toStringAsFixed(0),
                value: _settings.footerFontSize,
                min: NovelReaderSettings.minChromeFontSize,
                max: NovelReaderSettings.maxChromeFontSize,
                divisions: 16,
                onChanged: (value) =>
                    _apply(_settings.copyWith(footerFontSize: value)),
              ),
              if (_settings.footerSlots.contains(NovelChromeSlot.custom))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextFormField(
                    key: const Key('novel-settings-footer-custom-text'),
                    initialValue: _settings.footerCustomText,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '页脚自定义文案',
                    ),
                    onChanged: (value) =>
                        _apply(_settings.copyWith(footerCustomText: value)),
                  ),
                ),
              const Divider(height: 14),
              SwitchListTile(
                key: const Key('novel-settings-show-header'),
                contentPadding: EdgeInsets.zero,
                title: const Text('显示页眉'),
                value: _settings.showHeader,
                onChanged: (value) =>
                    _apply(_settings.copyWith(showHeader: value)),
              ),
              if (_settings.showHeader) ...<Widget>[
                _chromeSlotRow(
                  key: 'novel-settings-header-left',
                  title: '页眉左槽',
                  slots: _settings.headerSlots,
                  index: 0,
                  onChanged: (slots) =>
                      _apply(_settings.copyWith(headerSlots: slots)),
                ),
                _chromeSlotRow(
                  key: 'novel-settings-header-center',
                  title: '页眉中槽',
                  slots: _settings.headerSlots,
                  index: 1,
                  onChanged: (slots) =>
                      _apply(_settings.copyWith(headerSlots: slots)),
                ),
                _chromeSlotRow(
                  key: 'novel-settings-header-right',
                  title: '页眉右槽',
                  slots: _settings.headerSlots,
                  index: 2,
                  onChanged: (slots) =>
                      _apply(_settings.copyWith(headerSlots: slots)),
                ),
                _sliderRow(
                  context,
                  key: 'novel-settings-header-font-size',
                  title: '页眉字号',
                  valueLabel: _settings.headerFontSize.toStringAsFixed(0),
                  value: _settings.headerFontSize,
                  min: NovelReaderSettings.minChromeFontSize,
                  max: NovelReaderSettings.maxChromeFontSize,
                  divisions: 16,
                  onChanged: (value) =>
                      _apply(_settings.copyWith(headerFontSize: value)),
                ),
                if (_settings.headerSlots.contains(NovelChromeSlot.custom))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TextFormField(
                      key: const Key('novel-settings-header-custom-text'),
                      initialValue: _settings.headerCustomText,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '页眉自定义文案',
                      ),
                      onChanged: (value) =>
                          _apply(_settings.copyWith(headerCustomText: value)),
                    ),
                  ),
              ],
            ],
          ),
        ),
        _card(
          child: Column(
            children: <Widget>[
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == rows.length - 1 ? 0 : 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 76,
                        child: Text(
                          rows[i].$1,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rows[i].$2,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 页眉/页脚单槽下拉行。
  Widget _chromeSlotRow({
    required String key,
    required String title,
    required List<NovelChromeSlot> slots,
    required int index,
    required ValueChanged<List<NovelChromeSlot>> onChanged,
  }) {
    final current = index < slots.length ? slots[index] : NovelChromeSlot.none;
    return _enumDropdownRow<NovelChromeSlot>(
      key: key,
      title: title,
      value: current,
      values: NovelChromeSlot.values,
      labelOf: (value) => value.label,
      onChanged: (value) {
        final next = List<NovelChromeSlot>.from(slots);
        while (next.length < 3) {
          next.add(NovelChromeSlot.none);
        }
        next[index] = value;
        onChanged(next);
      },
    );
  }

  /// 通用枚举下拉行。
  Widget _enumDropdownRow<T>({
    required String key,
    required String title,
    required T value,
    required List<T> values,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(title, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                key: Key(key),
                isExpanded: true,
                value: value,
                items: <DropdownMenuItem<T>>[
                  for (final item in values)
                    DropdownMenuItem<T>(
                      value: item,
                      child: Text(labelOf(item)),
                    ),
                ],
                onChanged: (picked) {
                  if (picked != null) onChanged(picked);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 更多 ──────────────────────────────────────────────────────────────
  Widget _buildMore(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 朗读放最上面：这是「更多」里改动频率最高的一组，也免得用户在
        // 一段长滑杆里翻找。
        _card(child: _buildTtsSettings(context)),
        const SizedBox(height: 8),
        _card(
          child: Column(
            children: <Widget>[
              _sliderRow(
                context,
                key: 'novel-settings-auto-interval-slider',
                title: '自动翻页间隔',
                valueLabel: '${_settings.autoPageSeconds} 秒',
                value: _settings.autoPageSeconds.toDouble(),
                min: NovelReaderSettings.minAutoPageSeconds.toDouble(),
                max: NovelReaderSettings.maxAutoPageSeconds.toDouble(),
                divisions:
                    NovelReaderSettings.maxAutoPageSeconds -
                    NovelReaderSettings.minAutoPageSeconds,
                onChanged: (value) =>
                    _apply(_settings.copyWith(autoPageSeconds: value.round())),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-line-height',
                title: '行距',
                valueLabel: _settings.lineHeight.toStringAsFixed(1),
                value: _settings.lineHeight,
                min: NovelReaderSettings.minLineHeight,
                max: NovelReaderSettings.maxLineHeight,
                divisions: 26,
                onChanged: (value) =>
                    _apply(_settings.copyWith(lineHeight: value)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-paragraph-spacing',
                title: '段距',
                valueLabel: '${_settings.paragraphSpacing.round()}',
                value: _settings.paragraphSpacing,
                min: NovelReaderSettings.minParagraphSpacing,
                max: NovelReaderSettings.maxParagraphSpacing,
                divisions: 16,
                onChanged: (value) =>
                    _apply(_settings.copyWith(paragraphSpacing: value)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-horizontal-padding',
                title: '左右边距',
                valueLabel: '${_settings.horizontalPadding.round()}',
                value: _settings.horizontalPadding,
                min: NovelReaderSettings.minHorizontalPadding,
                max: NovelReaderSettings.maxHorizontalPadding,
                divisions: 26,
                onChanged: (value) =>
                    _apply(_settings.copyWith(horizontalPadding: value)),
              ),
              _sliderRow(
                context,
                key: 'novel-settings-dim-brightness',
                title: '阅读亮度',
                valueLabel: '${_settings.dimBrightness}',
                value: _settings.dimBrightness.toDouble(),
                min: 20,
                max: 100,
                divisions: 80,
                onChanged: (value) =>
                    _apply(_settings.copyWith(dimBrightness: value.round())),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('novel-settings-reset'),
            onPressed: () => _apply(const NovelReaderSettings()),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('恢复默认设置'),
          ),
        ),
      ],
    );
  }

  /// 朗读设置卡：语速 / 音色 / 段间停顿 / 自动续章 / 手动翻页 / 睡眠定时。
  ///
  /// 这些项都是全局设置（每书覆盖白名单只收背景/字体/翻页/动画/点击区），
  /// 「只改这本」开着时由控制器把差异落全局，不会静默丢弃。
  Widget _buildTtsSettings(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final voiceValue = _ttsVoices.any((v) => v.id == _settings.ttsVoice)
        ? _settings.ttsVoice
        : '';
    final remaining = _sleepRemaining();
    final hasSleep = _sleepDeadline != null && remaining > Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.record_voice_over_outlined,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '朗读',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: MimaoFonts.bold,
              ),
            ),
            const Spacer(),
            if (hasSleep)
              Text(
                '剩余 ${_sleepLabel()}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _sliderRow(
          context,
          key: 'novel-settings-tts-rate',
          title: '语速',
          valueLabel: '×${_settings.ttsRate.toStringAsFixed(1)}',
          value: _settings.ttsRate,
          min: NovelReaderSettings.minTtsRate,
          max: NovelReaderSettings.maxTtsRate,
          divisions: 15,
          onChanged: (value) => _apply(
            _settings.copyWith(ttsRate: (value * 10).roundToDouble() / 10),
          ),
        ),
        _sliderRow(
          context,
          key: 'novel-settings-tts-pause',
          title: '段间停顿',
          valueLabel: '${_settings.ttsParagraphPauseMs} ms',
          value: _settings.ttsParagraphPauseMs.toDouble(),
          min: NovelReaderSettings.minTtsParagraphPauseMs.toDouble(),
          max: NovelReaderSettings.maxTtsParagraphPauseMs.toDouble(),
          divisions:
              (NovelReaderSettings.maxTtsParagraphPauseMs -
                  NovelReaderSettings.minTtsParagraphPauseMs) ~/
              100,
          onChanged: (value) => _apply(
            _settings.copyWith(
              ttsParagraphPauseMs: (value / 100).round() * 100,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 88,
                child: Text('音色', style: theme.textTheme.bodyMedium),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('novel-settings-tts-voice'),
                    isExpanded: true,
                    value: voiceValue,
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('自动（中文优先）'),
                      ),
                      for (final voice in _ttsVoices)
                        DropdownMenuItem<String>(
                          value: voice.id,
                          child: Text(
                            voice.locale.isEmpty
                                ? voice.label
                                : '${voice.label} · ${voice.locale}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _apply(_settings.copyWith(ttsVoice: value));
                    },
                  ),
                ),
              ),
              if (_loadingTtsVoices)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: '刷新系统音色',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    setState(() => _ttsVoices = const <NovelTtsVoice>[]);
                    unawaited(_loadTtsVoices());
                  },
                ),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('novel-settings-tts-auto-next'),
          contentPadding: EdgeInsets.zero,
          title: const Text('读完自动续章'),
          subtitle: const Text('本章读完接着读下一章，直到书末或手动停止'),
          value: _settings.ttsAutoNextChapter,
          onChanged: (value) =>
              _apply(_settings.copyWith(ttsAutoNextChapter: value)),
        ),
        _enumDropdownRow<NovelTtsTurnPolicy>(
          key: 'novel-settings-tts-turn-policy',
          title: '手动翻页',
          value: _settings.ttsTurnPagePolicy,
          values: NovelTtsTurnPolicy.values,
          labelOf: (value) => value.label,
          onChanged: (value) =>
              _apply(_settings.copyWith(ttsTurnPagePolicy: value)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 88,
                child: Text('睡眠定时', style: theme.textTheme.bodyMedium),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    for (final minutes in const <int>[0, 15, 30, 60])
                      ChoiceChip(
                        key: Key('novel-settings-tts-sleep-$minutes'),
                        label: Text(minutes == 0 ? '关闭' : '$minutes 分钟'),
                        selected: minutes == 0
                            ? !hasSleep
                            : hasSleep &&
                                  (remaining.inSeconds + 30) ~/ 60 == minutes,
                        onSelected: (_) => _setSleepTimer(
                          minutes == 0 ? null : Duration(minutes: minutes),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text(
          '睡眠定时只在本次阅读有效；到点停止朗读并提示。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (widget.loadTtsCacheStats != null || widget.onClearTtsCache != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _ttsCacheStats == null
                        ? '音频缓存：读取中…'
                        : '音频缓存：${_ttsCacheStats!.count} 段 · '
                              '${_formatBytes(_ttsCacheStats!.bytes)} / '
                              '${_formatBytes(_ttsCacheStats!.maxBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('novel-settings-tts-cache-clear'),
                  onPressed: _loadingTtsCache || widget.onClearTtsCache == null
                      ? null
                      : () => unawaited(_clearTtsCache()),
                  child: const Text('清理'),
                ),
              ],
            ),
          ),
        if (widget.onExportChapterAudio != null ||
            widget.onExportBookAudio != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                if (widget.onExportChapterAudio != null)
                  OutlinedButton.icon(
                    key: const Key('novel-settings-tts-export-chapter'),
                    onPressed: () =>
                        unawaited(widget.onExportChapterAudio!.call()),
                    icon: const Icon(Icons.audio_file_outlined, size: 18),
                    label: const Text('导出本章音频'),
                  ),
                if (widget.onExportBookAudio != null)
                  OutlinedButton.icon(
                    key: const Key('novel-settings-tts-export-book'),
                    onPressed: () =>
                        unawaited(widget.onExportBookAudio!.call()),
                    icon: const Icon(Icons.library_music_outlined, size: 18),
                    label: const Text('导出全书音频'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTabs(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: MimaoShapes.pill,
      ),
      child: Row(
        children: <Widget>[
          for (final tab in _SettingsTab.values)
            Expanded(
              child: GestureDetector(
                key: Key('novel-settings-tab-${tab.name}'),
                onTap: () => _selectTab(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == tab
                        ? scheme.primaryContainer
                        : const Color(0x00000000),
                    borderRadius: MimaoShapes.pill,
                  ),
                  child: Text(
                    _tabLabels[tab]!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _tab == tab
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 通用小组件 ────────────────────────────────────────────────────────
  Widget _card({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    // 用 Material 承载底色，ListTile/SwitchListTile 的水波纹才不会被 DecoratedBox 挡住。
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: MimaoShapes.md,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: child,
        ),
      ),
    );
  }

  Widget _stepButton({
    required String key,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton(
      key: Key(key),
      tooltip: icon == Icons.add ? '增大字号' : '减小字号',
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20),
      onPressed: onTap,
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }

  Widget _squareButton({
    required String key,
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: Key(key),
        onTap: onTap,
        borderRadius: MimaoShapes.md,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: MimaoShapes.md,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _backgroundTile({
    required String key,
    required String tooltip,
    required Color color,
    required bool selected,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: Key(key),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 56,
          height: 82,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: MimaoShapes.md,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 20, color: scheme.primary)
              : child,
        ),
      ),
    );
  }

  Widget _sliderRow(
    BuildContext context, {
    required String key,
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
              Text(
                valueLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: Key(key),
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ── 弹窗 ──────────────────────────────────────────────────────────────
  Future<void> _pickFont() async {
    var importRequested = false;
    final picked = await showDialog<NovelReaderFont>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('正文字体'),
        children: <Widget>[
          for (final font in novelReaderFonts)
            ListTile(
              leading: Icon(
                _settings.fontFamily == font.family
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
              ),
              title: Text(
                font.name,
                style: TextStyle(
                  fontFamily: font.family.isEmpty ? null : font.family,
                ),
              ),
              onTap: () => Navigator.of(context).pop(font),
            ),
          if (_importedFonts.isNotEmpty) const Divider(height: 8),
          for (final font in _importedFonts)
            ListTile(
              leading: Icon(
                _settings.fontFamily == font.family
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
              ),
              title: Text(
                font.label,
                style: TextStyle(fontFamily: font.family),
              ),
              subtitle: const Text('导入字体'),
              onTap: () => Navigator.of(
                context,
              ).pop(NovelReaderFont(font.label, font.family)),
            ),
          const Divider(height: 8),
          ListTile(
            key: const Key('novel-settings-font-import'),
            leading: const Icon(Icons.file_open_outlined, size: 20),
            title: const Text('导入本地字体…'),
            subtitle: const Text('支持 .ttf / .otf'),
            onTap: () {
              importRequested = true;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (importRequested) {
      await _importFont();
      return;
    }
    if (picked != null) {
      _apply(_settings.copyWith(fontFamily: picked.family));
    }
  }

  Future<void> _importFont() async {
    final path = await pickNovelFontFile();
    if (path == null || !mounted) return;
    final font = await NovelFontRegistry.instance.importFile(path);
    if (!mounted) return;
    if (font == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('字体导入失败，请确认文件是有效的 .ttf/.otf')),
      );
      return;
    }
    setState(() {
      _importedFonts = <NovelFontFile>[
        ..._importedFonts.where((item) => item.family != font.family),
        font,
      ]..sort((a, b) => a.label.compareTo(b.label));
    });
    _apply(_settings.copyWith(fontFamily: font.family));
  }

  Future<void> _pickBackgroundImage() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择阅读背景图',
      type: FileType.image,
    );
    if (files.isEmpty || !mounted) return;
    final path = files.first.path;
    if (path == null) return;
    _apply(_settings.copyWith(backgroundImagePath: path));
  }

  Future<void> _pickCustomColor() async {
    const palette = <int>[
      0xFF000000,
      0xFF1C1C1C,
      0xFF2B2B2B,
      0xFF3A3A3A,
      0xFF4A4A4A,
      0xFF1C2A24,
      0xFF2A1F2A,
      0xFFEDE4D3,
      0xFFF2E6CF,
      0xFFF7F1E4,
      0xFFDCE8D5,
      0xFFE7E3F5,
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('自定义背景色'),
          content: SizedBox(
            width: 320,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final argb in palette)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(argb),
                    borderRadius: MimaoShapes.md,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Color(argb),
                        borderRadius: MimaoShapes.md,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      _apply(_settings.useCustomBackground(picked));
    }
  }

  Future<void> _pickAnimationSpeed() async {
    const options = <(String, int)>[
      ('极速', 120),
      ('快速', 200),
      ('适中', 260),
      ('优雅', 400),
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('翻页动画速度'),
        children: <Widget>[
          for (final option in options)
            ListTile(
              leading: Icon(
                _settings.pageAnimationMs == option.$2
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
              ),
              title: Text(option.$1),
              onTap: () => Navigator.of(context).pop(option.$2),
            ),
        ],
      ),
    );
    if (picked != null && mounted) {
      _apply(_settings.copyWith(pageAnimationMs: picked));
    }
  }

  Future<void> _pickMargins() async {
    var padding = _settings.horizontalPadding;
    final picked = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('页边距'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: padding,
                  min: NovelReaderSettings.minHorizontalPadding,
                  max: NovelReaderSettings.maxHorizontalPadding,
                  divisions: 26,
                  label: '${padding.round()}',
                  onChanged: (value) => setDialogState(() => padding = value),
                ),
              ),
              Text('${padding.round()}'),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(padding),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (picked != null && mounted) {
      _apply(_settings.copyWith(horizontalPadding: picked));
    }
  }
}
