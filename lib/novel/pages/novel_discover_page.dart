// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「发现」：左侧分组筛选栏 + 书源列表（搜索、启停、进管理页）。
///
/// 参考图里「发现」是书源内容流；书源引擎尚未接入，所以本页只做真实可用的
/// 书源侧：按 `bookSourceGroup` 分组、按名称/地址搜索、启停落仓库。内容榜单
/// 用一条能力边界横幅说明，不摆假书。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class NovelDiscoverPage extends StatefulWidget {
  const NovelDiscoverPage({
    super.key,
    required this.active,
    this.sourceImporter,
    this.openRoute,
  });

  final bool active;
  final NovelSourceImporter? sourceImporter;
  final NovelRouteOpener? openRoute;

  @override
  State<NovelDiscoverPage> createState() => _NovelDiscoverPageState();
}

class _NovelDiscoverPageState extends State<NovelDiscoverPage> {
  static const String _ungrouped = '\u0000ungrouped';

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<NovelBookSource> _sources = const <NovelBookSource>[];
  bool _loading = true;
  String? _error;

  /// null = 全部；[_ungrouped] = 未分组；其余为分组名。
  String? _category;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load();
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
  void didUpdateWidget(NovelDiscoverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.active && widget.active) ||
        oldWidget.sourceImporter != widget.sourceImporter) {
      _load();
    }
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _load() async {
    final importer = widget.sourceImporter;
    if (importer == null) {
      setState(() {
        _sources = const <NovelBookSource>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources = await importer.store.loadAll();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取书源失败：$error';
      });
    }
  }

  Future<void> _toggle(NovelBookSource source, bool enabled) async {
    final importer = widget.sourceImporter;
    if (importer == null) return;
    final previous = _sources;
    setState(() {
      _sources = <NovelBookSource>[
        for (final item in _sources)
          item.key == source.key ? item.copyWith(enabled: enabled) : item,
      ];
    });
    try {
      await importer.store.setEnabled(source.key, enabled);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _sources = previous;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('启停书源失败：$error')));
    }
  }

  Future<void> _openManage() async {
    await openNovelRoute(context, widget.openRoute, NovelRoute.sourceManage);
    if (mounted) await _load();
  }

  Map<String, int> _groupCounts() {
    final counts = <String, int>{};
    var ungrouped = 0;
    for (final source in _sources) {
      if (source.groups.isEmpty) {
        ungrouped++;
        continue;
      }
      for (final group in source.groups) {
        counts[group] = (counts[group] ?? 0) + 1;
      }
    }
    if (ungrouped > 0) counts[_ungrouped] = ungrouped;
    return counts;
  }

  List<NovelBookSource> _visible() {
    final query = _search.text.trim().toLowerCase();
    return <NovelBookSource>[
      for (final source in _sources)
        if (_matchesCategory(source) &&
            (query.isEmpty ||
                '${source.name} ${source.url} ${source.groupLabel}'
                    .toLowerCase()
                    .contains(query)))
          source,
    ];
  }

  bool _matchesCategory(NovelBookSource source) {
    final category = _category;
    if (category == null) return true;
    if (category == _ungrouped) return source.groups.isEmpty;
    return source.groups.contains(category);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _sources.where((source) => source.enabled).length;
    final subtitle = _sources.isEmpty
        ? '书源内容探索需要书源引擎'
        : '${_sources.length} 个书源 · $enabled 个启用';
    return NovelFillContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelPageHeader(
            title: '发现',
            subtitle: subtitle,
            actions: <Widget>[
              NovelCircleAction(
                icon: Icons.search,
                tooltip: '搜索书源',
                onPressed: _searchFocus.requestFocus,
              ),
              NovelCircleAction(
                icon: Icons.refresh,
                tooltip: '刷新书源',
                onPressed: _load,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const NovelLoadingState(label: '正在读取书源…')
                : widget.sourceImporter == null
                ? NovelEmptyState(
                    icon: Icons.source_outlined,
                    title: '书源仓库未接线',
                    message: '书源导入与发现需要书源仓库；当前宿主没有注入该能力。',
                  )
                : _sources.isEmpty
                ? NovelEmptyState(
                    icon: Icons.explore_outlined,
                    title: '还没有书源',
                    message:
                        '去书源网站点「一键导入」，或粘贴书源链接。'
                        '导入后这里会按分组列出书源，可搜索、启停和进管理页。',
                    action: FilledButton.tonalIcon(
                      onPressed: _openManage,
                      icon: const Icon(Icons.add_link),
                      label: const Text('导入书源'),
                    ),
                  )
                : _buildBrowser(_visible()),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowser(List<NovelBookSource> visible) {
    final counts = _groupCounts();
    final categories = counts.keys.where((key) => key != _ungrouped).toList()
      ..sort();
    final panel = _CategoryPanel(
      total: _sources.length,
      counts: counts,
      categories: categories,
      ungrouped: _ungrouped,
      selected: _category,
      onSelect: (value) => setState(() => _category = value),
    );
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _CapabilityBanner(),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          focusNode: _searchFocus,
          decoration: InputDecoration(
            hintText: '搜索书源名称 / 地址 / 分组',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _search.clear,
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Text(
              _category == null
                  ? '全部书源'
                  : _category == _ungrouped
                  ? '未分组'
                  : _category!,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 8),
            Text(
              '${visible.length} 个',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _openManage,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('管理'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: visible.isEmpty
              ? NovelEmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: '这个筛选下没有书源',
                  message: '换一个分组，或清空搜索词再看。',
                  action: FilledButton.tonal(
                    onPressed: () {
                      _search.clear();
                      setState(() => _category = null);
                    },
                    child: const Text('重置筛选'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final source = visible[index];
                    return NovelSourceCard(
                      source: source,
                      onToggle: (value) => _toggle(source, value),
                      onTap: _openManage,
                    );
                  },
                ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    NovelFilterChip(
                      label: '全部',
                      count: _sources.length,
                      selected: _category == null,
                      onTap: () => setState(() => _category = null),
                    ),
                    const SizedBox(width: 8),
                    for (final group in categories) ...<Widget>[
                      NovelFilterChip(
                        label: group,
                        count: counts[group] ?? 0,
                        selected: _category == group,
                        onTap: () => setState(() => _category = group),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if ((counts[_ungrouped] ?? 0) > 0)
                      NovelFilterChip(
                        label: '未分组',
                        count: counts[_ungrouped] ?? 0,
                        selected: _category == _ungrouped,
                        onTap: () => setState(() => _category = _ungrouped),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: list),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: 220, child: panel),
            const SizedBox(width: 20),
            Expanded(child: list),
          ],
        );
      },
    );
  }
}

/// 左侧分类栏：全部 / 各分组 / 未分组。
class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({
    required this.total,
    required this.counts,
    required this.categories,
    required this.ungrouped,
    required this.selected,
    required this.onSelect,
  });

  final int total;
  final Map<String, int> counts;
  final List<String> categories;
  final String ungrouped;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = <Widget>[
      _CategoryTile(
        icon: Icons.apps,
        label: '全部',
        count: total,
        selected: selected == null,
        onTap: () => onSelect(null),
      ),
      for (final group in categories)
        _CategoryTile(
          icon: Icons.folder_outlined,
          label: group,
          count: counts[group] ?? 0,
          selected: selected == group,
          onTap: () => onSelect(group),
        ),
      if ((counts[ungrouped] ?? 0) > 0)
        _CategoryTile(
          icon: Icons.folder_off_outlined,
          label: '未分组',
          count: counts[ungrouped] ?? 0,
          selected: selected == ungrouped,
          onTap: () => onSelect(ungrouped),
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MimaoRadii.lg),
      ),
      child: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Text(
              '分组',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          ...entries,
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(MimaoRadii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? cs.onSecondaryContainer : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected
                        ? cs.onSecondaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilityBanner extends StatelessWidget {
  const _CapabilityBanner();

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
              '书源榜单、跨源搜索与开书需要书源引擎，当前尚未接入。'
              '这里可以先按分组筛选、搜索、启停书源。',
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
