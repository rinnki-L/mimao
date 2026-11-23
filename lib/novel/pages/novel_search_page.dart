// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 统一搜索页：搜索历史（真实落库）+ 本地书架/阅读记录/书源的关键词匹配。
///
/// 在线跨源搜索走 `NovelOnlineEngine`（按源分组、限流并发）；本地匹配是
/// 点书进详情、点书源进管理，不伪造搜索结果。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_store.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

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

  final List<_OnlineGroup> _onlineGroups = <_OnlineGroup>[];
  bool _onlineSearching = false;
  int _onlineDone = 0;
  int _onlineTotal = 0;
  int _onlineFailures = 0;
  String? _onlineError;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _loadTerms();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_submit(initial));
      });
    }
  }

  @override
  void dispose() {
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

  Future<void> _submit(String raw) async {
    final keyword = raw.trim();
    if (keyword.isEmpty) {
      _focus.requestFocus();
      return;
    }
    _controller.text = keyword;
    _controller.selection = TextSelection.collapsed(offset: keyword.length);
    final token = ++_searchToken;
    setState(() {
      _query = keyword;
      _loading = true;
      _error = null;
      _onlineGroups.clear();
      _onlineSearching = false;
      _onlineDone = 0;
      _onlineTotal = 0;
      _onlineFailures = 0;
      _onlineError = null;
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
      unawaited(_searchOnline(keyword, token));
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
    final importer = widget.sourceImporter;
    if (importer != null) {
      try {
        sources = await importer.store.loadAll();
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

  static const int _onlineConcurrency = 6;

  Future<void> _searchOnline(String keyword, int token) async {
    final engine = widget.onlineEngine;
    final store = widget.sourceStore ?? widget.sourceImporter?.store;
    if (engine == null || store == null) return;
    List<NovelBookSource> all;
    try {
      all = await store.loadAll();
    } on Object catch (error) {
      if (token != _searchToken || !mounted) return;
      setState(() => _onlineError = '书源读取失败：$error');
      return;
    }
    final searchable =
        <NovelBookSource>[
          for (final source in all)
            if (source.enabled &&
                source.type == 0 &&
                source.searchUrl.trim().isNotEmpty &&
                source.searchUrl.trim() != '-')
              source,
        ]..sort((a, b) {
          final weight = b.weight.compareTo(a.weight);
          if (weight != 0) return weight;
          return a.name.compareTo(b.name);
        });
    final selected = searchable.take(_onlineSourceLimit).toList();
    if (token != _searchToken || !mounted) return;
    if (selected.isEmpty) {
      setState(() {
        _onlineSearching = false;
        _onlineTotal = 0;
        _onlineError = '没有可搜索的启用书源（文本类型且配置了搜索地址）';
      });
      return;
    }
    setState(() {
      _onlineSearching = true;
      _onlineTotal = selected.length;
      _onlineDone = 0;
      _onlineFailures = 0;
      _onlineGroups.clear();
      _onlineError = null;
    });

    final queue = List<NovelBookSource>.of(selected);
    final groups = <String, _OnlineGroup>{};
    final failures = <String>[];
    var done = 0;
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (token != _searchToken) return;
        final source = queue.removeAt(0);
        try {
          final books = await engine
              .searchSource(source, keyword)
              .timeout(const Duration(seconds: 12));
          if (token != _searchToken) return;
          final visible = <NovelSummary>[
            for (final book in books)
              if (book.type == 0) book,
          ];
          if (visible.isNotEmpty) {
            groups[source.key] = _OnlineGroup(source: source, books: visible);
          }
        } on Object catch (error) {
          if (failures.length < 3) {
            failures.add('${source.name}：$error');
          }
        } finally {
          if (token == _searchToken) {
            done++;
            final sorted = groups.values.toList()
              ..sort((a, b) => a.source.name.compareTo(b.source.name));
            if (mounted) {
              setState(() {
                _onlineDone = done;
                _onlineFailures = failures.length;
                _onlineGroups
                  ..clear()
                  ..addAll(sorted);
              });
            }
          }
        }
      }
    }

    final workers = selected.length < _onlineConcurrency
        ? selected.length
        : _onlineConcurrency;
    await Future.wait(<Future<void>>[
      for (var i = 0; i < workers; i++) worker(),
    ]);
    if (token != _searchToken || !mounted) return;
    setState(() {
      _onlineSearching = false;
      _onlineDone = selected.length;
      _onlineError = failures.isEmpty ? null : failures.join('\n');
    });
  }

  Future<void> _openBook(_SearchBook item) async {
    await openNovelRoute(
      context,
      widget.openRoute,
      NovelRoute.bookInfo,
      args: <String, Object?>{
        'bookId': item.book.id,
        'title': item.book.title,
        'author': item.book.author,
        'coverUrl': item.book.coverUrl,
        'sourceKey': item.book.sourceKey,
        'bookUrl': item.book.bookUrl,
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

  Widget _buildOnlineSection(ThemeData theme, ColorScheme cs) {
    final truncated = _onlineTotal >= _onlineSourceLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '在线书源 · ${_onlineGroups.length} 个源命中',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (_onlineSearching)
              Text(
                '$_onlineDone/$_onlineTotal',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (_onlineSearching) ...<Widget>[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(MimaoRadii.pill),
            child: LinearProgressIndicator(
              value: _onlineTotal == 0 ? null : _onlineDone / _onlineTotal,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (_onlineGroups.isNotEmpty)
          for (final group in _onlineGroups) ...<Widget>[
            _ResultSection(
              title: group.source.name,
              count: group.books.length,
              child: Column(
                children: <Widget>[
                  for (final book in group.books)
                    _SearchBookRow(
                      item: _SearchBook(book: book),
                      onTap: () => _openBook(_SearchBook(book: book)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ]
        else if (!_onlineSearching && _onlineTotal > 0)
          NovelEmptyState(
            icon: Icons.travel_explore,
            title: '在线书源没有结果',
            message:
                '已搜 $_onlineTotal 个源，${_onlineFailures > 0 ? '$_onlineFailures 个失败或超时。' : ''}'
                '换一个关键词，或到「发现」里按源查看。',
          ),
        if (_onlineError != null && _onlineGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _onlineError!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '每次最多并发搜索前 $_onlineSourceLimit 个启用书源（按权重）。'
              '其余书源可在「发现」里单独搜索。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
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
            const SizedBox(height: 14),
            _BoundaryBanner(online: widget.onlineEngine != null),
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
                            onTap: () => _openBook(item),
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
                if (widget.onlineEngine != null) ...<Widget>[
                  const SizedBox(height: 24),
                  _buildOnlineSection(theme, cs),
                ],
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

class _OnlineGroup {
  const _OnlineGroup({required this.source, required this.books});

  final NovelBookSource source;
  final List<NovelSummary> books;
}

class _SearchBook {
  const _SearchBook({required this.book, this.history, this.collected = false});

  final NovelSummary book;
  final NovelHistoryItem? history;
  final bool collected;
}

class _BoundaryBanner extends StatelessWidget {
  const _BoundaryBanner({required this.online});

  final bool online;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online
                  ? '同时搜索本地书架与已启用书源；在线结果按书源分组，'
                        '最多并发搜前 $_onlineSourceLimit 个源（按权重）。'
                  : '当前只搜本地书架、阅读记录与已导入书源。'
                        '在线书源引擎未注入。',
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
