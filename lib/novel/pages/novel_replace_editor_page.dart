// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 替换规则编辑器：规则字段可视化编辑 + 样例正文实时预览 + 本书有效替换对照。
///
/// 规则模型/执行在 `source/novel_rule_model.dart`（与阅读器共用
/// [applyReplaceRules]），因此预览看到的结果就是阅读页实际会做的；页面只
/// 负责收集字段、调仓库保存，不另写一套替换逻辑。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';

/// 预览模式：只看当前这条草稿，或看当前书命中的全部规则。
enum NovelReplacePreviewMode { single, effective }

class NovelReplaceEditorPage extends StatefulWidget {
  const NovelReplaceEditorPage({
    super.key,
    required this.store,
    this.bookId = '',
    this.bookTitle = '',
    this.sourceKey = '',
    this.bookUrl = '',
    this.sampleText = '',
    this.onHighlightRules,
  });

  final NovelReplaceRuleStorage store;

  /// 当前书上下文：作用范围判定与「有效替换」预览都按它算。
  final String bookId;
  final String bookTitle;
  final String sourceKey;
  final String bookUrl;

  /// 当前章正文；为空时用内置样例。
  final String sampleText;

  /// 可选：从替换面板跳去高亮规则（阅读页注入；独立打开时为 null）。
  final Future<void> Function()? onHighlightRules;

  @override
  State<NovelReplaceEditorPage> createState() => _NovelReplaceEditorPageState();
}

class _NovelReplaceEditorPageState extends State<NovelReplaceEditorPage> {
  static const String _defaultSample =
      '第12章 风起\n'
      '　　林间有风。广告：请收藏本站 www.example.com，本章完。\n'
      '　　他抬头看见月亮，又低下去继续赶路。';

  bool _loading = true;
  String? _loadError;
  String? _formError;
  bool _saving = false;
  List<NovelReplaceRule> _rules = const <NovelReplaceRule>[];
  String? _selectedKey;

  late final TextEditingController _name;
  late final TextEditingController _pattern;
  late final TextEditingController _replacement;
  late final TextEditingController _scope;
  late final TextEditingController _sample = TextEditingController(
    text: widget.sampleText.trim().isEmpty ? _defaultSample : widget.sampleText,
  );

  bool _isRegex = false;
  bool _enabled = true;
  bool _scopeTitle = false;
  bool _scopeContent = true;
  NovelReplacePreviewMode _previewMode = NovelReplacePreviewMode.single;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _pattern = TextEditingController();
    _replacement = TextEditingController();
    _scope = TextEditingController();
    _reload(selectFirst: true);
  }

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    _replacement.dispose();
    _scope.dispose();
    _sample.dispose();
    super.dispose();
  }

  Future<void> _reload({bool selectFirst = false, String? selectKey}) async {
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
      final key =
          selectKey ??
          (selectFirst && rules.isNotEmpty ? rules.first.key : null);
      if (key != null) {
        final match = rules.where((rule) => rule.key == key).firstOrNull;
        if (match != null) _loadRule(match);
      } else if (rules.isEmpty) {
        _newRule();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = '读取替换规则失败：$error';
        _loading = false;
      });
    }
  }

  void _newRule() {
    setState(() {
      _selectedKey = null;
      _formError = null;
      _name.text = '';
      _pattern.text = '';
      _replacement.text = '';
      _scope.text = '';
      _isRegex = false;
      _enabled = true;
      _scopeTitle = false;
      _scopeContent = true;
    });
  }

  void _loadRule(NovelReplaceRule rule) {
    setState(() {
      _selectedKey = rule.key;
      _formError = null;
      _name.text = rule.name;
      _pattern.text = rule.pattern;
      _replacement.text = rule.replacement;
      _scope.text = rule.scope;
      _isRegex = rule.isRegex;
      _enabled = rule.enabled;
      _scopeTitle = rule.scopeTitle;
      _scopeContent = rule.scopeContent;
    });
  }

  NovelReplaceRule _draft() {
    final name = _name.text.trim();
    final pattern = _pattern.text;
    final replacement = _replacement.text;
    return NovelReplaceRule(
      key: NovelReplaceRule.keyFor(
        name.isEmpty ? pattern : name,
        pattern,
        replacement,
      ),
      name: name.isEmpty ? pattern : name,
      pattern: pattern,
      replacement: replacement,
      isRegex: _isRegex,
      enabled: _enabled,
      scope: _scope.text.trim(),
      scopeTitle: _scopeTitle,
      scopeContent: _scopeContent,
      raw: const <String, dynamic>{},
    );
  }

  /// 校验并返回错误文案；null = 可以保存。
  String? _validate(NovelReplaceRule rule) {
    if (rule.pattern.isEmpty) return '「查找」不能为空';
    if (rule.isRegex) {
      try {
        RegExp(rule.pattern);
      } on Object catch (error) {
        return '正则不合法：$error';
      }
    }
    if (!rule.scopeTitle && !rule.scopeContent) {
      return '作用对象至少选一个：标题或正文';
    }
    return null;
  }

  Future<void> _save() async {
    final rule = _draft();
    final error = _validate(rule);
    if (error != null) {
      setState(() => _formError = error);
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    final previousKey = _selectedKey;
    final next = <NovelReplaceRule>[
      for (final existing in _rules)
        if (existing.key != previousKey && existing.key != rule.key) existing,
      rule,
    ];
    try {
      await widget.store.saveAll(next);
      // 改名称/查找/替换会换 key：saveAll 只增量写文件，不删旧 key，
      // 不显式删除的话旧规则会留在 manifest 里，下次加载又冒出来。
      if (previousKey != null && previousKey != rule.key) {
        await widget.store.delete(previousKey);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存；回到阅读页立即按新规则净化正文')));
      await _reload(selectKey: rule.key);
    } on Object catch (saveError) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = '保存失败：$saveError';
      });
    }
  }

  Future<void> _toggle(NovelReplaceRule rule, bool enabled) async {
    await widget.store.setEnabled(rule.key, enabled);
    await _reload(
      selectKey: _selectedKey == rule.key ? rule.key : _selectedKey,
    );
  }

  Future<void> _delete() async {
    final key = _selectedKey;
    if (key == null) return;
    final rule = _rules.where((item) => item.key == key).firstOrNull;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除替换规则「${rule?.name ?? ''}」？'),
        content: const Text('删除后阅读器不再应用这条替换。'),
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
    await widget.store.delete(key);
    await _reload(selectFirst: true);
  }

  List<NovelReplaceRule> get _effectiveRules {
    final rules = <NovelReplaceRule>[];
    for (final rule in _rules) {
      if (!rule.enabled) continue;
      if (widget.bookId.isNotEmpty &&
          !rule.appliesToBook(
            bookTitle: widget.bookTitle,
            sourceKey: widget.sourceKey,
            bookUrl: widget.bookUrl,
          )) {
        continue;
      }
      rules.add(rule);
    }
    return rules;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('替换规则'),
        actions: <Widget>[
          if (widget.onHighlightRules != null)
            TextButton.icon(
              key: const Key('novel-replace-open-highlight'),
              onPressed: () => widget.onHighlightRules!(),
              icon: const Icon(Icons.border_color_outlined, size: 18),
              label: const Text('高亮规则'),
            ),
          IconButton(
            key: const Key('novel-replace-refresh'),
            tooltip: '刷新',
            onPressed: () => _reload(selectKey: _selectedKey),
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.tonalIcon(
            key: const Key('novel-replace-new'),
            onPressed: _newRule,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建规则'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const NovelLoadingState(label: '正在读取替换规则…')
          : _loadError != null
          ? NovelErrorState(
              message: _loadError!,
              onRetry: () => _reload(selectFirst: true),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                if (!wide) {
                  return Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed: _openRulePicker,
                              icon: const Icon(Icons.list_alt, size: 18),
                              label: Text('规则列表（${_rules.length}）'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: _buildEditor()),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: 340, child: _buildRuleList()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildEditor()),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _openRulePicker() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            if (_rules.isEmpty)
              const ListTile(
                title: Text('还没有替换规则'),
                subtitle: Text('点右上角「新建规则」开始'),
              ),
            for (final rule in _rules)
              ListTile(
                key: Key('novel-replace-pick-${rule.key}'),
                leading: Icon(
                  rule.enabled
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                ),
                title: Text(rule.name),
                subtitle: Text(
                  rule.pattern,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: rule.key == _selectedKey,
                onTap: () => Navigator.of(sheetContext).pop(rule.key),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final rule = _rules.where((item) => item.key == picked).firstOrNull;
    if (rule != null) _loadRule(rule);
  }

  Widget _buildRuleList() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: <Widget>[
              Text('规则（${_rules.length}）', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                key: const Key('novel-replace-empty-new'),
                onPressed: _newRule,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rules.isEmpty
              ? NovelEmptyState(
                  icon: Icons.find_replace,
                  title: '还没有替换规则',
                  message: '新建一条规则，用右侧样例正文看效果；保存后阅读页立即生效。',
                  action: FilledButton.tonalIcon(
                    onPressed: _newRule,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建规则'),
                  ),
                )
              : ListView.separated(
                  key: const Key('novel-replace-rule-list'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: _rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    final selected = rule.key == _selectedKey;
                    return Material(
                      color: selected
                          ? cs.secondaryContainer
                          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: MimaoShapes.md,
                      child: InkWell(
                        borderRadius: MimaoShapes.md,
                        onTap: () => _loadRule(rule),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      rule.name,
                                      style: theme.textTheme.bodyMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      rule.pattern,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: rule.enabled,
                                onChanged: (value) => _toggle(rule, value),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _rules
        .where((rule) => rule.key == _selectedKey)
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                selected == null ? '新建替换规则' : '编辑：${selected.name}',
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected != null)
              TextButton.icon(
                key: const Key('novel-replace-delete'),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除'),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('novel-replace-save'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        NovelCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const Key('novel-replace-field-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: '名称（留空用查找内容）'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('novel-replace-field-pattern'),
                controller: _pattern,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '查找',
                  hintText: r'正则示例：(?<num>\d+)章',
                ),
                onChanged: (_) => setState(() => _formError = null),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('novel-replace-field-replacement'),
                controller: _replacement,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: r'替换为（支持 $1 / ${name}）',
                  hintText: r'示例：第$1章 / 第${num}章',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('novel-replace-field-scope'),
                controller: _scope,
                decoration: const InputDecoration(
                  labelText: '作用范围（留空 = 全部书籍）',
                  helperText:
                      '按书名 / 书源 key / 书源地址匹配；'
                      '&& 表示都要命中，, 、 | 分隔表示任一命中。',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  FilterChip(
                    key: const Key('novel-replace-regex'),
                    label: const Text('正则'),
                    selected: _isRegex,
                    onSelected: (value) => setState(() => _isRegex = value),
                  ),
                  FilterChip(
                    key: const Key('novel-replace-target-title'),
                    label: const Text('作用于标题'),
                    selected: _scopeTitle,
                    onSelected: (value) => setState(() => _scopeTitle = value),
                  ),
                  FilterChip(
                    key: const Key('novel-replace-target-content'),
                    label: const Text('作用于正文'),
                    selected: _scopeContent,
                    onSelected: (value) =>
                        setState(() => _scopeContent = value),
                  ),
                  FilterChip(
                    key: const Key('novel-replace-enabled'),
                    label: const Text('启用'),
                    selected: _enabled,
                    onSelected: (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
              if (_formError != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _formError!,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildPreview(theme, cs),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme, ColorScheme cs) {
    final sample = _sample.text;
    final draft = _draft();
    final validation = _validate(draft);
    final singleAfter = validation == null
        ? applyReplaceRules(sample, <NovelReplaceRule>[draft])
        : sample;
    final effective = previewReplaceRules(sample, _effectiveRules);
    final finalText = effective.isEmpty ? sample : effective.last.after;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('预览', style: theme.textTheme.titleSmall),
            const Spacer(),
            SegmentedButton<NovelReplacePreviewMode>(
              key: const Key('novel-replace-preview-mode'),
              segments: const <ButtonSegment<NovelReplacePreviewMode>>[
                ButtonSegment<NovelReplacePreviewMode>(
                  value: NovelReplacePreviewMode.single,
                  label: Text('本条规则'),
                ),
                ButtonSegment<NovelReplacePreviewMode>(
                  value: NovelReplacePreviewMode.effective,
                  label: Text('本书有效替换'),
                ),
              ],
              selected: <NovelReplacePreviewMode>{_previewMode},
              onSelectionChanged: (selection) =>
                  setState(() => _previewMode = selection.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        NovelCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const Key('novel-replace-sample'),
                controller: _sample,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '样例正文',
                  helperText: '改动或粘贴一段正文，下方结果实时更新。',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              if (_previewMode == NovelReplacePreviewMode.single)
                _previewSingle(theme, cs, validation, singleAfter)
              else
                _previewEffective(theme, cs, effective, finalText),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewSingle(
    ThemeData theme,
    ColorScheme cs,
    String? validation,
    String after,
  ) {
    if (_pattern.text.isEmpty) {
      return Text(
        '填入「查找」后，这里会显示替换前 / 替换后的对照。',
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      );
    }
    if (validation != null) {
      return Text(
        validation,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
      );
    }
    final before = _sample.text;
    final changed = before != after;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('替换前', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text(
              changed ? '已改变' : '未命中：检查「查找」是否出现在样例里',
              style: theme.textTheme.labelSmall?.copyWith(
                color: changed ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _PreviewBox(text: before, maxHeight: 160),
        const SizedBox(height: 12),
        Text('替换后', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        _PreviewBox(
          key: const Key('novel-replace-preview-after'),
          text: after,
          maxHeight: 160,
          emphasized: changed,
        ),
      ],
    );
  }

  Widget _previewEffective(
    ThemeData theme,
    ColorScheme cs,
    List<NovelReplaceOutcome> outcomes,
    String finalText,
  ) {
    final hits = <NovelReplaceOutcome>[
      for (final outcome in outcomes)
        if (outcome.matched) outcome,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.bookId.isNotEmpty)
          Text(
            '当前书：${widget.bookTitle.isEmpty ? widget.bookId : widget.bookTitle}'
            ' · 生效规则 ${outcomes.length} 条 · 命中 ${hits.length} 条',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        else
          Text(
            '没有带书上下文：这里列出全部启用规则。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 10),
        if (hits.isEmpty)
          Text(
            '样例正文没有被任何规则命中。换一段含规则关键词的正文试试。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        else
          Column(
            key: const Key('novel-replace-effective-list'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final outcome in hits) ...<Widget>[
                _EffectiveRow(outcome: outcome),
                const SizedBox(height: 8),
              ],
            ],
          ),
        if (hits.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text('最终结果', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          _PreviewBox(
            key: const Key('novel-replace-effective-final'),
            text: finalText,
            maxHeight: 160,
            emphasized: true,
          ),
        ],
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({
    super.key,
    required this.text,
    required this.maxHeight,
    this.emphasized = false,
  });

  final String text;
  final double maxHeight;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasized
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: MimaoShapes.sm,
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text.isEmpty ? '（空）' : text,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _EffectiveRow extends StatelessWidget {
  const _EffectiveRow({required this.outcome});

  final NovelReplaceOutcome outcome;

  /// 截取第一处差异附近的片段：只截开头 90 字时，命中往往在正文深处，
  /// 「前 / 后」看起来一模一样，对照就失效了。
  (String, String) _diffExcerpt(String before, String after) {
    final a = before.replaceAll(RegExp(r'\s+'), ' ').trim();
    final b = after.replaceAll(RegExp(r'\s+'), ' ').trim();
    var index = 0;
    final limit = a.length < b.length ? a.length : b.length;
    while (index < limit && a.codeUnitAt(index) == b.codeUnitAt(index)) {
      index++;
    }
    const radius = 36;
    final start = (index - radius).clamp(0, limit);
    String cut(String text) {
      final end = (index + radius).clamp(0, text.length);
      final head = start > 0 ? '…' : '';
      final tail = end < text.length ? '…' : '';
      return '$head${text.substring(start, end)}$tail';
    }

    return (cut(a), cut(b));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rule = outcome.rule;
    final targets = <String>[
      if (rule.scopeTitle) '标题',
      if (rule.scopeContent) '正文',
    ].join(' / ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: MimaoShapes.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  rule.name,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              NovelTag(label: targets.isEmpty ? '正文' : targets),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '前：${_diffExcerpt(outcome.before, outcome.after).$1}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '后：${_diffExcerpt(outcome.before, outcome.after).$2}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
