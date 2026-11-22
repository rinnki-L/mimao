// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「订阅」：已导入书源按 `bookSourceGroup` 分组展示，可按启停筛选、
/// 启停单源、进书源管理页。参考图里这一页是订阅源列表，本应用对应"我的书源"。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

enum _SubscribeFilter { all, enabled, disabled }

extension on _SubscribeFilter {
  String get label => switch (this) {
    _SubscribeFilter.all => '全部',
    _SubscribeFilter.enabled => '启用中',
    _SubscribeFilter.disabled => '已停用',
  };
}

class NovelSubscribePage extends StatefulWidget {
  const NovelSubscribePage({
    super.key,
    required this.active,
    this.sourceImporter,
    this.openRoute,
  });

  final bool active;
  final NovelSourceImporter? sourceImporter;
  final NovelRouteOpener? openRoute;

  @override
  State<NovelSubscribePage> createState() => _NovelSubscribePageState();
}

class _NovelSubscribePageState extends State<NovelSubscribePage> {
  static const String _ungrouped = '未分组';

  List<NovelBookSource> _sources = const <NovelBookSource>[];
  bool _loading = true;
  String? _error;
  _SubscribeFilter _filter = _SubscribeFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NovelSubscribePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.active && widget.active) ||
        oldWidget.sourceImporter != widget.sourceImporter) {
      _load();
    }
  }

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

  List<NovelBookSource> _filtered() {
    return switch (_filter) {
      _SubscribeFilter.all => _sources,
      _SubscribeFilter.enabled =>
        _sources.where((source) => source.enabled).toList(),
      _SubscribeFilter.disabled =>
        _sources.where((source) => !source.enabled).toList(),
    };
  }

  /// 分组 → 源列表；多分组源在每个组里各出现一次（与 Legado 一致）。
  Map<String, List<NovelBookSource>> _grouped(List<NovelBookSource> sources) {
    final result = <String, List<NovelBookSource>>{};
    for (final source in sources) {
      if (source.groups.isEmpty) {
        result.putIfAbsent(_ungrouped, () => <NovelBookSource>[]).add(source);
        continue;
      }
      for (final group in source.groups) {
        result.putIfAbsent(group, () => <NovelBookSource>[]).add(source);
      }
    }
    final keys = result.keys.where((key) => key != _ungrouped).toList()..sort();
    final ordered = <String, List<NovelBookSource>>{
      for (final key in keys) key: result[key]!,
      if (result.containsKey(_ungrouped)) _ungrouped: result[_ungrouped]!,
    };
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _sources.where((source) => source.enabled).length;
    final subtitle = _sources.isEmpty
        ? '导入书源后按分组管理'
        : '${_sources.length} 个书源 · $enabled 个启用';
    return NovelFillContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelPageHeader(
            title: '订阅',
            subtitle: subtitle,
            actions: <Widget>[
              NovelCircleAction(
                icon: Icons.refresh,
                tooltip: '刷新书源',
                onPressed: _load,
              ),
            ],
            bottom: _buildActions(),
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
                    icon: Icons.rss_feed,
                    title: '书源仓库未接线',
                    message: '书源订阅需要书源仓库；当前宿主没有注入该能力。',
                  )
                : _sources.isEmpty
                ? NovelEmptyState(
                    icon: Icons.rss_feed,
                    title: '还没有订阅源',
                    message:
                        '打开书源网站点「一键导入」，导入的书源会按分组'
                        '出现在这里，可启停或进管理页删改。',
                    action: FilledButton.tonalIcon(
                      onPressed: _openManage,
                      icon: const Icon(Icons.add_link),
                      label: const Text('导入书源'),
                    ),
                  )
                : _buildContent(_grouped(_filtered())),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: _openManage,
          icon: const Icon(Icons.source_outlined),
          label: const Text('书源管理'),
        ),
        OutlinedButton.icon(
          onPressed: _openManage,
          icon: const Icon(Icons.add_link),
          label: const Text('导入书源'),
        ),
        const SizedBox(width: 8),
        for (final filter in _SubscribeFilter.values)
          NovelFilterChip(
            label: filter.label,
            count: switch (filter) {
              _SubscribeFilter.all => _sources.length,
              _SubscribeFilter.enabled =>
                _sources.where((source) => source.enabled).length,
              _SubscribeFilter.disabled =>
                _sources.where((source) => !source.enabled).length,
            },
            selected: _filter == filter,
            onTap: () => setState(() => _filter = filter),
          ),
      ],
    );
  }

  Widget _buildContent(Map<String, List<NovelBookSource>> grouped) {
    if (grouped.isEmpty) {
      return NovelEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '这个筛选下没有书源',
        message: '切换到「全部」，或去书源管理页导入新的书源。',
        action: FilledButton.tonal(
          onPressed: () => setState(() => _filter = _SubscribeFilter.all),
          child: const Text('查看全部'),
        ),
      );
    }
    final groups = grouped.entries.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        if (columns == 1) {
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _GroupCard(
              group: groups[index].key,
              sources: groups[index].value,
              onManage: _openManage,
              onToggle: _toggle,
            ),
          );
        }
        final width = (constraints.maxWidth - 16) / 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: <Widget>[
              for (final entry in groups)
                SizedBox(
                  width: width,
                  child: _GroupCard(
                    group: entry.key,
                    sources: entry.value,
                    onManage: _openManage,
                    onToggle: _toggle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.sources,
    required this.onManage,
    required this.onToggle,
  });

  final String group;
  final List<NovelBookSource> sources;
  final VoidCallback onManage;
  final void Function(NovelBookSource source, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = sources.where((source) => source.enabled).length;
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              NovelSourceBadge(name: group, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      group,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${sources.length} 个 · $enabled 启用',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onManage, child: const Text('管理')),
            ],
          ),
          const SizedBox(height: 6),
          for (final source in sources.take(6))
            _SourceRow(
              source: source,
              onToggle: (value) => onToggle(source, value),
            ),
          if (sources.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                '还有 ${sources.length - 6} 个书源，进管理页查看全部',
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

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.onToggle});

  final NovelBookSource source;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: source.enabled ? cs.primary : cs.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              source.name,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            source.typeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Switch(value: source.enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}
