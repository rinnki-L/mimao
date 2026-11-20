// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
/// 漫画模块「发现」分区：各源站点的探索流（推荐/排行/最新等分栏）。
///
/// 数据来自 [ComicBrowseSource.exploreGroups]：一次进 QuickJS 执行某源
/// `explore` 的全部分区，逐分区容错。UI 只做「选源 → 分区横向条」，点卡片
/// 进详情——与源站点的发现页内容对应，只是换成本应用的展示。
library;

import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/pages/comic_poster_card.dart';

/// 发现分区。
class ComicDiscoverPage extends StatefulWidget {
  const ComicDiscoverPage({
    super.key,
    required this.browseSource,
    this.showAppBar = true,
    this.onOpenDetail,
  });

  final ComicBrowseSource browseSource;

  final bool showAppBar;

  final ValueChanged<ComicSummary>? onOpenDetail;

  @override
  State<ComicDiscoverPage> createState() => _ComicDiscoverPageState();
}

class _ComicDiscoverPageState extends State<ComicDiscoverPage> {
  /// 可选源（进入页面读一次）。
  late Future<List<ComicBrowseSourceInfo>> _sourcesFuture;

  /// 当前选中的源 key；null = 尚未选定（首帧取列表第一个）。
  String? _selectedKey;

  /// 当前源的探索结果。
  Future<List<ComicBrowseGroup>>? _groupsFuture;

  @override
  void initState() {
    super.initState();
    _sourcesFuture = widget.browseSource.browseSources();
  }

  @override
  void didUpdateWidget(ComicDiscoverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.browseSource != widget.browseSource) {
      _sourcesFuture = widget.browseSource.browseSources();
      _selectedKey = null;
      _groupsFuture = null;
    }
  }

  void _select(String key) {
    if (key == _selectedKey) return;
    setState(() {
      _selectedKey = key;
      _groupsFuture = widget.browseSource.exploreGroups(key);
    });
  }

  void _reload() {
    final key = _selectedKey;
    if (key == null) {
      setState(() => _sourcesFuture = widget.browseSource.browseSources());
      return;
    }
    setState(() => _groupsFuture = widget.browseSource.exploreGroups(key));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('发现')) : null,
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ComicBrowseSourceInfo>>(
          future: _sourcesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _DiscoverMessage(
                icon: Icons.error_outline_rounded,
                title: '源列表加载失败',
                detail: '${snapshot.error}',
                onRetry: _reload,
              );
            }
            final sources = snapshot.data ?? const <ComicBrowseSourceInfo>[];
            if (sources.isEmpty) {
              return const _DiscoverMessage(
                icon: Icons.source_outlined,
                title: '还没有可浏览的来源',
                detail: '先在主页的「源管理」里导入并启用一个源，发现页会显示它的推荐内容。',
              );
            }
            // 首帧自动选中第一个源（用户不需要先点一下才看到内容）。
            final selected = _selectedKey ?? sources.first.key;
            if (_selectedKey == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _select(sources.first.key);
              });
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SourceChips(
                  keyPrefix: 'discover-source',
                  sources: sources,
                  selectedKey: selected,
                  onSelect: _select,
                ),
                Expanded(child: _buildGroups(selected)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGroups(String key) {
    final future = _groupsFuture;
    if (future == null) return const Center(child: CircularProgressIndicator());
    return FutureBuilder<List<ComicBrowseGroup>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _DiscoverMessage(
            icon: Icons.error_outline_rounded,
            title: '发现内容加载失败',
            detail: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        final groups = snapshot.data ?? const <ComicBrowseGroup>[];
        final nonEmpty = [
          for (final group in groups)
            if (group.comics.isNotEmpty) group,
        ];
        // 失败分区（有诊断、无数据）：把真实原因列出来，而不是让它凭空消失。
        final failed = [
          for (final group in groups)
            if (group.comics.isEmpty && group.diagnostics.isNotEmpty) group,
        ];
        if (nonEmpty.isEmpty) {
          return _DiscoverMessage(
            icon: Icons.explore_off_outlined,
            title: '这个来源没有发现内容',
            detail: failed.isEmpty
                ? '源脚本没有提供 explore（或本次加载失败）。可以换个来源，或用主页搜索。'
                : [
                    '加载失败原因：',
                    for (final group in failed)
                      for (final reason in group.diagnostics)
                        '• ${group.title}：$reason',
                  ].join('\n'),
            onRetry: _reload,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _groupsFuture;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              if (failed.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${failed.length} 个分区加载失败：${failed.map((g) => g.title).join('、')}',
                    key: const Key('discover-partial-failures'),
                    style: Theme.of(context).textTheme.bodySmall?.apply(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (final group in nonEmpty) ...<Widget>[
                ComicSectionHeader(title: group.title),
                ComicPosterRow(
                  items: group.comics,
                  keyPrefix: 'discover-${group.exploreIndex}',
                  onOpen: widget.onOpenDetail,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 源选择 chip 行（发现/分类共用）。
class _SourceChips extends StatelessWidget {
  const _SourceChips({
    required this.keyPrefix,
    required this.sources,
    required this.selectedKey,
    required this.onSelect,
  });

  final String keyPrefix;
  final List<ComicBrowseSourceInfo> sources;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: Key('$keyPrefix-${source.key}'),
                  label: Text(source.name),
                  selected: source.key == selectedKey,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onSelect(source.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 发现/分类共用的空态/错误态（带可选重试）。
class _DiscoverMessage extends StatelessWidget {
  const _DiscoverMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 供分类页复用的消息组件（同一视觉）。
class ComicBrowseMessage extends StatelessWidget {
  const ComicBrowseMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _DiscoverMessage(
    icon: icon,
    title: title,
    detail: detail,
    onRetry: onRetry,
  );
}

/// 供分类页复用的源 chip 行。
class ComicBrowseSourceChips extends StatelessWidget {
  const ComicBrowseSourceChips({
    super.key,
    required this.keyPrefix,
    required this.sources,
    required this.selectedKey,
    required this.onSelect,
  });

  final String keyPrefix;
  final List<ComicBrowseSourceInfo> sources;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => _SourceChips(
    keyPrefix: keyPrefix,
    sources: sources,
    selectedKey: selectedKey,
    onSelect: onSelect,
  );
}
