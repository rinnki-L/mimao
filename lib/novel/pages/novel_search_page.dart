// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 统一搜索页：搜索历史（真实落库）+ 本地书架/阅读记录/书源的关键词匹配 +
/// 在线跨源搜索（选源范围 / 去重合并 / 排序 / 分页 / 单源重试 / 直接入架）。
///
/// 在线部分的状态机在 `search/novel_search_session.dart`（可单测），选源与
/// 合并排序在 `search/novel_search_scope.dart` / `novel_search_merge.dart`；
/// 本页只负责把它们接上 UI，不重复实现解析逻辑。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/search/novel_search_merge.dart';
import 'package:mimao/novel/search/novel_search_scope.dart';
import 'package:mimao/novel/search/novel_search_session.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

/// 单次在线搜索最多并发搜多少个源（其余源可在「规则管理」里手动指定分组缩小范围）。
const int _onlineSourceLimit = 60;

class NovelSearchPage extends StatefulWidget {
  const NovelSearchPage({
    super.key,
    this.collect,
    this.history,
    this.searchHistory,
    this.sourceImporter,
    this.onlineEngine,
    this.sourceStore,
    this.initialQuery,
    this.openRoute,
  });

  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final NovelSourceImporter? sourceImporter;
  final NovelOnlineEngine? onlineEngine;
  final NovelSourceStorage? sourceStore;

  /// 深链/调试入口预填关键词并在首帧后自动搜索。
  final String? initialQuery;
  final NovelRouteOpener? openRoute;

  @override
  State<NovelSearchPage> createState() => _NovelSearchPageState();
}

class _NovelSearchPageState extends State<NovelSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<String> _terms = const <String>[];
  String _query = '';
  bool _loading = false;
  String? _error;
  _SearchResults _results = _SearchResults.empty;

  /// 已加载的全部书源（选源面板与搜索共用同一份快照）。
  List<NovelBookSource> _allSources = const <NovelBookSource>[];

  /// 本次搜索范围。
  NovelSearchScope _scope = const NovelSearchScope();

  NovelSearchSession? _session;
  NovelSearchSort _sort = NovelSearchSort.relevance;

  /// 已加入书架的本地 id 集合（用于结果行按钮状态）。
  Set<String> _collectedIds = <String>{};

  /// 正在加入书架的合并键。
  final Set<String> _collecting = <String>{};

  /// 展开查看各源的合并键。
  final Set<String> _expanded = <String>{};

  String? _sourceError;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadTerms();
    unawaited(_loadCollected());
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_submit(initial));
      });
    }
  }

  @override
  void dispose() {
    _session?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadTerms() async {
    final api = widget.searchHistory;
    if (api == null) return;
    try {
      final terms = await api.recent(limit: 20);
      if (!mounted) return;
      setState(() {
        _terms = terms;
      });
    } on Object {
      // 历史读取失败不阻断搜索本身。
    }
  }

  Future<void> _loadCollected() async {
    final api = widget.collect;
    if (api == null) return;
    try {
      final ids = await api.collectedIds();
      if (!mounted) return;
      setState(() => _collectedIds = ids);
    } on Object {
      // 书架读取失败不影响搜索结果展示。
    }
  }

  NovelSourceStorage? get _store =>
      widget.sourceStore ?? widget.sourceImporter?.store;

  /// 读全部书源（选源面板与在线搜索共用一次读取）。
  Future<List<NovelBookSource>> _loadSources() async {
    final store = _store;
    if (store == null) return const <NovelBookSource>[];
    return store.loadAll();
  }

  Future<void> _submit(String raw) async {
    final keyword = raw.trim();
    if (keyword.isEmpty) {
      _focus.requestFocus();
      return;
    }
    _controller.text = keyword;
    _controller.selection = TextSelection.collapsed(offset: keyword.length);
    setState(() {
      _query = keyword;
      _loading = true;
      _error = null;
      _status = null;
      _sourceError = null;
      _expanded.clear();
    });
    try {
      await widget.searchHistory?.record(keyword);
    } on Object {
      // 记录搜索词失败不影响结果展示。
    }
    await _loadTerms();
    try {
      final results = await _search(keyword);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      await _searchOnline(keyword);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '本地搜索失败：$error';
      });
    }
  }

  Future<_SearchResults> _search(String keyword) async {
    final needle = keyword.toLowerCase();
    final errors = <String>[];

    var collects = const <NovelCollectItem>[];
    final collectApi = widget.collect;
    if (collectApi != null) {
      try {
        collects = await collectApi.list();
      } on Object catch (error) {
        errors.add('书架读取失败：$error');
      }
    }
    var recent = const <NovelHistoryItem>[];
    final historyApi = widget.history;
    if (historyApi != null) {
      try {
        recent = await historyApi.recent(limit: 300);
      } on Object catch (error) {
        errors.add('阅读记录读取失败：$error');
      }
    }
    var sources = const <NovelBookSource>[];
    if (_store != null) {
      try {
        sources = await _loadSources();
      } on Object catch (error) {
        errors.add('书源读取失败：$error');
      }
    }

    final historyById = <String, NovelHistoryItem>{
      for (final item in recent) item.book.id: item,
    };
    final seen = <String>{};
    final books = <_SearchBook>[];
    for (final item in collects) {
      seen.add(item.ref.id);
      final historyItem = historyById[item.ref.id];
      final book =
          item.book ??
          historyItem?.book ??
          NovelSummary(
            id: item.ref.id,
            title: item.title,
            coverUrl: item.coverUrl ?? '',
            sourceName: item.ref.sourceName,
          );
      if (!'${book.title} ${book.author} ${book.id}'.toLowerCase().contains(
        needle,
      )) {
        continue;
      }
      books.add(_SearchBook(book: book, history: historyItem, collected: true));
    }
    for (final item in recent) {
      if (seen.contains(item.book.id)) continue;
      if (!'${item.book.title} ${item.book.author} ${item.book.id}'
          .toLowerCase()
          .contains(needle)) {
        continue;
      }
      books.add(_SearchBook(book: item.book, history: item));
    }
    final matchedSources = <NovelBookSource>[
      for (final source in sources)
        if ('${source.name} ${source.url} ${source.groupLabel}'
            .toLowerCase()
            .contains(needle))
          source,
    ];
    return _SearchResults(
      books: books,
      sources: matchedSources,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  Future<void> _searchOnline(String keyword) async {
    final engine = widget.onlineEngine;
    final store = _store;
    if (engine == null || store == null) return;

    List<NovelBookSource> all;
    try {
      all = await _loadSources();
    } on Object catch (error) {
      if (!mounted || _query != keyword) return;
      setState(() => _sourceError = '书源读取失败：$error');
      return;
    }
    if (!mounted || _query != keyword) return;

    final searchable = _scope.select(all);
    setState(() {
      _allSources = all;
      _sourceError = null;
    });
    if (searchable.isEmpty) {
      _session?.cancel();
      setState(() {
        _session = null;
        _sourceError =
            '没有可搜索的启用书源（文本类型且配置了搜索地址）；'
            '换个选源范围，或到「规则管理」里导入书源。';
      });
      return;
    }

    final truncated = searchable.length > _onlineSourceLimit;
    final selected = truncated
        ? searchable.take(_onlineSourceLimit).toList()
        : searchable;

    _session?.cancel();
    final session = NovelSearchSession(engine: engine)
      ..onChanged = () {
        if (mounted && _query == keyword) setState(() {});
      };
    setState(() {
      _session = session;
      if (truncated) {
        _status =
            '本次只搜前 $_onlineSourceLimit 个源（按权重）；'
            '可在选源面板里手选或按分组缩小范围。';
      }
    });
    await session.start(selected, keyword);
    if (!mounted || _query != keyword) return;
    await _loadCollected();
  }

  Future<void> _loadMore() async {
    final session = _session;
    if (session == null || session.running) return;
    await session.loadMore();
  }

  Future<void> _retrySource(String sourceKey) async {
    final session = _session;
    if (session == null) return;
    await session.retrySource(sourceKey);
  }

  Future<void> _retryAllFailed() async {
    final session = _session;
    if (session == null) return;
    await session.retryFailed();
  }

  Future<void> _openScopePanel() async {
    final sources = _allSources.isEmpty ? await _loadSources() : _allSources;
    if (!mounted) return;
    setState(() => _allSources = sources);
    final next = await showModalBottomSheet<NovelSearchScope>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SearchScopeSheet(
        sources: sources,
        initial: _scope,
        limit: _onlineSourceLimit,
      ),
    );
    if (next == null || !mounted) return;
    setState(() => _scope = next);
    if (_query.isNotEmpty) await _searchOnline(_query);
  }

  Future<void> _changeSort(NovelSearchSort sort) async {
    if (sort == _sort) return;
    setState(() => _sort = sort);
  }

  /// 直接把搜索结果加入书架（不必先进详情）。
  Future<void> _collectMerged(NovelMergedBook merged) async {
    final api = widget.collect;
    if (api == null) {
      setState(() => _status = '没有注入书架服务，无法加入书架');
      return;
    }
    if (_collecting.contains(merged.key)) return;
    setState(() => _collecting.add(merged.key));
    try {
      await api.collect(merged.displayBook);
      if (!mounted) return;
      setState(() {
        _collectedIds = <String>{..._collectedIds, merged.book.id};
        _status = '已加入书架：${merged.book.title}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = '加入书架失败：$error');
    } finally {
      if (mounted) setState(() => _collecting.remove(merged.key));
    }
  }

  Future<void> _openBook(NovelSummary book) async {
    await openNovelRoute(
      context,
      widget.openRoute,
      NovelRoute.bookInfo,
      args: <String, Object?>{
        'bookId': book.id,
        'title': book.title,
        'author': book.author,
        'coverUrl': book.coverUrl,
        'sourceKey': book.sourceKey,
        'bookUrl': book.bookUrl,
      },
    );
  }

  Future<void> _openSources() async {
    await openNovelRoute(context, widget.openRoute, NovelRoute.sourceManage);
  }

  Future<void> _clearTerms() async {
    final api = widget.searchHistory;
    if (api == null) return;
    await api.clear();
    if (mounted) {
      setState(() {
        _terms = const <String>[];
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 在线结果区

  Widget _buildOnlineSection(ThemeData theme, ColorScheme cs) {
    final session = _session;
    final online = widget.onlineEngine != null && _store != null;
    if (!online) {
      return NovelEmptyState(
        icon: Icons.cloud_off,
        title: '在线书源未接入',
        message:
            '当前只搜本地书架、阅读记录与已导入书源。'
            '接入在线引擎后，这里会显示跨源搜索结果。',
      );
    }
    if (session == null) {
      if (_sourceError != null) {
        return NovelErrorState(
          message: _sourceError!,
          onRetry: () => _searchOnline(_query),
        );
      }
      return const SizedBox.shrink();
    }

    final merged = session.merged(sort: _sort);
    final failed = session.failedStates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '在线书源 · ${merged.length} 本 / ${session.total} 个源',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (session.running)
              Text(
                '${session.done}/${session.total}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            PopupMenuButton<NovelSearchSort>(
              key: const Key('novel-search-sort'),
              tooltip: '排序',
              initialValue: _sort,
              onSelected: (value) => unawaited(_changeSort(value)),
              itemBuilder: (context) => <PopupMenuEntry<NovelSearchSort>>[
                for (final sort in NovelSearchSort.values)
                  PopupMenuItem<NovelSearchSort>(
                    value: sort,
                    child: Text(sort.label),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.sort, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(_sort.label, style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (session.running) ...<Widget>[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(MimaoRadii.pill),
            child: LinearProgressIndicator(
              value: session.total == 0 ? null : session.done / session.total,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
        if (failed.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _FailedSourcesBar(
            states: failed,
            busy: session.running,
            onRetry: _retrySource,
            onRetryAll: _retryAllFailed,
          ),
        ],
        const SizedBox(height: 12),
        if (merged.isEmpty && !session.running)
          NovelEmptyState(
            icon: Icons.travel_explore,
            title: '在线书源没有结果',
            message: session.total == 0
                ? '没有可搜索的源，先在选源面板里调整范围。'
                : '已搜 ${session.total} 个源'
                      '${session.failureCount > 0 ? '，${session.failureCount} 个失败或超时' : ''}。'
                      '换一个关键词，或到「发现」里按源查看。',
          )
        else
          for (final book in merged) ...<Widget>[
            _MergedBookRow(
              key: ValueKey<String>('merged-${book.key}'),
              book: book,
              collected: _collectedIds.contains(book.book.id),
              collecting: _collecting.contains(book.key),
              expanded: _expanded.contains(book.key),
              onTap: () => _openBook(book.displayBook),
              onCollect: () => unawaited(_collectMerged(book)),
              onToggleExpand: () => setState(() {
                if (!_expanded.remove(book.key)) _expanded.add(book.key);
              }),
              onOpenHit: (hit) => _openBook(hit.book),
            ),
            const SizedBox(height: 8),
          ],
        if (merged.isNotEmpty && !session.running) ...<Widget>[
          const SizedBox(height: 8),
          Center(
            child: session.canLoadMore
                ? OutlinedButton.icon(
                    key: const Key('novel-search-load-more'),
                    onPressed: _loadMore,
                    icon: const Icon(Icons.expand_more, size: 18),
                    label: const Text('加载下一页'),
                  )
                : Text(
                    '已到最后一页',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: NovelPageContent(
        maxWidth: 900,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: ListView(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: '搜索书名 / 作者 / 书源',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onSubmitted: _submit,
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _submit(_controller.text),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('搜索'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ScopeBar(
              scope: _scope,
              enabled: widget.onlineEngine != null && _store != null,
              onTap: _openScopePanel,
            ),
            if (_status != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
              ),
            ],
            if (_terms.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('搜索历史', style: theme.textTheme.titleSmall),
                  ),
                  TextButton(onPressed: _clearTerms, child: const Text('清除')),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final term in _terms)
                    ActionChip(
                      label: Text(term),
                      onPressed: () => _submit(term),
                    ),
                ],
              ),
            ],
            if (_query.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: NovelLoadingState(label: '正在搜索本地书架与书源…'),
                )
              else if (_error != null)
                NovelErrorState(
                  message: _error!,
                  onRetry: () => _submit(_query),
                )
              else ...<Widget>[
                if (_results.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _results.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                      ),
                    ),
                  ),
                if (_results.isEmpty)
                  NovelEmptyState(
                    icon: Icons.search_off,
                    title: '本地没有匹配「$_query」',
                    message: widget.onlineEngine != null
                        ? '本地书架、阅读记录与书源里都没有；在线书源结果在下方。'
                        : '本地书架、阅读记录与书源里都没有。在线书源引擎未注入。',
                  )
                else ...<Widget>[
                  _ResultSection(
                    title: '本地书籍',
                    count: _results.books.length,
                    child: Column(
                      children: <Widget>[
                        for (final item in _results.books)
                          _SearchBookRow(
                            item: item,
                            onTap: () => _openBook(item.book),
                          ),
                      ],
                    ),
                  ),
                  if (_results.sources.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    _ResultSection(
                      title: '书源',
                      count: _results.sources.length,
                      child: Column(
                        children: <Widget>[
                          for (final source in _results.sources.take(8))
                            _SearchSourceRow(
                              source: source,
                              onTap: _openSources,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                _buildOnlineSection(theme, cs),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchResults {
  const _SearchResults({
    required this.books,
    required this.sources,
    this.error,
  });

  static const _SearchResults empty = _SearchResults(
    books: <_SearchBook>[],
    sources: <NovelBookSource>[],
  );

  final List<_SearchBook> books;
  final List<NovelBookSource> sources;
  final String? error;

  bool get isEmpty => books.isEmpty && sources.isEmpty;
}

class _SearchBook {
  const _SearchBook({required this.book, this.history, this.collected = false});

  final NovelSummary book;
  final NovelHistoryItem? history;
  final bool collected;
}

/// 选源范围条：点开面板；未接入在线引擎时禁用并说明。
class _ScopeBar extends StatelessWidget {
  const _ScopeBar({
    required this.scope,
    required this.enabled,
    required this.onTap,
  });

  final NovelSearchScope scope;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(MimaoRadii.md),
      child: InkWell(
        key: const Key('novel-search-scope'),
        borderRadius: BorderRadius.circular(MimaoRadii.md),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: <Widget>[
              Icon(
                scope.isNarrowed ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 18,
                color: enabled ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      enabled ? '选源范围 · ${scope.describe()}' : '选源范围 · 在线引擎未接入',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? '全部启用源 / 指定分组 / 手选源；范围会记住到下次搜索。'
                          : '接入在线引擎后可限定搜索范围。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.tune, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选源面板：三种模式 + 分组多选 + 手选源多选。
class _SearchScopeSheet extends StatefulWidget {
  const _SearchScopeSheet({
    required this.sources,
    required this.initial,
    required this.limit,
  });

  final List<NovelBookSource> sources;
  final NovelSearchScope initial;
  final int limit;

  @override
  State<_SearchScopeSheet> createState() => _SearchScopeSheetState();
}

class _SearchScopeSheetState extends State<_SearchScopeSheet> {
  late NovelSearchScope _scope = widget.initial;
  late final List<String> _groups = novelSourceGroups(widget.sources);
  late final List<NovelBookSource> _searchable = const NovelSearchScope()
      .select(widget.sources);
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedCount = _scope.select(widget.sources).length;
    final visible = <NovelBookSource>[
      for (final source in _searchable)
        if (_filter.isEmpty ||
            '${source.name} ${source.url} ${source.groupLabel}'
                .toLowerCase()
                .contains(_filter.toLowerCase()))
          source,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text('选源范围', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    '将搜 $selectedCount 个源',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<NovelSearchScopeMode>(
                segments: const <ButtonSegment<NovelSearchScopeMode>>[
                  ButtonSegment<NovelSearchScopeMode>(
                    value: NovelSearchScopeMode.all,
                    label: Text('全部'),
                    icon: Icon(Icons.public, size: 16),
                  ),
                  ButtonSegment<NovelSearchScopeMode>(
                    value: NovelSearchScopeMode.group,
                    label: Text('分组'),
                    icon: Icon(Icons.folder_outlined, size: 16),
                  ),
                  ButtonSegment<NovelSearchScopeMode>(
                    value: NovelSearchScopeMode.manual,
                    label: Text('手选'),
                    icon: Icon(Icons.checklist, size: 16),
                  ),
                ],
                selected: <NovelSearchScopeMode>{_scope.mode},
                onSelectionChanged: (value) =>
                    setState(() => _scope = _scope.withMode(value.first)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: switch (_scope.mode) {
                NovelSearchScopeMode.all => _buildAllMode(theme, cs),
                NovelSearchScopeMode.group => _buildGroupMode(theme, cs),
                NovelSearchScopeMode.manual => _buildManualMode(
                  theme,
                  cs,
                  visible,
                ),
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '面板只列可搜索的源（启用 + 文本 + 有搜索地址）。'
                      '本次最多搜 ${widget.limit} 个源。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () =>
                        setState(() => _scope = const NovelSearchScope()),
                    child: const Text('重置'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('novel-search-scope-apply'),
                    onPressed: () => Navigator.of(context).pop(_scope),
                    child: const Text('应用'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllMode(ThemeData theme, ColorScheme cs) {
    final groups = _groups;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: <Widget>[
        Text(
          '搜全部 ${_searchable.length} 个可搜索源，按权重从高到低排队；'
          '超过 ${widget.limit} 个时只跑前 ${widget.limit} 个。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        if (groups.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text('当前分组', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final group in groups)
                NovelFilterChip(
                  label: group,
                  count: _searchable
                      .where(
                        (source) => group == novelUngroupedLabel
                            ? source.groups.isEmpty
                            : source.groups.contains(group),
                      )
                      .length,
                  selected: false,
                  onTap: () =>
                      setState(() => _scope = _scope.toggleGroup(group)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '点分组即切到「分组」模式并只搜它。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGroupMode(ThemeData theme, ColorScheme cs) {
    if (_groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          '所有书源都没有分组。到「规则管理 → 书源」里给书源加分组，'
          '或在上面切到「手选」逐个勾。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: <Widget>[
        Text(
          '勾选要搜的分组；一个都不勾等于搜全部分组。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final group in _groups)
              NovelFilterChip(
                key: ValueKey<String>('scope-group-$group'),
                label: group,
                count: _searchable
                    .where(
                      (source) => group == novelUngroupedLabel
                          ? source.groups.isEmpty
                          : source.groups.contains(group),
                    )
                    .length,
                selected: _scope.groups.contains(group),
                onTap: () => setState(() => _scope = _scope.toggleGroup(group)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildManualMode(
    ThemeData theme,
    ColorScheme cs,
    List<NovelBookSource> visible,
  ) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '筛选书源名称 / 地址 / 分组',
              prefixIcon: Icon(Icons.filter_list, size: 18),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _filter = value.trim()),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '勾选要搜的源；一个都不勾等于搜全部源。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _scope = NovelSearchScope(
                    mode: NovelSearchScopeMode.manual,
                    groups: _scope.groups,
                    sourceKeys: <String>{
                      for (final source in visible) source.key,
                    },
                  ),
                ),
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _scope = NovelSearchScope(
                    mode: NovelSearchScopeMode.manual,
                    groups: _scope.groups,
                  ),
                ),
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '没有匹配「$_filter」的可搜索书源。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final source = visible[index];
                    return CheckboxListTile(
                      key: ValueKey<String>('scope-source-${source.key}'),
                      dense: true,
                      value: _scope.includesSource(source.key),
                      onChanged: (_) => setState(
                        () => _scope = _scope.toggleSource(source.key),
                      ),
                      title: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${source.groupLabel} · 权重 ${source.weight}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 失败源条：列出失败源与可读原因，支持单源重试 / 全部重试。
class _FailedSourcesBar extends StatelessWidget {
  const _FailedSourcesBar({
    required this.states,
    required this.busy,
    required this.onRetry,
    required this.onRetryAll,
  });

  final List<NovelSourceSearchState> states;
  final bool busy;
  final Future<void> Function(String sourceKey) onRetry;
  final Future<void> Function() onRetryAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline, size: 18, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${states.length} 个源失败或超时',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                ),
              ),
              TextButton(
                key: const Key('novel-search-retry-all'),
                onPressed: busy ? null : () => onRetryAll(),
                child: const Text('全部重试'),
              ),
            ],
          ),
          for (final state in states.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${state.source.name}：${state.error ?? '未知错误'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    key: ValueKey<String>('retry-${state.source.key}'),
                    onPressed: busy ? null : () => onRetry(state.source.key),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (states.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '另有 ${states.length - 4} 个源失败，点「全部重试」。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 合并后的一本书：封面 + 书名 + 作者 + 覆盖源数 + 字数 + 加入书架 + 展开各源。
class _MergedBookRow extends StatelessWidget {
  const _MergedBookRow({
    super.key,
    required this.book,
    required this.collected,
    required this.collecting,
    required this.expanded,
    required this.onTap,
    required this.onCollect,
    required this.onToggleExpand,
    required this.onOpenHit,
  });

  final NovelMergedBook book;
  final bool collected;
  final bool collecting;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onCollect;
  final VoidCallback onToggleExpand;
  final void Function(NovelSearchHit hit) onOpenHit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final display = book.displayBook;
    final wordCount = book.wordCount;
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 44,
                height: 64,
                child: NovelBookCover(
                  url: display.coverUrl,
                  title: display.title,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        display.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        display.author.isEmpty ? '作者未知' : display.author,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          NovelTag(
                            label: '${book.sourceCount} 个源',
                            highlighted: book.sourceCount > 1,
                          ),
                          if (display.kind.isNotEmpty)
                            NovelTag(label: display.kind.split(',').first),
                          if (wordCount != null)
                            NovelTag(label: '${(wordCount / 10000).ceil()} 万字'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: ValueKey<String>('collect-${book.key}'),
                tooltip: collected ? '已在书架' : '加入书架',
                onPressed: collected || collecting ? null : onCollect,
                icon: collecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        collected
                            ? Icons.bookmark
                            : Icons.bookmark_add_outlined,
                        size: 20,
                      ),
              ),
              IconButton(
                tooltip: expanded ? '收起各源' : '展开各源',
                onPressed: onToggleExpand,
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
              ),
            ],
          ),
          if (expanded) ...<Widget>[
            const SizedBox(height: 8),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 6),
            for (final hit in book.hits)
              InkWell(
                key: ValueKey<String>('hit-${hit.source.key}'),
                onTap: () => onOpenHit(hit),
                borderRadius: BorderRadius.circular(MimaoRadii.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    children: <Widget>[
                      NovelSourceBadge(name: hit.source.name, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              hit.source.name,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              [
                                '权重 ${hit.source.weight}',
                                if (hit.book.latestChapter.isNotEmpty)
                                  '最新 ${hit.book.latestChapter}',
                                '第 ${hit.page} 页',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.title,
    required this.count,
    required this.child,
  });

  final String title;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('$title · $count', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SearchBookRow extends StatelessWidget {
  const _SearchBookRow({required this.item, required this.onTap});

  final _SearchBook item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final history = item.history;
    final progress = history == null
        ? '未读'
        : novelProgressText(
            chapterIndex: history.chapterIndex,
            chapterCount: history.chapterCount,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NovelCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 44,
              height: 64,
              child: NovelBookCover(
                url: item.book.coverUrl,
                title: item.book.title,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.book.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.book.author.isEmpty ? '作者未知' : item.book.author}'
                    ' · $progress',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (item.collected)
              Icon(Icons.bookmark, size: 16, color: cs.primary),
            Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SearchSourceRow extends StatelessWidget {
  const _SearchSourceRow({required this.source, required this.onTap});

  final NovelBookSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NovelCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: <Widget>[
            NovelSourceBadge(name: source.name, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    source.name,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    source.url,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
