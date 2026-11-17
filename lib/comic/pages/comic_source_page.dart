// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';

/// 漫画源管理页：已导入源列表 + 「从 URL 导入源」入口 + 启用/删除。
///
/// 只认 [ComicSourceRepository]；源存储就绪后换实现即可，UI 不变。
/// 写操作（导入/启用/删除）都通过仓库拿到新列表并重建状态；同时对外暴露
/// [onImport] / [onToggle] / [onDelete] 回调，方便上层记录埋点或联动其它模块。
class ComicSourcePage extends StatefulWidget {
  const ComicSourcePage({
    super.key,
    required this.repository,
    this.showAppBar = true,
    this.onImport,
    this.onToggle,
    this.onDelete,
  });

  final ComicSourceRepository repository;

  /// 壳已提供顶部导航时设为 false，本页不再画自己的 AppBar。
  final bool showAppBar;

  /// 从 URL 成功导入后回调，参数是用户输入的 URL。
  final ValueChanged<String>? onImport;

  /// 启用状态切换后回调。
  final void Function(ComicSourceInfo source, bool enabled)? onToggle;

  /// 删除后回调。
  final ValueChanged<ComicSourceInfo>? onDelete;

  @override
  State<ComicSourcePage> createState() => _ComicSourcePageState();
}

class _ComicSourcePageState extends State<ComicSourcePage> {
  final TextEditingController _urlController = TextEditingController();
  late Future<List<ComicSourceInfo>> _future;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listSources();
  }

  @override
  void didUpdateWidget(ComicSourcePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _future = widget.repository.listSources();
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _error = null;
      _future = widget.repository.listSources();
    });
  }

  Future<void> _import() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请输入源地址 URL');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    try {
      final sources = await widget.repository.importSource(url);
      if (!mounted) return;
      _urlController.clear();
      setState(() {
        _future = Future<List<ComicSourceInfo>>.value(sources);
      });
      widget.onImport?.call(url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '导入失败：$e');
    }
  }

  Future<void> _toggle(ComicSourceInfo source, bool enabled) async {
    try {
      final sources = await widget.repository.setEnabled(source.id, enabled);
      if (!mounted) return;
      setState(() {
        _future = Future<List<ComicSourceInfo>>.value(sources);
      });
      widget.onToggle?.call(source, enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '操作失败：$e');
    }
  }

  Future<void> _delete(ComicSourceInfo source) async {
    try {
      final sources = await widget.repository.deleteSource(source.id);
      if (!mounted) return;
      setState(() {
        _future = Future<List<ComicSourceInfo>>.value(sources);
      });
      widget.onDelete?.call(source);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('源管理')) : null,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ImportEntry(controller: _urlController, onImport: _import),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return FutureBuilder<List<ComicSourceInfo>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('源列表加载失败'),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          );
        }
        final sources = snapshot.data ?? const <ComicSourceInfo>[];
        if (sources.isEmpty) {
          return const Center(child: Text('还没有导入任何来源'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '已导入 ${sources.length} 个来源',
                style: Theme.of(context).textTheme.labelLarge?.apply(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: sources.length,
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return ComicSourceTile(
                    key: ValueKey<String>('source-${source.id}'),
                    source: source,
                    onToggle: (enabled) => _toggle(source, enabled),
                    onDelete: () => _delete(source),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 「从 URL 导入源」入口：一个输入框 + 导入按钮，MD3 色调容器。
class _ImportEntry extends StatelessWidget {
  const _ImportEntry({required this.controller, required this.onImport});

  final TextEditingController controller;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.add_link_rounded,
                size: 18,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                '从 URL 导入源',
                style: Theme.of(context).textTheme.titleSmall?.apply(
                  color: cs.onSecondaryContainer,
                  fontWeightDelta: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/source.json',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onImport(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('import-source-button'),
                onPressed: onImport,
                child: const Text('导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单条来源：名称/URL/数量 + 启用开关 + 删除按钮。
class ComicSourceTile extends StatelessWidget {
  const ComicSourceTile({
    super.key,
    required this.source,
    required this.onToggle,
    required this.onDelete,
  });

  final ComicSourceInfo source;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              child: const Icon(Icons.source_rounded, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    source.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.apply(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (source.comicCount != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      '${source.comicCount} 部漫画',
                      style: textTheme.labelSmall?.apply(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              key: Key('toggle-${source.id}'),
              value: source.enabled,
              onChanged: onToggle,
            ),
            IconButton(
              key: Key('delete-${source.id}'),
              tooltip: '删除',
              icon: Icon(Icons.delete_outline_rounded, color: cs.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
