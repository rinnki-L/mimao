// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 「我的 → 字典规则」：规则管理 + 直接查词。
///
/// 规则与查询共用同一套服务（`novel_dict_service.dart`）；阅读页的选词「词典」
/// 也复用本文件的 [NovelDictResults] / [showNovelDictSheet]，两处看到的解析
/// 结果一致。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/dict/novel_dict_rule.dart';
import 'package:mimao/novel/dict/novel_dict_service.dart';
import 'package:mimao/novel/file_gate.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

class NovelDictPage extends StatefulWidget {
  const NovelDictPage({
    super.key,
    required this.store,
    required this.lookup,
    this.fileGate,
    this.initialWord,
  });

  final NovelDictRuleStorage store;
  final NovelDictLookup lookup;

  /// 导入 JSON 用的文件缝；null = 只支持粘贴文本。
  final NovelJsonFileGate? fileGate;

  /// 直接带一个词进入并自动查询（深链/截图验收用）。
  final String? initialWord;

  @override
  State<NovelDictPage> createState() => _NovelDictPageState();
}

class _NovelDictPageState extends State<NovelDictPage> {
  final TextEditingController _word = TextEditingController();
  bool _loading = true;
  String? _loadError;
  List<NovelDictRule> _rules = const <NovelDictRule>[];

  bool _querying = false;
  String _queriedWord = '';
  String? _queryError;
  List<NovelDictResult> _results = const <NovelDictResult>[];

  @override
  void initState() {
    super.initState();
    final word = widget.initialWord?.trim() ?? '';
    if (word.isNotEmpty) _word.text = word;
    _reload().then((_) {
      if (word.isNotEmpty) _query();
    });
  }

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rules = await widget.store.loadAll();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } on Object catch (error) {
      debugPrint('novel: 读取词典规则失败: $error');
      if (!mounted) return;
      setState(() {
        _loadError = '读取词典规则失败：本地库暂时打不开。';
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _query() async {
    final input = _word.text.trim();
    final word = normalizeNovelDictWord(input);
    if (word.isEmpty) {
      _toast('先输入一个要查的词');
      return;
    }
    if (input.length != word.length) {
      _toast('查询词太长，已截取前 ${word.length} 个字');
    }
    setState(() {
      _querying = true;
      _queriedWord = word;
      _queryError = null;
      _results = const <NovelDictResult>[];
    });
    try {
      final enabled = <NovelDictRule>[
        for (final rule in _rules)
          if (rule.enabled && rule.isValid) rule,
      ];
      if (enabled.isEmpty) {
        setState(() {
          _querying = false;
          _queryError = '没有启用的词典规则。先启用一条（或恢复默认规则）再查。';
        });
        return;
      }
      final results = await widget.lookup.lookupAll(enabled, word);
      if (!mounted) return;
      setState(() {
        _results = results;
        _querying = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _queryError = '查询失败：$error';
        _querying = false;
      });
    }
  }

  Future<void> _toggle(NovelDictRule rule, bool enabled) async {
    final id = rule.id;
    if (id == null) return;
    try {
      await widget.store.setEnabled(id, enabled);
      await _reload();
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _edit([NovelDictRule? rule]) async {
    final saved = await showDialog<NovelDictRule>(
      context: context,
      builder: (_) => _DictRuleDialog(rule: rule),
    );
    if (saved == null) return;
    try {
      await widget.store.save(saved);
      await _reload();
      _toast(rule == null ? '已新建词典规则' : '已保存');
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _delete(NovelDictRule rule) async {
    final id = rule.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除词典「${rule.name}」？'),
        content: const Text('内置规则删掉后可以用「恢复默认规则」找回；自建规则删掉就没了。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.delete(id);
      await _reload();
    } on Object catch (error) {
      _toast('删除失败：$error');
    }
  }

  Future<void> _import() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _DictImportDialog(fileGate: widget.fileGate),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final rules = decodeNovelDictRules(text);
      await widget.store.replaceAll(rules);
      await _reload();
      _toast('已导入 ${rules.length} 条词典规则');
    } on FormatException catch (error) {
      _toast('导入失败：${error.message}');
    } on Object catch (error) {
      _toast('导入失败：$error');
    }
  }

  Future<void> _restore() async {
    try {
      await widget.store.restoreDefaults();
      await _reload();
      _toast('已恢复内置词典规则');
    } on Object catch (error) {
      _toast('恢复默认失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('字典规则'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.tonalIcon(
            key: const Key('novel-dict-new'),
            onPressed: () => _edit(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建规则'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'import') _import();
              if (value == 'restore') _restore();
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('导入规则 JSON'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('恢复默认规则'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: NovelPageContent(
        maxWidth: 900,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: _loading
            ? const NovelLoadingState(label: '正在读取词典规则…')
            : _loadError != null
            ? NovelErrorState(
                message: _loadError!,
                hint: '可以重试一次；反复失败就退出应用重启，让本地库重新打开。',
                onRetry: _reload,
              )
            : ListView(
                children: <Widget>[
                  _buildQueryCard(context),
                  if (_querying ||
                      _queryError != null ||
                      _results.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    NovelDictResults(
                      word: _queriedWord,
                      loading: _querying,
                      error: _queryError,
                      results: _results,
                    ),
                  ],
                  const SizedBox(height: 22),
                  _buildRulesSection(context),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildQueryCard(BuildContext context) {
    final theme = Theme.of(context);
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('novel-dict-word'),
            controller: _word,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _query(),
            decoration: InputDecoration(
              labelText: '查词',
              hintText: '输入一个词，按启用规则逐个站点查询',
              prefixIcon: const Icon(Icons.translate),
              suffixIcon: _querying
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      key: const Key('novel-dict-search'),
                      tooltip: '查询',
                      icon: const Icon(Icons.search),
                      onPressed: _query,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '阅读页里选中一段文字，选区菜单的「词典」会用同一套规则解析；'
            '这里也可以直接手输。规则地址里的 {{key}} 会替换成查询词。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('词典规则', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            NovelTag(label: '${_rules.length} 条'),
            const Spacer(),
            TextButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('导入 JSON'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_rules.isEmpty)
          NovelEmptyState(
            icon: Icons.translate,
            title: '还没有词典规则',
            message:
                '用右上角「新建规则」加一条（地址 + 解析规则），'
                '或从 Legado 的 dictRules.json 导入。没有规则时查词不会发请求。',
            action: FilledButton.tonalIcon(
              onPressed: _import,
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('导入规则'),
            ),
          )
        else
          for (final rule in _rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NovelCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Switch(
                      value: rule.enabled,
                      onChanged: (value) => _toggle(rule, value),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  rule.name.isEmpty ? '（未命名规则）' : rule.name,
                                  style: theme.textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (rule.builtin) ...<Widget>[
                                const SizedBox(width: 8),
                                const NovelTag(label: '内置'),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            rule.urlRule,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (rule.showRule.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              '解析：${rule.showRule}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      onPressed: () => _edit(rule),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '删除',
                      onPressed: () => _delete(rule),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// 查询结果面板（页面与阅读页选区「词典」共用）。
class NovelDictResults extends StatelessWidget {
  const NovelDictResults({
    super.key,
    required this.word,
    required this.loading,
    required this.results,
    this.error,
  });

  final String word;
  final bool loading;
  final List<NovelDictResult> results;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.translate, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  word.isEmpty ? '查询结果' : '「$word」的查询结果',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          for (final result in results) ...<Widget>[
            const SizedBox(height: 14),
            _ResultBlock(result: result),
          ],
        ],
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.result});

  final NovelDictResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: MimaoShapes.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                result.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: result.ok ? cs.primary : cs.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.ruleName,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: result.ok ? cs.primary : cs.error,
                  ),
                ),
              ),
              if (result.url.isNotEmpty)
                IconButton(
                  tooltip: '复制查询链接',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.link, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: result.url));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('链接已复制')));
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (result.error != null)
            Text(
              result.error!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            )
          else
            SelectableText(result.text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// 阅读页选区「词典」底部面板。
///
/// 自己加载启用规则再查询：阅读页只传「词 + 服务 + 仓库」，不在这里存规则快照，
/// 用户在词典页刚改的规则下一次查词就生效。
Future<void> showNovelDictSheet(
  BuildContext context, {
  required String word,
  required NovelDictRuleStorage store,
  required NovelDictLookup lookup,
  ThemeData? theme,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme?.colorScheme.surfaceContainerLow,
    builder: (sheetContext) {
      final content = Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.paddingOf(sheetContext).bottom + 20,
        ),
        child: NovelDictSheet(word: word, store: store, lookup: lookup),
      );
      return theme == null ? content : Theme(data: theme, child: content);
    },
  );
}

/// 面板主体（独立成 widget 便于测试直接 pump）。
class NovelDictSheet extends StatefulWidget {
  const NovelDictSheet({
    super.key,
    required this.word,
    required this.store,
    required this.lookup,
  });

  final String word;
  final NovelDictRuleStorage store;
  final NovelDictLookup lookup;

  @override
  State<NovelDictSheet> createState() => _NovelDictSheetState();
}

class _NovelDictSheetState extends State<NovelDictSheet> {
  late final String _word = normalizeNovelDictWord(widget.word);
  bool _loading = true;
  String? _error;
  List<NovelDictResult> _results = const <NovelDictResult>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_word.isEmpty) {
      setState(() {
        _loading = false;
        _error = '没选中可查的文字';
      });
      return;
    }
    try {
      final rules = <NovelDictRule>[
        for (final rule in await widget.store.loadAll())
          if (rule.enabled && rule.isValid) rule,
      ];
      if (rules.isEmpty) {
        setState(() {
          _loading = false;
          _error = '没有启用的词典规则。到「我的 → 字典规则」启用或导入一条再试。';
        });
        return;
      }
      final results = await widget.lookup.lookupAll(rules, _word);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '查询失败：$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _word.isEmpty ? '词典' : _word,
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            NovelDictResults(
              word: _word,
              loading: _loading,
              error: _error,
              results: _results,
            ),
          ],
        ),
      ),
    );
  }
}

/// 规则编辑对话框：地址 + 解析规则 + 启停。
class _DictRuleDialog extends StatefulWidget {
  const _DictRuleDialog({this.rule});

  final NovelDictRule? rule;

  @override
  State<_DictRuleDialog> createState() => _DictRuleDialogState();
}

class _DictRuleDialogState extends State<_DictRuleDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.rule?.name ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.rule?.urlRule ?? '',
  );
  late final TextEditingController _show = TextEditingController(
    text: widget.rule?.showRule ?? '',
  );
  late bool _enabled = widget.rule?.enabled ?? true;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _show.dispose();
    super.dispose();
  }

  bool get _valid =>
      _url.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.rule == null ? '新建词典规则' : '编辑词典规则'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: '名称（站点名）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '查询地址',
                  hintText: 'https://www.zdic.net/hans/{{key}}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _show,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '解析规则（可空）',
                  hintText: '#jbjs@html 或 tag.body@all；留空 = 显示整页正文',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Switch(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  const SizedBox(width: 8),
                  const Text('启用'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '{{key}} 会替换成查询词（自动做 URL 编码）；'
                '「解析规则」与书源选择器同一套写法。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: !_valid
              ? null
              : () {
                  final base =
                      widget.rule ?? const NovelDictRule(name: '', urlRule: '');
                  Navigator.of(context).pop(
                    base.copyWith(
                      name: _name.text.trim(),
                      urlRule: _url.text.trim(),
                      showRule: _show.text.trim(),
                      enabled: _enabled,
                    ),
                  );
                },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 导入对话框：粘贴 JSON（也可从文件读）。
class _DictImportDialog extends StatefulWidget {
  const _DictImportDialog({this.fileGate});

  final NovelJsonFileGate? fileGate;

  @override
  State<_DictImportDialog> createState() => _DictImportDialogState();
}

class _DictImportDialogState extends State<_DictImportDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final gate = widget.fileGate;
    if (gate == null) return;
    try {
      final file = await gate.pick(dialogTitle: '选择词典规则 JSON');
      if (file == null || !mounted) return;
      setState(() {
        _text.text = file.text;
        _error = null;
      });
    } on Object catch (error) {
      setState(() => _error = '读取文件失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入词典规则'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: '规则 JSON',
                hintText: '粘贴 Legado 的 dictRules.json，或单个规则对象',
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        if (widget.fileGate != null)
          TextButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: const Text('从文件读取'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('导入'),
        ),
      ],
    );
  }
}
