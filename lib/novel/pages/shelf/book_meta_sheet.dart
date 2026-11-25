// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与小说其他页面同款说明。
/// 单本书的「书籍信息」编辑面板：备注、自定义封面、系列、分组。
///
/// 从书架页拆出：这四个字段是同一类操作（改收藏行的元数据），放一个对话框
/// 里一次改完，比在右键菜单里塞四个入口清楚。任何一项保存失败都保留其它
/// 已成功的改动并把错误抛给页面提示，不静默吞掉。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/shelf/novel_cover_picker.dart';

/// 面板结果：只带"改成了什么"，写库由页面做（便于统一提示/刷新）。
class NovelBookMetaEdit {
  const NovelBookMetaEdit({
    required this.note,
    required this.groupName,
    required this.seriesId,
    required this.seriesName,
    required this.customCoverPath,
    required this.clearCover,
  });

  final String note;
  final String? groupName;

  /// 选中的系列 id；null 且 [seriesName] 非空表示要新建。
  final int? seriesId;
  final String? seriesName;

  final String? customCoverPath;
  final bool clearCover;
}

/// 打开书籍信息面板；返回 null 表示用户取消。
Future<NovelBookMetaEdit?> showNovelBookMetaSheet(
  BuildContext context, {
  required String title,
  required String coverUrl,
  required String currentNote,
  required String? currentGroupName,
  required int? currentSeriesId,
  required String? currentSeriesName,
  required String? currentCustomCover,
  required List<String> groups,
  required List<NovelSeriesItem> series,
  required NovelCoverPicker coverPicker,
  required String bookId,
}) => showDialog<NovelBookMetaEdit>(
  context: context,
  builder: (_) => _NovelBookMetaDialog(
    title: title,
    coverUrl: coverUrl,
    currentNote: currentNote,
    currentGroupName: currentGroupName,
    currentSeriesId: currentSeriesId,
    currentSeriesName: currentSeriesName,
    currentCustomCover: currentCustomCover,
    groups: groups,
    series: series,
    coverPicker: coverPicker,
    bookId: bookId,
  ),
);

class _NovelBookMetaDialog extends StatefulWidget {
  const _NovelBookMetaDialog({
    required this.title,
    required this.coverUrl,
    required this.currentNote,
    required this.currentGroupName,
    required this.currentSeriesId,
    required this.currentSeriesName,
    required this.currentCustomCover,
    required this.groups,
    required this.series,
    required this.coverPicker,
    required this.bookId,
  });

  final String title;
  final String coverUrl;
  final String currentNote;
  final String? currentGroupName;
  final int? currentSeriesId;
  final String? currentSeriesName;
  final String? currentCustomCover;
  final List<String> groups;
  final List<NovelSeriesItem> series;
  final NovelCoverPicker coverPicker;
  final String bookId;

  @override
  State<_NovelBookMetaDialog> createState() => _NovelBookMetaDialogState();
}

class _NovelBookMetaDialogState extends State<_NovelBookMetaDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.currentNote,
  );
  final TextEditingController _group = TextEditingController();
  final TextEditingController _seriesName = TextEditingController();

  late String? _groupName = widget.currentGroupName;
  late int? _seriesId = widget.currentSeriesId;
  late String? _customCover = widget.currentCustomCover;
  bool _clearCover = false;
  bool _pickingCover = false;
  String? _coverError;

  @override
  void dispose() {
    _note.dispose();
    _group.dispose();
    _seriesName.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    setState(() {
      _pickingCover = true;
      _coverError = null;
    });
    try {
      final path = await widget.coverPicker.pickAndStore(widget.bookId);
      if (!mounted) return;
      setState(() {
        _pickingCover = false;
        if (path != null) {
          _customCover = path;
          _clearCover = false;
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _pickingCover = false;
        _coverError = '读取图片失败：$error';
      });
    }
  }

  void _save() {
    final typedGroup = _group.text.trim();
    final groupName = typedGroup.isNotEmpty
        ? typedGroup
        : (_groupName == null || _groupName!.isEmpty ? null : _groupName);
    final typedSeries = _seriesName.text.trim();
    Navigator.of(context).pop(
      NovelBookMetaEdit(
        note: _note.text.trim(),
        groupName: groupName,
        seriesId: typedSeries.isEmpty ? _seriesId : null,
        seriesName: typedSeries.isEmpty ? null : typedSeries,
        customCoverPath: _customCover,
        clearCover: _clearCover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final previewUrl = _clearCover
        ? widget.coverUrl
        : (_customCover ?? widget.coverUrl);
    return AlertDialog(
      title: Text(
        '书籍信息 · ${widget.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 84,
                    height: 122,
                    child: NovelBookCover(url: previewUrl, title: widget.title),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text('封面', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          _customCover == null || _clearCover
                              ? '当前使用书源封面。可以换成自己的图片（会复制进应用目录）。'
                              : '当前使用自定义封面。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: _pickingCover ? null : _pickCover,
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: Text(_pickingCover ? '选择中…' : '选择图片'),
                            ),
                            if (_customCover != null && !_clearCover)
                              TextButton(
                                onPressed: () => setState(() {
                                  _clearCover = true;
                                }),
                                child: const Text('恢复书源封面'),
                              ),
                          ],
                        ),
                        if (_coverError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _coverError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('novel-book-meta-note'),
                controller: _note,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '给这本书写点自己的话（不参与筛选与排序）',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Text('分组', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('未分组'),
                    selected: _groupName == null || _groupName!.isEmpty,
                    onSelected: (_) => setState(() {
                      _groupName = null;
                      _group.clear();
                    }),
                  ),
                  for (final group in widget.groups)
                    ChoiceChip(
                      label: Text(group),
                      selected: _groupName == group,
                      onSelected: (_) => setState(() {
                        _groupName = group;
                        _group.clear();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _group,
                decoration: const InputDecoration(
                  labelText: '或新建分组',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Text('系列', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                '同系列的书可以在书架上收成一组（如三部曲）。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('不属于系列'),
                    selected: _seriesId == null,
                    onSelected: (_) => setState(() {
                      _seriesId = null;
                      _seriesName.clear();
                    }),
                  ),
                  for (final item in widget.series)
                    ChoiceChip(
                      label: Text(item.name),
                      selected: _seriesId == item.id,
                      onSelected: (_) => setState(() {
                        _seriesId = item.id;
                        _seriesName.clear();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _seriesName,
                decoration: const InputDecoration(
                  labelText: '或新建系列',
                  isDense: true,
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
          key: const Key('novel-book-meta-save'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
