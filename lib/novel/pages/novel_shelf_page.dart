// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「书架」：在读 / 未读 / 已读 / 全部筛选、网格或列表、本地搜索、
/// 分组、选择模式（批量分组/移除）、书单导入导出、单本右键菜单。
///
/// 数据是收藏表与阅读历史的并集（收藏优先、历史补全）；分组只存在收藏行上，
/// 把一本"仅读过"的书加入分组时会先补一条收藏。删除走确认对话框，并明确
/// 说明会同时清除阅读记录。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/booklist_io.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

/// 书架筛选页签。
enum NovelShelfFilter { reading, unread, finished, all }

extension on NovelShelfFilter {
  String get label => switch (this) {
    NovelShelfFilter.reading => '在读',
    NovelShelfFilter.unread => '未读',
    NovelShelfFilter.finished => '已读',
    NovelShelfFilter.all => '全部',
  };
}

enum _ShelfSort { recent, collected, title }

extension on _ShelfSort {
  String get key => name;
}

class NovelShelfPage extends StatefulWidget {
  const NovelShelfPage({
    super.key,
    required this.active,
    this.collect,
    this.history,
    this.prefs,
    this.booklistGate,
    this.openRoute,
    this.onSelectTab,
  });

  final bool active;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelPrefsApi? prefs;
  final NovelBooklistFileGate? booklistGate;
  final NovelRouteOpener? openRoute;
  final ValueChanged<int>? onSelectTab;

  @override
  State<NovelShelfPage> createState() => _NovelShelfPageState();
}

class _NovelShelfPageState extends State<NovelShelfPage> {
  late Future<_ShelfData> _future;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  NovelShelfFilter _filter = NovelShelfFilter.reading;
  String? _group;
  _ShelfSort _sort = _ShelfSort.recent;
  bool _grid = true;
  int _columns = 0; // 0 = 自动
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _future = _load();
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NovelShelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = !oldWidget.active && widget.active;
    final servicesChanged =
        oldWidget.collect != widget.collect ||
        oldWidget.history != widget.history ||
        oldWidget.prefs != widget.prefs;
    if (becameActive || servicesChanged) _reload();
  }

  void _onSearchChanged() => setState(() {});

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_ShelfData> _load() async {
    final errors = <String>[];

    var collects = const <NovelCollectItem>[];
    final collect = widget.collect;
    if (collect != null) {
      try {
        collects = await collect.list();
      } on Object catch (error) {
        errors.add('收藏读取失败：$error');
      }
    }

    var recent = const <NovelHistoryItem>[];
    final history = widget.history;
    if (history != null) {
      try {
        recent = await history.recent(limit: 300);
      } on Object catch (error) {
        errors.add('阅读记录读取失败：$error');
      }
    }

    // 布局/排序偏好：读失败用默认值，不让偏好把整页拖进错误态。
    var grid = true;
    var columns = 0;
    var sort = _ShelfSort.recent;
    final prefs = widget.prefs;
    if (prefs != null) {
      try {
        grid = (await prefs.read(novelPrefShelfLayout) ?? 'grid') != 'list';
        columns =
            int.tryParse(await prefs.read(novelPrefShelfColumns) ?? '') ?? 0;
        final rawSort = await prefs.read(novelPrefShelfSort);
        sort = _ShelfSort.values.firstWhere(
          (value) => value.key == rawSort,
          orElse: () => _ShelfSort.recent,
        );
      } on Object catch (error) {
        errors.add('书架偏好读取失败：$error');
      }
    }
    if (mounted) {
      _grid = grid;
      _columns = columns.clamp(0, 8).toInt();
      _sort = sort;
    }

    final books = _mergeBooks(collects: collects, recent: recent);
    final groups = <String>{};
    for (final item in collects) {
      final name = item.groupName;
      if (name != null && name.isNotEmpty) groups.add(name);
    }
    final sortedGroups = groups.toList()..sort();

    return _ShelfData(
      books: books,
      groups: sortedGroups,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  List<_ShelfBook> _mergeBooks({
    required List<NovelCollectItem> collects,
    required List<NovelHistoryItem> recent,
  }) {
    final historyById = <String, NovelHistoryItem>{
      for (final item in recent) item.book.id: item,
    };
    final seen = <String>{};
    final books = <_ShelfBook>[];
    for (final item in collects) {
      seen.add(item.ref.id);
      final historyItem = historyById[item.ref.id];
      books.add(
        _ShelfBook(
          book:
              item.book ??
              historyItem?.book ??
              NovelSummary(
                id: item.ref.id,
                title: item.title,
                coverUrl: item.coverUrl ?? '',
                sourceName: item.ref.sourceName,
              ),
          collect: item,
          history: historyItem,
        ),
      );
    }
    for (final item in recent) {
      if (seen.contains(item.book.id)) continue;
      seen.add(item.book.id);
      books.add(_ShelfBook(book: item.book, history: item));
    }
    return books;
  }

  Future<void> _openRoute(
    NovelRoute route, {
    Map<String, Object?> args = const <String, Object?>{},
  }) async {
    await openNovelRoute(context, widget.openRoute, route, args: args);
    if (mounted) _reload();
  }

  Future<void> _openDetail(_ShelfBook item) async {
    await _openRoute(
      NovelRoute.bookInfo,
      args: <String, Object?>{'bookId': item.book.id, 'title': item.book.title},
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectAll(List<_ShelfBook> books) {
    setState(() {
      if (_selected.length == books.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(books.map((book) => book.book.id));
      }
    });
  }

  Future<void> _setLayout({bool? grid, int? columns}) async {
    setState(() {
      if (grid != null) _grid = grid;
      if (columns != null) _columns = columns;
    });
    final prefs = widget.prefs;
    if (prefs == null) return;
    try {
      if (grid != null) {
        await prefs.write(novelPrefShelfLayout, grid ? 'grid' : 'list');
      }
      if (columns != null) {
        await prefs.write(novelPrefShelfColumns, columns.toString());
      }
    } on Object catch (error) {
      _toast('保存布局失败：$error');
    }
  }

  Future<void> _setSort(_ShelfSort sort) async {
    setState(() {
      _sort = sort;
    });
    try {
      await widget.prefs?.write(novelPrefShelfSort, sort.key);
    } on Object catch (error) {
      _toast('保存排序失败：$error');
    }
  }

  Future<void> _showLayoutDialog() async {
    var grid = _grid;
    var columns = _columns;
    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('布局设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('展示方式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.grid_view_outlined),
                    label: Text('网格'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.view_list_outlined),
                    label: Text('列表'),
                  ),
                ],
                selected: <bool>{grid},
                onSelectionChanged: (value) =>
                    setDialogState(() => grid = value.first),
              ),
              const SizedBox(height: 18),
              Text('每行数量', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final option in <int>[0, 3, 4, 5, 6])
                    ChoiceChip(
                      label: Text(option == 0 ? '自动' : '$option 列'),
                      selected: columns == option,
                      onSelected: (_) => setDialogState(() => columns = option),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '每行数量只影响网格；列表模式固定单列。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((grid, columns)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _setLayout(grid: result.$1, columns: result.$2);
  }

  Future<void> _showGroupManage(List<String> groups) async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架未接线，暂时不能管理分组。');
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _GroupManageDialog(collect: collect, groups: groups),
    );
    if (changed == true) _reload();
  }

  Future<void> _assignGroup(List<_ShelfBook> books) async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架未接线，暂时不能设置分组。');
      return;
    }
    if (_selected.isEmpty) return;
    final selectedBooks = books
        .where((book) => _selected.contains(book.book.id))
        .toList();
    final groups = <String>{
      for (final item in books)
        if (item.collect?.groupName != null &&
            item.collect!.groupName!.isNotEmpty)
          item.collect!.groupName!,
    }.toList()..sort();
    final choice = await showDialog<_GroupChoice>(
      context: context,
      builder: (_) => _GroupChoiceDialog(groups: groups),
    );
    if (choice == null) return;
    try {
      for (final item in selectedBooks) {
        // 仅读过、未收藏的书：先补收藏再落分组（分组只存在收藏行上）。
        if (item.collect == null) {
          await collect.collect(item.book);
        }
        await collect.setGroup(item.book.id, choice.name);
      }
    } on Object catch (error) {
      _toast('设置分组失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _reload();
    _toast(choice.name == null ? '已移出分组' : '已加入「${choice.name}」');
  }

  Future<void> _removeSelected(List<_ShelfBook> books) async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('从书架移除 $count 本？'),
        content: const Text(
          '会同时删除这些书的收藏与阅读记录（含阅读进度）。'
          '书源里的原书不受影响，重新打开会重新生成记录。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final selectedBooks = books
        .where((book) => _selected.contains(book.book.id))
        .toList();
    final errors = <String>[];
    for (final item in selectedBooks) {
      try {
        await widget.collect?.remove(item.book.id);
        await widget.history?.remove(item.book.id);
      } on Object catch (error) {
        errors.add('${item.book.title}：$error');
      }
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _reload();
    _toast(errors.isEmpty ? '已移除 $count 本' : '部分移除失败：${errors.join('；')}');
  }

  Future<void> _removeOne(_ShelfBook item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除《${item.book.title}》？'),
        content: const Text('收藏与阅读记录会一起删除，此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.collect?.remove(item.book.id);
      await widget.history?.remove(item.book.id);
    } on Object catch (error) {
      _toast('移除失败：$error');
      return;
    }
    _reload();
  }

  Future<void> _exportBooklist() async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架未接线，暂时不能导出。');
      return;
    }
    try {
      final items = await collect.list();
      if (items.isEmpty) {
        _toast('书架是空的，没有可导出的书。');
        return;
      }
      final books = <NovelBooklistBook>[];
      for (final item in items) {
        final latest = await widget.history?.latest(item.ref.id);
        books.add(
          NovelBooklistBook.fromCollect(
            item,
            chapterIndex: latest?.chapterIndex ?? 0,
            chapterCount: latest?.chapterCount ?? 0,
          ),
        );
      }
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final gate = widget.booklistGate ?? const FilePickerBooklistFileGate();
      final path = await gate.save(
        'mimao-书单-$stamp.json',
        Uint8List.fromList(utf8.encode(encodeNovelBooklist(books))),
      );
      if (path != null) _toast('已导出 ${books.length} 本');
    } on Object catch (error) {
      _toast('导出失败：$error');
    }
  }

  Future<void> _importBooklist() async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架未接线，暂时不能导入书单。');
      return;
    }
    try {
      final gate = widget.booklistGate ?? const FilePickerBooklistFileGate();
      final file = await gate.pick();
      if (file == null) return;
      final text = utf8.decode(file.bytes, allowMalformed: true);
      final books = decodeNovelBooklist(text);
      var imported = 0;
      for (final item in books) {
        final book = item.toSummary();
        await collect.collect(book);
        if (item.groupName != null && item.groupName!.isNotEmpty) {
          await collect.setGroup(item.id, item.groupName);
        }
        if (item.hasProgress) {
          await widget.history?.saveProgress(
            book,
            item.chapterIndex,
            item.chapterCount,
          );
        }
        imported++;
      }
      _reload();
      _toast('已导入 $imported 本');
    } on FormatException catch (error) {
      _toast('书单格式不对：${error.message}');
    } on Object catch (error) {
      _toast('导入失败：$error');
    }
  }

  void _onMenuSelected(String action, List<_ShelfBook> books) {
    switch (action) {
      case 'select':
        setState(() {
          _selecting = true;
          _selected.clear();
        });
      case 'layout':
        _showLayoutDialog();
      case 'groups':
        _showGroupManage(_currentGroups(books));
      case 'sort-recent':
        _setSort(_ShelfSort.recent);
      case 'sort-collected':
        _setSort(_ShelfSort.collected);
      case 'sort-title':
        _setSort(_ShelfSort.title);
      case 'import':
        _importBooklist();
      case 'export':
        _exportBooklist();
    }
  }

  List<String> _currentGroups(List<_ShelfBook> books) {
    final set = <String>{};
    for (final item in books) {
      final name = item.collect?.groupName;
      if (name != null && name.isNotEmpty) set.add(name);
    }
    return set.toList()..sort();
  }

  void _showBookMenu(_ShelfBook item, Offset position, List<_ShelfBook> books) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'open', child: const Text('查看详情')),
        PopupMenuItem<String>(value: 'group', child: const Text('设置分组')),
        PopupMenuItem<String>(value: 'remove', child: const Text('从书架移除')),
      ],
    ).then((value) async {
      if (!mounted) return;
      if (value == 'open') {
        await _openDetail(item);
        return;
      }
      if (value == 'group') {
        setState(() {
          _selecting = true;
          _selected
            ..clear()
            ..add(item.book.id);
        });
        if (mounted) await _assignGroup(books);
        return;
      }
      if (value == 'remove') {
        await _removeOne(item);
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  List<_ShelfBook> _visibleBooks(_ShelfData data) {
    final query = _search.text.trim().toLowerCase();
    final filtered = <_ShelfBook>[];
    for (final item in data.books) {
      if (_group != null && item.collect?.groupName != _group) continue;
      if (!_matchesFilter(item, _filter)) continue;
      if (query.isNotEmpty) {
        final haystack =
            '${item.book.title} ${item.book.author} ${item.book.id}'
                .toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      filtered.add(item);
    }
    filtered.sort(switch (_sort) {
      _ShelfSort.title => (a, b) => a.book.title.compareTo(b.book.title),
      _ShelfSort.collected => (a, b) => _timeOf(b).compareTo(_timeOf(a)),
      _ShelfSort.recent => (a, b) => _recentOf(b).compareTo(_recentOf(a)),
    });
    return filtered;
  }

  DateTime _timeOf(_ShelfBook book) =>
      book.collect?.collectedAt ??
      book.history?.openedAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _recentOf(_ShelfBook book) =>
      book.history?.openedAt ?? _timeOf(book);

  bool _matchesFilter(_ShelfBook item, NovelShelfFilter filter) {
    final percent = item.percent;
    final hasProgress = (item.history?.chapterIndex ?? 0) > 0;
    final finished = percent != null && percent >= 100;
    return switch (filter) {
      NovelShelfFilter.reading => hasProgress && !finished,
      NovelShelfFilter.unread => !hasProgress,
      NovelShelfFilter.finished => finished,
      NovelShelfFilter.all => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShelfData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NovelLoadingState(label: '正在读取书架…');
        }
        if (snapshot.hasError) {
          return NovelErrorState(
            message: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        final data = snapshot.data ?? _ShelfData.empty;
        final books = _visibleBooks(data);
        return NovelFillContent(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NovelPageHeader(
                title: '书架',
                subtitle: data.subtitle,
                actions: <Widget>[
                  NovelCircleAction(
                    key: const Key('novel-shelf-search'),
                    icon: Icons.search,
                    tooltip: '搜索书架',
                    onPressed: _searchFocus.requestFocus,
                  ),
                  if (_selecting)
                    TextButton(
                      onPressed: () => setState(() {
                        _selecting = false;
                        _selected.clear();
                      }),
                      child: const Text('退出选择'),
                    )
                  else
                    _ShelfMenuButton(
                      sorting: _sort,
                      hasData: data.books.isNotEmpty,
                      canWrite: widget.collect != null,
                      onSelected: (action) =>
                          _onMenuSelected(action, data.books),
                    ),
                ],
                bottom: _buildFilterBar(data, books),
              ),
              if (_selecting)
                _SelectionBar(
                  count: _selected.length,
                  allSelected:
                      books.isNotEmpty && _selected.length == books.length,
                  onSelectAll: () => _selectAll(books),
                  onGroup: () => _assignGroup(data.books),
                  onRemove: () => _removeSelected(data.books),
                ),
              if (data.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    data.error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: data.books.isEmpty
                    ? _ShelfEmpty(
                        onOpenDiscover: () => widget.onSelectTab?.call(2),
                        onImport: _importBooklist,
                        canWrite: widget.collect != null,
                      )
                    : books.isEmpty
                    ? _FilterEmpty(
                        filter: _filter,
                        onShowAll: () => setState(() {
                          _filter = NovelShelfFilter.all;
                          _group = null;
                        }),
                      )
                    : _buildGrid(books),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(_ShelfData data, List<_ShelfBook> visible) {
    final counts = <NovelShelfFilter, int>{
      for (final filter in NovelShelfFilter.values)
        filter: data.books
            .where(
              (item) => (queryMatches(item) && _matchesFilter(item, filter)),
            )
            .length,
    };
    final chips = <Widget>[
      for (final filter in NovelShelfFilter.values)
        NovelFilterChip(
          label: filter.label,
          count: counts[filter],
          selected: _filter == filter,
          onTap: () => setState(() => _filter = filter),
        ),
      if (data.groups.isNotEmpty)
        PopupMenuButton<String>(
          tooltip: '按分组筛选',
          onSelected: (value) => setState(() {
            _group = value.isEmpty ? null : value;
          }),
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            CheckedPopupMenuItem<String>(
              value: '',
              checked: _group == null,
              child: const Text('全部分组'),
            ),
            for (final group in data.groups)
              CheckedPopupMenuItem<String>(
                value: group,
                checked: _group == group,
                child: Text(group),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _group == null
                  ? Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withValues(alpha: .6)
                  : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(MimaoRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  _group ?? '分组',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      if (visible.isEmpty)
        Text(
          '没有匹配的书',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ];
    final searchField = TextField(
      controller: _search,
      focusNode: _searchFocus,
      decoration: InputDecoration(
        hintText: '搜索书名 / 作者',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空搜索',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _search.clear,
              ),
      ),
      textInputAction: TextInputAction.search,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final chip in chips) ...<Widget>[
                      chip,
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              searchField,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
            const SizedBox(width: 16),
            SizedBox(width: 300, child: searchField),
          ],
        );
      },
    );
  }

  bool queryMatches(_ShelfBook item) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${item.book.title} ${item.book.author} ${item.book.id}'
        .toLowerCase()
        .contains(query);
  }

  Widget _buildGrid(List<_ShelfBook> books) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!_grid) {
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = books[index];
              return _ShelfListRow(
                item: item,
                selecting: _selecting,
                selected: _selected.contains(item.book.id),
                onTap: () {
                  if (_selecting) {
                    _toggleSelection(item.book.id);
                  } else {
                    _openDetail(item);
                  }
                },
                onSecondaryTap: (position) =>
                    _showBookMenu(item, position, books),
              );
            },
          );
        }

        final auto = (width / 142).floor().clamp(3, 8).toInt();
        final columns = _columns == 0 ? auto : _columns.clamp(3, 8).toInt();
        const spacing = 16.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        final extent = itemWidth * 1.5 + 70;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 20,
            mainAxisExtent: extent,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final item = books[index];
            return _ShelfCard(
              item: item,
              selecting: _selecting,
              selected: _selected.contains(item.book.id),
              onTap: () {
                if (_selecting) {
                  _toggleSelection(item.book.id);
                } else {
                  _openDetail(item);
                }
              },
              onSecondaryTap: (position) =>
                  _showBookMenu(item, position, books),
            );
          },
        );
      },
    );
  }
}

/// 书架聚合快照。
class _ShelfData {
  const _ShelfData({required this.books, required this.groups, this.error});

  static const _ShelfData empty = _ShelfData(
    books: <_ShelfBook>[],
    groups: <String>[],
  );

  final List<_ShelfBook> books;
  final List<String> groups;
  final String? error;

  String get subtitle {
    if (books.isEmpty) return '收藏与阅读过的书都会出现在这里';
    final reading = books.where((book) {
      final percent = book.percent;
      final hasProgress = (book.history?.chapterIndex ?? 0) > 0;
      return hasProgress && (percent == null || percent < 100);
    }).length;
    return '${books.length} 本 · 在读 $reading 本';
  }
}

/// 书架里的一本书（收藏行优先，历史行补全进度）。
class _ShelfBook {
  const _ShelfBook({required this.book, this.collect, this.history});

  final NovelSummary book;
  final NovelCollectItem? collect;
  final NovelHistoryItem? history;

  bool get collected => collect != null;

  int? get percent => novelBookPercent(
    chapterIndex: history?.chapterIndex ?? 0,
    chapterCount: history?.chapterCount ?? 0,
  );

  String get progressText => history == null
      ? '未读'
      : novelProgressText(
          chapterIndex: history!.chapterIndex,
          chapterCount: history!.chapterCount,
        );

  String get authorText => book.author.isEmpty ? '作者未知' : book.author;

  String get subtitle => history != null ? progressText : authorText;
}

class _ShelfMenuButton extends StatelessWidget {
  const _ShelfMenuButton({
    required this.sorting,
    required this.hasData,
    required this.canWrite,
    required this.onSelected,
  });

  final _ShelfSort sorting;
  final bool hasData;
  final bool canWrite;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: '书架操作',
      icon: const Icon(Icons.more_vert),
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '排序',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        CheckedPopupMenuItem<String>(
          value: 'sort-recent',
          checked: sorting == _ShelfSort.recent,
          child: const Text('最近阅读'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'sort-collected',
          checked: sorting == _ShelfSort.collected,
          child: const Text('收藏时间'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'sort-title',
          checked: sorting == _ShelfSort.title,
          child: const Text('书名'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(value: 'layout', child: const Text('布局设置')),
        PopupMenuItem<String>(
          value: 'groups',
          enabled: canWrite,
          child: const Text('分组管理'),
        ),
        PopupMenuItem<String>(
          value: 'select',
          enabled: hasData,
          child: const Text('选择模式'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'import',
          enabled: canWrite,
          child: const Text('导入书单'),
        ),
        PopupMenuItem<String>(
          value: 'export',
          enabled: canWrite && hasData,
          child: const Text('导出书单'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(enabled: false, child: Text('添加本地（需阅读器）')),
        const PopupMenuItem<String>(enabled: false, child: Text('更新目录（需书源引擎）')),
        const PopupMenuItem<String>(enabled: false, child: Text('添加网址（需书源引擎）')),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.onSelectAll,
    required this.onGroup,
    required this.onRemove,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onGroup;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '已选 $count 本',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onSelectAll,
            child: Text(allSelected ? '取消全选' : '全选当前'),
          ),
          const Spacer(),
          TextButton(
            onPressed: count == 0 ? null : onGroup,
            child: const Text('加入分组'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            onPressed: count == 0 ? null : onRemove,
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final _ShelfBook item;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final badge = (item.history?.chapterCount ?? 0) > 0
        ? '${item.history!.chapterCount}'
        : item.percent == null
        ? null
        : '${item.percent}%';
    return Semantics(
      button: true,
      selected: selecting ? selected : null,
      label: '${item.book.title}，${item.progressText}',
      child: GestureDetector(
        onSecondaryTapDown: (details) => onSecondaryTap(details.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MimaoRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: NovelBookCover(
                          url: item.book.coverUrl,
                          title: item.book.title,
                        ),
                      ),
                      if (badge != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: NovelCoverBadge(text: badge),
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
                            child: Icon(
                              Icons.bookmark,
                              size: 14,
                              color: cs.primary,
                            ),
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
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: selected
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.book.title,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfListRow extends StatelessWidget {
  const _ShelfListRow({
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final _ShelfBook item;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      onSecondaryTapDown: (details) => onSecondaryTap(details.globalPosition),
      child: Material(
        color: selected && selecting
            ? cs.secondaryContainer
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(MimaoRadii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 56,
                  height: 80,
                  child: NovelBookCover(
                    url: item.book.coverUrl,
                    title: item.book.title,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        item.book.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    ],
                  ),
                ),
                if (selecting)
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

class _ShelfEmpty extends StatelessWidget {
  const _ShelfEmpty({
    required this.onOpenDiscover,
    required this.onImport,
    required this.canWrite,
  });

  final VoidCallback onOpenDiscover;
  final VoidCallback onImport;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    return NovelEmptyState(
      icon: Icons.collections_bookmark_outlined,
      title: '书架还是空的',
      message:
          '收藏书籍或开始阅读后会排在这里。当前书源引擎尚未接入，'
          '可以先在「订阅」导入书源，或从别处导出一份 mimao 书单再导入。',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: <Widget>[
          FilledButton.tonalIcon(
            onPressed: onOpenDiscover,
            icon: const Icon(Icons.explore_outlined),
            label: const Text('去发现'),
          ),
          OutlinedButton.icon(
            onPressed: canWrite ? onImport : null,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导入书单'),
          ),
        ],
      ),
    );
  }
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty({required this.filter, required this.onShowAll});

  final NovelShelfFilter filter;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return NovelEmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: '「${filter.label}」里没有书',
      message: '切到「全部」能看到书架里的所有书；也可以清掉搜索词或分组筛选。',
      action: FilledButton.tonal(
        onPressed: onShowAll,
        child: const Text('查看全部'),
      ),
    );
  }
}

/// 分组管理：重命名/删除已有分组（空分组不存在，分组由收藏行派生）。
class _GroupManageDialog extends StatefulWidget {
  const _GroupManageDialog({required this.collect, required this.groups});

  final NovelCollectApi collect;
  final List<String> groups;

  @override
  State<_GroupManageDialog> createState() => _GroupManageDialogState();
}

class _GroupManageDialogState extends State<_GroupManageDialog> {
  late List<String> _groups = List<String>.of(widget.groups);
  bool _changed = false;

  Future<void> _rename(String from) async {
    final controller = TextEditingController(text: from);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '分组名'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == from) return;
    try {
      await widget.collect.renameGroup(from, name);
      if (!mounted) return;
      setState(() {
        _groups = <String>[
          for (final group in _groups) group == from ? name : group,
        ]..sort();
        _changed = true;
      });
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重命名失败：$error')));
      }
    }
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除分组「$name」？'),
        content: const Text('组里的书不会被删除，只会回到未分组。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.collect.deleteGroup(name);
      if (!mounted) return;
      setState(() {
        _groups = _groups.where((group) => group != name).toList();
        _changed = true;
      });
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('分组管理'),
      content: SizedBox(
        width: 420,
        child: _groups.isEmpty
            ? Text(
                '还没有分组。进入选择模式，把书「加入分组」时可以直接输入新分组名。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final group in _groups)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(group),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: '重命名',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _rename(group),
                          ),
                          IconButton(
                            tooltip: '删除分组',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(group),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(_changed),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _GroupChoice {
  const _GroupChoice(this.name);

  final String? name;
}

/// 加入分组：选已有分组、输入新分组名，或移出分组。
class _GroupChoiceDialog extends StatefulWidget {
  const _GroupChoiceDialog({required this.groups});

  final List<String> groups;

  @override
  State<_GroupChoiceDialog> createState() => _GroupChoiceDialogState();
}

class _GroupChoiceDialogState extends State<_GroupChoiceDialog> {
  final TextEditingController _controller = TextEditingController();

  /// 空串 = 移出分组（用空串而不是 null，Radio 的 null 会被当成"未选择"）。
  String _selected = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('加入分组'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.groups.isNotEmpty)
              Column(
                children: <Widget>[
                  for (final group in widget.groups)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: group,
                      groupValue: _selected,
                      title: Text(group),
                      onChanged: (value) => setState(() {
                        _selected = value ?? '';
                        _controller.clear();
                      }),
                    ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: '',
                    groupValue: _selected,
                    title: const Text('移出分组'),
                    onChanged: (value) => setState(() {
                      _selected = value ?? '';
                      _controller.clear();
                    }),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '或新建分组',
                hintText: '输入新分组名',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '分组只存在于书架收藏上；仅读过的书加入分组时会自动补一条收藏。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final typed = _controller.text.trim();
            if (typed.isNotEmpty) {
              Navigator.of(context).pop(_GroupChoice(typed));
              return;
            }
            Navigator.of(
              context,
            ).pop(_GroupChoice(_selected.isEmpty ? null : _selected));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
