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
import 'novel_reader_fonts.dart';
import 'novel_reader_settings.dart';

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

class NovelReaderSettingsSheet extends StatefulWidget {
  const NovelReaderSettingsSheet({
    super.key,
    required this.initial,
    required this.info,
    required this.onChanged,
    required this.onClose,
  });

  final NovelReaderSettings initial;
  final NovelReaderBookInfo info;
  final ValueChanged<NovelReaderSettings> onChanged;
  final VoidCallback onClose;

  /// 背景「预览」：收起面板看效果。

  @override
  State<NovelReaderSettingsSheet> createState() =>
      _NovelReaderSettingsSheetState();
}

class _NovelReaderSettingsSheetState extends State<NovelReaderSettingsSheet> {
  late NovelReaderSettings _settings = widget.initial;
  _SettingsTab _tab = _SettingsTab.global;
  List<NovelFontFile> _importedFonts = const <NovelFontFile>[];
  late final TextEditingController _dividerController;

  @override
  void initState() {
    super.initState();
    _dividerController = TextEditingController(
      text: widget.initial.titleSegmentDivider,
    );
    unawaited(_loadImportedFonts());
  }

  @override
  void dispose() {
    _dividerController.dispose();
    super.dispose();
  }

  Future<void> _loadImportedFonts() async {
    final fonts = await NovelFontRegistry.instance.list();
    if (!mounted) return;
    setState(() => _importedFonts = fonts);
  }

  void _apply(NovelReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
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
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.topCenter,
                child: switch (_tab) {
                  _SettingsTab.global => _buildGlobal(context),
                  _SettingsTab.typography => _buildTypography(context),
                  _SettingsTab.menu => _buildMenu(context),
                  _SettingsTab.info => _buildInfo(context),
                  _SettingsTab.more => _buildMore(context),
                },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
                subtitle: const Text('左右翻页时播放滑动动画'),
                value: _settings.pageAnimation,
                onChanged: (value) =>
                    _apply(_settings.copyWith(pageAnimation: value)),
              ),
            ],
          ),
        ),
      ],
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
                onTap: () => setState(() => _tab = tab),
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
