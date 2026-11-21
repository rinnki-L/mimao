// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/pages/comic_poster_card.dart'
    show ComicPosterGrid, ComicSectionHeader;

// 卡片与网格已抽到 comic_poster_card.dart（四个分区页共用同一形态）；
// 这里 re-export，既有 `import 'comic_search_page.dart'` 拿 ComicPosterCard
// 的调用方零改动。
export 'package:mimao/comic/pages/comic_poster_card.dart'
    show ComicPosterCard, ComicPosterGrid;

/// 漫画搜索页：搜索框 + 结果网格 + 空/错误/重试。
///
/// 只认 [ComicDataSource]；fixture 与 A′ 源引擎实现可无缝替换。
/// 空关键词返回推荐列表（fixture 语义），搜索无结果时显示空态。
class ComicSearchPage extends StatefulWidget {
  const ComicSearchPage({
    super.key,
    required this.dataSource,
    this.showAppBar = true,
    this.onOpenDetail,
  });

  final ComicDataSource dataSource;

  /// 壳已提供顶部导航时设为 false，本页不再画自己的 AppBar。
  final bool showAppBar;

  /// 点结果卡片时回调；由模块层决定如何钻进详情页。
  final ValueChanged<ComicSummary>? onOpenDetail;

  @override
  State<ComicSearchPage> createState() => _ComicSearchPageState();
}

/// 一次搜索的视图数据：聚合模式带按源分组的 sections，单源/无来源模式带摊平
/// 结果。用一个 future 同时携带两者，避免为了拿诊断再调一次数据源。
class _SearchViewData {
  const _SearchViewData._({this.sections, this.items});

  factory _SearchViewData.grouped(List<ComicSourceSearchSection> sections) =>
      _SearchViewData._(sections: sections);
  factory _SearchViewData.flat(List<ComicSummary> items) =>
      _SearchViewData._(items: items);

  /// 非 null 表示聚合模式（结果按源分组）。
  final List<ComicSourceSearchSection>? sections;

  /// 非 null 表示摊平模式（单源搜索 / 数据源未暴露来源）。
  final List<ComicSummary>? items;

  bool get isGrouped => sections != null;

  /// 总条目数（计数行 + 空态判定共用）。
  int get count =>
      sections?.fold<int>(0, (sum, s) => sum + s.items.length) ??
      items?.length ??
      0;
}

class _ComicSearchPageState extends State<ComicSearchPage> {
  final TextEditingController _controller = TextEditingController();
  late Future<_SearchViewData> _future;
  String _query = '';

  /// 诊断是"取走即清"，builder 内不能 setState。按 [_future] 身份缓存一次读取
  /// 结果：同一 future 的多次 build 复用缓存，换 future（新一轮搜索）才重新取。
  /// 这样既满足 builder 无副作用，也避免 rebuild 时诊断被清空后错误态闪烁回空态。
  /// 聚合模式下逐源诊断由 section.diagnostics 承担，这里只服务摊平模式空态。
  Future<_SearchViewData>? _diagnosticsForFuture;
  List<String> _searchDiagnostics = const <String>[];

  List<String> _diagnosticsFor(Future<_SearchViewData> future) {
    if (!identical(_diagnosticsForFuture, future)) {
      _diagnosticsForFuture = future;
      _searchDiagnostics = widget.dataSource.takeSearchDiagnostics();
    }
    return _searchDiagnostics;
  }

  /// 数据源提供的可选来源；空表示数据源未暴露来源（退化为全源搜索）。
  late List<String> _sourceKeys;

  /// 搜索历史：每次搜索后重建，FutureBuilder 从数据源读取真实历史词。
  late Future<List<String>> _historyFuture;

  /// 当前选中的来源；null = 聚合搜索（全源并发，结果按源分组）。
  String? _selectedSource;

  /// 是否处于聚合模式：数据源暴露了来源筛选且当前未选中任何单源。
  /// 无来源数据源（fixture/fake）保持旧行为——摊平网格，避免无谓分组。
  bool get _isGroupedMode => _sourceKeys.isNotEmpty && _selectedSource == null;

  @override
  void initState() {
    super.initState();
    _sourceKeys = widget.dataSource.availableSourceKeys();
    _historyFuture = widget.dataSource.recentSearchTerms();
    _future = _runQuery(_query);
  }

  @override
  void didUpdateWidget(ComicSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据源被替换（fixture 切换 / A′ 引擎注入）时刷新来源并按当前关键词重查。
    if (oldWidget.dataSource != widget.dataSource) {
      _sourceKeys = widget.dataSource.availableSourceKeys();
      // 选中的来源在新数据源里已不存在时回到「全部来源」。
      if (_selectedSource != null && !_sourceKeys.contains(_selectedSource)) {
        _selectedSource = null;
      }
      _future = _runQuery(_query);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按当前选中来源路由搜索：聚合模式走 [ComicDataSource.searchGrouped]
  /// （全源并发、按源分组），单源走 [ComicDataSource.searchSource]，无来源
  /// 数据源与空关键词走 [ComicDataSource.search] 保持旧行为。
  Future<_SearchViewData> _runQuery(String query) async {
    final key = _selectedSource;
    if (_isGroupedMode) {
      // 经统一入口分派：静态类型是 ComicDataSource 时扩展方法不会自动分派到
      // 引擎的 GroupedComicDataSource override，必须由 groupedSearch 做 is 收窄。
      final sections = await groupedSearch(widget.dataSource, query);
      return _SearchViewData.grouped(sections);
    }
    if (query.isNotEmpty && key != null && key.isNotEmpty) {
      return _SearchViewData.flat(
        await widget.dataSource.searchSource(key, query),
      );
    }
    return _SearchViewData.flat(await widget.dataSource.search(query));
  }

  void _runSearch(String value) {
    final query = value.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _query = query;
      _future = _runQuery(query);
      // 搜索经数据源落库后刷新历史 chips（真实读回最近词）。
      _historyFuture = widget.dataSource.recentSearchTerms();
    });
  }

  /// 切换来源后用当前关键词自动重搜；关键词为空时保持原语义（全源空查询）。
  void _selectSource(String? key) {
    setState(() {
      _selectedSource = key;
      _future = _runQuery(_query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('搜索漫画')) : null,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SearchBar(
                controller: _controller,
                hintText: '搜索漫画名称',
                leading: const Icon(Icons.search),
                trailing: <Widget>[
                  IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () => _runSearch(_controller.text),
                  ),
                ],
                textInputAction: TextInputAction.search,
                onSubmitted: _runSearch,
              ),
              if (_sourceKeys.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _buildSourceFilter(cs),
              ],
              const SizedBox(height: 8),
              _buildSearchHistory(cs),
              const SizedBox(height: 8),
              Expanded(child: _buildResults(context, cs)),
            ],
          ),
        ),
      ),
    );
  }

  /// 来源筛选行：「聚合搜索」+ 各可用源 key。选中后自动重搜。
  /// 用横向滚动避免多来源时挤出 390 宽屏幕。
  Widget _buildSourceFilter(ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _SourceFilterChip(
            label: '聚合搜索',
            selected: _selectedSource == null,
            onSelected: (_) => _selectSource(null),
            filterKey: const Key('source-filter-all'),
          ),
          for (final key in _sourceKeys)
            _SourceFilterChip(
              label: key,
              selected: _selectedSource == key,
              onSelected: (selected) => _selectSource(selected ? key : null),
              filterKey: Key('source-filter-$key'),
            ),
        ],
      ),
    );
  }

  /// 搜索历史行：真实读回最近关键词，点 chip 回填搜索框。数据源未实现
  /// （fixture/fake）时 recentSearchTerms 默认空 → 整行隐藏，零副作用。
  Widget _buildSearchHistory(ColorScheme cs) {
    return FutureBuilder<List<String>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        final terms = snapshot.data ?? const <String>[];
        if (terms.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              for (final term in terms.take(10))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(term),
                    onPressed: () => _runSearch(term),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(BuildContext context, ColorScheme cs) {
    return FutureBuilder<_SearchViewData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _SearchErrorState(onRetry: () => _runSearch(_query));
        }
        final view = snapshot.data;
        // 聚合模式只要拿到 section 就逐源展示：即使全源失败（count==0），
        // 每个失败源的 section.diagnostics 仍能上达，绝不退回笼统空态。
        // 只有「section 列表本身为空」（如空关键词）才走原空态。
        if (view != null && view.isGrouped) {
          if (view.sections!.isEmpty) {
            // 默认分组源（无 searchGrouped override）没有 section：失败原因
            // 只能走 takeSearchDiagnostics 全局出口（A/C 共存语义）。有诊断
            // 仍显示错误态，无诊断才回退空态。
            final diagnostics = _diagnosticsFor(_future);
            if (diagnostics.isNotEmpty) {
              return _SearchDiagnosticsState(
                diagnostics: diagnostics,
                onRetry: () => _runSearch(_query),
              );
            }
            return _SearchEmptyState(query: _query);
          }
          return _buildGroupedResults(context, cs, view.sections!);
        }
        if (view == null || view.count == 0) {
          // 摊平模式：失败被吞成空结果时，用搜索期诊断还原真实原因；
          // 无诊断时保留原空态（回显关键词）。
          final diagnostics = _diagnosticsFor(_future);
          if (diagnostics.isNotEmpty) {
            return _SearchDiagnosticsState(
              diagnostics: diagnostics,
              onRetry: () => _runSearch(_query),
            );
          }
          return _SearchEmptyState(query: _query);
        }
        return _buildFlatResults(context, cs, view.items!);
      },
    );
  }

  /// 摊平结果（单源搜索 / 无来源数据源）：保留旧版「共 N 部」+ 网格。
  Widget _buildFlatResults(
    BuildContext context,
    ColorScheme cs,
    List<ComicSummary> results,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          '共 ${results.length} 部',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.apply(color: cs.onSurfaceVariant),
        ),
      ),
      Expanded(
        child: ComicPosterGrid(
          items: results,
          keyPrefix: 'search-result',
          onOpen: widget.onOpenDetail,
        ),
      ),
    ],
  );

  /// 聚合结果：每个源一个可见 section（含 0 结果带诊断的源）。
  /// 排序：有结果的组在前、失败/空组在后，组内按源 key 稳定序。
  Widget _buildGroupedResults(
    BuildContext context,
    ColorScheme cs,
    List<ComicSourceSearchSection> sections,
  ) {
    final ordered = <ComicSourceSearchSection>[
      ...sections.where((s) => s.items.isNotEmpty),
      ...sections.where((s) => s.items.isEmpty),
    ];
    final sourceCount = sections.length;
    final comicCount = sections.fold<int>(0, (sum, s) => sum + s.items.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            '$sourceCount 个源 · $comicCount 部',
            key: const Key('search-group-summary'),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.apply(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          // 用 SingleChildScrollView + Column 而非 ListView.builder：懒构建会
          // 让屏幕外的失败/空源 section 不在树里，违背「每源 section 可见」，
          // widget 测试也找不到。源数量有限（已启用源），全量构建可接受。
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final section in ordered)
                  _buildSourceSection(context, cs, section),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 单个源的分区：组头（源 key + 「N 部」）+ 可选失败原因行 + 结果网格。
  Widget _buildSourceSection(
    BuildContext context,
    ColorScheme cs,
    ComicSourceSearchSection section,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        key: Key('search-group-${section.sourceKey}'),
        children: <Widget>[
          ComicSectionHeader(
            title: section.sourceKey,
            trailing: Text(
              '${section.items.length} 部',
              style: theme.textTheme.labelMedium?.apply(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          // 失败/空结果原因逐条列出，带「源key：」前缀的原文，绝不静默吞掉。
          for (final reason in section.diagnostics)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $reason',
                key: Key('search-group-diagnostic-${section.sourceKey}'),
                style: theme.textTheme.bodySmall?.apply(color: cs.error),
              ),
            ),
          if (section.items.isNotEmpty)
            ComicPosterGrid(
              items: section.items,
              // 卡片 key 沿用 search-result-<id>：既有调用方/测试用该 key 定位
              // 结果卡片，分组只是外层包裹，不应破坏卡片级定位契约。不同源的
              // 网格是不同父节点，key 不构成兄弟冲突。
              keyPrefix: 'search-result',
              onOpen: widget.onOpenDetail,
              shrinkWrap: true,
            ),
        ],
      ),
    );
  }
}

/// 单个来源筛选 chip。故意包装成无状态组件：外层只关心选中态与回调，
/// 测试用 [key] 稳定定位（all / 具体源 key）。
class _SourceFilterChip extends StatelessWidget {
  const _SourceFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.filterKey,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Key? filterKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        key: filterKey,
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty ? '暂时没有可搜索的漫画' : '没有找到「$query」',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '换个关键词试试',
              style: textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
          const SizedBox(height: 12),
          const Text('搜索失败，请稍后重试'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 搜索无结果但有诊断时的错误态：逐条列出各源失败原因，而不是笼统的"没找到"。
/// 最多展示 10 条，超出用"还有 N 条"收口；提供重试。
class _SearchDiagnosticsState extends StatelessWidget {
  const _SearchDiagnosticsState({
    required this.diagnostics,
    required this.onRetry,
  });

  /// 单页最多列出的原因条数（超出显示"还有 N 条"）。
  static const int _maxVisible = 10;

  final List<String> diagnostics;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visible = diagnostics.take(_maxVisible).toList(growable: false);
    final remaining = diagnostics.length - visible.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('搜索未成功', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '以下来源未能返回结果：',
              style: theme.textTheme.bodyMedium?.apply(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final reason in visible)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '• $reason',
                          key: Key('search-diagnostic-$reason'),
                          style: theme.textTheme.bodySmall?.apply(
                            color: cs.error,
                          ),
                        ),
                      ),
                    if (remaining > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '还有 $remaining 条',
                          key: const Key('search-diagnostics-remaining'),
                          style: theme.textTheme.bodySmall?.apply(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
