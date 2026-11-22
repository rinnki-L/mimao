// 阅读器设置面板：六模式 ChoiceChip、预加载数滑杆、单击边缘翻页与双击缩放开关。
//
// 用 showModalBottomSheet 承载；DialogTheme / BottomSheet 形状由
// lib/core/theme.dart 统一定义，这里不覆写。每次改动即 controller.updateSettings，
// 面板内容从 controller.settings 读取，做到即时反映。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明
// （Flutter 3.50 弃用整个 material.dart，M1 起全仓沿用）。

import 'package:flutter/material.dart';

import 'reader_controller.dart';
import 'reader_models.dart';

/// 打开设置面板。拆成函数方便页面层一个入口调用。
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderController controller,
}) => showModalBottomSheet<void>(
  context: context,
  builder: (_) => ReaderSettingsPanel(controller: controller),
);

class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({super.key, required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    // 面板挂在独立路由里，不随阅读页重建；这里自己监听 controller，
    // 保证每次改动（含模式按钮）后 chip 选中态、滑杆、开关即时反映。
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final settings = controller.settings;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('阅读设置', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('阅读模式', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final mode in ReaderMode.values)
                  ChoiceChip(
                    key: Key('reader-mode-chip-${mode.name}'),
                    label: Text(_modeLabel(mode)),
                    selected: settings.mode == mode,
                    onSelected: (_) => controller.setMode(mode),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '预加载张数：${settings.preloadCount}',
              style: theme.textTheme.titleSmall,
            ),
            Slider(
              key: const Key('reader-preload-slider'),
              value: settings.preloadCount.toDouble(),
              min: ReaderSettings.minPreloadCount.toDouble(),
              max: ReaderSettings.maxPreloadCount.toDouble(),
              divisions: ReaderSettings.maxPreloadCount,
              label: '${settings.preloadCount}',
              onChanged: (value) => controller.updateSettings(
                settings.copyWith(preloadCount: value.round()),
              ),
            ),
            SwitchListTile(
              key: const Key('reader-tap-switch'),
              title: const Text('单击边缘翻页'),
              subtitle: const Text('关闭后单击边缘只呼出工具栏'),
              value: settings.tapToTurn,
              onChanged: (value) => controller.updateSettings(
                settings.copyWith(tapToTurn: value),
              ),
            ),
            SwitchListTile(
              key: const Key('reader-doubletap-switch'),
              title: const Text('双击缩放'),
              subtitle: const Text('分页模式下双击图片放大/还原'),
              value: settings.doubleTapZoom,
              onChanged: (value) => controller.updateSettings(
                settings.copyWith(doubleTapZoom: value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _modeLabel(ReaderMode mode) => switch (mode) {
  ReaderMode.pagedLtr => '分页 左→右',
  ReaderMode.pagedRtl => '分页 右→左',
  ReaderMode.pagedTtb => '分页 上→下',
  ReaderMode.continuousTtb => '连续 上→下',
  ReaderMode.continuousLtr => '连续 左→右',
  ReaderMode.continuousRtl => '连续 右→左',
};
