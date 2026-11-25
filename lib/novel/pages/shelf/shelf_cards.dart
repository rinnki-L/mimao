// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与小说其他页面同款说明。
/// 书架卡片：网格 / 列表 / 瀑布三种单书呈现 + 分节头。
///
/// 从 `novel_shelf_page.dart` 拆出来（原 1700 行继续膨胀会看不清），页面只
/// 负责数据、筛选、布局骨架与交互；这里只管"一本书长什么样"。所有展示项
/// 都受 [NovelShelfViewConfig] 控制，默认值与改造前一致。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/local/local_models.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/shelf/shelf_view_config.dart';

/// 书架里的一本书（收藏行优先，历史行补全进度）。
class ShelfBook {
  const ShelfBook({
    required this.book,
    this.collect,
    this.history,
    this.seriesName,
  });

  final NovelSummary book;
  final NovelCollectItem? collect;
  final NovelHistoryItem? history;

  /// 系列名（收藏行有 seriesId 且系列存在时才有）。
  final String? seriesName;

  String get id => book.id;
  String get title => book.title;
  String get author => book.author;
  String get coverUrl => book.coverUrl;
  String get intro => book.intro;
  String get latestChapter => book.latestChapter;
  String get kind => book.kind;

  /// 本地导入的书（TXT / EPUB / Markdown）：书架/详情上挂来源标记，
  /// 但走的仍是同一套详情与阅读页（没有第二套 UI）。
  bool get isLocal => isNovelLocalBookId(book.id);

  /// 自定义封面优先。
  String? get customCoverPath => collect?.customCoverPath;

  String get effectiveCoverUrl => customCoverPath ?? coverUrl;

  String? get groupName => collect?.groupName;
  int? get seriesId => collect?.seriesId;
  String get note => collect?.note ?? '';
  bool get collected => collect != null;

  int get chapterIndex => history?.chapterIndex ?? 0;
  int get chapterCount => history?.chapterCount ?? 0;

  int? get percent =>
      novelBookPercent(chapterIndex: chapterIndex, chapterCount: chapterCount);

  String get progressText => history == null
      ? '未读'
      : novelProgressText(
          chapterIndex: chapterIndex,
          chapterCount: chapterCount,
        );

  String get authorText => author.isEmpty ? '作者未知' : author;

  String get subtitle => history != null ? progressText : authorText;

  /// 更新时间展示：书源给的原文，没有就退回最近阅读的相对时间。
  String? get updateText {
    if (book.updateTime.isNotEmpty) return book.updateTime;
    final openedAt = history?.openedAt;
    if (openedAt == null) return null;
    return novelRelativeTime(openedAt);
  }

  /// 分类标签（逗号分隔取前两个）。
  List<String> get tags => <String>[
    for (final tag in kind.split(RegExp(r'[,，]')))
      if (tag.trim().isNotEmpty) tag.trim(),
  ].take(2).toList();
}

/// 卡片交互回调打包（网格/列表/瀑布共用，避免每个构造器塞五个参数）。
class ShelfCardActions {
  const ShelfCardActions({
    required this.onTap,
    required this.onSecondaryTap,
    this.onLongPress,
  });

  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;
  final VoidCallback? onLongPress;
}

/// 封面阴影：只在配置开启时加，避免默认观感变化。
List<BoxShadow> shelfCoverShadow(ColorScheme cs, bool enabled) => enabled
    ? <BoxShadow>[
        BoxShadow(
          color: cs.shadow.withValues(alpha: .28),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ]
    : const <BoxShadow>[];

/// 网格卡片：封面 + 可选标签/最新章/简介/更新时间。
class ShelfGridCard extends StatelessWidget {
  const ShelfGridCard({
    super.key,
    required this.item,
    required this.config,
    required this.selecting,
    required this.selected,
    required this.actions,
    this.badge,
  });

  final ShelfBook item;
  final NovelShelfViewConfig config;
  final bool selecting;
  final bool selected;
  final ShelfCardActions actions;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selecting ? selected : null,
      label: '${item.title}，${item.progressText}',
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            actions.onSecondaryTap(details.globalPosition),
        onLongPress: actions.onLongPress,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: actions.onTap,
            borderRadius: BorderRadius.circular(MimaoRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(config.coverRadius),
                      boxShadow: shelfCoverShadow(cs, config.coverShadow),
                    ),
                    child: ShelfCoverStack(
                      item: item,
                      config: config,
                      selecting: selecting,
                      selected: selected,
                      badge: badge,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (config.showTags && item.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  ShelfTagRow(tags: item.tags),
                ],
                if (config.showLatestChapter && item.latestChapter.isNotEmpty)
                  _ExtraLine(text: '最新：${item.latestChapter}'),
                if (config.showIntro && item.intro.isNotEmpty)
                  _ExtraLine(text: item.intro, maxLines: 2),
                if (config.showUpdateTime && item.updateText != null)
                  _ExtraLine(text: '更新：${item.updateText}'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 瀑布卡片：封面按给定宽高比铺满 + 与网格相同的文字区。
///
/// 与网格的区别只在封面高度由调用方按列宽与伪随机高度决定（错落感），
/// 文字区完全复用，避免两套卡片样式漂移。
class ShelfWaterfallCard extends StatelessWidget {
  const ShelfWaterfallCard({
    super.key,
    required this.item,
    required this.config,
    required this.selecting,
    required this.selected,
    required this.actions,
    required this.coverHeight,
    this.badge,
  });

  final ShelfBook item;
  final NovelShelfViewConfig config;
  final bool selecting;
  final bool selected;
  final ShelfCardActions actions;
  final double coverHeight;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selecting ? selected : null,
      label: '${item.title}，${item.progressText}',
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            actions.onSecondaryTap(details.globalPosition),
        onLongPress: actions.onLongPress,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(config.coverRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: actions.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: coverHeight,
                    width: double.infinity,
                    child: ShelfCoverStack(
                      item: item,
                      config: config,
                      selecting: selecting,
                      selected: selected,
                      badge: badge,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.title,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (config.showTags &&
                            item.tags.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          ShelfTagRow(tags: item.tags),
                        ],
                        if (config.showLatestChapter &&
                            item.latestChapter.isNotEmpty)
                          _ExtraLine(text: '最新：${item.latestChapter}'),
                        if (config.showUpdateTime && item.updateText != null)
                          _ExtraLine(text: '更新：${item.updateText}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表行：横向封面 + 多行文字（列表模式信息最全）。
class ShelfListRow extends StatelessWidget {
  const ShelfListRow({
    super.key,
    required this.item,
    required this.config,
    required this.selecting,
    required this.selected,
    required this.actions,
    this.coverWidth = 56,
    this.trailing,
  });

  final ShelfBook item;
  final NovelShelfViewConfig config;
  final bool selecting;
  final bool selected;
  final ShelfCardActions actions;
  final double coverWidth;

  /// 拖拽手柄等额外尾部控件。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          actions.onSecondaryTap(details.globalPosition),
      onLongPress: actions.onLongPress,
      child: Material(
        color: selected && selecting
            ? cs.secondaryContainer
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(MimaoRadii.md),
          onTap: actions.onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: coverWidth,
                  height: coverWidth * 1.45,
                  child: NovelBookCover(
                    url: item.effectiveCoverUrl,
                    title: item.title,
                    borderRadius: config.coverRadius,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.isLocal) ...<Widget>[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: NovelTag(
                            label: novelLocalSourceLabel,
                            highlighted: true,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        item.authorText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.progressText,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (config.showTags && item.tags.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        ShelfTagRow(tags: item.tags),
                      ],
                      if (config.showLatestChapter &&
                          item.latestChapter.isNotEmpty)
                        _ExtraLine(text: '最新：${item.latestChapter}'),
                      if (config.showIntro && item.intro.isNotEmpty)
                        _ExtraLine(text: item.intro, maxLines: 2),
                      if (config.showUpdateTime && item.updateText != null)
                        _ExtraLine(text: '更新：${item.updateText}'),
                      if (item.note.isNotEmpty)
                        _ExtraLine(text: '备注：${item.note}', maxLines: 2),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailing != null)
                  trailing!
                else if (selecting)
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  )
                else
                  Icon(
                    item.collected ? Icons.bookmark : Icons.chevron_right,
                    color: item.collected ? cs.primary : cs.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面叠层：角标 / 收藏标记 / 选择圈，三种卡片共用。
class ShelfCoverStack extends StatelessWidget {
  const ShelfCoverStack({
    super.key,
    required this.item,
    required this.config,
    required this.selecting,
    required this.selected,
    this.badge,
  });

  final ShelfBook item;
  final NovelShelfViewConfig config;
  final bool selecting;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(config.coverRadius),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          NovelBookCover(
            url: item.effectiveCoverUrl,
            title: item.title,
            borderRadius: config.coverRadius,
          ),
          if (badge != null)
            Positioned(top: 6, right: 6, child: NovelCoverBadge(text: badge!)),
          // 本地书来源标记：与选择态复选框同处左上角，选择模式下让位给复选框
          // （选中状态更重要）；只加一枚小 chip，不改卡片结构、不加第二套页面。
          if (item.isLocal && !selecting)
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(MimaoRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.sd_storage_outlined,
                      size: 11,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      novelLocalSourceLabel,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
              ),
            ),
          if (!selecting && item.collected)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: .9),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bookmark, size: 14, color: cs.primary),
              ),
            ),
          if (selecting)
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: selected
                      ? cs.primary
                      : cs.surface.withValues(alpha: .85),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 标签行（分类 chip 的小号变体）。
class ShelfTagRow extends StatelessWidget {
  const ShelfTagRow({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: <Widget>[
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(MimaoRadii.sm),
            ),
            child: Text(
              tag,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer),
            ),
          ),
      ],
    );
  }
}

class _ExtraLine extends StatelessWidget {
  const _ExtraLine({required this.text, this.maxLines = 1});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 分节头：文件夹/系列共用（图标 + 标题 + 数量 + 可选操作）。
class ShelfSectionHeader extends StatelessWidget {
  const ShelfSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.icon = Icons.folder_outlined,
    this.onToggle,
    this.collapsed = false,
    this.trailing,
  });

  final String title;
  final int count;
  final IconData icon;
  final VoidCallback? onToggle;
  final bool collapsed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(MimaoRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (trailing != null) trailing!,
            if (onToggle != null)
              Icon(
                collapsed ? Icons.expand_more : Icons.expand_less,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
