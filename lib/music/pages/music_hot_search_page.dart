// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 热门搜索页（发现页入口网格落位）：默认搜索词 + 热搜榜两个 section。
///
/// 两个 section 独立 loading/error/retry，失败只影响自己；chips 点击调用
/// 注入的 [MusicHotSearchPage.onSearch] 后返回上一页（发现页把关键词填入
/// 搜索框并提交，用户回到发现页时已在搜索结果）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:mimao/music/pages/music_discovery_list_page.dart';

/// 热门搜索页。
class MusicHotSearchPage extends StatefulWidget {
  const MusicHotSearchPage({
    super.key,
    required this.searchExt,
    required this.onSearch,
  });

  /// 搜索扩展端点组（searchDefault promotions / searchHot 分组）。
  final MusicSearchExtApi searchExt;

  /// 关键词命中回调：调用方负责把词填入搜索框并提交；本页随后 pop 返回。
  final void Function(String keyword) onSearch;

  @override
  State<MusicHotSearchPage> createState() => _MusicHotSearchPageState();
}

/// 一份 section 的独立三态（loading/error/items）；两个 section 互不阻塞。
class _AsyncList<T> {
  bool loading = false;
  Object? error;
  List<T> items = List<T>.empty();
}

class _MusicHotSearchPageState extends State<MusicHotSearchPage> {
  final _AsyncList<MusicSearchPromotion> _defaults =
      _AsyncList<MusicSearchPromotion>();
  final _AsyncList<MusicHotSearchGroup> _groups =
      _AsyncList<MusicHotSearchGroup>();

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    _loadGroups();
  }

  Future<void> _loadDefaults() => _load(
    _defaults,
    () async => (await widget.searchExt.searchDefault()).promotions,
  );

  Future<void> _loadGroups() => _load(_groups, widget.searchExt.searchHot);

  /// 跑一个 section 的加载：独立 loading/错误态，失败只影响自己。
  Future<void> _load<T>(
    _AsyncList<T> section,
    Future<List<T>> Function() task,
  ) async {
    section
      ..loading = true
      ..error = null;
    if (mounted) setState(() {});
    try {
      final items = await task();
      section
        ..items = items
        ..loading = false;
    } on Object catch (error) {
      section
        ..items = List<T>.empty()
        ..error = error
        ..loading = false;
    }
    if (mounted) setState(() {});
  }

  /// 点词：先返回发现页，再把关键词交给调用方填词提交（回调只操作发现页
  /// 状态，先 pop 可避免「搜索已提交却仍停在热门页」的错位）。
  void _search(String keyword) {
    final navigator = Navigator.of(context);
    navigator.pop();
    widget.onSearch(keyword);
  }

  // ── 骨架 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('热门搜索')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final defaultsVisible = _sectionVisible(_defaults);
    final groupsVisible = _sectionVisible(_groups);
    if (!defaultsVisible && !groupsVisible) {
      return const DiscoveryEmptyState(message: '暂无热门搜索');
    }
    return ListView(
      key: const Key('hot-search'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        if (defaultsVisible) ...<Widget>[
          Text('默认搜索词', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _defaultsBody(),
          const SizedBox(height: 16),
        ],
        if (groupsVisible) ...<Widget>[
          Text('热搜榜', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _groupsBody(),
        ],
      ],
    );
  }

  /// section 是否值得渲染：loading/有错误/有数据三种都要占位；
  /// 全空（未加载到内容且无错误）时整块隐藏，不留下光秃秃的标题。
  bool _sectionVisible<T>(_AsyncList<T> section) =>
      section.loading || section.error != null || section.items.isNotEmpty;

  /// 默认搜索词 chips（searchDefault promotions；title 即搜索词）。
  Widget _defaultsBody() {
    final section = _defaults;
    if (section.loading) return const _ChipPlaceholder();
    final error = section.error;
    if (error != null) {
      return DiscoverySectionError(error: error, onRetry: _loadDefaults);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final promotion in section.items)
          if (promotion.title.isNotEmpty || promotion.mainTitle.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.campaign_outlined, size: 16),
              label: Text(
                promotion.title.isNotEmpty
                    ? promotion.title
                    : promotion.mainTitle,
              ),
              onPressed: () => _search(
                promotion.title.isNotEmpty
                    ? promotion.title
                    : promotion.mainTitle,
              ),
            ),
      ],
    );
  }

  /// 热搜分组（searchHot）：每组一张卡 + 关键词 chips。
  Widget _groupsBody() {
    final section = _groups;
    if (section.loading) return const _ChipPlaceholder();
    final error = section.error;
    if (error != null) {
      return DiscoverySectionError(error: error, onRetry: _loadGroups);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final group in section.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      group.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final keyword in group.keywords)
                          ActionChip(
                            avatar: const Icon(
                              Icons.local_fire_department_outlined,
                              size: 16,
                            ),
                            label: Text(keyword.keyword),
                            tooltip: keyword.reason,
                            onPressed: () => _search(keyword.keyword),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// chips 区的加载占位：静态灰块（不用 indeterminate 进度条，避免
/// pumpAndSettle 不收敛）。
class _ChipPlaceholder extends StatelessWidget {
  const _ChipPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final width in const <double>[72, 96, 64, 88])
          Container(
            width: width,
            height: 32,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: MimaoShapes.pill,
            ),
          ),
      ],
    );
  }
}
