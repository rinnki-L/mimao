// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 歌单信息编辑表单（标题/简介/标签）——详情页「编辑信息」弹出的底部
/// sheet。只负责收集输入（校验 + trim），playlistUpdate 写端点由详情页
/// 执行（与「对话框只收集、页面层写」的新建歌单模式一致）。
library;

import 'package:flutter/material.dart';

/// 编辑结果（pop 带出；三个字段都已 trim，标签保留用户输入的逗号分隔形态）。
class MusicPlaylistEditSheetResult {
  const MusicPlaylistEditSheetResult({
    required this.title,
    required this.description,
    required this.tags,
  });

  final String title;
  final String description;
  final String tags;
}

/// 打开编辑 sheet；下拉关闭/取消返回 null。
Future<MusicPlaylistEditSheetResult?> showMusicPlaylistEditSheet(
  BuildContext context, {
  required String initialTitle,
  String initialDescription = '',
  String initialTags = '',
}) => showModalBottomSheet<MusicPlaylistEditSheetResult>(
  context: context,
  isScrollControlled: true,
  builder: (_) => MusicPlaylistEditSheet(
    initialTitle: initialTitle,
    initialDescription: initialDescription,
    initialTags: initialTags,
  ),
);

class MusicPlaylistEditSheet extends StatefulWidget {
  const MusicPlaylistEditSheet({
    super.key,
    required this.initialTitle,
    this.initialDescription = '',
    this.initialTags = '',
  });

  final String initialTitle;
  final String initialDescription;
  final String initialTags;

  @override
  State<MusicPlaylistEditSheet> createState() => _MusicPlaylistEditSheetState();
}

class _MusicPlaylistEditSheetState extends State<MusicPlaylistEditSheet> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.initialTitle,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initialDescription);
  late final TextEditingController _tagsController = TextEditingController(
    text: widget.initialTags,
  );

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      MusicPlaylistEditSheetResult(
        title: title,
        description: _descriptionController.text.trim(),
        tags: _tagsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // isScrollControlled + viewInsets：键盘弹出时不遮挡输入框。
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('编辑歌单信息', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '歌单名称',
                hintText: '输入歌单标题',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '简介',
                hintText: '介绍一下这个歌单',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: '标签',
                hintText: '多个标签用逗号分隔',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                // 标题实时驱动保存按钮可用态；空标题不允许提交。
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _titleController,
                  builder: (context, value, _) => FilledButton(
                    onPressed: value.text.trim().isEmpty ? null : _submit,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
