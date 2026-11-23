// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读器浮层组件：顶部栏、底部菜单面板、页脚。
//
// 颜色取自当前阅读背景（深底浅字 / 浅底深字），这是「覆盖在阅读画布上」
// 的例外场景；面板本身用与背景同族的加深/提亮色，不用 ColorScheme 角色，
// 否则选羊皮纸背景时会出现灰色面板。其余尺寸/圆角仍走 [MimaoRadii]。

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'novel_reader_settings.dart';

/// 阅读背景色。
Color novelReaderBackgroundColor(NovelReaderSettings settings) =>
    Color(settings.backgroundColorArgb);

/// 正文/图标的主文字色。
Color novelReaderTextColor(NovelReaderSettings settings) =>
    Color(settings.textColorArgb);

/// 次级文字色。
Color novelReaderSecondaryColor(NovelReaderSettings settings) =>
    Color(settings.secondaryTextColorArgb);

/// 浮层面板色：深色底加深、浅色底提亮，保证与背景分层。
Color novelReaderPanelColor(NovelReaderSettings settings) {
  final dark = settings.darkBackground;
  final bg = novelReaderBackgroundColor(settings);
  return Color.lerp(
    bg,
    dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    dark ? 0.34 : 0.55,
  )!;
}

/// 顶部栏：返回 / 书名章节名 / 缓存、刷新、换源、更多 / 当前书源名。
class NovelReaderTopBar extends StatelessWidget {
  const NovelReaderTopBar({
    super.key,
    required this.settings,
    required this.bookTitle,
    required this.chapterTitle,
    required this.sourceName,
    required this.onBack,
    required this.onDownload,
    required this.onRefresh,
    required this.onSwitchSource,
    required this.onMore,
  });

  final NovelReaderSettings settings;
  final String bookTitle;
  final String chapterTitle;
  final String sourceName;
  final VoidCallback onBack;
  final VoidCallback onDownload;
  final VoidCallback onRefresh;
  final VoidCallback onSwitchSource;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = novelReaderTextColor(settings);
    final secondary = novelReaderSecondaryColor(settings);
    final bg = novelReaderBackgroundColor(settings);
    return Material(
      color: bg.withValues(alpha: 0.94),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 48,
              child: Row(
                children: <Widget>[
                  IconButton(
                    key: const Key('novel-reader-back'),
                    tooltip: '返回',
                    color: text,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('novel-reader-download'),
                    tooltip: '缓存本章',
                    color: text,
                    icon: const Icon(Icons.cloud_download_outlined),
                    onPressed: onDownload,
                  ),
                  IconButton(
                    key: const Key('novel-reader-refresh'),
                    tooltip: '刷新本章',
                    color: text,
                    icon: const Icon(Icons.refresh),
                    onPressed: onRefresh,
                  ),
                  IconButton(
                    key: const Key('novel-reader-switch-source'),
                    tooltip: '换源',
                    color: text,
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: onSwitchSource,
                  ),
                  IconButton(
                    key: const Key('novel-reader-more'),
                    tooltip: '更多',
                    color: text,
                    icon: const Icon(Icons.more_vert),
                    onPressed: onMore,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          bookTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: text,
                            fontWeight: MimaoFonts.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sourceName.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 12),
                    InkWell(
                      key: const Key('novel-reader-source-name'),
                      onTap: onSwitchSource,
                      borderRadius: MimaoShapes.sm,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          sourceName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部菜单面板：亮度 / 章节进度滑杆 / 五个功能键。
class NovelReaderBottomPanel extends StatelessWidget {
  const NovelReaderBottomPanel({
    super.key,
    required this.settings,
    required this.brightness,
    required this.onBrightnessChanged,
    required this.showAutoBrightness,
    required this.autoBrightness,
    required this.onToggleAutoBrightness,
    required this.page,
    required this.pageCount,
    required this.onSeekPage,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onSearch,
    required this.onToggleAutoPage,
    required this.onCatalog,
    required this.onTts,
    required this.onSettings,
    this.autoReading = false,
    this.speaking = false,
  });

  final NovelReaderSettings settings;
  final double brightness;
  final ValueChanged<double> onBrightnessChanged;
  final bool showAutoBrightness;
  final bool autoBrightness;
  final VoidCallback onToggleAutoBrightness;
  final int page;
  final int pageCount;
  final ValueChanged<int> onSeekPage;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onSearch;
  final VoidCallback onToggleAutoPage;
  final VoidCallback onCatalog;
  final VoidCallback onTts;
  final VoidCallback onSettings;
  final bool autoReading;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = novelReaderTextColor(settings);
    final secondary = novelReaderSecondaryColor(settings);
    final panel = novelReaderPanelColor(settings);
    final scheme = theme.colorScheme;
    final maxPage = pageCount < 1 ? 1 : pageCount;

    return Material(
      color: panel,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.xl),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 第一行：自动亮度 + 亮度滑杆。
            Row(
              children: <Widget>[
                if (showAutoBrightness)
                  Tooltip(
                    message: '自动亮度',
                    child: InkWell(
                      key: const Key('novel-reader-auto-brightness'),
                      onTap: onToggleAutoBrightness,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: autoBrightness
                              ? scheme.primary
                              : text.withValues(alpha: 0.10),
                          border: Border.all(
                            color: autoBrightness
                                ? scheme.primary
                                : text.withValues(alpha: 0.26),
                          ),
                        ),
                        child: Text(
                          'A',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: autoBrightness ? scheme.onPrimary : text,
                            fontWeight: MimaoFonts.bold,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 6),
                Expanded(
                  child: _slimSlider(
                    context,
                    key: 'novel-reader-brightness',
                    value: autoBrightness ? 100 : brightness.clamp(20, 100),
                    min: 20,
                    max: 100,
                    onChanged: autoBrightness ? null : onBrightnessChanged,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            // 第二行：上一章 / 章节内进度 / 下一章。
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('novel-reader-prev-page'),
                  tooltip: '上一章',
                  color: secondary,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: onPrevChapter,
                ),
                Expanded(
                  child: _slimSlider(
                    context,
                    key: 'novel-reader-page-slider',
                    value: page.clamp(1, maxPage).toDouble(),
                    min: 1,
                    max: maxPage.toDouble(),
                    divisions: maxPage <= 1 ? 1 : maxPage - 1,
                    label: '$page/$maxPage',
                    onChanged: (value) => onSeekPage(value.round()),
                  ),
                ),
                IconButton(
                  key: const Key('novel-reader-next-page'),
                  tooltip: '下一章',
                  color: secondary,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: onNextChapter,
                ),
              ],
            ),
            const SizedBox(height: 2),
            // 第三行：搜索 / 自动翻页 / 目录 / 朗读 / 设置。
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                _action(
                  context,
                  key: 'novel-reader-search',
                  tooltip: '书内搜索',
                  icon: Icons.search,
                  color: text,
                  onPressed: onSearch,
                ),
                _action(
                  context,
                  key: 'novel-reader-auto-page',
                  tooltip: autoReading ? '停止自动翻页' : '自动翻页',
                  icon: autoReading ? Icons.pause : Icons.play_arrow,
                  color: text,
                  active: autoReading,
                  onPressed: onToggleAutoPage,
                ),
                _action(
                  context,
                  key: 'novel-reader-catalog',
                  tooltip: '目录',
                  icon: Icons.menu,
                  color: text,
                  onPressed: onCatalog,
                ),
                _action(
                  context,
                  key: 'novel-reader-tts',
                  tooltip: speaking ? '停止朗读' : '语音朗读',
                  icon: Icons.record_voice_over_outlined,
                  color: text,
                  active: speaking,
                  onPressed: onTts,
                ),
                _action(
                  context,
                  key: 'novel-reader-settings',
                  tooltip: '阅读设置',
                  icon: Icons.settings_outlined,
                  color: text,
                  onPressed: onSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required String key,
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: Key(key),
      tooltip: tooltip,
      color: active ? scheme.primary : color,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget _slimSlider(
    BuildContext context, {
    required String key,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double>? onChanged,
    int? divisions,
    String? label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final text = novelReaderTextColor(settings);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: text.withValues(alpha: 0.18),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        key: Key(key),
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
    );
  }
}

/// 页脚：按设置里的左/右槽位拼内容（对照 legado 的页脚三槽）。
class NovelReaderFooter extends StatelessWidget {
  const NovelReaderFooter({
    super.key,
    required this.settings,
    required this.chapterTitle,
    required this.bookTitle,
    required this.page,
    required this.pageCount,
    required this.percent,
  });

  final NovelReaderSettings settings;
  final String chapterTitle;
  final String bookTitle;
  final int page;
  final int pageCount;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = novelReaderSecondaryColor(settings);
    final style = theme.textTheme.labelSmall?.copyWith(color: secondary);
    final leftText = switch (settings.footerLeft) {
      NovelFooterLeft.chapter => chapterTitle,
      NovelFooterLeft.book => bookTitle,
      NovelFooterLeft.none => '',
    };
    final rightText = switch (settings.footerRight) {
      NovelFooterRight.pageAndPercent =>
        '$page/$pageCount  ${percent.toStringAsFixed(1)}%',
      NovelFooterRight.page => '$page/$pageCount',
      NovelFooterRight.percent => '${percent.toStringAsFixed(1)}%',
      NovelFooterRight.none => '',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        settings.horizontalPadding,
        6,
        settings.horizontalPadding,
        10,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              leftText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (rightText.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Text(rightText, style: style),
          ],
        ],
      ),
    );
  }
}

/// 章节目录（底部抽屉）：按卷分组，当前章高亮，VIP 章显示锁。
class NovelCatalogSheet extends StatefulWidget {
  const NovelCatalogSheet({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onPick,
    required this.settings,
  });

  final List<({String title, bool isVolume, bool isVip})> chapters;
  final int currentIndex;
  final ValueChanged<int> onPick;
  final NovelReaderSettings settings;

  @override
  State<NovelCatalogSheet> createState() => _NovelCatalogSheetState();
}

class _NovelCatalogSheetState extends State<NovelCatalogSheet> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: (widget.currentIndex - 4).clamp(0, 100000) * 48.0,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = novelReaderSecondaryColor(widget.settings);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: <Widget>[
                  Text('目录', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.chapters.length} 章',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('novel-catalog-close'),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: const Key('novel-catalog-list'),
                controller: _scroll,
                itemCount: widget.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = widget.chapters[index];
                  if (chapter.isVolume) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(
                        chapter.title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: secondary,
                        ),
                      ),
                    );
                  }
                  final selected = index == widget.currentIndex;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: theme.colorScheme.secondaryContainer
                        .withValues(alpha: 0.55),
                    title: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: selected
                          ? TextStyle(color: theme.colorScheme.primary)
                          : null,
                    ),
                    trailing: chapter.isVip
                        ? Icon(Icons.lock_outline, size: 14, color: secondary)
                        : null,
                    onTap: () => widget.onPick(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
