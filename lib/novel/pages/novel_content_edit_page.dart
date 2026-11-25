// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 单章正文编辑：改当前章正文并落本地覆盖，随时可恢复原样。
///
/// 覆盖只在写库时发生一次（[NovelContentOverrides] 一张表），阅读器下次打开
/// 这一章优先用它；页面本身不碰网络，也不改替换规则——保存后的文本就是
/// 用户要看的最终文本。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/reader/novel_reader_controller.dart';

class NovelContentEditPage extends StatefulWidget {
  const NovelContentEditPage({super.key, required this.controller});

  final NovelReaderController controller;

  @override
  State<NovelContentEditPage> createState() => _NovelContentEditPageState();
}

class _NovelContentEditPageState extends State<NovelContentEditPage> {
  late final TextEditingController _text = TextEditingController(
    text: (widget.controller.content?.paragraphs ?? const <String>[]).join(
      '\n',
    ),
  );
  bool _hasOverride = false;
  bool _busy = false;
  bool _loadingOverride = true;

  /// 本地覆盖状态读取失败：页面给「重试读取」而不是假装「没有覆盖」。
  bool _overrideReadFailed = false;

  /// 保存/恢复失败的错误文案；非空时页面顶部给重试按钮。
  String? _actionError;
  bool _retryIsRestore = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOverrideState());
  }

  Future<void> _loadOverrideState() async {
    final has = await widget.controller.readChapterOverrideState();
    if (!mounted) return;
    setState(() {
      _hasOverride = has ?? false;
      _overrideReadFailed = has == null;
      _loadingOverride = false;
      if (has != null) _actionError = null;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _paragraphs() => <String>[
    for (final line in _text.text.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) line,
  ];

  Future<void> _save() async {
    final paragraphs = _paragraphs();
    if (paragraphs.isEmpty) {
      _toast('正文不能为空：至少保留一段，再点保存');
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    final ok = await widget.controller.saveChapterOverride(paragraphs);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _actionError = '保存失败：本地库暂时不可写。可重试；仍不行就退出后重启应用。';
        _retryIsRestore = false;
      }
    });
    if (!ok) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复原样？'),
        content: const Text('会删除这一章的本地覆盖，回到网络/缓存里的原正文。此操作不能撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复原样'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    final ok = await widget.controller.restoreChapterOverride();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _actionError = '恢复失败：没有找到本地覆盖，或本地库暂时不可写。可重试。';
        _retryIsRestore = true;
      }
    });
    if (!ok) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final content = widget.controller.content;
    final chapter = widget.controller.chapter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('正文编辑'),
        actions: <Widget>[
          if (_hasOverride)
            TextButton.icon(
              key: const Key('novel-content-edit-restore'),
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('恢复原样'),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('novel-content-edit-save'),
            onPressed: _busy || content == null ? null : _save,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('保存'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: content == null
          ? NovelEmptyState(
              icon: Icons.edit_off_outlined,
              title: '这一章还没有正文',
              message: '等正文加载完成后再进正文编辑；如果一直加载失败，先回阅读页重试加载。',
              action: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回阅读页'),
              ),
            )
          : NovelPageContent(
              maxWidth: 900,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  NovelCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          _hasOverride
                              ? Icons.cloud_done_outlined
                              : Icons.edit_note_outlined,
                          size: 22,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                chapter?.title ?? content.title,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _loadingOverride
                                    ? '正在检查本地覆盖…'
                                    : _overrideReadFailed
                                    ? '本地覆盖状态读取失败；可重试，仍不行就退出后重启应用。'
                                    : _hasOverride
                                    ? '当前章已有本地覆盖：下次打开这一章优先使用编辑后的正文。'
                                    : '保存后写入本地覆盖，下次打开这一章优先使用它；随时可以恢复原样。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_overrideReadFailed) ...<Widget>[
                    const SizedBox(height: 10),
                    _OverrideErrorBanner(
                      key: const Key('novel-content-edit-read-error'),
                      message: '读不到本地覆盖状态：本地库暂时不可读。仍可继续编辑，但保存可能失败。',
                      actionLabel: '重试读取',
                      onAction: _busy
                          ? null
                          : () {
                              setState(() => _loadingOverride = true);
                              unawaited(_loadOverrideState());
                            },
                    ),
                  ],
                  if (_actionError != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _OverrideErrorBanner(
                      key: const Key('novel-content-edit-action-error'),
                      message: _actionError!,
                      actionLabel: _retryIsRestore ? '重试恢复' : '重试保存',
                      onAction: _busy
                          ? null
                          : (_retryIsRestore ? _restore : _save),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('novel-content-edit-field'),
                      controller: _text,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      enabled: !_busy,
                      style: theme.textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: '在这里编辑正文；每行一段，空行会被忽略。',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Text(
                        '${_paragraphs().length} 段 · ${_text.text.length} 字',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '保存后阅读页会重新排版并停在原位置附近',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (_busy) ...<Widget>[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                ],
              ),
            ),
    );
  }
}

/// 正文编辑页的局部错误条：只挡状态/动作，不把编辑器整块换成错误屏，
/// 用户仍能改字；按钮给可操作的重试。
class _OverrideErrorBanner extends StatelessWidget {
  const _OverrideErrorBanner({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: MimaoShapes.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 20, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
