// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/anime/engine/engine.dart';
import 'package:mimao/anime/pages/anime_image_mirror.dart';

/// 番剧规则管理面板——番剧模块主页底部导航最右侧「设置」tab 的内容。
///
/// 只依赖规则引擎的存储/导入器与 Flutter：不认识壳、播放器、收藏或 core 服务，
/// 由 [AnimeModule.buildSettings] 注入依赖（docs/prompts/closure-01 §5）。
///
/// 两种导入方式并存：
/// - 仓库浏览：拉取 Kazumi 格式仓库的 `index.json`，用户勾选后按需下载导入；
/// - 自定义 URL：沿用最初的"粘贴规则 JSON 地址"入口，保留给非标准来源。
class AnimeRuleSettings extends StatefulWidget {
  const AnimeRuleSettings({
    super.key,
    required this.store,
    required this.importer,
    this.onRulesChanged,
    this.mirror,
  });

  final RuleStore store;
  final RuleImporter importer;

  /// 规则列表变动（导入/删除成功）后回调，便于数据源下次搜索即生效。
  final VoidCallback? onRulesChanged;

  /// 封面镜像开关控制器；注入后设置页顶部显示开关并即时生效。
  final AnimeImageAccelerationController? mirror;

  @override
  State<AnimeRuleSettings> createState() => _AnimeRuleSettingsState();
}

class _AnimeRuleSettingsState extends State<AnimeRuleSettings> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _repoUrlController = TextEditingController(
    text: defaultKazumiRulesBaseUrl,
  );

  bool _loading = true;
  bool _importing = false;
  bool _browsing = false;
  bool _browsed = false;
  String? _loadError;
  List<AnimeRule> _rules = const <AnimeRule>[];
  List<String> _loadFailures = const <String>[];
  List<RuleIndexEntry> _indexEntries = const <RuleIndexEntry>[];
  final Set<String> _selected = <String>{};
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _repoUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await widget.store.loadAllDetailed();
      if (!mounted) return;
      setState(() {
        _rules = result.rules;
        _loadFailures = result.failures;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = '$error';
        _loading = false;
      });
    }
  }

  /// 校验 URL：非空且为绝对 http(s) 地址。非法时不发请求。
  Uri? _parseUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Future<void> _import() async {
    if (_importing) return;
    final uri = _parseUrl(_urlController.text);
    if (uri == null) {
      setState(() => _message = '请输入合法的 http(s) 规则 URL');
      return;
    }

    setState(() {
      _importing = true;
      _message = null;
    });

    RuleImportResult result;
    try {
      result = await widget.importer.importFromUrl(uri.toString());
    } catch (error) {
      // RuleImporter 契约上不抛异常；这里仍兜底，保证导入失败不清空已有规则。
      if (mounted) {
        setState(() {
          _importing = false;
          _message = '导入失败：$error';
        });
      }
      return;
    }

    if (result.rules.isNotEmpty) {
      try {
        await widget.store.saveAll(result.rules);
      } catch (error) {
        if (mounted) {
          setState(() {
            _importing = false;
            _message = '保存规则失败：$error';
          });
        }
        return;
      }
    }

    // 重新读盘，让列表立即反映导入结果（同名覆盖 / 坏文件诊断一并刷新）。
    await _refreshKeepingMessage(
      _importMessage(result),
      changed: result.rules.isNotEmpty,
    );
  }

  /// 失败原因格式化：最多展示前 [_maxFailuresShown] 条、每条一行，
  /// 超出用"还有 N 条失败未列出"收口；空列表返回空串（调用方据此不显示失败区）。
  /// 四处失败展示复用本 helper，避免只显示 `failures.first`。
  static const int _maxFailuresShown = 5;

  String _formatFailures(List<String> failures) {
    if (failures.isEmpty) return '';
    final shown = failures.take(_maxFailuresShown).toList(growable: false);
    final buffer = StringBuffer(shown.join('\n'));
    final remaining = failures.length - shown.length;
    if (remaining > 0) {
      buffer.writeln();
      buffer.write('还有 $remaining 条失败未列出');
    }
    return buffer.toString();
  }

  String _importMessage(RuleImportResult result) {
    if (result.failures.isNotEmpty) {
      return '导入 ${result.rules.length} 条，失败 ${result.failures.length} 条：\n'
          '${_formatFailures(result.failures)}';
    }
    if (result.rules.isEmpty) return '没有可导入的规则';
    return '导入 ${result.rules.length} 条';
  }

  /// 当前仓库地址输入框里的合法根地址；非法返回 null（调用方负责提示）。
  Uri? _repoBase() => normalizeRepositoryBaseUrl(_repoUrlController.text);

  /// 拉取仓库清单，列出可导入的规则供用户勾选。
  Future<void> _browse() async {
    if (_browsing || _importing) return;
    final base = _repoBase();
    if (base == null) {
      setState(() => _message = '仓库地址不合法：只支持不含凭据的 http(s) 地址');
      return;
    }

    setState(() {
      _browsing = true;
      _browsed = true;
      _message = null;
      _indexEntries = const <RuleIndexEntry>[];
      _selected.clear();
    });

    final result = await widget.importer.fetchIndex(base.toString());
    if (!mounted) return;
    setState(() {
      _browsing = false;
      _indexEntries = result.entries;
      _message = _indexMessage(result);
    });
  }

  String _indexMessage(RuleIndexResult result) {
    if (result.failures.isNotEmpty) {
      return '读取清单 ${result.entries.length} 条，失败 ${result.failures.length} 条：\n'
          '${_formatFailures(result.failures)}';
    }
    if (result.entries.isEmpty) return '仓库里没有可导入的规则';
    return '发现 ${result.entries.length} 条规则，勾选后导入';
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _indexEntries.length) {
        _selected.clear();
      } else {
        _selected.addAll(_indexEntries.map((entry) => entry.name));
      }
    });
  }

  /// 逐个下载用户勾选的规则并一次性落盘；单条失败不影响其他规则。
  Future<void> _importSelected() async {
    if (_importing || _browsing || _selected.isEmpty) return;
    final base = _repoBase();
    if (base == null) {
      setState(() => _message = '仓库地址不合法：只支持不含凭据的 http(s) 地址');
      return;
    }

    setState(() {
      _importing = true;
      _message = null;
    });

    final rules = <AnimeRule>[];
    final failures = <String>[];
    final names = _selected.toList()..sort();
    for (final name in names) {
      try {
        final result = await widget.importer.importFromUrl(
          widget.importer.ruleUrl(base.toString(), name),
        );
        rules.addAll(result.rules);
        for (final failure in result.failures) {
          failures.add('$name：$failure');
        }
      } catch (error) {
        failures.add('$name：$error');
      }
    }

    if (rules.isNotEmpty) {
      try {
        await widget.store.saveAll(rules);
      } catch (error) {
        if (mounted) {
          setState(() {
            _importing = false;
            _message = '保存规则失败：$error';
          });
        }
        return;
      }
    }

    await _refreshKeepingMessage(
      _repoImportMessage(rules.length, failures),
      changed: rules.isNotEmpty,
    );
  }

  String _repoImportMessage(int count, List<String> failures) {
    if (failures.isNotEmpty) {
      return '导入 $count 条，失败 ${failures.length} 条：\n'
          '${_formatFailures(failures)}';
    }
    if (count == 0) return '没有可导入的规则';
    return '导入 $count 条';
  }

  Future<void> _refreshKeepingMessage(
    String message, {
    required bool changed,
  }) async {
    try {
      final result = await widget.store.loadAllDetailed();
      if (!mounted) return;
      setState(() {
        _rules = result.rules;
        _loadFailures = result.failures;
        _importing = false;
        _message = message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = '$error';
        _importing = false;
        _message = message;
      });
    }
    if (changed && mounted) widget.onRulesChanged?.call();
  }

  Future<void> _confirmDelete(AnimeRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('确定删除规则「${rule.name}」？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('anime-rule-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.store.delete(rule.name);
    } catch (error) {
      if (mounted) setState(() => _message = '删除失败：$error');
      return;
    }
    await _refreshKeepingMessage('已删除「${rule.name}」', changed: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.mirror != null) ...<Widget>[
            _buildMirrorSection(theme),
            const Divider(height: 24),
          ],
          _buildRepositorySection(theme),
          const Divider(height: 24),
          TextField(
            key: const Key('anime-rule-url'),
            controller: _urlController,
            enabled: !_importing,
            // 边框/填充形态由 inputDecorationTheme 统一（MD3 填充式 r12）。
            decoration: const InputDecoration(
              labelText: '自定义规则 URL',
              hintText: 'https://…/rules.json',
              isDense: true,
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _import(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('anime-rule-import'),
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(_importing ? '导入中…' : '导入'),
          ),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _message!,
              key: const Key('anime-rule-message'),
              style: theme.textTheme.bodySmall?.apply(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('已安装规则', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          _buildRuleList(theme),
        ],
      ),
    );
  }

  /// 图片加速：对齐 Kazumi 的 direct/mirror 两态选择（ECH 需原生依赖，不引入）。
  Widget _buildMirrorSection(ThemeData theme) {
    final controller = widget.mirror!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.image_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text('图片加速', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<AnimeImageAcceleration>(
          valueListenable: controller,
          builder: (context, mode, _) =>
              SegmentedButton<AnimeImageAcceleration>(
                key: const Key('anime-image-acceleration'),
                segments: <ButtonSegment<AnimeImageAcceleration>>[
                  for (final option in AnimeImageAcceleration.values)
                    ButtonSegment<AnimeImageAcceleration>(
                      value: option,
                      label: Text(option.label),
                      icon: Icon(
                        option == AnimeImageAcceleration.direct
                            ? Icons.public_outlined
                            : Icons.speed_outlined,
                      ),
                    ),
                ],
                selected: <AnimeImageAcceleration>{mode},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) controller.set(selected.first);
                },
              ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<AnimeImageAcceleration>(
          valueListenable: controller,
          builder: (context, mode, _) => Text(
            mode.description,
            key: const Key('anime-image-acceleration-desc'),
            style: theme.textTheme.bodySmall?.apply(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// Kazumi 格式仓库区块：改地址 → 浏览清单 → 勾选 → 导入选中。
  Widget _buildRepositorySection(ThemeData theme) {
    final installed = _rules.map((rule) => rule.name).toSet();
    final allSelected =
        _indexEntries.isNotEmpty && _selected.length == _indexEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Kazumi 规则仓库', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          key: const Key('anime-repo-url'),
          controller: _repoUrlController,
          enabled: !_browsing && !_importing,
          decoration: const InputDecoration(
            labelText: '仓库地址',
            hintText: defaultKazumiRulesBaseUrl,
            isDense: true,
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _browse(),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              key: const Key('anime-repo-browse'),
              onPressed: _browsing || _importing ? null : _browse,
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
                key: const Key('anime-repo-select-all'),
                onPressed: _importing ? null : _toggleSelectAll,
                child: Text(allSelected ? '清空选择' : '全选'),
              ),
          ],
        ),
        if (_indexEntries.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _indexEntries.length,
              itemBuilder: (context, index) {
                final entry = _indexEntries[index];
                final isInstalled = installed.contains(entry.name);
                return CheckboxListTile(
                  key: Key('anime-repo-check-${entry.name}'),
                  dense: true,
                  value: _selected.contains(entry.name),
                  onChanged: _importing
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(entry.name);
                          } else {
                            _selected.remove(entry.name);
                          }
                        }),
                  title: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'v${entry.version.isEmpty ? '—' : entry.version} · '
                    '${entry.lastUpdateLabel}${isInstalled ? ' · 已安装' : ''}',
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
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('anime-repo-import-selected'),
            onPressed: _importing || _selected.isEmpty ? null : _importSelected,
            icon: const Icon(Icons.download_outlined),
            label: Text('导入选中（${_selected.length}）'),
          ),
        ] else if (_browsed && !_browsing)
          Padding(
            key: const Key('anime-repo-empty'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '仓库里没有可导入的规则',
              style: theme.textTheme.bodySmall?.apply(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRuleList(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '读取规则失败：$_loadError',
              style: theme.textTheme.bodySmall?.apply(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('anime-rule-retry'),
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_rules.isEmpty)
          Padding(
            key: const Key('anime-rule-empty'),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '还没有规则，先从 KazumiRules 导入',
              style: theme.textTheme.bodyMedium?.apply(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final rule in _rules)
            _RuleTile(rule: rule, onDelete: () => _confirmDelete(rule)),
        if (_loadFailures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '读取时跳过 ${_loadFailures.length} 个坏文件：\n'
              '${_formatFailures(_loadFailures)}',
              key: const Key('anime-rule-load-failures'),
              style: theme.textTheme.bodySmall?.apply(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.rule, required this.onDelete});

  final AnimeRule rule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('anime-rule-item-${rule.name}'),
      dense: true,
      title: Text(rule.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'v${rule.version.isEmpty ? '—' : rule.version} · ${rule.baseUrl.isEmpty ? '—' : rule.baseUrl}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.apply(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        key: Key('anime-rule-delete-${rule.name}'),
        tooltip: '删除',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}
