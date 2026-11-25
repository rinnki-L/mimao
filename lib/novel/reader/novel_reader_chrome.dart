// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读器浮层组件：顶部栏、底部菜单面板、页脚。
//
// 颜色取自当前阅读背景（深底浅字 / 浅底深字），这是「覆盖在阅读画布上」
// 的例外场景；面板本身用与背景同族的加深/提亮色，不用 ColorScheme 角色，
// 否则选羊皮纸背景时会出现灰色面板。其余尺寸/圆角仍走 [MimaoRadii]。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'novel_click_actions.dart';
import 'novel_menu_actions.dart';
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

/// 解析一个菜单动作的点击回调；返回 null 表示该动作在当前页面没有入口
/// （按钮仍渲染但禁用，避免「配了却消失」让人以为设置没生效）。
typedef NovelMenuActionOnTap = VoidCallback? Function(NovelMenuActionDef def);

/// 顶部栏：返回 / 书名章节名 / 按注册表渲染的按钮 / 当前书源名。
///
/// 按钮清单来自 [NovelReaderSettings.titleBarMenu]：先按
/// [resolveNovelTitleBarActions] 过滤掉不可用项、截断到
/// [novelTitleBarMaxActions]，紧凑模式下只留「更多」。
class NovelReaderTopBar extends StatelessWidget {
  const NovelReaderTopBar({
    super.key,
    required this.settings,
    required this.bookTitle,
    required this.chapterTitle,
    required this.sourceName,
    required this.onBack,
    required this.onTap,
    this.actionContext = const NovelMenuActionContext(),
  });

  final NovelReaderSettings settings;
  final String bookTitle;
  final String chapterTitle;
  final String sourceName;
  final VoidCallback onBack;
  final NovelMenuActionOnTap onTap;
  final NovelMenuActionContext actionContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = novelReaderTextColor(settings);
    final secondary = novelReaderSecondaryColor(settings);
    final bg = novelReaderBackgroundColor(settings);
    final actions = resolveNovelTitleBarActions(
      items: settings.titleBarMenu,
      context: actionContext,
      compact: settings.titleBarCompact,
    );
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
                  for (final def in actions)
                    IconButton(
                      key: Key(novelMenuActionKey(def.id)),
                      tooltip: def.label,
                      color: text,
                      icon: Icon(def.icon),
                      onPressed: onTap(def),
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
                        // 紧凑标题栏连副标题一起收掉：只留书名，把纵向空间
                        // 还给正文。
                        if (!settings.titleBarCompact) ...<Widget>[
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
                      ],
                    ),
                  ),
                  // 书源名与「换源」是同一件事，紧凑模式下按钮都没了，
                  // 这里也不再单独占位。
                  if (sourceName.isNotEmpty &&
                      !settings.titleBarCompact) ...<Widget>[
                    const SizedBox(width: 12),
                    InkWell(
                      key: const Key('novel-reader-source-name'),
                      onTap: onTap(
                        novelMenuActionById(novelMenuActionSwitchSource)!,
                      ),
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

/// 底部菜单面板：亮度 / 章节进度滑杆 / 按注册表渲染的功能键网格。
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
    this.scrollMode = false,
    this.progress = 0,
    this.onSeekProgress,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onTap,
    this.actionContext = const NovelMenuActionContext(),
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

  /// 滚动模式没有「页」的概念，进度条改按章内滚动比例走。
  final bool scrollMode;
  final double progress;
  final ValueChanged<double>? onSeekProgress;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final NovelMenuActionOnTap onTap;
  final NovelMenuActionContext actionContext;
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
    final actions = resolveNovelMenuActions(
      items: settings.bottomBarMenu,
      context: actionContext,
    );
    final layout = layoutNovelMenuRows(
      actions: actions,
      itemsPerRow: settings.menuIconItemsPerRow,
      rowCount: settings.menuIconRowCount,
      showMore: false,
    );

    return Material(
      color: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(settings.menuBottomRadiusValue),
      ),
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
                  child: scrollMode
                      ? _slimSlider(
                          context,
                          key: 'novel-reader-page-slider',
                          value: (progress * 100).clamp(0, 100),
                          min: 0,
                          max: 100,
                          label: '${(progress * 100).round()}%',
                          onChanged: onSeekProgress,
                        )
                      : _slimSlider(
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
            // 功能键：顺序/启用/每行几个/几行都来自设置，动作来自注册表。
            for (final row in layout.rows)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  for (final def in row)
                    _actionButton(context, def, text, secondary),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    NovelMenuActionDef def,
    Color text,
    Color secondary,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final active = _actionActive(def);
    final icon = _actionIcon(def, active);
    final onPressed = onTap(def);
    if (!settings.menuShowIconText) {
      return IconButton(
        key: Key(novelMenuActionKey(def.id)),
        tooltip: _actionTooltip(def, active),
        color: active ? scheme.primary : text,
        icon: Icon(icon),
        onPressed: onPressed,
      );
    }
    return InkWell(
      key: Key(novelMenuActionKey(def.id)),
      onTap: onPressed,
      borderRadius: MimaoShapes.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: active ? scheme.primary : text),
            const SizedBox(height: 2),
            Text(
              def.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: active ? scheme.primary : secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 自动翻页 / 朗读开着的按钮高亮，图标也换成「停止」语义。
  bool _actionActive(NovelMenuActionDef def) => switch (def.id) {
    novelMenuActionAutoPage => autoReading,
    novelMenuActionTts => speaking,
    _ => false,
  };

  IconData _actionIcon(NovelMenuActionDef def, bool active) => switch (def.id) {
    novelMenuActionAutoPage when active => Icons.pause,
    novelMenuActionTts when active => Icons.stop_circle_outlined,
    _ => def.icon,
  };

  String _actionTooltip(NovelMenuActionDef def, bool active) =>
      switch (def.id) {
        novelMenuActionAutoPage when active => '停止自动翻页',
        novelMenuActionTts when active => '停止朗读',
        _ => def.label,
      };

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

/// 按槽位内容拼展示文本（页眉页脚共用；页码为空时退成百分比）。
String novelChromeSlotText(
  NovelChromeSlot slot, {
  required String chapterTitle,
  required String bookTitle,
  required int? page,
  required int? pageCount,
  required double percent,
  required String customText,
}) {
  return switch (slot) {
    NovelChromeSlot.none => '',
    NovelChromeSlot.chapter => chapterTitle,
    NovelChromeSlot.book => bookTitle,
    NovelChromeSlot.page => page == null ? '' : '$page/${pageCount ?? page}',
    NovelChromeSlot.percent => '${percent.toStringAsFixed(1)}%',
    NovelChromeSlot.pageAndPercent =>
      page == null
          ? '${percent.toStringAsFixed(1)}%'
          : '$page/${pageCount ?? page}  ${percent.toStringAsFixed(1)}%',
    NovelChromeSlot.custom => customText,
  };
}

/// 页眉：三槽（左/中/右），字号独立于正文与页脚。
class NovelReaderHeader extends StatelessWidget {
  const NovelReaderHeader({
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
  final int? page;
  final int? pageCount;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final secondary = novelReaderSecondaryColor(settings);
    final style = TextStyle(
      fontSize: settings.headerFontSize,
      color: secondary,
      fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
    );
    final texts = <String>[
      for (final slot in settings.headerSlots)
        novelChromeSlotText(
          slot,
          chapterTitle: chapterTitle,
          bookTitle: bookTitle,
          page: page,
          pageCount: pageCount,
          percent: percent,
          customText: settings.headerCustomText,
        ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        settings.horizontalPadding,
        2,
        settings.horizontalPadding,
        4,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              texts[0],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (texts[1].isNotEmpty)
            Text(
              texts[1],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          Expanded(
            child: Text(
              texts[2],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// 页脚：三槽（左/中/右），字号独立。
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

  /// 滚动模式传 null，页脚只显示百分比。
  final int? page;
  final int? pageCount;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final secondary = novelReaderSecondaryColor(settings);
    final style = TextStyle(
      fontSize: settings.footerFontSize,
      color: secondary,
      fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
    );
    final texts = <String>[
      for (final slot in settings.footerSlots)
        novelChromeSlotText(
          slot,
          chapterTitle: chapterTitle,
          bookTitle: bookTitle,
          page: page,
          pageCount: pageCount,
          percent: percent,
          customText: settings.footerCustomText,
        ),
    ];
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
              texts[0],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (texts[1].isNotEmpty)
            Text(
              texts[1],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          Expanded(
            child: Text(
              texts[2],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// 背景纹理：纯代码绘制，颜色由阅读背景派生，不引资源图。
class NovelBackgroundTexturePainter extends CustomPainter {
  const NovelBackgroundTexturePainter({
    required this.texture,
    required this.color,
  });

  final NovelBackgroundTexture texture;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == NovelBackgroundTexture.none) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    switch (texture) {
      case NovelBackgroundTexture.none:
        return;
      case NovelBackgroundTexture.dots:
        const gap = 18.0;
        for (var x = gap; x < size.width; x += gap) {
          for (var y = gap; y < size.height; y += gap) {
            canvas.drawCircle(Offset(x, y), 1.1, paint);
          }
        }
      case NovelBackgroundTexture.lines:
        const gap = 24.0;
        for (var y = gap; y < size.height; y += gap) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case NovelBackgroundTexture.grid:
        const gap = 26.0;
        for (var y = gap; y < size.height; y += gap) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (var x = gap; x < size.width; x += gap) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
      case NovelBackgroundTexture.diagonal:
        const gap = 22.0;
        for (var offset = -size.height; offset < size.width; offset += gap) {
          canvas.drawLine(
            Offset(offset, size.height),
            Offset(offset + size.height, 0),
            paint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(NovelBackgroundTexturePainter oldDelegate) =>
      oldDelegate.texture != texture || oldDelegate.color != color;
}

/// 背景图铺放方式 → BoxFit。
BoxFit novelBackgroundBoxFit(NovelBackgroundFit fit) => switch (fit) {
  NovelBackgroundFit.cover => BoxFit.cover,
  NovelBackgroundFit.contain => BoxFit.contain,
  NovelBackgroundFit.fill => BoxFit.fill,
  NovelBackgroundFit.fitWidth => BoxFit.fitWidth,
  NovelBackgroundFit.fitHeight => BoxFit.fitHeight,
};

/// 九宫格对齐 → Alignment。
Alignment novelBackgroundAlignment(NovelBackgroundAlign align) =>
    switch (align) {
      NovelBackgroundAlign.topLeft => Alignment.topLeft,
      NovelBackgroundAlign.topCenter => Alignment.topCenter,
      NovelBackgroundAlign.topRight => Alignment.topRight,
      NovelBackgroundAlign.centerLeft => Alignment.centerLeft,
      NovelBackgroundAlign.center => Alignment.center,
      NovelBackgroundAlign.centerRight => Alignment.centerRight,
      NovelBackgroundAlign.bottomLeft => Alignment.bottomLeft,
      NovelBackgroundAlign.bottomCenter => Alignment.bottomCenter,
      NovelBackgroundAlign.bottomRight => Alignment.bottomRight,
    };

/// 正文文字（含下划线）。下划线由 [CustomPainter] 按行绘制，因此能：
/// - 用实线 / 波浪 / 虚线三种样式；
/// - 用 [extend] 决定是贴着字走还是延伸到整行宽度（段尾空白也有线）。
///
/// Flutter 的 `TextStyle.decoration` 只能贴着字形画、也拿不到行边界，
/// 所以这里不交给 TextStyle，改由绘制层按 `computeLineMetrics()` 画。
class NovelUnderlinedText extends StatelessWidget {
  const NovelUnderlinedText({
    super.key,
    required this.text,
    required this.style,
    required this.textAlign,
    required this.underlineStyle,
    required this.thickness,
    required this.spacing,
    required this.extend,
    this.textHeightBehavior,
    this.backgroundColor,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final NovelUnderlineStyle underlineStyle;
  final double thickness;
  final double spacing;
  final bool extend;
  final TextHeightBehavior? textHeightBehavior;

  /// 搜索命中等场景的高亮底色（画在文字下面）。
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (underlineStyle == NovelUnderlineStyle.none) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        textHeightBehavior: textHeightBehavior,
      );
    }
    final base = style.copyWith(
      decoration: TextDecoration.none,
      decorationStyle: null,
      decorationThickness: null,
    );
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        foregroundPainter: _NovelUnderlinePainter(
          text: text,
          style: base,
          textAlign: textAlign,
          textHeightBehavior: textHeightBehavior,
          maxWidth: constraints.maxWidth,
          underlineStyle: underlineStyle,
          thickness: thickness,
          spacing: spacing,
          extend: extend,
          color: style.color ?? const Color(0xFF000000),
          background: backgroundColor,
        ),
        child: Text(
          text,
          style: base,
          textAlign: textAlign,
          textHeightBehavior: textHeightBehavior,
        ),
      ),
    );
  }
}

class _NovelUnderlinePainter extends CustomPainter {
  _NovelUnderlinePainter({
    required this.text,
    required this.style,
    required this.textAlign,
    required this.textHeightBehavior,
    required this.maxWidth,
    required this.underlineStyle,
    required this.thickness,
    required this.spacing,
    required this.extend,
    required this.color,
    required this.background,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final TextHeightBehavior? textHeightBehavior;
  final double maxWidth;
  final NovelUnderlineStyle underlineStyle;
  final double thickness;
  final double spacing;
  final bool extend;
  final Color color;
  final Color? background;

  @override
  void paint(Canvas canvas, Size size) {
    if (maxWidth <= 0 || text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textHeightBehavior: textHeightBehavior,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final bgPaint = background == null ? null : (Paint()..color = background!);

    for (final line in painter.computeLineMetrics()) {
      // 下划线落在 baseline 下方 spacing 处。
      final y = line.baseline + spacing;
      final lineRight = line.left + line.width;
      final left = extend ? 0.0 : line.left;
      final right = extend ? maxWidth : lineRight;
      if (right <= left) continue;
      if (bgPaint != null) {
        canvas.drawRect(
          Rect.fromLTRB(line.left, line.baseline - line.ascent, lineRight, y),
          bgPaint,
        );
      }
      switch (underlineStyle) {
        case NovelUnderlineStyle.none:
          break;
        case NovelUnderlineStyle.solid:
          canvas.drawLine(Offset(left, y), Offset(right, y), paint);
        case NovelUnderlineStyle.dash:
          const dash = 6.0;
          const gap = 4.0;
          for (var x = left; x < right; x += dash + gap) {
            canvas.drawLine(
              Offset(x, y),
              Offset(math.min(x + dash, right), y),
              paint,
            );
          }
        case NovelUnderlineStyle.wave:
          final path = Path()..moveTo(left, y);
          const amplitude = 1.6;
          const period = 8.0;
          var x = left;
          var up = true;
          while (x < right) {
            final next = math.min(x + period / 2, right);
            path.quadraticBezierTo(
              (x + next) / 2,
              y + (up ? -amplitude : amplitude),
              next,
              y,
            );
            up = !up;
            x = next;
          }
          canvas.drawPath(path, paint);
      }
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_NovelUnderlinePainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.underlineStyle != underlineStyle ||
      oldDelegate.thickness != thickness ||
      oldDelegate.spacing != spacing ||
      oldDelegate.extend != extend ||
      oldDelegate.color != color ||
      oldDelegate.background != background ||
      oldDelegate.textAlign != textAlign;
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
  late final ScrollController _scroll = ScrollController();
  final GlobalKey _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 卷行/章节行高不一致，不能再按固定 48px 估算；等首帧布局完再按真实
    // 位置居中（与 legado 目录定位一致，字号/密度变了也不会偏）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _selectedKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(target, alignment: 0.5, duration: Duration.zero);
    });
  }

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
                    key: selected ? _selectedKey : null,
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

/// 九宫格点击区配置面板（对照 legado 的 ClickActionConfigSheet）。
///
/// 9 个格子按「左上 → 右下」排成 3×3；每格显示当前动作，点开下拉换动作。
/// 未实现的动作在下拉里显灰并注明「需先完成 X」，选中后按无动作落库，
/// 不会出现「配了却静默无效」的格子。
class NovelClickZoneSheet extends StatelessWidget {
  const NovelClickZoneSheet({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onClose,
  });

  final NovelReaderSettings settings;
  final ValueChanged<NovelReaderSettings> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.xl),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('novel-click-zones-back'),
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onClose,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '点击区',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: MimaoFonts.bold,
                        ),
                      ),
                      Text(
                        '把屏幕分成 3×3，每格绑一个动作',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 3×3 网格：行 = 上/中/下，列 = 左/中/右。
            // 行高由格子自己的固定高度决定（不能 stretch：外层 Column 是
            // mainAxisSize.min，纵向无界，stretch 会要求 Row 有确定高度）。
            for (var row = 0; row < 3; row++) ...<Widget>[
              Row(
                children: <Widget>[
                  for (var column = 0; column < 3; column++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _ZoneCell(
                          zone: NovelClickZone.values[row * 3 + column],
                          action: settings.clickZoneAction(
                            NovelClickZone.values[row * 3 + column],
                          ),
                          onPick: (action) {
                            final next = List<NovelClickAction>.from(
                              settings.clickZones,
                            );
                            next[row * 3 + column] = action;
                            onChanged(settings.copyWith(clickZones: next));
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '默认：左=上一页、中=菜单、右=下一页，上下两行无动作。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('novel-click-zones-reset'),
                  onPressed: () => onChanged(
                    settings.copyWith(clickZones: novelDefaultClickZones),
                  ),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('恢复默认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个格子：显示当前动作，点开下拉换动作。
class _ZoneCell extends StatelessWidget {
  const _ZoneCell({
    required this.zone,
    required this.action,
    required this.onPick,
  });

  final NovelClickZone zone;
  final NovelClickAction action;
  final ValueChanged<NovelClickAction> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isNone = action == NovelClickAction.none;
    return PopupMenuButton<NovelClickAction>(
      key: Key('novel-click-zone-${zone.name}'),
      tooltip: '${zone.label}：${action.label}',
      position: PopupMenuPosition.under,
      onSelected: onPick,
      itemBuilder: (context) => <PopupMenuEntry<NovelClickAction>>[
        for (final item in NovelClickAction.values)
          PopupMenuItem<NovelClickAction>(
            key: Key('novel-click-action-${item.name}'),
            value: item.available ? item : NovelClickAction.none,
            // 未实现的动作显灰：能看见、知道自己缺什么，但选不了。
            enabled: item.available,
            child: Text(
              item.available
                  ? item.label
                  : '${item.label}（${item.unavailableHint}）',
              style: item.available
                  ? null
                  : TextStyle(color: scheme.onSurface.withValues(alpha: 0.38)),
            ),
          ),
      ],
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: MimaoShapes.md,
          border: Border.all(
            color: isNone ? scheme.outlineVariant : scheme.primary,
            width: isNone ? 1 : 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              zone.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isNone ? scheme.onSurfaceVariant : scheme.onSurface,
                fontWeight: isNone ? MimaoFonts.regular : MimaoFonts.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 浮动图标行：贴底栏上方的一排按钮，配置为空时不渲染。
///
/// 与底栏分开存配置（[NovelReaderSettings.floatingBarMenu]），
/// 用户可以把「翻页/章节」这类低频动作放这里，底栏只留常用项。
class NovelReaderFloatingBar extends StatelessWidget {
  const NovelReaderFloatingBar({
    super.key,
    required this.settings,
    required this.onTap,
    this.actionContext = const NovelMenuActionContext(),
  });

  final NovelReaderSettings settings;
  final NovelMenuActionOnTap onTap;
  final NovelMenuActionContext actionContext;

  @override
  Widget build(BuildContext context) {
    final actions = resolveNovelMenuActions(
      items: settings.floatingBarMenu,
      context: actionContext,
    );
    if (actions.isEmpty) return const SizedBox.shrink();
    final layout = layoutNovelMenuRows(
      actions: actions,
      itemsPerRow: settings.menuIconItemsPerRow,
      rowCount: settings.menuIconRowCount,
      showMore: false,
    );
    final text = novelReaderTextColor(settings);
    final secondary = novelReaderSecondaryColor(settings);
    final panel = novelReaderPanelColor(settings);
    return Material(
      color: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(settings.menuBottomRadiusValue),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final row in layout.rows)
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (final def in row)
                    if (settings.menuShowIconText)
                      InkWell(
                        key: Key(novelMenuActionKey(def.id)),
                        onTap: onTap(def),
                        borderRadius: MimaoShapes.md,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(def.icon, size: 20, color: text),
                              const SizedBox(height: 2),
                              Text(
                                def.label,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: secondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      IconButton(
                        key: Key(novelMenuActionKey(def.id)),
                        tooltip: def.label,
                        color: text,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(def.icon, size: 20),
                        onPressed: onTap(def),
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
