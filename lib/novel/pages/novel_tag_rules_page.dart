// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 「我的 → 标签规则」：正则命中分类标签/书名 → 给书打一个（带颜色的）标签。
///
/// 标签写入书架分组（同一个 `groupName` 列，既有分组筛选直接可用），并且
/// **只加不减**：已有分组的书一律不覆盖。页面负责预览命中与手动应用，
/// 规则本身不自动往书上写。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/file_gate.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/tags/novel_tag_rule_service.dart';
import 'package:mimao/novel/tags/novel_tag_rules.dart';

/// 标签配色候选（用户数据，按 ARGB 存；null = 跟随主题默认色）。
const List<int> novelTagColorPresets = <int>[
  0xFFB3261E,
  0xFFE8710A,
  0xFFF9A825,
  0xFF2E7D32,
  0xFF00838F,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFF4E342E,
];

class NovelTagRulesPage extends StatefulWidget {
  const NovelTagRulesPage({super.key, required this.store, this.fileGate});

  final NovelTagRuleStorage store;

  /// 导入/导出 JSON 的文件缝；null = 只支持粘贴/复制文本。
  final NovelJsonFileGate? fileGate;

  @override
  State<NovelTagRulesPage> createState() => _NovelTagRulesPageState();
}

class _NovelTagRulesPageState extends State<NovelTagRulesPage> {
  bool _loading = true;
  String? _error;
  List<NovelTagRule> _rules = const <NovelTagRule>[];
  NovelTagApplyResult? _lastApply;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await widget.store.loadAll();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } on Object catch (error) {
      debugPrint('novel: 读取标签规则失败: $error');
      if (!mounted) return;
      setState(() {
        _error = '读取标签规则失败：本地库暂时打不开。';
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

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      final result = await widget.store.applyToShelf();
      if (!mounted) return;
      setState(() {
        _lastApply = result;
        _applying = false;
      });
      _toast(
        result.matched == 0
            ? '没有书命中当前规则；检查正则，或给书补分类标签'
            : '已应用：新打标 ${result.updated} 本，'
                  '保留原分组 ${result.kept} 本'
                  '${result.affectedNames.isEmpty ? '' : '（${result.affectedNames.join('、')}）'}',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      _toast('应用失败：$error');
    }
  }

  Future<void> _edit([NovelTagRule? rule]) async {
    final saved = await showDialog<NovelTagRule>(
      context: context,
      builder: (_) => _TagRuleDialog(rule: rule),
    );
    if (saved == null) return;
    try {
      await widget.store.save(saved);
      await _reload();
      _toast(rule == null ? '已新建标签规则' : '已保存');
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _toggle(NovelTagRule rule, bool enabled) async {
    final id = rule.id;
    if (id == null) return;
    try {
      await widget.store.setEnabled(id, enabled);
      await _reload();
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _delete(NovelTagRule rule) async {
    final id = rule.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除标签规则「${rule.name}」？'),
        content: const Text('已经写到书架上的分组不会被撤回（只加不减）；需要时在书架里手动改分组。'),
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
      builder: (_) => _TagImportDialog(fileGate: widget.fileGate),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final rules = decodeNovelTagRules(text);
      await widget.store.replaceAll(rules);
      await _reload();
      _toast('已导入 ${rules.length} 条标签规则');
    } on FormatException catch (error) {
      _toast('导入失败：${error.message}');
    } on Object catch (error) {
      _toast('导入失败：$error');
    }
  }

  Future<void> _export() async {
    if (_rules.isEmpty) {
      _toast('还没有规则可导出');
      return;
    }
    final json = encodeNovelTagRules(_rules);
    final gate = widget.fileGate;
    if (gate == null) {
      _toast('导出需要文件选择器；当前环境不支持。');
      return;
    }
    try {
      final path = await gate.save(
        'mimao-tag-rules.json',
        Uint8List.fromList(utf8.encode(json)),
        dialogTitle: '导出标签规则',
      );
      if (path == null) return;
      _toast('已导出到 $path');
    } on Object catch (error) {
      _toast('导出失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签规则'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.tonalIcon(
            key: const Key('novel-tag-new'),
            onPressed: () => _edit(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建规则'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'import') _import();
              if (value == 'export') _export();
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
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.save_alt),
                  title: Text('导出规则 JSON'),
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
            ? const NovelLoadingState(label: '正在读取标签规则…')
            : _error != null
            ? NovelErrorState(
                message: _error!,
                hint: '可以重试一次；反复失败就退出应用重启，让本地库重新打开。',
                onRetry: _reload,
              )
            : ListView(
                children: <Widget>[
                  _buildApplyCard(context),
                  const SizedBox(height: 18),
                  if (_rules.isEmpty)
                    NovelEmptyState(
                      icon: Icons.sell_outlined,
                      title: '还没有标签规则',
                      message:
                          '规则 = 正则 + 标签名：命中书的分类标签（书源给的 kind）或书名，'
                          '就给书打上这个标签。例如正则「修[真仙]」→ 标签「修仙」。',
                      action: FilledButton.tonalIcon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建第一条规则'),
                      ),
                    )
                  else
                    for (final rule in _rules)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildRuleCard(context, rule),
                      ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildApplyCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final last = _lastApply;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.local_offer_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('按规则给书架打标签', style: theme.textTheme.titleMedium),
              ),
              FilledButton.icon(
                key: const Key('novel-tag-apply'),
                onPressed: _applying || _rules.isEmpty ? null : _apply,
                icon: _applying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_check, size: 18),
                label: const Text('应用到书架'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '标签写在书架分组上，所以「书架 → 分组筛选」直接能筛；'
            '只加不减：已经有分组的书不会被规则覆盖。'
            '规则不自动执行，改完点「应用到书架」才生效。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (last != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: MimaoShapes.sm,
              ),
              child: Text(
                '上次应用：命中 ${last.matched} 本 · 新打标 ${last.updated} 本 · '
                '保留原分组 ${last.kept} 本'
                '${last.affectedNames.isEmpty ? '' : ' · 标签：${last.affectedNames.join('、')}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRuleCard(BuildContext context, NovelTagRule rule) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = rule.colorArgb == null ? null : Color(rule.colorArgb!);
    final regex = compileNovelTagPattern(rule.pattern);
    return NovelCard(
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
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color ?? cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        rule.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  rule.pattern,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: regex == null ? cs.error : cs.onSurfaceVariant,
                  ),
                ),
                if (regex == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '这条正则编译不过，应用时会被跳过。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                      ),
                    ),
                  ),
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
    );
  }
}

/// 规则编辑：名称 + 正则（实时校验/命中预览）+ 颜色。
class _TagRuleDialog extends StatefulWidget {
  const _TagRuleDialog({this.rule});

  final NovelTagRule? rule;

  @override
  State<_TagRuleDialog> createState() => _TagRuleDialogState();
}

class _TagRuleDialogState extends State<_TagRuleDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.rule?.name ?? '',
  );
  late final TextEditingController _pattern = TextEditingController(
    text: widget.rule?.pattern ?? '',
  );
  late final TextEditingController _sample = TextEditingController(
    text: '玄幻，修真，都市',
  );
  late int? _color = widget.rule?.colorArgb;

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    _sample.dispose();
    super.dispose();
  }

  RegExp? get _regex => compileNovelTagPattern(_pattern.text);

  bool get _valid =>
      _name.text.trim().isNotEmpty && _regex != null && _sampleMatch;

  bool get _sampleMatch {
    final regex = _regex;
    if (regex == null) return false;
    final tags = splitNovelKindTags(_sample.text);
    if (tags.any(regex.hasMatch)) return true;
    return regex.hasMatch(_sample.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: Text(widget.rule == null ? '新建标签规则' : '编辑标签规则'),
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
                decoration: const InputDecoration(
                  labelText: '标签名（= 书架分组名）',
                  hintText: '修仙',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pattern,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '正则表达式',
                  hintText: r'修[真仙]|凡人流',
                  errorText: _pattern.text.trim().isEmpty || _regex != null
                      ? null
                      : '正则写错了，编译不过',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sample,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: '命中预览（逗号分隔的分类标签）'),
              ),
              const SizedBox(height: 6),
              Text(
                _regex == null
                    ? '先写一条能编译的正则。'
                    : _sampleMatch
                    ? '✓ 这条规则会命中示例'
                    : '✗ 这条规则不会命中示例（可能本来就该如此）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _regex != null && _sampleMatch
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text('标签颜色', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  _ColorDot(
                    key: const Key('novel-tag-color-default'),
                    color: null,
                    selected: _color == null,
                    onTap: () => setState(() => _color = null),
                  ),
                  for (final argb in novelTagColorPresets)
                    _ColorDot(
                      color: Color(argb),
                      selected: _color == argb,
                      onTap: () => setState(() => _color = argb),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '匹配对象：书的分类标签（书源给的 kind，逗号/顿号分隔）与书名。'
                '本地书没有分类标签，靠书名命中。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
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
                      widget.rule ?? const NovelTagRule(name: '', pattern: '');
                  Navigator.of(context).pop(
                    base.copyWith(
                      name: _name.text.trim(),
                      pattern: _pattern.text.trim(),
                      colorArgb: _color,
                      clearColor: _color == null,
                    ),
                  );
                },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: MimaoShapes.pill,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 18,
                color: color == null ? cs.primary : cs.onPrimary,
              )
            : null,
      ),
    );
  }
}

/// 导入对话框：粘贴 JSON 或从文件读。
class _TagImportDialog extends StatefulWidget {
  const _TagImportDialog({this.fileGate});

  final NovelJsonFileGate? fileGate;

  @override
  State<_TagImportDialog> createState() => _TagImportDialogState();
}

class _TagImportDialogState extends State<_TagImportDialog> {
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
      final file = await gate.pick(dialogTitle: '选择标签规则 JSON');
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
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('导入标签规则'),
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
                hintText: '[{"name":"修仙","pattern":"修真"}]',
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
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
