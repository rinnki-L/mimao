// 阅读设置面板：抽屉 / 底部面板形态，实时改 [ReaderSettings] 并回调。
//
// 纯展示层：不读盘、不持久化，状态由外面的阅读页持有；每次改动用
// copyWith 产生新快照经 onChanged 抛出，阅读视图据此立即重建。
// 样式全部取自 lib/core/theme.dart（圆角、字体、颜色角色），不手搓数值。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明
// （Flutter 3.50 弃用整个 material.dart，M1 起全仓沿用）。

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'reader_settings.dart';
import 'reader_view_mode.dart';

/// 阅读设置面板。
///
/// [initial] 是打开面板时的设置快照；面板内部持有自己的副本用于即时重建，
/// 每次修改都经 [onChanged] 抛出完整的新 [ReaderSettings]。
class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.initial,
    required this.onChanged,
    this.onClose,
  });

  final ReaderSettings initial;
  final ValueChanged<ReaderSettings> onChanged;
  final VoidCallback? onClose;

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  late ReaderSettings _settings = widget.initial;

  @override
  void didUpdateWidget(covariant ReaderSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部换了新快照（例如另一处设置生效）时同步面板，不覆盖用户正在改的副本。
    if (!identical(oldWidget.initial, widget.initial)) {
      _settings = widget.initial;
    }
  }

  void _apply(ReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '阅读设置',
                      style: theme.textTheme.titleLarge,
                      key: const Key('reader-settings-title'),
                    ),
                  ),
                  IconButton(
                    key: const Key('reader-settings-close'),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: ListView(
                key: const Key('reader-settings-list'),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: <Widget>[
                  _sectionTitle(theme, '阅读模式'),
                  _buildModeChips(theme),
                  _switchTile(
                    key: 'reader-settings-auto-layout',
                    title: '自动选择阅读模式',
                    subtitle: '按后续图片宽高比判断条漫/页漫；只影响本次打开',
                    value: _settings.autoLayout,
                    onChanged: (value) =>
                        _apply(_settings.copyWith(autoLayout: value)),
                  ),
                  _sectionTitle(theme, '分页设置'),
                  _buildImagesPerPage(theme),
                  _switchTile(
                    key: 'reader-settings-first-page-single',
                    title: '首页单图',
                    subtitle: '第一页只放一张图（章节封面感）',
                    value: _settings.singleImageOnFirstPage,
                    onChanged: (value) => _apply(
                      _settings.copyWith(singleImageOnFirstPage: value),
                    ),
                  ),
                  _sectionTitle(theme, '手势'),
                  _switchTile(
                    key: 'reader-settings-tap-to-turn',
                    title: '点击翻页',
                    subtitle: '点屏幕左右半边翻页',
                    value: _settings.tapToTurnPages,
                    onChanged: (value) =>
                        _apply(_settings.copyWith(tapToTurnPages: value)),
                  ),
                  _switchTile(
                    key: 'reader-settings-reverse-tap',
                    title: '反向点击翻页',
                    subtitle: '左右点击方向对调（配合日漫右到左）',
                    value: _settings.reverseTapToTurnPages,
                    onChanged: (value) => _apply(
                      _settings.copyWith(reverseTapToTurnPages: value),
                    ),
                  ),
                  _switchTile(
                    key: 'reader-settings-double-tap-zoom',
                    title: '双击缩放',
                    subtitle: '双击画面在原始大小与放大间切换',
                    value: _settings.doubleTapToZoom,
                    onChanged: (value) =>
                        _apply(_settings.copyWith(doubleTapToZoom: value)),
                  ),
                  _switchTile(
                    key: 'reader-settings-long-press-zoom',
                    title: '长按缩放',
                    subtitle: '长按临时放大，松手还原',
                    value: _settings.longPressToZoom,
                    onChanged: (value) =>
                        _apply(_settings.copyWith(longPressToZoom: value)),
                  ),
                  _sectionTitle(theme, '显示'),
                  _switchTile(
                    key: 'reader-settings-page-animation',
                    title: '翻页动画',
                    subtitle: '翻页/滚动时使用过渡动画',
                    value: _settings.pageAnimation,
                    onChanged: (value) =>
                        _apply(_settings.copyWith(pageAnimation: value)),
                  ),
                  _switchTile(
                    key: 'reader-settings-show-page-number',
                    title: '显示页码',
                    subtitle: '阅读时叠加当前页码',
                    value: _settings.showPageNumber,
                    onChanged: (value) =>
                        _apply(_settings.copyWith(showPageNumber: value)),
                  ),
                  _switchTile(
                    key: 'reader-settings-limit-image-width',
                    title: '限制长图宽度',
                    subtitle: '纵向阅读时不把长条图拉满屏宽',
                    value: _settings.limitImageWidth,
                    onChanged: (value) =>
                        _apply(_settings.copyWith(limitImageWidth: value)),
                  ),
                  _buildSideMargin(theme),
                  _buildDimBrightness(theme),
                  _sectionTitle(theme, '性能与自动'),
                  _buildPreloadCount(theme),
                  _buildScrollSpeed(theme),
                  _buildAutoReadingInterval(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildModeChips(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final mode in ReaderViewMode.values)
          ChoiceChip(
            key: Key('reader-settings-mode-${mode.name}'),
            label: Text(mode.label),
            selected: _settings.mode == mode,
            showCheckmark: false,
            selectedColor: scheme.primaryContainer,
            side: BorderSide(
              color: _settings.mode == mode
                  ? scheme.primary
                  : scheme.outlineVariant,
            ),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: _settings.mode == mode
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            onSelected: (_) => _apply(_settings.copyWith(mode: mode)),
          ),
      ],
    );
  }

  Widget _buildImagesPerPage(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '每屏图数',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              key: const Key('reader-settings-images-per-page'),
              showSelectedIcon: false,
              segments: <ButtonSegment<int>>[
                for (var i = 1; i <= 5; i++)
                  ButtonSegment<int>(value: i, label: Text('$i')),
              ],
              selected: <int>{_settings.imagesPerPage},
              onSelectionChanged: (selection) =>
                  _apply(_settings.copyWith(imagesPerPage: selection.first)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideMargin(ThemeData theme) {
    return _sliderTile(
      theme,
      key: 'reader-settings-side-margin',
      title: '条漫缩小（每侧边距）',
      subtitle: '纵向连续/瀑布时左右各留白；0% 为铺满，仅影响显示',
      valueLabel: '${_settings.sideMargin}%',
      slider: Slider(
        key: const Key('reader-settings-side-margin-slider'),
        value: _settings.sideMargin.toDouble(),
        min: 0,
        max: 30,
        divisions: 30,
        label: '${_settings.sideMargin}%',
        activeColor: theme.colorScheme.primary,
        thumbColor: theme.colorScheme.primary,
        onChanged: (value) =>
            _apply(_settings.copyWith(sideMargin: value.round())),
      ),
    );
  }

  Widget _buildDimBrightness(ThemeData theme) {
    return _sliderTile(
      theme,
      key: 'reader-settings-dim-brightness',
      title: '阅读亮度',
      subtitle: '压暗画面，值越大越亮；100 表示不压暗',
      valueLabel: '${_settings.dimBrightness}',
      slider: Slider(
        key: const Key('reader-settings-dim-brightness-slider'),
        value: _settings.dimBrightness.toDouble(),
        min: 20,
        max: 100,
        divisions: 80,
        label: '${_settings.dimBrightness}',
        activeColor: theme.colorScheme.primary,
        thumbColor: theme.colorScheme.primary,
        onChanged: (value) =>
            _apply(_settings.copyWith(dimBrightness: value.round())),
      ),
    );
  }

  Widget _buildPreloadCount(ThemeData theme) {
    return _sliderTile(
      theme,
      key: 'reader-settings-preload-count',
      title: '预加载数',
      subtitle: '提前取下一页的图片数',
      valueLabel: '${_settings.preloadCount} 张',
      slider: Slider(
        key: const Key('reader-settings-preload-count-slider'),
        value: _settings.preloadCount.toDouble(),
        min: 1,
        max: 16,
        divisions: 15,
        label: '${_settings.preloadCount}',
        activeColor: theme.colorScheme.primary,
        thumbColor: theme.colorScheme.primary,
        onChanged: (value) =>
            _apply(_settings.copyWith(preloadCount: value.round())),
      ),
    );
  }

  Widget _buildScrollSpeed(ThemeData theme) {
    return _sliderTile(
      theme,
      key: 'reader-settings-scroll-speed',
      title: '滚动速度',
      subtitle: '连续模式点击/键盘/自动滚的翻屏距离倍率',
      valueLabel: '${_settings.scrollSpeed.toStringAsFixed(1)}x',
      slider: Slider(
        key: const Key('reader-settings-scroll-speed-slider'),
        value: _settings.scrollSpeed,
        min: 0.5,
        max: 3,
        divisions: 10,
        label: _settings.scrollSpeed.toStringAsFixed(1),
        activeColor: theme.colorScheme.primary,
        thumbColor: theme.colorScheme.primary,
        onChanged: (value) => _apply(_settings.copyWith(scrollSpeed: value)),
      ),
    );
  }

  Widget _buildAutoReadingInterval(ThemeData theme) {
    return _sliderTile(
      theme,
      key: 'reader-settings-auto-interval',
      title: '自动翻页间隔',
      subtitle: '自动阅读时每页停留秒数',
      valueLabel: '${_settings.autoReadingInterval} 秒',
      slider: Slider(
        key: const Key('reader-settings-auto-interval-slider'),
        value: _settings.autoReadingInterval.toDouble(),
        min: 1,
        max: 20,
        divisions: 19,
        label: '${_settings.autoReadingInterval}',
        activeColor: theme.colorScheme.primary,
        thumbColor: theme.colorScheme.primary,
        onChanged: (value) =>
            _apply(_settings.copyWith(autoReadingInterval: value.round())),
      ),
    );
  }

  /// 滑块行：标题 + 当前值徽标 + 滑块。徽标容器用统一圆角 token。
  Widget _sliderTile(
    ThemeData theme, {
    required String key,
    required String title,
    required String subtitle,
    required String valueLabel,
    required Slider slider,
  }) {
    final scheme = theme.colorScheme;
    return Padding(
      key: Key('$key-row'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: MimaoShapes.sm,
                ),
                child: Text(
                  valueLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          slider,
        ],
      ),
    );
  }

  /// 开关行：交给 [SwitchListTile]，自带 hover / focus / 键盘操作反馈。
  Widget _switchTile({
    required String key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      key: Key(key),
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
