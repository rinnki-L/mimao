// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他三个模块的页面同款说明：保持类型一致、patch 可重放。
/// 小说规则管理页：书源 / 订阅源 / 替换规则三个分类，各自导入、启停、删除。
///
/// 书源分类是社区工具的主界面：搜索框、排序、批量启停、批量移动分组、权重
/// 编辑、分组增删改、单条/全部导入导出（URL / 本地文件 / 剪贴板）、编辑与
/// 调试入口。纯逻辑都在 `source/novel_source_edit.dart`，本页只接 UI。
///
/// 点「订阅源」里的订阅站点卡片会 push 满窗口的 [NovelSourceSitePage] 打开该
/// 站点，站点上的「一键导入」由那边拦截并落库，返回本页后重新读取列表。
///
/// 本页不构造 WebView，页面进场零插件调用——无插件测试环境也能渲染列表与按钮。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';

import '../engine/online_engine.dart';
import '../source/novel_rule_model.dart';
import '../source/novel_source_edit.dart';
import '../source/novel_source_importer.dart';
import '../source/novel_source_model.dart';
import '../source/novel_source_store.dart' show NovelSourceStorage;
import '../source/novel_subscription.dart'
    show
        NovelSourceSubscription,
        NovelSubscriptionStore,
        defaultNovelSubscription;
import 'novel_source_debug_page.dart';
import 'novel_source_detail_page.dart';
import 'novel_source_edit_page.dart';
import 'novel_source_site_page.dart';
import 'novel_rule_import_dialog.dart';
import 'novel_widgets.dart';

/// 书源列表排序。
enum _SourceSort {
  name('名称'),
  weight('权重'),
  group('分组'),
  type('类型');

  const _SourceSort(this.label);

  final String label;
}

/// 打开规则管理页。由 NovelModule 出口接到 Navigator。
class NovelSourceManagePage extends StatefulWidget {
  const NovelSourceManagePage({
    super.key,
    required this.store,
    required this.importer,
    this.subscriptionStore,
    this.siteUrl = novelSourceSiteUrl,
    this.initialTab = NovelRuleKind.bookSource,
    this.webViewBuilder,
    this.onlineEngine,
    this.fileGate,
    this.clipboard,
    this.enableDebug = true,
  });

  final NovelSourceStorage store;
  final NovelSourceImporter importer;

  /// 订阅站点仓库：订阅页里的「喵公子」等条目也属于订阅源。
  /// null 时显示内置默认订阅（与订阅页的回落一致）。
  final NovelSubscriptionStore? subscriptionStore;
  final String siteUrl;

  /// 进场默认选中的分类（书源 / 订阅源 / 替换规则）。
  final NovelRuleKind initialTab;

  /// 测试注入缝：转发给订阅站点页，替换真实 WebView。
  final Widget Function(
    BuildContext context,
    void Function(String link) onImportLink,
  )?
  webViewBuilder;

  /// 在线引擎：调试页要用；null 时不显示调试入口（只保留编辑）。
  final NovelOnlineEngine? onlineEngine;

  /// 本地文件选择/保存缝；null 时走 file_picker。
  final NovelSourceFileGate? fileGate;

  /// 剪贴板读写缝（测试注入，避免碰平台通道）。
  final NovelClipboardGate? clipboard;

  /// 是否显示调试入口（调用方按 `kDebugMode` 传）。
  final bool enableDebug;

  @override
  State<NovelSourceManagePage> createState() => _NovelSourceManagePageState();
}

class _NovelSourceManagePageState extends State<NovelSourceManagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: NovelRuleKind.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  bool _loading = true;
  String? _status;
  String? _error;
  List<NovelBookSource> _sources = const <NovelBookSource>[];
  List<NovelRssSource> _rssSources = const <NovelRssSource>[];
  List<NovelReplaceRule> _replaceRules = const <NovelReplaceRule>[];
  List<NovelSourceSubscription> _subscriptions =
      const <NovelSourceSubscription>[defaultNovelSubscription];

  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  _SourceSort _sort = _SourceSort.name;
  String? _groupFilter;
  final Set<String> _selected = <String>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  NovelSourceFileGate get _fileGate =>
      widget.fileGate ?? const FilePickerNovelSourceFileGate();

  NovelClipboardGate get _clipboard =>
      widget.clipboard ?? const _PlatformClipboardGate();

  Future<void> _reloadAll() async {
    try {
      final sources = await widget.store.loadAll();
      final rssStore = widget.importer.rssStore;
      final replaceStore = widget.importer.replaceStore;
      final rss = rssStore == null
          ? const <NovelRssSource>[]
          : await rssStore.loadAll();
      final rules = replaceStore == null
          ? const <NovelReplaceRule>[]
          : await replaceStore.loadAll();
      final subscriptionStore = widget.subscriptionStore;
      final subscriptions = subscriptionStore == null
          ? const <NovelSourceSubscription>[defaultNovelSubscription]
          : await subscriptionStore.loadAll();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _rssSources = rss;
        _replaceRules = rules;
        _subscriptions = subscriptions;
        _loading = false;
        // 列表变化后清掉已不存在的选中项。
        final keys = sources.map((s) => s.key).toSet();
        _selected.removeWhere((key) => !keys.contains(key));
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取规则失败：$error';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 列表视图（过滤 / 排序）

  List<NovelBookSource> get _visibleSources {
    final needle = _filter.trim().toLowerCase();
    final filtered = <NovelBookSource>[
      for (final source in _sources)
        if ((_groupFilter == null ||
                (_groupFilter == novelUngroupedLabel
                    ? source.groups.isEmpty
                    : source.groups.contains(_groupFilter))) &&
            (needle.isEmpty ||
                '${source.name} ${source.url} ${source.groupLabel} ${source.typeLabel}'
                    .toLowerCase()
                    .contains(needle)))
          source,
    ];
    filtered.sort((a, b) {
      switch (_sort) {
        case _SourceSort.name:
          return a.name.compareTo(b.name);
        case _SourceSort.weight:
          final byWeight = b.weight.compareTo(a.weight);
          return byWeight != 0 ? byWeight : a.name.compareTo(b.name);
        case _SourceSort.group:
          final byGroup = a.groupLabel.compareTo(b.groupLabel);
          return byGroup != 0 ? byGroup : a.name.compareTo(b.name);
        case _SourceSort.type:
          final byType = a.type.compareTo(b.type);
          return byType != 0 ? byType : a.name.compareTo(b.name);
      }
    });
    return filtered;
  }

  List<String> get _allGroups {
    final groups = <String>{};
    var hasUngrouped = false;
    for (final source in _sources) {
      if (source.groups.isEmpty) {
        hasUngrouped = true;
      } else {
        groups.addAll(source.groups);
      }
    }
    final sorted = groups.toList()..sort();
    if (hasUngrouped) sorted.add(novelUngroupedLabel);
    return sorted;
  }

  void _setStatus(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      if (error) {
        _error = message;
        _status = null;
      } else {
        _status = message;
        _error = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 导入

  Future<void> _openImportDialog(NovelRuleKind kind) async {
    final result = await showNovelRuleImportDialog(
      context,
      importer: widget.importer,
      initialKind: kind,
      // 分类内导入锁死类型：书源 tab 就只导书源，不在弹窗里再选一遍。
      allowTypeSwitch: false,
    );
    if (result == null || !mounted) return;
    _setStatus(result.message ?? '已导入 ${result.saved} 条${result.kind.label}');
    await _reloadAll();
  }

  Future<void> _importFromFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.importer.importFromPickedFile(
        kind: NovelRuleKind.bookSource,
      );
      if (result == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      _setStatus(
        '${result.message ?? '已导入'}（来自 ${result.sourceUrl.isEmpty ? '本地文件' : result.sourceUrl}）',
      );
      await _reloadAll();
    } on NovelSourceImportException catch (error) {
      _setStatus(error.message, error: true);
    } on Object catch (error) {
      _setStatus('导入失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromClipboard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final text = await _clipboard.readText();
      if (text == null || text.trim().isEmpty) {
        _setStatus('剪贴板是空的；先复制书源 JSON 或书源文件地址', error: true);
        return;
      }
      final trimmed = text.trim();
      // 剪贴板里也可能是书源文件地址（从浏览器复制链接更常见）。
      final result = isFetchableSourceUrl(trimmed)
          ? await widget.importer.importFromUrl(
              trimmed,
              kind: NovelRuleKind.bookSource,
            )
          : await widget.importer.importFromText(
              trimmed,
              kind: NovelRuleKind.bookSource,
              origin: '剪贴板',
            );
      _setStatus(result.message ?? '已导入 ${result.saved} 个书源');
      await _reloadAll();
    } on NovelSourceImportException catch (error) {
      _setStatus(error.message, error: true);
    } on Object catch (error) {
      _setStatus('导入失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 导出

  Future<void> _exportSources(
    List<NovelBookSource> sources, {
    required bool toFile,
  }) async {
    if (sources.isEmpty) {
      _setStatus('没有可导出的书源', error: true);
      return;
    }
    final text = exportNovelSourcesText(sources);
    if (!toFile) {
      await _clipboard.writeText(text);
      _setStatus('已复制 ${sources.length} 个书源的 JSON 到剪贴板');
      return;
    }
    setState(() => _busy = true);
    try {
      final stamp = DateTime.now();
      final name =
          'mimao-sources-${stamp.year}'
          '${stamp.month.toString().padLeft(2, '0')}'
          '${stamp.day.toString().padLeft(2, '0')}.json';
      final location = await _fileGate.save(name, utf8.encode(text));
      if (location == null) {
        _setStatus('已取消导出');
        return;
      }
      _setStatus('已导出 ${sources.length} 个书源 → $location');
    } on Object catch (error) {
      _setStatus('导出失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showExportMenu(List<NovelBookSource> targets) async {
    final scope = targets.length == 1 ? '这条书源' : '${targets.length} 个书源';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text('导出$scope'),
              subtitle: const Text('Legado 书源 JSON，可直接分享给别人导入'),
            ),
            ListTile(
              key: const Key('novel-source-export-file'),
              leading: const Icon(Icons.save_alt),
              title: const Text('导出为文件'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
            ListTile(
              key: const Key('novel-source-export-clipboard'),
              leading: const Icon(Icons.content_copy),
              title: const Text('复制到剪贴板'),
              onTap: () => Navigator.of(context).pop('clipboard'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _exportSources(targets, toFile: choice == 'file');
  }

  // ---------------------------------------------------------------------------
  // 编辑 / 调试

  Future<void> _openEditor({NovelBookSource? source}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/source-edit'),
        builder: (_) => NovelSourceEditPage(
          store: widget.store,
          initial: source,
          onSaved: (_) => _setStatus('已保存书源，立即生效'),
          onDebug: widget.enableDebug && widget.onlineEngine != null
              ? (saved) => _openDebug(initialSourceKey: saved.key)
              : null,
        ),
      ),
    );
    if (mounted) await _reloadAll();
  }

  Future<void> _openDebug({String? initialSourceKey}) async {
    final engine = widget.onlineEngine;
    if (engine == null) {
      _setStatus('在线引擎未接入，无法调试书源', error: true);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/source-debug'),
        builder: (_) => NovelSourceDebugPage(
          engine: engine,
          store: widget.store,
          initialSourceKey: initialSourceKey,
        ),
      ),
    );
    if (mounted) await _reloadAll();
  }

  // ---------------------------------------------------------------------------
  // 批量操作

  Future<void> _setSelectedEnabled(bool enabled) async {
    if (_selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final updated = <NovelBookSource>[
        for (final source in _sources)
          if (_selected.contains(source.key))
            source.copyWith(enabled: enabled)
          else
            source,
      ];
      await widget.store.saveAll(
        updated.where((s) => _selected.contains(s.key)),
      );
      _setStatus('已${enabled ? '启用' : '停用'} ${_selected.length} 个书源');
      await _reloadAll();
    } on Object catch (error) {
      _setStatus('批量操作失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveSelectedToGroup() async {
    if (_selected.isEmpty) return;
    final group = await _askGroupName(
      title: '移动到分组',
      hint: '留空表示从当前分组移除',
      initial: '',
    );
    if (group == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = moveNovelSourcesToGroup(
        _sources,
        keys: _selected,
        group: group,
        additive: false,
      );
      await widget.store.saveAll(
        updated.where((s) => _selected.contains(s.key)),
      );
      _setStatus(
        group.trim().isEmpty
            ? '已把 ${_selected.length} 个书源移出分组'
            : '已把 ${_selected.length} 个书源移到「${group.trim()}」',
      );
      await _reloadAll();
    } on Object catch (error) {
      _setStatus('移动分组失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除选中的 ${_selected.length} 个书源？'),
        content: const Text('只会删除本机保存的书源文件，不影响网站上的书源。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('novel-source-bulk-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final key in _selected.toList()) {
        await widget.store.delete(key);
      }
      _setStatus('已删除 ${_selected.length} 个书源');
      _selected.clear();
      await _reloadAll();
    } on Object catch (error) {
      _setStatus('删除失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editWeight(NovelBookSource source) async {
    final value = await _askGroupName(
      title: '设置权重',
      hint: '越大越优先（排序与搜索选源都用它）',
      initial: '${source.weight}',
      numeric: true,
    );
    if (value == null || !mounted) return;
    final weight = int.tryParse(value.trim());
    if (weight == null) {
      _setStatus('权重必须是整数', error: true);
      return;
    }
    final updated = setNovelSourceWeight(source, weight);
    await widget.store.saveAll(<NovelBookSource>[updated]);
    _setStatus('「${source.name}」权重已设为 $weight');
    await _reloadAll();
  }

  /// 分组管理：新建 / 重命名 / 删除。
  Future<void> _manageGroups() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('分组管理')),
            ListTile(
              key: const Key('novel-group-create'),
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建分组'),
              subtitle: const Text('选中的书源会移入新分组；没选中则只创建名字'),
              onTap: () => Navigator.of(context).pop('create'),
            ),
            ListTile(
              key: const Key('novel-group-rename'),
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名分组'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              key: const Key('novel-group-delete'),
              leading: const Icon(Icons.folder_delete_outlined),
              title: const Text('删除分组'),
              subtitle: const Text('只摘掉分组名，书源保留'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'create':
        final name = await _askGroupName(title: '新建分组', hint: '分组名');
        if (name == null || name.trim().isEmpty || !mounted) return;
        if (_selected.isEmpty) {
          _setStatus('分组「${name.trim()}」已创建（选中的书源会移入该分组）');
          return;
        }
        setState(() => _busy = true);
        try {
          final updated = moveNovelSourcesToGroup(
            _sources,
            keys: _selected,
            group: name,
          );
          await widget.store.saveAll(
            updated.where((s) => _selected.contains(s.key)),
          );
          _setStatus('已把 ${_selected.length} 个书源移入「${name.trim()}」');
          await _reloadAll();
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case 'rename':
        final from = await _pickGroup('重命名分组', '选择要重命名的分组');
        if (from == null || !mounted) return;
        final to = await _askGroupName(
          title: '重命名「$from」',
          hint: '新分组名',
          initial: from,
        );
        if (to == null || to.trim().isEmpty || !mounted) return;
        setState(() => _busy = true);
        try {
          final updated = renameNovelSourceGroup(_sources, from: from, to: to);
          await widget.store.saveAll(
            updated.where(
              (s) => s.groups.contains(to.trim()) || s.groups.contains(from),
            ),
          );
          _setStatus('分组「$from」已重命名为「${to.trim()}」');
          if (_groupFilter == from) _groupFilter = to.trim();
          await _reloadAll();
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case 'delete':
        final group = await _pickGroup('删除分组', '选择要删除的分组');
        if (group == null || !mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('删除分组「$group」？'),
            content: const Text('只会把分组名从书源上摘掉，书源本身保留。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除分组'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        setState(() => _busy = true);
        try {
          final updated = deleteNovelSourceGroup(_sources, group);
          await widget.store.saveAll(updated);
          _setStatus('已删除分组「$group」');
          if (_groupFilter == group) _groupFilter = null;
          await _reloadAll();
        } finally {
          if (mounted) setState(() => _busy = false);
        }
    }
  }

  Future<String?> _pickGroup(String title, String subtitle) async {
    final groups = _allGroups;
    if (groups.isEmpty) {
      _setStatus('还没有任何分组', error: true);
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final group in groups)
            SimpleDialogOption(
              key: ValueKey<String>('pick-group-$group'),
              onPressed: () => Navigator.of(context).pop(group),
              child: Text(group),
            ),
        ],
      ),
    );
  }

  Future<String?> _askGroupName({
    required String title,
    required String hint,
    String initial = '',
    bool numeric = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  // ---------------------------------------------------------------------------
  // 构建

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则管理'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新规则',
            onPressed: _reloadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: <Widget>[
            for (final kind in NovelRuleKind.values) Tab(text: kind.label),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[_buildBookTab(), _buildRssTab(), _buildReplaceTab()],
      ),
    );
  }

  Widget _buildBookTab() {
    return NovelFillContent(
      maxWidth: 1100,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildBookToolbar(),
          const SizedBox(height: 10),
          _Feedback(status: _status, error: _error),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_selected.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _buildBulkBar(),
          ],
          Expanded(child: _buildSourceList()),
        ],
      ),
    );
  }

  Widget _buildBookToolbar() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('novel-source-search'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索书源名称 / 地址 / 分组',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filter = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _filter = value.trim()),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<_SourceSort>(
              key: const Key('novel-source-sort'),
              tooltip: '排序',
              initialValue: _sort,
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (context) => <PopupMenuEntry<_SourceSort>>[
                for (final sort in _SourceSort.values)
                  PopupMenuItem<_SourceSort>(
                    value: sort,
                    child: Text('按${sort.label}排序'),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.tonalIcon(
              key: const Key('novel-source-paste-import'),
              onPressed: () => _openImportDialog(NovelRuleKind.bookSource),
              icon: const Icon(Icons.add_link),
              label: const Text('导入书源'),
            ),
            OutlinedButton.icon(
              key: const Key('novel-source-import-file'),
              onPressed: _busy ? null : _importFromFile,
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('本地文件'),
            ),
            OutlinedButton.icon(
              key: const Key('novel-source-import-clipboard'),
              onPressed: _busy ? null : _importFromClipboard,
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('剪贴板'),
            ),
            OutlinedButton.icon(
              key: const Key('novel-source-new'),
              onPressed: _busy ? null : () => _openEditor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建'),
            ),
            OutlinedButton.icon(
              key: const Key('novel-source-export-all'),
              onPressed: _sources.isEmpty
                  ? null
                  : () => _showExportMenu(_sources),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('全部导出'),
            ),
            OutlinedButton.icon(
              key: const Key('novel-source-manage-groups'),
              onPressed: _busy ? null : _manageGroups,
              icon: const Icon(Icons.folder_outlined, size: 18),
              label: const Text('分组管理'),
            ),
            if (widget.enableDebug && widget.onlineEngine != null)
              OutlinedButton.icon(
                key: const Key('novel-source-debug'),
                onPressed: _busy ? null : () => _openDebug(),
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: const Text('调试'),
              ),
          ],
        ),
        if (_allGroups.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: NovelFilterChip(
                    key: const Key('novel-source-group-all'),
                    label: '全部',
                    count: _sources.length,
                    selected: _groupFilter == null,
                    onTap: () => setState(() => _groupFilter = null),
                  ),
                ),
                for (final group in _allGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: NovelFilterChip(
                      key: ValueKey<String>('novel-source-group-$group'),
                      label: group,
                      count: _sources
                          .where(
                            (source) => group == novelUngroupedLabel
                                ? source.groups.isEmpty
                                : source.groups.contains(group),
                          )
                          .length,
                      selected: _groupFilter == group,
                      onTap: () => setState(
                        () =>
                            _groupFilter = _groupFilter == group ? null : group,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBulkBar() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      child: Row(
        children: <Widget>[
          Text('已选 ${_selected.length} 个', style: theme.textTheme.bodyMedium),
          const SizedBox(width: 12),
          TextButton(
            key: const Key('novel-source-bulk-enable'),
            onPressed: _busy ? null : () => _setSelectedEnabled(true),
            child: const Text('启用'),
          ),
          TextButton(
            key: const Key('novel-source-bulk-disable'),
            onPressed: _busy ? null : () => _setSelectedEnabled(false),
            child: const Text('停用'),
          ),
          TextButton(
            key: const Key('novel-source-bulk-move'),
            onPressed: _busy ? null : _moveSelectedToGroup,
            child: const Text('移动分组'),
          ),
          TextButton(
            key: const Key('novel-source-bulk-export'),
            onPressed: _busy
                ? null
                : () => _showExportMenu(<NovelBookSource>[
                    for (final source in _sources)
                      if (_selected.contains(source.key)) source,
                  ]),
            child: const Text('导出'),
          ),
          const Spacer(),
          TextButton(
            key: const Key('novel-source-bulk-clear'),
            onPressed: () => setState(_selected.clear),
            child: const Text('取消选择'),
          ),
          TextButton(
            key: const Key('novel-source-bulk-delete'),
            onPressed: _busy ? null : _deleteSelected,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceList() {
    if (_loading) {
      return const NovelLoadingState(label: '正在读取规则…');
    }
    if (_sources.isEmpty) {
      return NovelEmptyState(
        icon: Icons.source_outlined,
        title: '还没有书源',
        message:
            '点上方「导入书源」粘贴链接，或「本地文件 / 剪贴板」导入 JSON；'
            '也可以到「订阅源」里点订阅站点卡片，打开网站后点「一键导入」。',
        action: FilledButton.tonalIcon(
          key: const Key('novel-source-import-empty'),
          onPressed: () => _openImportDialog(NovelRuleKind.bookSource),
          icon: const Icon(Icons.add_link),
          label: const Text('导入书源'),
        ),
      );
    }
    final visible = _visibleSources;
    if (visible.isEmpty) {
      return NovelEmptyState(
        icon: Icons.filter_alt_off,
        title: '没有匹配的书源',
        message: _filter.isEmpty && _groupFilter != null
            ? '分组「$_groupFilter」里没有书源；点上面的「全部」看所有源。'
            : '没有书源匹配「$_filter」。清空搜索词或换个分组。',
        action: OutlinedButton(
          onPressed: () {
            _searchController.clear();
            setState(() {
              _filter = '';
              _groupFilter = null;
            });
          },
          child: const Text('清除筛选'),
        ),
      );
    }
    final allSelected = visible.every((s) => _selected.contains(s.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Checkbox(
              key: const Key('novel-source-select-all'),
              value: allSelected,
              tristate: false,
              onChanged: (_) => setState(() {
                if (allSelected) {
                  _selected.removeAll(visible.map((s) => s.key));
                } else {
                  _selected.addAll(visible.map((s) => s.key));
                }
              }),
            ),
            Text(
              '${visible.length} / ${_sources.length} 个书源',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final source = visible[index];
              return _SourceRow(
                key: ValueKey<String>('source-${source.key}'),
                source: source,
                selected: _selected.contains(source.key),
                onSelected: (value) => setState(() {
                  if (value) {
                    _selected.add(source.key);
                  } else {
                    _selected.remove(source.key);
                  }
                }),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'novel/source-detail'),
                    builder: (_) => NovelSourceDetailPage(source: source),
                  ),
                ),
                onToggle: (value) async {
                  await widget.store.setEnabled(source.key, value);
                  await _reloadAll();
                },
                onEdit: () => _openEditor(source: source),
                onWeight: () => _editWeight(source),
                onExport: () => _showExportMenu(<NovelBookSource>[source]),
                onDebug: widget.enableDebug && widget.onlineEngine != null
                    ? () => _openDebug(initialSourceKey: source.key)
                    : null,
                onDelete: () => _confirmDelete(
                  title: '删除书源「${source.name}」？',
                  message: '只会删除本机保存的书源文件，不影响网站上的书源。',
                  onDelete: () => widget.store.delete(source.key),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRssTab() {
    return NovelFillContent(
      maxWidth: 1100,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildRuleImportBar(
            kind: NovelRuleKind.rssSource,
            key: const Key('novel-rss-paste-import'),
          ),
          _Feedback(status: _status, error: _error),
          Expanded(child: _buildRssList()),
        ],
      ),
    );
  }

  Widget _buildReplaceTab() {
    return NovelFillContent(
      maxWidth: 1100,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildRuleImportBar(
            kind: NovelRuleKind.replaceRule,
            key: const Key('novel-replace-paste-import'),
          ),
          _Feedback(status: _status, error: _error),
          Expanded(child: _buildReplaceList()),
        ],
      ),
    );
  }

  Widget _buildRuleImportBar({required NovelRuleKind kind, required Key key}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        key: key,
        onPressed: () => _openImportDialog(kind),
        icon: const Icon(Icons.add_link),
        label: Text('导入${kind.label}'),
      ),
    );
  }

  /// 点订阅站点卡片：满窗口打开这个站点；返回后刷新规则列表。
  Future<void> _openSite(NovelSourceSubscription subscription) async {
    final url = subscription.siteUrl.isEmpty
        ? widget.siteUrl
        : subscription.siteUrl;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/source-site'),
        builder: (_) => NovelSourceSitePage(
          title: subscription.name,
          url: url,
          importer: widget.importer,
          webViewBuilder: widget.webViewBuilder,
        ),
      ),
    );
    if (mounted) await _reloadAll();
  }

  /// 订阅源 tab：先列订阅站点（订阅页那批），再列导入的 RSS 订阅规则。
  ///
  /// 两者在用户语义里都叫「订阅源」：订阅站点是书源的来源站点（默认为
  /// 「喵公子书源管理」），RSS 是 Legado `rsssource` 规则。订阅站点只读展示，
  /// 点按切回「书源」分类看它导入的源。
  Widget _buildRssList() {
    if (_loading) {
      return const NovelLoadingState(label: '正在读取订阅源…');
    }
    final hasSubscriptions = _subscriptions.isNotEmpty;
    final hasRss = _rssSources.isNotEmpty;
    if (!hasSubscriptions && !hasRss) {
      return NovelEmptyState(
        icon: Icons.rss_feed,
        title: '还没有订阅源',
        message: '导入订阅源规则后会出现在这里，可以启停或删除。',
        action: FilledButton.tonalIcon(
          key: const Key('novel-rss-import-empty'),
          onPressed: () => _openImportDialog(NovelRuleKind.rssSource),
          icon: const Icon(Icons.add_link),
          label: const Text('导入订阅源'),
        ),
      );
    }
    final store = widget.importer.rssStore;
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: <Widget>[
        if (hasSubscriptions) ...<Widget>[
          const NovelSectionHeader(icon: Icons.rss_feed, title: '订阅站点'),
          const SizedBox(height: 8),
          for (final subscription in _subscriptions) ...<Widget>[
            _SubscriptionSiteCard(
              subscription: subscription,
              sourceCount: _sources.length,
              onOpen: () => _openSite(subscription),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 12),
        if (hasRss) ...<Widget>[
          const NovelSectionHeader(
            icon: Icons.subscriptions_outlined,
            title: 'RSS 订阅规则',
          ),
          const SizedBox(height: 8),
          for (final source in _rssSources) ...<Widget>[
            _RuleCard(
              icon: Icons.rss_feed,
              title: source.name,
              subtitle: source.url,
              tag: source.group,
              enabled: source.enabled,
              onToggle: store == null
                  ? null
                  : (value) async {
                      await store.setEnabled(source.key, value);
                      await _reloadAll();
                    },
              onDelete: () => _confirmDelete(
                title: '删除订阅源「${source.name}」？',
                message: '只会删除本机保存的规则，不影响订阅源网站。',
                onDelete: () async => await store?.delete(source.key) ?? false,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildReplaceList() {
    if (_loading) {
      return const NovelLoadingState(label: '正在读取替换规则…');
    }
    if (_replaceRules.isEmpty) {
      return NovelEmptyState(
        icon: Icons.auto_fix_high_outlined,
        title: '还没有替换规则',
        message: '导入替换规则后，阅读器加载正文和标题时会自动净化。',
        action: FilledButton.tonalIcon(
          key: const Key('novel-replace-import-empty'),
          onPressed: () => _openImportDialog(NovelRuleKind.replaceRule),
          icon: const Icon(Icons.add_link),
          label: const Text('导入替换规则'),
        ),
      );
    }
    final store = widget.importer.replaceStore;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _replaceRules.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final rule = _replaceRules[index];
        return _RuleCard(
          icon: Icons.auto_fix_high_outlined,
          title: rule.name,
          subtitle: '${rule.pattern} → ${rule.replacement}',
          tag: rule.isRegex ? '正则' : '普通',
          enabled: rule.enabled,
          onToggle: store == null
              ? null
              : (value) async {
                  await store.setEnabled(rule.key, value);
                  await _reloadAll();
                },
          onDelete: () => _confirmDelete(
            title: '删除替换规则「${rule.name}」？',
            message: '删除后阅读器不再应用这条替换。',
            onDelete: () async => await store?.delete(rule.key) ?? false,
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete({
    required String title,
    required String message,
    required Future<bool> Function() onDelete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    await onDelete();
    await _reloadAll();
  }
}

/// 剪贴板读写缝（测试注入，避免碰平台通道）。
abstract interface class NovelClipboardGate {
  Future<String?> readText();

  Future<void> writeText(String text);
}

class _PlatformClipboardGate implements NovelClipboardGate {
  const _PlatformClipboardGate();

  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> writeText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// 一条书源：勾选 + 卡片 + 编辑/权重/导出/调试/删除。
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.selected,
    required this.onSelected,
    required this.onTap,
    required this.onToggle,
    required this.onEdit,
    required this.onWeight,
    required this.onExport,
    required this.onDelete,
    this.onDebug,
  });

  final NovelBookSource source;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onWeight;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback? onDebug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Checkbox(
          key: ValueKey<String>('select-${source.key}'),
          value: selected,
          onChanged: (value) => onSelected(value ?? false),
        ),
        Expanded(
          child: NovelCard(
            onTap: onTap,
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: <Widget>[
                NovelSourceBadge(name: source.name, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              source.name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          NovelTag(label: source.typeLabel),
                          const SizedBox(width: 6),
                          NovelTag(label: '权重 ${source.weight}'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source.url,
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
                          for (final group in source.groups.take(3))
                            NovelTag(label: group),
                          if (source.groups.isEmpty)
                            const NovelTag(label: '未分组'),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey<String>('menu-${source.key}'),
                  tooltip: '更多操作',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                      case 'weight':
                        onWeight();
                      case 'export':
                        onExport();
                      case 'debug':
                        onDebug?.call();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('编辑'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'weight',
                      child: Text('设置权重'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'export',
                      child: Text('导出'),
                    ),
                    if (onDebug != null)
                      const PopupMenuItem<String>(
                        value: 'debug',
                        child: Text('调试'),
                      ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('删除'),
                    ),
                  ],
                ),
                Switch(value: source.enabled, onChanged: onToggle),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 导入结果 / 读取错误，三个 tab 共用同一份状态。
class _Feedback extends StatelessWidget {
  const _Feedback({required this.status, required this.error});

  final String? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              status!,
              key: const Key('novel-source-status'),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error!,
              key: const Key('novel-source-error'),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
            ),
          ),
      ],
    );
  }
}

/// 订阅站点卡：名称 + 书源数量 + 备注 + 站点地址，点按切到「书源」分类。
class _SubscriptionSiteCard extends StatelessWidget {
  const _SubscriptionSiteCard({
    required this.subscription,
    required this.sourceCount,
    required this.onOpen,
  });

  final NovelSourceSubscription subscription;
  final int sourceCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: <Widget>[
          NovelSourceBadge(name: subscription.name, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  subscription.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$sourceCount 个书源 · 点按打开网站',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (subscription.note.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    subscription.note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  subscription.siteUrl,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// 订阅源 / 替换规则列表卡：图标 + 名称 + 备注 + 标签 + 开关 + 删除。
class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.enabled,
    required this.onToggle,
    required this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final bool enabled;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: <Widget>[
          Icon(icon, color: cs.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tag.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(
                        tag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onToggle),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
