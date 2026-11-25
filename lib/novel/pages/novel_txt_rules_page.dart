// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 「我的 → TXT 目录规则」：管理导入本地 TXT 时用的分章规则。
///
/// 与导入页里的规则弹窗共用 [NovelTxtRuleStorage]；这里没有真实文件可预览，
/// 所以只做「规则本身」的事：启停、改正则、新建、删除、恢复默认。
/// 想验证规则效果就去导入页选一个 TXT，目录预览会按当前规则实时分章。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/local/local_txt.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

class NovelTxtRulesPage extends StatefulWidget {
  const NovelTxtRulesPage({super.key, this.rules});

  /// 规则仓库；null 时页面只展示内置默认规则（只读）。
  final NovelTxtRuleStorage? rules;

  @override
  State<NovelTxtRulesPage> createState() => _NovelTxtRulesPageState();
}

class _NovelTxtRulesPageState extends State<NovelTxtRulesPage> {
  late Future<List<NovelTxtRule>> _future = _load();

  Future<List<NovelTxtRule>> _load() async {
    final storage = widget.rules;
    if (storage == null) return novelDefaultTxtRules;
    final rules = await storage.loadAll();
    return rules.isEmpty ? novelDefaultTxtRules : rules;
  }

  void _reload() => setState(() => _future = _load());

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(NovelTxtRule rule, bool enabled) async {
    final storage = widget.rules;
    if (storage == null) {
      _toast('规则仓库未启用，暂时不能修改。重启应用后再试。');
      return;
    }
    try {
      if (rule.id != 0) {
        await storage.setEnabled(rule.id, enabled);
      } else {
        await storage.save(rule.copyWith(enabled: enabled));
      }
      _reload();
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _edit(NovelTxtRule? rule) async {
    final storage = widget.rules;
    if (storage == null) {
      _toast('规则仓库未启用，暂时不能编辑。重启应用后再试。');
      return;
    }
    final result = await showDialog<NovelTxtRule>(
      context: context,
      builder: (_) => _TxtRuleEditDialog(rule: rule),
    );
    if (result == null) return;
    try {
      await storage.save(result);
      _reload();
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _delete(NovelTxtRule rule) async {
    final storage = widget.rules;
    if (storage == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除规则「${rule.name}」？'),
        content: const Text('删除后可以用「恢复默认」找回内置规则；自建规则删掉就没了。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (rule.id != 0) await storage.delete(rule.id);
      _reload();
    } on Object catch (error) {
      _toast('删除失败：$error');
    }
  }

  Future<void> _restore() async {
    final storage = widget.rules;
    if (storage == null) {
      _toast('规则仓库未启用，暂时不能恢复默认。重启应用后再试。');
      return;
    }
    try {
      await storage.restoreDefaults();
      _reload();
      _toast('已恢复内置规则');
    } on Object catch (error) {
      _toast('恢复默认失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TXT 目录规则'),
        actions: <Widget>[
          IconButton(
            tooltip: '新建规则',
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'restore') _restore();
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'restore', child: Text('恢复默认规则')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<NovelTxtRule>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const NovelLoadingState(label: '正在读取目录规则…');
          }
          if (snapshot.hasError) {
            return NovelErrorState(
              message: '${snapshot.error}',
              hint: '规则表读不出来时，导入本地 TXT 会退回内置规则；可以重试一次。',
              onRetry: _reload,
            );
          }
          final rules = snapshot.data ?? const <NovelTxtRule>[];
          if (rules.isEmpty) {
            return NovelEmptyState(
              icon: Icons.format_list_numbered,
              title: '还没有目录规则',
              message:
                  '没有规则时，导入的 TXT 会按整本一章处理。'
                  '新建一条正则规则，或用右上角菜单恢复默认规则。',
              action: FilledButton.icon(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add),
                label: const Text('新建规则'),
              ),
            );
          }
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return NovelPageContent(
            maxWidth: 880,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ListView(
              children: <Widget>[
                Text(
                  '导入本地 TXT 时按顺序尝试这些规则，命中即分章。'
                  '规则是正则，对每一行整行匹配；行太长（超过 $novelTxtTitleMaxLength 字）'
                  '会被当成正文跳过。想验证效果：去书架「添加本地书」选一个 TXT，'
                  '目录预览会按当前规则实时分章。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final rule in rules)
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
                                        rule.name.isEmpty
                                            ? '（未命名规则）'
                                            : rule.name,
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
                                  rule.pattern,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: rule.isValid
                                        ? cs.onSurfaceVariant
                                        : cs.error,
                                  ),
                                ),
                                if (!rule.isValid)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '这条正则编译不过，导入时会被跳过。',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: cs.error),
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
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 单条规则编辑：名称 + 正则，实时校验能否编译。
class _TxtRuleEditDialog extends StatefulWidget {
  const _TxtRuleEditDialog({required this.rule});

  /// null = 新建。
  final NovelTxtRule? rule;

  @override
  State<_TxtRuleEditDialog> createState() => _TxtRuleEditDialogState();
}

class _TxtRuleEditDialogState extends State<_TxtRuleEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.rule?.name ?? '',
  );
  late final TextEditingController _pattern = TextEditingController(
    text: widget.rule?.pattern ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_pattern.text.trim().isEmpty) return false;
    try {
      RegExp(_pattern.text);
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.rule == null ? '新建目录规则' : '编辑目录规则'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '规则名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pattern,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '正则表达式',
                hintText: r'^\s*第\s*[0-9一二三四五六七八九十]+\s*章',
                errorText: _pattern.text.trim().isEmpty || _valid
                    ? null
                    : '正则写错了，编译不过',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '对每一行整行匹配；用 `^` 锚定行首、`\$` 锚定行尾更稳。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
                      widget.rule ??
                      NovelTxtRule(name: '', pattern: '', enabled: true);
                  Navigator.of(context).pop(
                    base.copyWith(
                      name: _name.text.trim().isEmpty
                          ? '自建规则'
                          : _name.text.trim(),
                      pattern: _pattern.text.trim(),
                    ),
                  );
                },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
