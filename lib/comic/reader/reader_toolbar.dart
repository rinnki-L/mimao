// 阅读器工具栏：顶栏（返回/标题/设置）与底栏（切章/页码滑杆/模式切换），
// 以及工具栏隐藏时常驻左下角的页码小字。全部走 ColorScheme 语义色。
//
// 顶栏/底栏本身不带 Positioned，滑入滑出由页面层的 AnimatedPositioned 负责；
// key 由页面层挂上，工具栏隐藏时整个 widget 移出树 → find.byKey 找不到。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明
// （Flutter 3.50 弃用整个 material.dart，M1 起全仓沿用）。

import 'package:flutter/material.dart';

import 'reader_controller.dart';
import 'reader_models.dart';

/// 顶栏内容：返回 + 漫画标题/章节标题（两行）+ 设置入口。
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.controller,
    required this.onBack,
    required this.onSettings,
  });

  final String title;
  final ReaderController controller;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: onBack,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '第 ${controller.chapterNumber} 章 · ${controller.chapterTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('reader-settings-button'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: '阅读设置',
              onPressed: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏内容：第一行上一章/页码滑杆/下一章；第二行页码文本/模式按钮/设置入口。
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.controller,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onCycleMode,
    required this.onSettings,
  });

  final ReaderController controller;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onCycleMode;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final maxPage = controller.pageCount < 1 ? 1 : controller.pageCount;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('reader-prev-chapter'),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一章',
                  onPressed: controller.hasPreviousChapter
                      ? onPrevChapter
                      : null,
                ),
                Expanded(
                  child: Slider(
                    key: const Key('reader-slider'),
                    value: controller.pageNumber.toDouble().clamp(
                      1.0,
                      maxPage.toDouble(),
                    ),
                    min: 1,
                    max: maxPage.toDouble(),
                    divisions: maxPage > 1 ? maxPage - 1 : 1,
                    onChanged: controller.pageCount == 0
                        ? null
                        : (value) => controller.goToPage(value.round() - 1),
                  ),
                ),
                IconButton(
                  key: const Key('reader-next-chapter'),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一章',
                  onPressed: controller.hasNextChapter ? onNextChapter : null,
                ),
              ],
            ),
            Row(
              children: <Widget>[
                const SizedBox(width: 48),
                Text(
                  'P${controller.pageNumber}/${controller.pageCount}',
                  key: const Key('reader-page-label'),
                  style: theme.textTheme.labelMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  key: const Key('reader-mode-button'),
                  icon: const Icon(Icons.view_stream_outlined),
                  label: Text(_modeShortLabel(controller.settings.mode)),
                  onPressed: onCycleMode,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 工具栏隐藏时左下角的页码小字。黑底上的文字属图片遮罩文字例外，
/// 用固定白 + 阴影保证在任意图片上都可读。
class ReaderPageInfo extends StatelessWidget {
  const ReaderPageInfo({super.key, required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: const Key('reader-page-info'),
      left: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Text(
          'P${controller.pageNumber}/${controller.pageCount}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            shadows: const <Shadow>[
              Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }
}

String _modeShortLabel(ReaderMode mode) => switch (mode) {
  ReaderMode.pagedLtr => '分页 →',
  ReaderMode.pagedRtl => '分页 ←',
  ReaderMode.pagedTtb => '分页 ↓',
  ReaderMode.continuousTtb => '连续 ↓',
  ReaderMode.continuousLtr => '连续 →',
  ReaderMode.continuousRtl => '连续 ←',
};
