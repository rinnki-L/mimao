// ignore_for_file: deprecated_member_use — 与其他小说页面同款 Flutter 3.50 说明。
/// 「导入规则」弹窗：挑规则类型（含自动识别）→ 粘贴链接 → 下载落库。
///
/// 书源 / 订阅源 / 替换规则共用这一个入口：类型手选优先，自动识别按文件内容
/// 判断；深链 host 也带着类型，所以从网站点「一键导入」时不用再选。
/// 订阅页与规则管理页都用这个弹窗，避免两处导入逻辑漂移。
library;

import 'package:flutter/material.dart';

import '../source/novel_rule_model.dart';
import '../source/novel_source_importer.dart';

/// 弹出导入规则对话框；成功返回导入结果，取消返回 null。
Future<NovelSourceImportResult?> showNovelRuleImportDialog(
  BuildContext context, {
  required NovelSourceImporter importer,
  NovelRuleKind? initialKind,
  bool allowTypeSwitch = true,
}) {
  return showDialog<NovelSourceImportResult>(
    context: context,
    builder: (_) => _NovelRuleImportDialog(
      importer: importer,
      initialKind: initialKind,
      allowTypeSwitch: allowTypeSwitch,
    ),
  );
}

class _NovelRuleImportDialog extends StatefulWidget {
  const _NovelRuleImportDialog({
    required this.importer,
    this.initialKind,
    this.allowTypeSwitch = true,
  });

  final NovelSourceImporter importer;
  final NovelRuleKind? initialKind;

  /// 从某个分类进来时锁死类型（不显示类型 chip）；订阅页的总入口才允许切换。
  final bool allowTypeSwitch;

  @override
  State<_NovelRuleImportDialog> createState() => _NovelRuleImportDialogState();
}

class _NovelRuleImportDialogState extends State<_NovelRuleImportDialog> {
  late NovelRuleKind? _kind = widget.initialKind;
  final TextEditingController _controller = TextEditingController();
  bool _importing = false;
  String? _error;

  String get _title {
    final kind = _kind;
    if (!widget.allowTypeSwitch && kind != null) return '导入${kind.label}';
    return '导入规则';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_importing) return;
    final link = _controller.text.trim();
    if (link.isEmpty) {
      setState(() => _error = '先粘贴规则链接或规则文件地址');
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await widget.importer.importFromLink(link, kind: _kind);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on NovelSourceImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.allowTypeSwitch) ...<Widget>[
              Text(
                '书源、订阅源、替换规则分别保存。类型可以自动识别，也可以手动指定。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('自动识别'),
                    selected: _kind == null,
                    onSelected: _importing
                        ? null
                        : (_) => setState(() => _kind = null),
                  ),
                  for (final kind in NovelRuleKind.values)
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: _kind == kind,
                      onSelected: _importing
                          ? null
                          : (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              key: const Key('novel-rule-import-link'),
              controller: _controller,
              enabled: !_importing,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '规则链接',
                hintText: 'https://… 或 yuedu://…importonline?src=…',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_importing) ...<Widget>[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
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
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('novel-rule-import-submit'),
          onPressed: _importing ? null : _submit,
          child: const Text('导入'),
        ),
      ],
    );
  }
}
