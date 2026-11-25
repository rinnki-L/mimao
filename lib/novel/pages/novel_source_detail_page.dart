// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 书源详情 / 能力说明：只读展示书源元信息与正文规则字段的支持情况。
///
/// 「编辑书源」不在客户端做（书源 JSON 字段多、改坏难排查）；这里给的是
/// 能力边界：哪些字段已支持、哪些降级、哪些暂不支持及原因。引擎在抓正文时
/// 会把同一条说明记成警告，用户不会再遇到「解析了但静默不生效」。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/engine/source_capability.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class NovelSourceDetailPage extends StatelessWidget {
  const NovelSourceDetailPage({super.key, required this.source});

  final NovelBookSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final capabilities = novelContentCapabilities(source.ruleSet);
    final unsupported = capabilities
        .where((item) => item.status == NovelCapabilityStatus.unsupported)
        .toList();
    final degraded = capabilities
        .where((item) => item.status == NovelCapabilityStatus.degraded)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('书源详情')),
      body: NovelPageContent(
        maxWidth: 900,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: ListView(
          children: <Widget>[
            NovelCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      NovelSourceBadge(name: source.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          source.name,
                          style: theme.textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      NovelTag(label: source.typeLabel),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    source.url,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      NovelTag(label: source.enabled ? '已启用' : '已停用'),
                      for (final group in source.groups) NovelTag(label: group),
                      if (source.groups.isEmpty) const NovelTag(label: '未分组'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (unsupported.isNotEmpty || degraded.isNotEmpty)
              NovelCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.info_outline, size: 20, color: cs.tertiary),
                        const SizedBox(width: 8),
                        Text('这个书源有字段未完全支持', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '解析到的规则不会静默丢弃：下面列出的字段会在抓正文时'
                      '按标注降级或跳过，并在引擎里留一条警告。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            const NovelSectionHeader(icon: Icons.menu_book, title: '正文规则能力'),
            const SizedBox(height: 8),
            for (final item in capabilities) ...<Widget>[
              _CapabilityRow(capability: item),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Text(
              '说明：客户端是纯本地阅读器，不做 WebView 渲染、正文插图与书源购买；'
              '这些字段仍会原样保留在书源 JSON 里，后续实现后自动生效。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.capability});

  final NovelSourceCapability capability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (IconData icon, Color color) = switch (capability.status) {
      NovelCapabilityStatus.supported => (
        Icons.check_circle_outline,
        cs.primary,
      ),
      NovelCapabilityStatus.degraded => (
        Icons.warning_amber_outlined,
        cs.tertiary,
      ),
      NovelCapabilityStatus.unsupported => (Icons.block_outlined, cs.error),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: MimaoShapes.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        capability.label,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    NovelTag(label: capability.status.label),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  capability.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
