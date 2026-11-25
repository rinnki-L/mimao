// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「书架」：在读 / 未读 / 已读 / 全部筛选、五种布局（网格/列表/瀑布/
/// 文件夹分组/平板双列）、本地搜索、分组与系列、选择模式（批量分组/移除）、
/// 拖拽手动排序、书籍信息（备注/自定义封面/系列）、书单导入导出。
///
/// 数据是收藏表与阅读历史的并集（收藏优先、历史补全）；分组/系列/备注/封面
/// 都只存在收藏行上，把一本"仅读过"的书加分组时会先补一条收藏。
///
/// 单书卡片在 `shelf/shelf_cards.dart`，布局设置与书籍信息面板各在
/// `shelf/shelf_layout_dialog.dart`、`shelf/book_meta_sheet.dart`——本文件
/// 只留数据、筛选、布局骨架与交互（原 1700 行继续膨胀就看不清了）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/navigation.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/booklist_io.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/pages/shelf/book_meta_sheet.dart';
import 'package:mimao/novel/pages/shelf/shelf_cards.dart';
import 'package:mimao/novel/pages/shelf/shelf_layout_dialog.dart';
import 'package:mimao/novel/shelf/novel_cover_picker.dart';
import 'package:mimao/novel/shelf/shelf_view_config.dart';

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

enum _ShelfSort { recent, collected, title, manual }

extension on _ShelfSort {
  String get key => name;

  String get label => switch (this) {
    _ShelfSort.recent => '最近阅读',
    _ShelfSort.collected => '收藏时间',
    _ShelfSort.title => '书名',
    _ShelfSort.manual => '手动排序',
  };
}

class NovelShelfPage extends StatefulWidget {
  const NovelShelfPage({
    super.key,
    required this.active,
    this.refreshTick = 0,
    this.collect,
    this.history,
    this.prefs,
    this.booklistGate,
    this.openRoute,
    this.onSelectTab,
    this.coverPicker,
    this.localBooks,
  });

  final bool active;
  final int refreshTick;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelPrefsApi? prefs;
  final NovelBooklistFileGate? booklistGate;
  final NovelRouteOpener? openRoute;
  final ValueChanged<int>? onSelectTab;

  /// 自定义封面选择缝；null 时首次使用构造 file_picker 生产实现
  /// （测试注入 fake，绝不真调插件）。
  final NovelCoverPicker? coverPicker;

  /// 本地书门面；null 时「添加本地书」入口给能力边界说明。
  final NovelLocalBookStorage? localBooks;

  @override
  State<NovelShelfPage> createState() => _NovelShelfPageState();
}

class _NovelShelfPageState extends State<NovelShelfPage> with RouteAware {
  late Future<_ShelfData> _future;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  NovelShelfFilter _filter = NovelShelfFilter.reading;
  String? _group;
  _ShelfSort _sort = _ShelfSort.recent;
  NovelShelfViewConfig _view = const NovelShelfViewConfig();
  List<String> _order = const <String>[];
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  /// 文件夹模式下被折叠的分区名（折叠状态只在本次会话有效）。
  final Set<String> _collapsed = <String>{};

  /// 懒构造的封面选择器（不在 build 里碰 file_picker 插件）。
  NovelCoverPicker? _lazyCoverPicker;
  NovelCoverPicker get _coverPicker =>
      widget.coverPicker ??
      (_lazyCoverPicker ??= const FilePickerNovelCoverPicker());

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
    if (_routeSubscribed) mimaoRouteObserver.unsubscribe(this);
    super.dispose();
  }

  PageRoute<dynamic>? _route;
  bool _routeSubscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      if (_routeSubscribed && _route != null) {
        mimaoRouteObserver.unsubscribe(this);
      }
      _route = route;
      mimaoRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    if (widget.active) _reload();
  }

  @override
  void didUpdateWidget(NovelShelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = !oldWidget.active && widget.active;
    final servicesChanged =
        oldWidget.collect != widget.collect ||
        oldWidget.history != widget.history ||
        oldWidget.prefs != widget.prefs;
    if (becameActive ||
        servicesChanged ||
        oldWidget.refreshTick != widget.refreshTick) {
      _reload();
    }
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
    var view = const NovelShelfViewConfig();
    var sort = _ShelfSort.recent;
    var order = const <String>[];
    final prefs = widget.prefs;
    if (prefs != null) {
      try {
        final rawView = await prefs.read(novelPrefShelfView);
        if (rawView == null) {
          // 旧版本只有 shelf_layout（grid/list）与 shelf_columns。
          final legacy = await prefs.read(novelPrefShelfLayout);
          final legacyColumns =
              int.tryParse(await prefs.read(novelPrefShelfColumns) ?? '') ?? 0;
          view = NovelShelfViewConfig(
            mode: NovelShelfModeLabel.fromKey(legacy),
            columns: legacyColumns.clamp(0, 8).toInt(),
          );
        } else {
          view = NovelShelfViewConfig.decode(rawView);
        }
        final rawSort = await prefs.read(novelPrefShelfSort);
        sort = _ShelfSort.values.firstWhere(
          (value) => value.key == rawSort,
          orElse: () => _ShelfSort.recent,
        );
        order = decodeShelfOrder(await prefs.read(novelPrefShelfOrder));
      } on Object catch (error) {
        errors.add('书架偏好读取失败：$error');
      }
    }

    var series = const <NovelSeriesItem>[];
    if (collect != null) {
      try {
        series = await collect.series();
      } on Object catch (error) {
        errors.add('系列读取失败：$error');
      }
    }
    final seriesNames = <int, String>{
      for (final item in series) item.id: item.name,
    };

    if (mounted) {
      _view = view;
      _sort = sort;
      _order = order;
    }

    final books = _mergeBooks(
      collects: collects,
      recent: recent,
      seriesNames: seriesNames,
    );
    final groups = <String>{};
    for (final item in collects) {
      final name = item.groupName;
      if (name != null && name.isNotEmpty) groups.add(name);
    }
    final sortedGroups = groups.toList()..sort();

    return _ShelfData(
      books: books,
      groups: sortedGroups,
      series: series,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  List<ShelfBook> _mergeBooks({
    required List<NovelCollectItem> collects,
    required List<NovelHistoryItem> recent,
    required Map<int, String> seriesNames,
  }) {
    final historyById = <String, NovelHistoryItem>{
      for (final item in recent) item.book.id: item,
    };
    final seen = <String>{};
    final books = <ShelfBook>[];
    for (final item in collects) {
      seen.add(item.ref.id);
      final historyItem = historyById[item.ref.id];
      final seriesId = item.seriesId;
      books.add(
        ShelfBook(
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
          seriesName: seriesId == null ? null : seriesNames[seriesId],
        ),
      );
    }
    for (final item in recent) {
      if (seen.contains(item.book.id)) continue;
      seen.add(item.book.id);
      books.add(ShelfBook(book: item.book, history: item));
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

  Future<void> _openDetail(ShelfBook item) async {
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

  void _selectAll(List<ShelfBook> books) {
    setState(() {
      if (_selected.length == books.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(books.map((book) => book.id));
      }
    });
  }

  Future<void> _saveView(NovelShelfViewConfig view) async {
    setState(() => _view = view);
    final prefs = widget.prefs;
    if (prefs == null) return;
    try {
      await prefs.write(novelPrefShelfView, view.encode());
      // 旧键同步一份，回退到旧版本时至少还认得 grid/list。
      await prefs.write(
        novelPrefShelfLayout,
        view.mode == NovelShelfMode.list ? 'list' : 'grid',
      );
      await prefs.write(novelPrefShelfColumns, view.columns.toString());
    } on Object catch (error) {
      _toast('保存布局失败：$error');
    }
  }

  Future<void> _setSort(_ShelfSort sort) async {
    setState(() => _sort = sort);
    try {
      await widget.prefs?.write(novelPrefShelfSort, sort.key);
    } on Object catch (error) {
      _toast('保存排序失败：$error');
    }
  }

  Future<void> _persistOrder(List<String> order) async {
    setState(() => _order = order);
    try {
      await widget.prefs?.write(novelPrefShelfOrder, encodeShelfOrder(order));
    } on Object catch (error) {
      _toast('保存排序失败：$error');
    }
  }

  Future<void> _showLayoutDialog(_ShelfData data) async {
    final result = await showNovelShelfLayoutDialog(
      context,
      current: _view,
      canGroupBySeries: data.series.isNotEmpty,
    );
    if (result == null) return;
    await _saveView(result);
  }

  Future<void> _showGroupManage(List<String> groups) async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架服务未启用，暂时不能管理分组。重启应用后再试。');
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _GroupManageDialog(collect: collect, groups: groups),
    );
    if (changed == true) _reload();
  }

  Future<void> _showSeriesManage(_ShelfData data) async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架服务未启用，暂时不能管理系列。重启应用后再试。');
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _SeriesManageDialog(collect: collect, series: data.series),
    );
    if (changed == true) _reload();
  }

  Future<void> _assignGroup(List<ShelfBook> books) async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架服务未启用，暂时不能设置分组。重启应用后再试。');
      return;
    }
    if (_selected.isEmpty) return;
    final selectedBooks = books
        .where((book) => _selected.contains(book.id))
        .toList();
    final groups = <String>{
      for (final item in books)
        if (item.groupName != null && item.groupName!.isNotEmpty)
          item.groupName!,
    }.toList()..sort();
    final choice = await showDialog<_GroupChoice>(
      context: context,
      builder: (_) => _GroupChoiceDialog(groups: groups),
    );
    if (choice == null) return;
    try {
      for (final item in selectedBooks) {
        // 仅读过、未收藏的书：先补收藏再落分组（分组只存在收藏行上）。
        if (!item.collected) {
          await collect.collect(item.book);
        }
        await collect.setGroup(item.id, choice.name);
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

  Future<void> _assignSeries(List<ShelfBook> books, _ShelfData data) async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架服务未启用，暂时不能设置系列。重启应用后再试。');
      return;
    }
    if (_selected.isEmpty) return;
    final selectedBooks = books
        .where((book) => _selected.contains(book.id))
        .toList();
    final choice = await showDialog<_SeriesChoice>(
      context: context,
      builder: (_) => _SeriesChoiceDialog(series: data.series),
    );
    if (choice == null) return;
    try {
      int? seriesId = choice.seriesId;
      if (choice.newName != null) {
        seriesId = await collect.createSeries(choice.newName!);
      }
      final ids = <String>[];
      for (final item in selectedBooks) {
        if (!item.collected) await collect.collect(item.book);
        ids.add(item.id);
      }
      await collect.setSeriesFor(ids, seriesId);
    } on Object catch (error) {
      _toast('设置系列失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _reload();
    _toast(choice.newName != null ? '已加入「${choice.newName}」' : '已更新系列');
  }

  Future<void> _editBookMeta(ShelfBook item, _ShelfData data) async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架服务未启用，暂时不能编辑书籍信息。重启应用后再试。');
      return;
    }
    final groups = <String>{
      for (final book in data.books)
        if (book.groupName != null && book.groupName!.isNotEmpty)
          book.groupName!,
    }.toList()..sort();
    final result = await showNovelBookMetaSheet(
      context,
      title: item.title,
      coverUrl: item.coverUrl,
      currentNote: item.note,
      currentGroupName: item.groupName,
      currentSeriesId: item.seriesId,
      currentSeriesName: item.seriesName,
      currentCustomCover: item.customCoverPath,
      groups: groups,
      series: data.series,
      coverPicker: _coverPicker,
      bookId: item.id,
    );
    if (result == null) return;
    final failures = <String>[];
    try {
      if (!item.collected) await collect.collect(item.book);
      if (result.note != item.note) {
        await collect.setNote(item.id, result.note);
      }
      if (result.groupName != item.groupName) {
        await collect.setGroup(item.id, result.groupName);
      }
      if (result.seriesName != null) {
        final id = await collect.createSeries(result.seriesName!);
        await collect.setSeriesFor(<String>[item.id], id);
      } else if (result.seriesId != item.seriesId) {
        await collect.setSeriesFor(<String>[item.id], result.seriesId);
      }
      if (result.clearCover) {
        await collect.setCustomCover(item.id, null);
      } else if (result.customCoverPath != null &&
          result.customCoverPath != item.customCoverPath) {
        await collect.setCustomCover(item.id, result.customCoverPath);
      }
    } on Object catch (error) {
      failures.add('$error');
    }
    _reload();
    _toast(failures.isEmpty ? '已保存书籍信息' : '部分保存失败：${failures.join('；')}');
  }

  Future<void> _removeSelected(List<ShelfBook> books) async {
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
        .where((book) => _selected.contains(book.id))
        .toList();
    final errors = <String>[];
    for (final item in selectedBooks) {
      try {
        await widget.collect?.remove(item.id);
        await widget.history?.remove(item.id);
      } on Object catch (error) {
        errors.add('${item.title}：$error');
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

  Future<void> _removeOne(ShelfBook item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除《${item.title}》？'),
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
      await widget.collect?.remove(item.id);
      await widget.history?.remove(item.id);
    } on Object catch (error) {
      _toast('移除失败：$error');
      return;
    }
    _reload();
  }

  Future<void> _exportBooklist() async {
    final collect = widget.collect;
    if (collect == null) {
      _toast('书架服务未启用，暂时不能导出。重启应用后再试。');
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
      _toast('书架服务未启用，暂时不能导入书单。重启应用后再试。');
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

  Future<void> _importLocalBook() async {
    if (widget.localBooks == null) {
      _toast('本地书服务未启用，暂时不能导入文件。重启应用后再试。');
      return;
    }
    await _openRoute(NovelRoute.importBook);
  }

  void _onMenuSelected(String action, _ShelfData data) {
    switch (action) {
      case 'select':
        setState(() {
          _selecting = true;
          _selected.clear();
        });
      case 'layout':
        _showLayoutDialog(data);
      case 'groups':
        _showGroupManage(_currentGroups(data.books));
      case 'series':
        _showSeriesManage(data);
      case 'sort-recent':
        _setSort(_ShelfSort.recent);
      case 'sort-collected':
        _setSort(_ShelfSort.collected);
      case 'sort-title':
        _setSort(_ShelfSort.title);
      case 'sort-manual':
        _setSort(_ShelfSort.manual);
      case 'import':
        _importBooklist();
      case 'import-local':
        _importLocalBook();
      case 'export':
        _exportBooklist();
    }
  }

  List<String> _currentGroups(List<ShelfBook> books) {
    final set = <String>{};
    for (final item in books) {
      final name = item.groupName;
      if (name != null && name.isNotEmpty) set.add(name);
    }
    return set.toList()..sort();
  }

  void _showBookMenu(ShelfBook item, Offset position, _ShelfData data) {
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
        PopupMenuItem<String>(
          value: 'meta',
          enabled: widget.collect != null,
          child: const Text('书籍信息（备注 / 封面 / 系列）'),
        ),
        PopupMenuItem<String>(value: 'group', child: const Text('设置分组')),
        PopupMenuItem<String>(value: 'remove', child: const Text('从书架移除')),
      ],
    ).then((value) async {
      if (!mounted) return;
      if (value == 'open') {
        await _openDetail(item);
        return;
      }
      if (value == 'meta') {
        await _editBookMeta(item, data);
        return;
      }
      if (value == 'group') {
        setState(() {
          _selecting = true;
          _selected
            ..clear()
            ..add(item.id);
        });
        if (mounted) await _assignGroup(data.books);
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

  List<ShelfBook> _visibleBooks(_ShelfData data) {
    final query = _search.text.trim().toLowerCase();
    final filtered = <ShelfBook>[];
    for (final item in data.books) {
      if (_group != null && item.groupName != _group) continue;
      if (!_matchesFilter(item, _filter)) continue;
      if (query.isNotEmpty) {
        final haystack = '${item.title} ${item.author} ${item.id} ${item.note}'
            .toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      filtered.add(item);
    }
    filtered.sort(switch (_sort) {
      _ShelfSort.title => (a, b) => a.title.compareTo(b.title),
      _ShelfSort.collected => (a, b) => _timeOf(b).compareTo(_timeOf(a)),
      _ShelfSort.recent => (a, b) => _recentOf(b).compareTo(_recentOf(a)),
      // 手动顺序：先按落库顺序，未排过的按最近阅读补在后面。
      _ShelfSort.manual => (a, b) => 0,
    });
    if (_sort == _ShelfSort.manual) {
      final base = <ShelfBook>[...filtered]
        ..sort((a, b) => _recentOf(b).compareTo(_recentOf(a)));
      return applyShelfOrder<ShelfBook>(base, _order, (book) => book.id);
    }
    return filtered;
  }

  DateTime _timeOf(ShelfBook book) =>
      book.collect?.collectedAt ??
      book.history?.openedAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _recentOf(ShelfBook book) => book.history?.openedAt ?? _timeOf(book);

  bool _matchesFilter(ShelfBook item, NovelShelfFilter filter) {
    final percent = item.percent;
    final hasProgress = item.chapterIndex > 0;
    final finished = percent != null && percent >= 100;
    return switch (filter) {
      NovelShelfFilter.reading => hasProgress && !finished,
      NovelShelfFilter.unread => !hasProgress,
      NovelShelfFilter.finished => finished,
      NovelShelfFilter.all => true,
    };
  }

  /// 只有「手动排序」且不在选择模式时允许拖拽，避免和点选冲突。
  bool get _canReorder => _sort == _ShelfSort.manual && !_selecting;

  void _reorderWithin(List<ShelfBook> visible, int from, int to) {
    if (from < 0 || from >= visible.length) return;
    final target = to.clamp(0, visible.length - 1);
    if (target == from) return;
    final ids = <String>[for (final book in visible) book.id];
    final moved = ids.removeAt(from);
    ids.insert(target, moved);
    // 被筛选掉的书记在后面，保持它们原有的相对顺序。
    final visibleIds = ids.toSet();
    final rest = <String>[
      for (final id in _order)
        if (!visibleIds.contains(id)) id,
      for (final book in _allBookIds)
        if (!visibleIds.contains(book)) book,
    ];
    final seen = <String>{};
    final merged = <String>[
      ...ids,
      for (final id in rest)
        if (seen.add(id)) id,
    ];
    _persistOrder(merged);
  }

  /// 当前数据里的全部 bookId（用于把手动顺序补全成完整列表）。
  List<String> get _allBookIds =>
      _lastData?.books.map((book) => book.id).toList() ?? const <String>[];

  _ShelfData? _lastData;

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
        _lastData = data;
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
                      mode: _view.mode,
                      hasData: data.books.isNotEmpty,
                      canWrite: widget.collect != null,
                      canLocal: widget.localBooks != null,
                      hasSeries: data.series.isNotEmpty,
                      onSelected: (action) => _onMenuSelected(action, data),
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
                  onSeries: () => _assignSeries(data.books, data),
                  onRemove: () => _removeSelected(data.books),
                ),
              if (_sort == _ShelfSort.manual && !_selecting && books.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '手动排序：长按封面拖动，松手后顺序会保存。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
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
                        onOpenSubscribe: () => widget.onSelectTab?.call(3),
                        onImport: _importBooklist,
                        onImportLocal: _importLocalBook,
                        canWrite: widget.collect != null,
                        canLocal: widget.localBooks != null,
                      )
                    : books.isEmpty
                    ? _FilterEmpty(
                        filter: _filter,
                        onShowAll: () => setState(() {
                          _filter = NovelShelfFilter.all;
                          _group = null;
                          _search.clear();
                        }),
                      )
                    : _buildContent(books, data),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(_ShelfData data, List<ShelfBook> visible) {
    final counts = <NovelShelfFilter, int>{
      for (final filter in NovelShelfFilter.values)
        filter: data.books
            .where((item) => queryMatches(item) && _matchesFilter(item, filter))
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
        hintText: '搜索书名 / 作者 / 备注',
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

  bool queryMatches(ShelfBook item) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${item.title} ${item.author} ${item.id} ${item.note}'
        .toLowerCase()
        .contains(query);
  }

  // ---------------------------------------------------------------------------
  // 布局分发

  Widget _buildContent(List<ShelfBook> books, _ShelfData data) {
    return switch (_view.mode) {
      NovelShelfMode.list => _buildList(books, data),
      NovelShelfMode.waterfall => _buildWaterfall(books, data),
      NovelShelfMode.folder => _buildFolder(books, data),
      NovelShelfMode.dualColumn => _buildDualColumn(books, data),
      NovelShelfMode.grid => _buildGrid(books, data),
    };
  }

  /// 网格列数：固定值优先，否则按封面宽度自动算。
  int _columnsFor(double width) => _view.columns == 0
      ? autoShelfColumns(width, _view.coverWidth)
      : _view.columns.clamp(1, 10).toInt();

  ShelfCardActions _actionsFor(
    ShelfBook item,
    List<ShelfBook> books,
    _ShelfData data,
  ) => ShelfCardActions(
    onTap: () {
      if (_selecting) {
        _toggleSelection(item.id);
      } else {
        _openDetail(item);
      }
    },
    onSecondaryTap: (position) => _showBookMenu(item, position, data),
  );

  String? _badgeFor(ShelfBook item) => item.chapterCount > 0
      ? '${item.chapterCount}'
      : item.percent == null
      ? null
      : '${item.percent}%';

  /// 包一层拖拽：手动排序模式下长按拖动换位。
  Widget _maybeDraggable({
    required int index,
    required List<ShelfBook> books,
    required Widget child,
  }) {
    if (!_canReorder) return child;
    final item = books[index];
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) =>
          _reorderWithin(books, details.data, index),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 96,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: NovelBookCover(
                      url: item.effectiveCoverUrl,
                      title: item.title,
                      borderRadius: _view.coverRadius,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .35, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_view.coverRadius),
              border: highlighted
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildGrid(List<ShelfBook> books, _ShelfData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = _columnsFor(width);
        const spacing = 16.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        // 封面按 2:3 撑满，文字区基础 84px：两行书名 + 一行进度；开了标签/
        // 简介/更新时间的行各再补一点，避免底部溢出。
        final extra =
            84.0 +
            (_view.showTags ? 24 : 0) +
            (_view.showLatestChapter ? 18 : 0) +
            (_view.showIntro ? 34 : 0) +
            (_view.showUpdateTime ? 18 : 0);
        final extent = itemWidth * 1.5 + extra;
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
            return _maybeDraggable(
              index: index,
              books: books,
              child: ShelfGridCard(
                key: ValueKey<String>(item.id),
                item: item,
                config: _view,
                selecting: _selecting,
                selected: _selected.contains(item.id),
                actions: _actionsFor(item, books, data),
                badge: _badgeFor(item),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildList(List<ShelfBook> books, _ShelfData data) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: books.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = books[index];
        return _maybeDraggable(
          index: index,
          books: books,
          child: ShelfListRow(
            key: ValueKey<String>(item.id),
            item: item,
            config: _view,
            selecting: _selecting,
            selected: _selected.contains(item.id),
            actions: _actionsFor(item, books, data),
            trailing: _canReorder
                ? const Icon(Icons.drag_indicator, size: 20)
                : null,
          ),
        );
      },
    );
  }

  /// 瀑布：按列宽算列数，每列独立滚动，封面高度按下标错落。
  Widget _buildWaterfall(List<ShelfBook> books, _ShelfData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = _columnsFor(width);
        const spacing = 16.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        final buckets = List<List<(int, ShelfBook)>>.generate(
          columns,
          (_) => <(int, ShelfBook)>[],
        );
        // 按预估高度往最矮的列放，视觉上更接近真瀑布。
        final heights = List<double>.filled(columns, 0);
        for (var index = 0; index < books.length; index++) {
          var target = 0;
          for (var column = 1; column < columns; column++) {
            if (heights[column] < heights[target]) target = column;
          }
          final item = books[index];
          // 高度方差 1.2..1.55，按下标确定性抖动，滚动时不跳。
          final variance = 1.2 + ((index * 37) % 8) * 0.05;
          final coverHeight = itemWidth * variance;
          buckets[target].add((index, item));
          heights[target] +=
              coverHeight + 96 + (_view.showTags ? 24 : 0) + spacing;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var column = 0; column < columns; column++) ...<Widget>[
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: buckets[column].length,
                  itemBuilder: (context, position) {
                    final (index, item) = buckets[column][position];
                    final variance = 1.2 + ((index * 37) % 8) * 0.05;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: spacing),
                      child: _maybeDraggable(
                        index: index,
                        books: books,
                        child: ShelfWaterfallCard(
                          key: ValueKey<String>(item.id),
                          item: item,
                          config: _view,
                          selecting: _selecting,
                          selected: _selected.contains(item.id),
                          actions: _actionsFor(item, books, data),
                          coverHeight: itemWidth * variance,
                          badge: _badgeFor(item),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (column != columns - 1) const SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }

  /// 文件夹分组：按书架分组分节；开启「按系列归组」时系列节排在最前。
  Widget _buildFolder(List<ShelfBook> books, _ShelfData data) {
    final seriesNames = <int, String>{
      for (final item in data.series) item.id: item.name,
    };
    final seriesGrouping = _view.groupBySeries && seriesNames.isNotEmpty
        ? groupShelfBySeries<ShelfBook>(
            books: books,
            seriesOf: (book) => book.seriesId,
            seriesNames: seriesNames,
          )
        : const NovelShelfSeriesGrouping<ShelfBook>(
            series: <NovelShelfSection<ShelfBook>>[],
            singles: <ShelfBook>[],
          );
    final folderSource = seriesGrouping.series.isEmpty
        ? books
        : seriesGrouping.singles;
    final folders = groupShelfByFolder<ShelfBook>(
      books: folderSource,
      folderOf: (book) => book.groupName,
    );
    final sections = <NovelShelfSection<ShelfBook>>[
      ...seriesGrouping.series,
      ...folders,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        for (final section in sections) ...<Widget>[
          ShelfSectionHeader(
            title: section.title,
            count: section.books.length,
            icon: section.seriesId != null
                ? Icons.auto_stories_outlined
                : section.folder == null
                ? Icons.folder_off_outlined
                : Icons.folder_outlined,
            collapsed: _collapsed.contains(section.title),
            onToggle: () => setState(() {
              if (!_collapsed.remove(section.title)) {
                _collapsed.add(section.title);
              }
            }),
          ),
          if (!_collapsed.contains(section.title))
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: _ShelfWrapGrid(
                books: section.books,
                columns: _columnsFor(MediaQuery.sizeOf(context).width - 48),
                coverWidth: _view.coverWidth,
                itemBuilder: (index, item) => _maybeDraggable(
                  index: books.indexOf(item),
                  books: books,
                  child: ShelfGridCard(
                    key: ValueKey<String>('${section.title}-${item.id}'),
                    item: item,
                    config: _view,
                    selecting: _selecting,
                    selected: _selected.contains(item.id),
                    actions: _actionsFor(item, books, data),
                    badge: _badgeFor(item),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 平板双列：左右两栏各自滚动，每栏内部仍是网格（列数按半宽算）。
  Widget _buildDualColumn(List<ShelfBook> books, _ShelfData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidth = (constraints.maxWidth - 20) / 2;
        final paneColumns = _columnsFor(paneWidth).clamp(1, 5).toInt();
        final left = <ShelfBook>[];
        final right = <ShelfBook>[];
        for (var index = 0; index < books.length; index++) {
          (index.isEven ? left : right).add(books[index]);
        }
        Widget pane(List<ShelfBook> paneBooks) {
          const spacing = 16.0;
          final itemWidth =
              (paneWidth - spacing * (paneColumns - 1)) / paneColumns;
          final extra =
              84.0 +
              (_view.showTags ? 24 : 0) +
              (_view.showLatestChapter ? 18 : 0) +
              (_view.showIntro ? 34 : 0) +
              (_view.showUpdateTime ? 18 : 0);
          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: paneColumns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: 20,
              mainAxisExtent: itemWidth * 1.5 + extra,
            ),
            itemCount: paneBooks.length,
            itemBuilder: (context, position) {
              final item = paneBooks[position];
              return _maybeDraggable(
                index: books.indexOf(item),
                books: books,
                child: ShelfGridCard(
                  key: ValueKey<String>(item.id),
                  item: item,
                  config: _view,
                  selecting: _selecting,
                  selected: _selected.contains(item.id),
                  actions: _actionsFor(item, books, data),
                  badge: _badgeFor(item),
                ),
              );
            },
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: pane(left)),
            const SizedBox(width: 20),
            Expanded(child: pane(right)),
          ],
        );
      },
    );
  }
}

/// 分区内的轻量网格（Wrap 实现，随内容撑高，配合外层 ListView 滚动）。
class _ShelfWrapGrid extends StatelessWidget {
  const _ShelfWrapGrid({
    required this.books,
    required this.columns,
    required this.coverWidth,
    required this.itemBuilder,
  });

  final List<ShelfBook> books;
  final int columns;
  final double coverWidth;
  final Widget Function(int index, ShelfBook item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final width = constraints.maxWidth;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 20,
          children: <Widget>[
            for (var index = 0; index < books.length; index++)
              SizedBox(
                width: itemWidth,
                child: itemBuilder(index, books[index]),
              ),
          ],
        );
      },
    );
  }
}

/// 书架聚合快照。
class _ShelfData {
  const _ShelfData({
    required this.books,
    required this.groups,
    this.series = const <NovelSeriesItem>[],
    this.error,
  });

  static const _ShelfData empty = _ShelfData(
    books: <ShelfBook>[],
    groups: <String>[],
  );

  final List<ShelfBook> books;
  final List<String> groups;
  final List<NovelSeriesItem> series;
  final String? error;

  String get subtitle {
    if (books.isEmpty) return '收藏与阅读过的书都会出现在这里';
    final reading = books.where((book) {
      final percent = book.percent;
      final hasProgress = book.chapterIndex > 0;
      return hasProgress && (percent == null || percent < 100);
    }).length;
    return '${books.length} 本 · 在读 $reading 本';
  }
}

class _ShelfMenuButton extends StatelessWidget {
  const _ShelfMenuButton({
    required this.sorting,
    required this.mode,
    required this.hasData,
    required this.canWrite,
    required this.canLocal,
    required this.hasSeries,
    required this.onSelected,
  });

  final _ShelfSort sorting;
  final NovelShelfMode mode;
  final bool hasData;
  final bool canWrite;

  /// 本地书服务是否可用（不可用时「添加本地书」置灰，不隐藏——隐藏会让人
  /// 以为这个版本根本没有本地书功能）。
  final bool canLocal;
  final bool hasSeries;
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
        for (final sort in _ShelfSort.values)
          CheckedPopupMenuItem<String>(
            value: 'sort-${sort.key}',
            checked: sorting == sort,
            child: Text(sort.label),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'layout',
          child: Text('布局设置（当前：${mode.label}）'),
        ),
        PopupMenuItem<String>(
          value: 'groups',
          enabled: canWrite,
          child: const Text('分组管理'),
        ),
        PopupMenuItem<String>(
          value: 'series',
          enabled: canWrite && hasSeries,
          child: const Text('系列管理'),
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
          value: 'import-local',
          enabled: canLocal,
          child: const Text('添加本地书'),
        ),
        PopupMenuItem<String>(
          value: 'export',
          enabled: canWrite && hasData,
          child: const Text('导出书单'),
        ),
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
    required this.onSeries,
    required this.onRemove,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onGroup;
  final VoidCallback onSeries;
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
          TextButton(
            onPressed: count == 0 ? null : onSeries,
            child: const Text('加入系列'),
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

class _ShelfEmpty extends StatelessWidget {
  const _ShelfEmpty({
    required this.onOpenDiscover,
    required this.onOpenSubscribe,
    required this.onImport,
    required this.onImportLocal,
    required this.canWrite,
    required this.canLocal,
  });

  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenSubscribe;
  final VoidCallback onImport;
  final VoidCallback onImportLocal;
  final bool canWrite;
  final bool canLocal;

  @override
  Widget build(BuildContext context) {
    return NovelEmptyState(
      icon: Icons.collections_bookmark_outlined,
      title: '书架还是空的',
      message:
          '两条通路都能填书架：导入本地 TXT / EPUB / Markdown 直接开读，'
          '或者导入书源后在「发现」里搜索并收藏。',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: <Widget>[
          FilledButton.tonalIcon(
            onPressed: canLocal ? onImportLocal : null,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('添加本地书'),
          ),
          FilledButton.tonalIcon(
            onPressed: onOpenSubscribe,
            icon: const Icon(Icons.rss_feed),
            label: const Text('导入书源'),
          ),
          OutlinedButton.icon(
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

/// 系列管理：重命名/删除系列（删除只解绑，书都留在书架）。
class _SeriesManageDialog extends StatefulWidget {
  const _SeriesManageDialog({required this.collect, required this.series});

  final NovelCollectApi collect;
  final List<NovelSeriesItem> series;

  @override
  State<_SeriesManageDialog> createState() => _SeriesManageDialogState();
}

class _SeriesManageDialogState extends State<_SeriesManageDialog> {
  late List<NovelSeriesItem> _series = List<NovelSeriesItem>.of(widget.series);
  bool _changed = false;

  Future<void> _rename(NovelSeriesItem item) async {
    final controller = TextEditingController(text: item.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名系列'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '系列名'),
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
    if (name == null || name.isEmpty || name == item.name) return;
    try {
      await widget.collect.renameSeries(item.id, name);
      if (!mounted) return;
      setState(() {
        _series = <NovelSeriesItem>[
          for (final entry in _series)
            entry.id == item.id
                ? NovelSeriesItem(
                    id: entry.id,
                    name: name,
                    createdAt: entry.createdAt,
                  )
                : entry,
        ]..sort((a, b) => a.name.compareTo(b.name));
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

  Future<void> _delete(NovelSeriesItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除系列「${item.name}」？'),
        content: const Text('系列里的书不会被删除，只是不再属于这个系列。'),
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
      await widget.collect.deleteSeries(item.id);
      if (!mounted) return;
      setState(() {
        _series = _series.where((entry) => entry.id != item.id).toList();
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
      title: const Text('系列管理'),
      content: SizedBox(
        width: 420,
        child: _series.isEmpty
            ? Text(
                '还没有系列。在书籍信息里可以给书设置系列，同系列的书能在书架上归组。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final item in _series)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: Text(item.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: '重命名',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _rename(item),
                          ),
                          IconButton(
                            tooltip: '删除系列',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(item),
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

class _SeriesChoice {
  const _SeriesChoice({this.seriesId, this.newName});

  final int? seriesId;
  final String? newName;
}

/// 加入系列：选已有系列、输入新系列名，或移出系列。
class _SeriesChoiceDialog extends StatefulWidget {
  const _SeriesChoiceDialog({required this.series});

  final List<NovelSeriesItem> series;

  @override
  State<_SeriesChoiceDialog> createState() => _SeriesChoiceDialogState();
}

class _SeriesChoiceDialogState extends State<_SeriesChoiceDialog> {
  final TextEditingController _controller = TextEditingController();

  /// -1 = 移出系列（0 是合法自增 id，不能用 0 当哨兵）。
  int _selected = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('加入系列'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.series.isNotEmpty)
              Column(
                children: <Widget>[
                  for (final item in widget.series)
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      value: item.id,
                      groupValue: _selected,
                      title: Text(item.name),
                      onChanged: (value) => setState(() {
                        _selected = value ?? -1;
                        _controller.clear();
                      }),
                    ),
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: -1,
                    groupValue: _selected,
                    title: const Text('移出系列'),
                    onChanged: (value) => setState(() {
                      _selected = value ?? -1;
                      _controller.clear();
                    }),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '或新建系列',
                hintText: '输入新系列名',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '系列与分组正交：分组是"我把它放哪"，系列是"它属于哪个作品集"。',
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
              Navigator.of(context).pop(_SeriesChoice(newName: typed));
              return;
            }
            Navigator.of(
              context,
            ).pop(_SeriesChoice(seriesId: _selected < 0 ? null : _selected));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
