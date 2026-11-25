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

  @override
  void initState() {
    super.initState();
    unawaited(_loadOverrideState());
  }

  Future<void> _loadOverrideState() async {
    final has = await widget.controller.hasChapterOverride();
    if (!mounted) return;
    setState(() {
      _hasOverride = has;
      _loadingOverride = false;
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
    setState(() => _busy = true);
    final ok = await widget.controller.saveChapterOverride(paragraphs);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _toast('保存失败：本地库暂时不可写，稍后重试');
      return;
    }
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
    setState(() => _busy = true);
    final ok = await widget.controller.restoreChapterOverride();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _toast('恢复失败：没有找到本地覆盖，或本地库暂时不可写');
      return;
    }
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
