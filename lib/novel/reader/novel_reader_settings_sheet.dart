// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读设置面板（对照截图「阅读界面」）：字号 / Tt 字体 / 背景预设与自定义 /
// 翻页动画 / 全局·菜单·信息·更多 四个页签。
//
// 面板只持有设置的本地副本，每次修改经 [onChanged] 抛出完整快照，阅读页据此
// 立即重建并落盘；面板自身不读盘。

import 'package:flutter/material.dart';

import '../../core/theme.dart';
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

enum _SettingsTab { global, menu, info, more }

const Map<_SettingsTab, String> _tabLabels = <_SettingsTab, String>{
  _SettingsTab.global: '全局',
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
    this.onPreview,
    this.showAutoBrightness = false,
  });

  final NovelReaderSettings initial;
  final NovelReaderBookInfo info;
  final ValueChanged<NovelReaderSettings> onChanged;
  final VoidCallback onClose;

  /// 背景「预览」：收起面板看效果。
  final VoidCallback? onPreview;
  final bool showAutoBrightness;

  @override
  State<NovelReaderSettingsSheet> createState() =>
      _NovelReaderSettingsSheetState();
}

class _NovelReaderSettingsSheetState extends State<NovelReaderSettingsSheet> {
  late NovelReaderSettings _settings = widget.initial;
  _SettingsTab _tab = _SettingsTab.global;

  void _apply(NovelReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
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
              tooltip: '夜间模式',
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
            children: <Widget>[
              _footerSlotRow<NovelFooterLeft>(
                key: 'novel-settings-footer-left',
                title: '页脚左槽',
                value: _settings.footerLeft,
                values: NovelFooterLeft.values,
                labelOf: (value) => value.label,
                onChanged: (value) =>
                    _apply(_settings.copyWith(footerLeft: value)),
              ),
              _footerSlotRow<NovelFooterRight>(
                key: 'novel-settings-footer-right',
                title: '页脚右槽',
                value: _settings.footerRight,
                values: NovelFooterRight.values,
                labelOf: (value) => value.label,
                onChanged: (value) =>
                    _apply(_settings.copyWith(footerRight: value)),
              ),
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

  /// 页脚槽位下拉行（信息页签）。
  Widget _footerSlotRow<T>({
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: MimaoShapes.md,
      ),
      child: child,
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
        ],
      ),
    );
    if (picked != null && mounted) {
      _apply(_settings.copyWith(fontFamily: picked.family));
    }
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
