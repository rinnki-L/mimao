// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/anime/engine/engine.dart';

/// 番剧规则管理面板——全局设置抽屉里"番剧"分组的内容。
///
/// 只依赖规则引擎的存储/导入器与 Flutter：不认识壳、播放器、收藏或 core 服务，
/// 由 [AnimeModule.buildSettings] 注入依赖（docs/prompts/closure-01 §5）。
class AnimeRuleSettings extends StatefulWidget {
  const AnimeRuleSettings({
    super.key,
    required this.store,
    required this.importer,
    this.onRulesChanged,
  });

  final RuleStore store;
  final RuleImporter importer;

  /// 规则列表变动（导入/删除成功）后回调，便于数据源下次搜索即生效。
  final VoidCallback? onRulesChanged;

  @override
  State<AnimeRuleSettings> createState() => _AnimeRuleSettingsState();
}

class _AnimeRuleSettingsState extends State<AnimeRuleSettings> {
  final TextEditingController _urlController = TextEditingController();

  bool _loading = true;
  bool _importing = false;
  String? _loadError;
  List<AnimeRule> _rules = const <AnimeRule>[];
  List<String> _loadFailures = const <String>[];
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
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

  String _importMessage(RuleImportResult result) {
    if (result.failures.isNotEmpty) {
      return '导入 ${result.rules.length} 条，失败 ${result.failures.length} 条：'
          '${result.failures.first}';
    }
    if (result.rules.isEmpty) return '没有可导入的规则';
    return '导入 ${result.rules.length} 条';
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
          TextField(
            key: const Key('anime-rule-url'),
            controller: _urlController,
            enabled: !_importing,
            decoration: const InputDecoration(
              labelText: 'KazumiRules URL',
              hintText: 'https://…/rules.json',
              border: OutlineInputBorder(),
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
              '读取时跳过 ${_loadFailures.length} 个坏文件：${_loadFailures.first}',
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
