// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 漫画模块「分类」分区：各源站点的分类树 + 分类漫画列表。
///
/// 源脚本的 `category` 结构差异极大（有的只有 explore、有的 parts 是动态
/// loader）。本页策略（用户拍板）：
/// 1. 选中源后读 `categoryTree`；
/// 2. 有分类树 → 分组 chip 列表，点一个分类拉 `categoryComics`；
/// 3. 没有分类树（null）→ **回退到 explore 分栏**：把该源的每个探索分区当成
///    一个分类项，点进去用 `exploreSection` 拉列表。
///
/// 这样任何源点进分类页都有内容可点，不会出现「选了源却空屏」。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/pages/comic_discover_page.dart'
    show ComicBrowseMessage, ComicBrowseSourceChips;
import 'package:mimao/comic/pages/comic_poster_card.dart';

/// 分类页的一个可点项：真实分类节点，或回退用的探索分区。
class _CategoryTarget {
  const _CategoryTarget.category(this.node, this.slot)
    : exploreIndex = null,
      exploreTitle = null;

  const _CategoryTarget.explore({
    required int index,
    required String title,
    required this.slot,
  }) : node = null,
       exploreIndex = index,
       exploreTitle = title;

  final ComicCategoryNode? node;
  final int? exploreIndex;
  final String? exploreTitle;

  /// 组内序号：分类名可能重复（第三方源数据里真实存在），key 里带序号才
  /// 不会产生重复 ValueKey（debug 下直接断言失败）。
  final int slot;

  String get label => node?.name ?? exploreTitle ?? '推荐';

  /// 稳定 key 片段（序号 + 分类名 / `explore-N`）。
  String get keySuffix =>
      node != null ? 'cat-$slot-${node!.name}' : 'explore-$exploreIndex';
}

/// 分类分区。
class ComicCategoryPage extends StatefulWidget {
  const ComicCategoryPage({
    super.key,
    required this.browseSource,
    this.showAppBar = true,
    this.onOpenDetail,
  });

  final ComicBrowseSource browseSource;

  final bool showAppBar;

  final ValueChanged<ComicSummary>? onOpenDetail;

  @override
  State<ComicCategoryPage> createState() => _ComicCategoryPageState();
}

class _ComicCategoryPageState extends State<ComicCategoryPage> {
  late Future<List<ComicBrowseSourceInfo>> _sourcesFuture;

  String? _selectedKey;

  /// 当前源的分类树（null = 该源没有 category，走 explore 回退）。
  Future<_CategoryData>? _treeFuture;

  /// 当前选中的分类项与它的漫画列表。
  _CategoryTarget? _target;
  Future<ComicBrowseGroup>? _comicsFuture;

  @override
  void initState() {
    super.initState();
    _sourcesFuture = widget.browseSource.browseSources();
  }

  @override
  void didUpdateWidget(ComicCategoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.browseSource != widget.browseSource) {
      _sourcesFuture = widget.browseSource.browseSources();
      _selectedKey = null;
      _treeFuture = null;
      _target = null;
      _comicsFuture = null;
    }
  }

  void _selectSource(String key) {
    if (key == _selectedKey) return;
    setState(() {
      _selectedKey = key;
      _treeFuture = _loadTree(key);
      _target = null;
      _comicsFuture = null;
    });
  }

  /// 读分类树；没有 category 时回退读探索分区，转成可点项。
  Future<_CategoryData> _loadTree(String key) async {
    final tree = await widget.browseSource.categoryTree(key);
    if (tree != null && !tree.isEmpty) {
      return _CategoryData(
        groups: [
          for (final group in tree.groups)
            if (group.nodes.isNotEmpty)
              _CategoryGroup(
                name: group.name,
                targets: [
                  for (var i = 0; i < group.nodes.length; i++)
                    _CategoryTarget.category(group.nodes[i], i),
                ],
              ),
        ],
      );
    }
    // 回退：把 explore 的分区当成分类项（用户拍板的兜底）。
    final groups = await widget.browseSource.exploreGroups(key);
    return _CategoryData(
      groups: [
        _CategoryGroup(
          name: '探索',
          targets: [
            for (final group in groups)
              if (group.exploreIndex >= 0)
                _CategoryTarget.explore(
                  index: group.exploreIndex,
                  title: group.title,
                  slot: group.exploreIndex,
                ),
          ],
        ),
      ],
      fallback: true,
    );
  }

  void _selectTarget(_CategoryTarget target) {
    final key = _selectedKey;
    if (key == null) return;
    setState(() {
      _target = target;
      _comicsFuture = _loadComics(key, target);
    });
  }

  Future<ComicBrowseGroup> _loadComics(String key, _CategoryTarget target) {
    final node = target.node;
    if (node != null) {
      return widget.browseSource.categoryComics(key, node);
    }
    return widget.browseSource.exploreSection(key, target.exploreIndex!);
  }

  void _reload() {
    final key = _selectedKey;
    if (key == null) {
      setState(() => _sourcesFuture = widget.browseSource.browseSources());
      return;
    }
    setState(() {
      _treeFuture = _loadTree(key);
      final target = _target;
      if (target != null) _comicsFuture = _loadComics(key, target);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('分类')) : null,
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ComicBrowseSourceInfo>>(
          future: _sourcesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ComicBrowseMessage(
                icon: Icons.error_outline_rounded,
                title: '源列表加载失败',
                detail: '${snapshot.error}',
                onRetry: _reload,
              );
            }
            final sources = snapshot.data ?? const <ComicBrowseSourceInfo>[];
            if (sources.isEmpty) {
              return const ComicBrowseMessage(
                icon: Icons.source_outlined,
                title: '还没有可浏览的来源',
                detail: '先在主页的「源管理」里导入并启用一个源，分类页会显示它的分类。',
              );
            }
            final selected = _selectedKey ?? sources.first.key;
            if (_selectedKey == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _selectSource(sources.first.key);
              });
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ComicBrowseSourceChips(
                  keyPrefix: 'category-source',
                  sources: sources,
                  selectedKey: selected,
                  onSelect: _selectSource,
                ),
                Expanded(child: _buildBody(selected)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(String key) {
    final treeFuture = _treeFuture;
    if (treeFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder<_CategoryData>(
      future: treeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ComicBrowseMessage(
            icon: Icons.error_outline_rounded,
            title: '分类加载失败',
            detail: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        final data = snapshot.data ?? const _CategoryData();
        final groups = [
          for (final group in data.groups)
            if (group.targets.isNotEmpty) group,
        ];
        if (groups.isEmpty) {
          return ComicBrowseMessage(
            icon: Icons.category_outlined,
            title: '这个来源没有分类',
            detail: '源脚本没有提供 category，也没有可用的探索分区。可以换个来源，或用主页搜索。',
            onRetry: _reload,
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            if (data.fallback)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '该来源没有分类，已回退到它的发现分栏。',
                  key: const Key('category-fallback-hint'),
                  style: Theme.of(context).textTheme.bodySmall?.apply(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final group in groups) ...<Widget>[
              ComicSectionHeader(title: group.name),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final target in group.targets)
                    ChoiceChip(
                      key: Key('category-item-${target.keySuffix}'),
                      label: Text(target.label),
                      selected: identical(_target, target),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _selectTarget(target),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            _buildComics(),
          ],
        );
      },
    );
  }

  Widget _buildComics() {
    final target = _target;
    final future = _comicsFuture;
    if (target == null || future == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '选择一个分类查看漫画',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.apply(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return FutureBuilder<ComicBrowseGroup>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return ComicBrowseMessage(
            icon: Icons.error_outline_rounded,
            title: '「${target.label}」加载失败',
            detail: '${snapshot.error}',
            onRetry: () => _selectTarget(target),
          );
        }
        final group = snapshot.data;
        final comics = group?.comics ?? const <ComicSummary>[];
        if (comics.isEmpty) {
          final reasons = group?.diagnostics ?? const <String>[];
          return ComicBrowseMessage(
            icon: reasons.isEmpty
                ? Icons.search_off_rounded
                : Icons.error_outline_rounded,
            title: reasons.isEmpty
                ? '「${target.label}」暂无漫画'
                : '「${target.label}」加载失败',
            detail: reasons.isEmpty
                ? '源返回了空列表。可以换一个分类，或稍后重试。'
                : reasons.join('\n'),
            onRetry: () => _selectTarget(target),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '共 ${comics.length} 部',
                style: Theme.of(context).textTheme.labelLarge?.apply(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // 分类结果网格放在外层 ListView 里：用 shrinkWrap + 禁用内层滚动，
            // 避免「无限高度」断言（分类页整体是一个滚动区）。
            ComicPosterGrid(
              items: comics,
              keyPrefix: 'category-result',
              onOpen: widget.onOpenDetail,
              padding: EdgeInsets.zero,
              shrinkWrap: true,
            ),
          ],
        );
      },
    );
  }
}

/// 分类页数据快照。
class _CategoryData {
  const _CategoryData({this.groups = const [], this.fallback = false});

  final List<_CategoryGroup> groups;

  /// true = 该源没有 category，展示的是 explore 回退项。
  final bool fallback;
}

class _CategoryGroup {
  const _CategoryGroup({required this.name, this.targets = const []});

  final String name;
  final List<_CategoryTarget> targets;
}
