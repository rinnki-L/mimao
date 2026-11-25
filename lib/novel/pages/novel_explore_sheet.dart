// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与小说其他页面同款说明。
/// 发现页的书源分类弹层：加载某个书源的分类目录、分类书单与继续翻页。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class NovelExploreSheet extends StatefulWidget {
  const NovelExploreSheet({
    super.key,
    required this.source,
    required this.engine,
    required this.onOpenBook,
  });

  final NovelBookSource source;
  final NovelOnlineEngine engine;
  final ValueChanged<NovelSummary> onOpenBook;

  @override
  State<NovelExploreSheet> createState() => _NovelExploreSheetState();
}

class _NovelExploreSheetState extends State<NovelExploreSheet> {
  List<NovelExploreKind> _kinds = const <NovelExploreKind>[];
  NovelExploreKind? _kind;
  List<NovelSummary> _books = const <NovelSummary>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_loadKinds());
  }

  Future<void> _loadKinds() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kinds = await widget.engine.exploreKinds(widget.source);
      if (!mounted) return;
      setState(() {
        _kinds = kinds;
        _loading = false;
      });
      if (kinds.isNotEmpty) {
        await _load(kinds.first, page: 1);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _load(NovelExploreKind kind, {int page = 1}) async {
    setState(() {
      _kind = kind;
      _loading = true;
      _error = null;
      if (page == 1) _books = const <NovelSummary>[];
    });
    try {
      final books = await widget.engine.exploreSource(
        widget.source,
        kind,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _books = page == 1 ? books : <NovelSummary>[..._books, ...books];
        _page = page;
        _loading = false;
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.source.name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              NovelTag(label: widget.source.typeLabel),
            ],
          ),
        ),
        if (_kinds.isNotEmpty) _buildKindBar(),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  /// 分类入口条：书源给了 `layout_flexBasisPercent` / `layout_flexGrow` 就按
  /// 权重排（占父宽度的百分比、行内拉伸），没给就用横向滚动的普通 chip。
  ///
  /// 解析出来的样式一定要落到布局上——上游 ExploreKindLayout 的语义就是
  /// 「按百分比占宽、按 grow 瓜分剩余宽度」，这里照做。
  Widget _buildKindBar() {
    final rows = layoutExploreKindRows(_kinds);
    final styled = rows.any(
      (row) => row.any((slot) => slot.factor != null || slot.grow > 0),
    );
    if (!styled) {
      return SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: <Widget>[
            for (final kind in _kinds)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _kindChip(kind),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 8.0;
                  // 间距要先从可用宽度里扣掉：百分比是「占父宽度」，
                  // 直接把 available*factor 当宽度再额外加间距会溢出
                  // （Row 的 overflow 条纹，实测出现过）。
                  final gaps = gap * (row.length - 1);
                  final available = (constraints.maxWidth - gaps).clamp(
                    0.0,
                    double.infinity,
                  );
                  final fixed = row
                      .where((slot) => slot.factor != null)
                      .fold<double>(0, (sum, slot) => sum + slot.factor!);
                  final growTotal = row
                      .where((slot) => slot.factor == null)
                      .fold<double>(0, (sum, slot) => sum + slot.grow);
                  final free = (1 - fixed).clamp(0.0, 1.0);
                  return Row(
                    children: <Widget>[
                      for (final slot in row) ...<Widget>[
                        if (slot.factor != null)
                          SizedBox(
                            width: available * slot.factor!,
                            child: SizedBox(
                              width: double.infinity,
                              child: _kindChip(_kinds[slot.index]),
                            ),
                          )
                        else if (growTotal > 0)
                          SizedBox(
                            width: available * free * (slot.grow / growTotal),
                            child: SizedBox(
                              width: double.infinity,
                              child: _kindChip(_kinds[slot.index]),
                            ),
                          )
                        else
                          Flexible(child: _kindChip(_kinds[slot.index])),
                        if (slot != row.last) const SizedBox(width: gap),
                      ],
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _kindChip(NovelExploreKind kind) => ChoiceChip(
    label: Text(kind.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
    selected: _kind?.name == kind.name,
    onSelected: (_) => _load(kind, page: 1),
  );

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const NovelLoadingState(label: '正在抓取发现页…');
    if (_error != null) {
      return NovelErrorState(
        message: _error!,
        onRetry: () => _kind == null ? _loadKinds() : _load(_kind!),
      );
    }
    if (_kinds.isEmpty) {
      return const NovelEmptyState(
        icon: Icons.explore_off_outlined,
        title: '这个书源没有发现分类',
        message: '可以直接在搜索页按书名搜索它。',
      );
    }
    if (_books.isEmpty) {
      return const NovelEmptyState(
        icon: Icons.menu_book_outlined,
        title: '这个分类暂时没有书',
        message: '换一个分类，或稍后再试。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _books.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _books.length) {
          return Center(
            child: TextButton(
              onPressed: _loadingMore
                  ? null
                  : () {
                      final kind = _kind;
                      if (kind == null) return;
                      setState(() => _loadingMore = true);
                      unawaited(_load(kind, page: _page + 1));
                    },
              child: Text(_loadingMore ? '加载中…' : '加载更多'),
            ),
          );
        }
        final book = _books[index];
        return Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(MimaoRadii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(MimaoRadii.md),
            onTap: () => widget.onOpenBook(book),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 44,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: NovelBookCover(
                        url: book.coverUrl,
                        title: book.title,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          book.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.author.isEmpty ? '作者未知' : book.author,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (book.latestChapter.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            '最新：${book.latestChapter}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
