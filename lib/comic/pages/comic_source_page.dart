// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/engine/engine.dart'
    show
        ComicSourceCatalog,
        ComicSourceIndexEntry,
        ComicSourceIndexResult,
        defaultComicSourceIndexUrl,
        normalizeIndexUrl;

/// 漫画源管理页：已导入源列表 + 「从 URL 导入源」入口 + 启用/删除。
///
/// 有 [catalog]（生产由 ComicModule 注入）时，额外显示「源仓库」区块：
/// 浏览 Venera 风格 `index.json` → 勾选 → 导入选中，导入走同一条
/// [ComicSourceRepository.importSource] 写入链路。
///
/// 只认 [ComicSourceRepository]；源存储就绪后换实现即可，UI 不变。
/// 写操作（导入/启用/删除）都通过仓库拿到新列表并重建状态；同时对外暴露
/// [onImport] / [onToggle] / [onDelete] 回调，方便上层记录埋点或联动其它模块。
///
/// 已知边界：仓库区块 + 导入入口 + 源列表同时展开时整体较高，390×844 竖屏
/// 与桌面窗口放得下；极矮视口（如手机横屏）仓库列表展开时可能裁掉底部——
/// 列表本体有 maxHeight 封顶，缺失仅影响可视范围，功能不受损。
class ComicSourcePage extends StatefulWidget {
  const ComicSourcePage({
    super.key,
    required this.repository,
    this.catalog,
    this.showAppBar = true,
    this.onImport,
    this.onToggle,
    this.onDelete,
  });

  final ComicSourceRepository repository;

  /// 源仓库目录（浏览 `index.json`）。null 时不显示「源仓库」区块——fixture
  /// 与旧调用方无需改动即保持原样。
  final ComicSourceCatalog? catalog;

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
  final TextEditingController _indexUrlController = TextEditingController(
    text: defaultComicSourceIndexUrl,
  );
  late Future<List<ComicSourceInfo>> _future;
  String? _error;

  /// 手动 URL 导入在途标记（防双击/与仓库导入并发写同一仓库）。
  bool _importing = false;

  // 「源仓库」区块状态（catalog 为 null 时整块不渲染）。
  bool _browsing = false;
  bool _importingRepo = false;
  bool _browsed = false;
  List<ComicSourceIndexEntry> _indexEntries = const <ComicSourceIndexEntry>[];
  final Set<String> _selectedKeys = <String>{};
  String? _repoMessage;

  /// 当前清单条目来源的地址：导入只认它，字段被改过后必须重新浏览，
  /// 避免把 A 仓库勾选的条目悄悄从 B 仓库拉取（预览与实际导入不一致）。
  String? _browsedIndexUrl;

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
    _indexUrlController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _error = null;
      _future = widget.repository.listSources();
    });
  }

  Future<void> _import() async {
    if (_importing || _browsing || _importingRepo) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请输入源地址 URL');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _importing = true;
    });
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
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 当前输入框里的合法清单地址；非法返回 null。
  Uri? _indexUri() => normalizeIndexUrl(_indexUrlController.text);

  /// 拉取仓库清单，列出可导入的源供用户勾选。
  Future<void> _browseRepo() async {
    final catalog = widget.catalog;
    if (catalog == null || _browsing || _importingRepo || _importing) return;
    if (_indexUri() == null) {
      setState(() => _repoMessage = '仓库地址不合法：只支持不含凭据的 http(s) 地址');
      return;
    }
    FocusScope.of(context).unfocus();
    // 取值在 await 之前：用户在 fetch 在途时改地址，也不至于把旧清单的
    // 条目绑到新地址上。
    final requestedUrl = _indexUrlController.text;
    setState(() {
      _browsing = true;
      _browsed = true;
      _repoMessage = null;
      _indexEntries = const <ComicSourceIndexEntry>[];
      _selectedKeys.clear();
    });

    final result = await catalog.fetchIndex(requestedUrl);
    if (!mounted) return;
    setState(() {
      _browsing = false;
      _indexEntries = result.entries;
      // 条目与清单地址绑定：导入时以此地址为准（改地址须重新浏览）。
      _browsedIndexUrl = requestedUrl;
      _repoMessage = _indexMessage(result);
    });
  }

  String _indexMessage(ComicSourceIndexResult result) {
    if (result.failures.isNotEmpty) {
      return '读取清单 ${result.entries.length} 条，失败 ${result.failures.length} 条：'
          '${result.failures.first}';
    }
    if (result.entries.isEmpty) return '仓库里没有可导入的源';
    return '发现 ${result.entries.length} 个源，勾选后导入';
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedKeys.length == _indexEntries.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys.addAll(_indexEntries.map((e) => e.key));
      }
    });
  }

  /// 逐个把选中的清单条目拼成 .js URL 并走仓库的 [ComicSourceRepository.importSource]
  /// 导入（同一条写入链路：下载→解析→注册执行池→落盘）。单条失败不影响其它源。
  ///
  /// 只认浏览时的清单地址（[_browsedIndexUrl]）：字段被改过后条目是旧仓库的
  /// 预览，必须重新浏览才能导入，防止「看的是 A、拉的是 B」。
  Future<void> _importSelected() async {
    final catalog = widget.catalog;
    if (catalog == null ||
        _importingRepo ||
        _browsing ||
        _importing ||
        _selectedKeys.isEmpty) {
      return;
    }
    if (_browsedIndexUrl == null ||
        _browsedIndexUrl != _indexUrlController.text) {
      setState(() => _repoMessage = '清单地址已改动，请重新浏览后再导入');
      return;
    }
    setState(() {
      _importingRepo = true;
      _repoMessage = null;
    });

    var count = 0;
    final failures = <String>[];
    List<ComicSourceInfo>? lastSources;
    final selected = _indexEntries.where((e) => _selectedKeys.contains(e.key));
    for (final entry in selected) {
      try {
        final sourceUrl = catalog.sourceUrl(_browsedIndexUrl!, entry);
        lastSources = await widget.repository.importSource(sourceUrl);
        count++;
        widget.onImport?.call(sourceUrl);
      } on Object catch (error) {
        failures.add('${entry.displayName}：$error');
      }
    }
    if (!mounted) return;
    setState(() {
      _importingRepo = false;
      if (lastSources != null) {
        _future = Future<List<ComicSourceInfo>>.value(lastSources);
      }
      _repoMessage = _repoImportMessage(count, failures);
    });
  }

  String _repoImportMessage(int count, List<String> failures) {
    if (failures.isNotEmpty) {
      return '导入 $count 个，失败 ${failures.length} 个：${failures.first}';
    }
    if (count == 0) return '没有可导入的源';
    return '导入 $count 个源';
  }

  Future<void> _toggle(ComicSourceInfo source, bool enabled) async {
    try {
      final sources = await widget.repository.setEnabled(source.id, enabled);
      if (!mounted) return;
      final updated = sources.firstWhere(
        (s) => s.id == source.id,
        orElse: () => source.copyWith(enabled: enabled),
      );
      setState(() {
        _error = null;
        _future = Future<List<ComicSourceInfo>>.value(sources);
      });
      // 回调用更新后的实体（enabled 已是新值），避免消费方读到旧状态。
      widget.onToggle?.call(updated, enabled);
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
        _error = null;
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
              if (widget.catalog != null) ...<Widget>[
                _buildRepoSection(Theme.of(context)),
                const SizedBox(height: 12),
              ],
              _ImportEntry(
                controller: _urlController,
                onImport: _import,
                busy: _importing || _browsing || _importingRepo,
              ),
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

  /// 「源仓库」区块：改清单地址 → 浏览 → 勾选 → 导入选中。全部由用户主动
  /// 触发，不自动安装、不为第三方源背书。
  Widget _buildRepoSection(ThemeData theme) {
    final allSelected =
        _indexEntries.isNotEmpty &&
        _selectedKeys.length == _indexEntries.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: MimaoShapes.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.library_books_outlined,
                size: 18,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                '源仓库',
                style: theme.textTheme.titleSmall?.apply(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontWeightDelta: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('comic-repo-url'),
            controller: _indexUrlController,
            enabled: !_browsing && !_importingRepo,
            decoration: const InputDecoration(
              labelText: '清单地址（index.json）',
              hintText: defaultComicSourceIndexUrl,
              isDense: true,
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _browseRepo(),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('comic-repo-browse'),
                onPressed: _browsing || _importingRepo || _importing
                    ? null
                    : _browseRepo,
                icon: _browsing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_browsing ? '读取中…' : '浏览'),
              ),
              const SizedBox(width: 8),
              if (_indexEntries.isNotEmpty)
                TextButton(
                  key: const Key('comic-repo-select-all'),
                  onPressed: _importingRepo ? null : _toggleSelectAll,
                  child: Text(allSelected ? '清空选择' : '全选'),
                ),
            ],
          ),
          if (_indexEntries.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              // 带背景色的 Container 是 DecoratedBox：ListTile 要有自己的
              // Material 祖先才画得出背景与墨水效果（否则框架断言报错）。
              child: Material(
                type: MaterialType.transparency,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _indexEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _indexEntries[index];
                    return CheckboxListTile(
                      key: Key('comic-repo-check-${entry.key}'),
                      dense: true,
                      value: _selectedKeys.contains(entry.key),
                      onChanged: _importingRepo
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                _selectedKeys.add(entry.key);
                              } else {
                                _selectedKeys.remove(entry.key);
                              }
                            }),
                      title: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.apply(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('comic-repo-import-selected'),
              onPressed: _importingRepo || _selectedKeys.isEmpty
                  ? null
                  : _importSelected,
              icon: _importingRepo
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text('导入选中（${_selectedKeys.length}）'),
            ),
          ] else if (_browsed && !_browsing)
            Padding(
              key: const Key('comic-repo-empty'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '仓库里没有可导入的源',
                style: theme.textTheme.bodySmall?.apply(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_repoMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _repoMessage!,
              key: const Key('comic-repo-message'),
              style: theme.textTheme.bodySmall?.apply(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
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
  const _ImportEntry({
    required this.controller,
    required this.onImport,
    this.busy = false,
  });

  final TextEditingController controller;
  final VoidCallback onImport;

  /// 任一导入/浏览在途时置 true：输入框与按钮禁用，防止两条写路径并发
  /// 打同一个源仓库。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: MimaoShapes.lg,
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
                  enabled: !busy,
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/source.json',
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onImport(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('import-source-button'),
                onPressed: busy ? null : onImport,
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
    // 形态走 cardTheme（无阴影 / surfaceContainerLow / r20）。
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
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
