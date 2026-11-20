// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 漫画条目卡片与网格：搜索 / 发现 / 分类 / 收藏 / 主页共用。
///
/// 从 comic_search_page.dart 抽出（该文件 re-export 保持既有 import 可用），
/// 四个分区页共用同一卡片形态与网格参数，避免各处重复定义导致视觉漂移。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/pages/comic_cover.dart';

/// 搜索结果卡片：封面 + 标题 + 状态行。
class ComicPosterCard extends StatelessWidget {
  const ComicPosterCard({super.key, required this.item, this.onTap});

  final ComicSummary item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 形态（无阴影 / surfaceContainerLow / r20）走 cardTheme，页面不再覆写。
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ComicCover(url: item.coverUrl, title: item.title),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  if (item.subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.apply(
                        color: cs.onSurfaceVariant,
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

/// 漫画卡片网格（统一列宽与间距）。
///
/// 用 [SliverGridDelegateWithMaxCrossAxisExtent] 而不是固定列数：手机两列、
/// 桌面窗口自动铺更多列，不需要按宽度分支。
class ComicPosterGrid extends StatelessWidget {
  const ComicPosterGrid({
    super.key,
    required this.items,
    this.onOpen,
    this.keyPrefix = 'comic',
    this.padding = const EdgeInsets.only(bottom: 16),
    this.shrinkWrap = false,
    this.physics,
  });

  final List<ComicSummary> items;

  /// 点卡片回调；null 时卡片不可点。
  final ValueChanged<ComicSummary>? onOpen;

  /// 列表 key 前缀（同页多网格时避免 key 冲突）。
  final String keyPrefix;

  final EdgeInsetsGeometry padding;

  /// 嵌在别的滚动容器里时置 true（分类页：整页一个 ListView，网格随内容
  /// 撑高、自己不再滚动）。
  final bool shrinkWrap;

  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics:
          physics ?? (shrinkWrap ? const NeverScrollableScrollPhysics() : null),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 296,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final onOpen = this.onOpen;
        return ComicPosterCard(
          key: ValueKey<String>('$keyPrefix-${item.id}'),
          item: item,
          onTap: onOpen == null ? null : () => onOpen(item),
        );
      },
    );
  }
}

/// 分区标题（发现/分类/主页的分段标题）。
class ComicSectionHeader extends StatelessWidget {
  const ComicSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 横向滚动的漫画条（发现页的一个分区、主页的「继续阅读」）。
///
/// 高度固定 296 + 卡片宽 150：与网格卡片同高，视觉上一致。
class ComicPosterRow extends StatelessWidget {
  const ComicPosterRow({
    super.key,
    required this.items,
    this.onOpen,
    this.keyPrefix = 'row',
    this.height = 296,
    this.cardWidth = 150,
  });

  final List<ComicSummary> items;
  final ValueChanged<ComicSummary>? onOpen;
  final String keyPrefix;
  final double height;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final onOpen = this.onOpen;
          return SizedBox(
            width: cardWidth,
            child: ComicPosterCard(
              key: ValueKey<String>('$keyPrefix-${item.id}'),
              item: item,
              onTap: onOpen == null ? null : () => onOpen(item),
            ),
          );
        },
      ),
    );
  }
}
