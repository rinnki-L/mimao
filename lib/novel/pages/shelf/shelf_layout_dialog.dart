// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与小说其他页面同款说明。
/// 书架布局设置对话框：五种布局 + 封面宽度/圆角/阴影 + 展示项开关。
///
/// 从书架页拆出。对话框只负责编辑一份 [NovelShelfViewConfig]，写 kv 与
/// 刷新由页面做；「恢复默认」与「保存」都返回完整配置，页面统一落库。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/shelf/shelf_view_config.dart';

/// 打开布局设置；返回 null 表示取消。
Future<NovelShelfViewConfig?> showNovelShelfLayoutDialog(
  BuildContext context, {
  required NovelShelfViewConfig current,
  required bool canGroupBySeries,
}) => showDialog<NovelShelfViewConfig>(
  context: context,
  builder: (_) => _NovelShelfLayoutDialog(
    current: current,
    canGroupBySeries: canGroupBySeries,
  ),
);

class _NovelShelfLayoutDialog extends StatefulWidget {
  const _NovelShelfLayoutDialog({
    required this.current,
    required this.canGroupBySeries,
  });

  final NovelShelfViewConfig current;
  final bool canGroupBySeries;

  @override
  State<_NovelShelfLayoutDialog> createState() =>
      _NovelShelfLayoutDialogState();
}

class _NovelShelfLayoutDialogState extends State<_NovelShelfLayoutDialog> {
  late NovelShelfViewConfig _config = widget.current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: const Text('布局设置'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('展示方式', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final mode in NovelShelfMode.values)
                    ChoiceChip(
                      key: Key('novel-shelf-mode-${mode.key}'),
                      label: Text(mode.label),
                      selected: _config.mode == mode,
                      onSelected: (_) => setState(
                        () => _config = _config.copyWith(mode: mode),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('每行数量', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final option in <int>[0, 3, 4, 5, 6, 7])
                    ChoiceChip(
                      label: Text(option == 0 ? '自动' : '$option 列'),
                      selected: _config.columns == option,
                      onSelected: (_) => setState(
                        () => _config = _config.copyWith(columns: option),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '每行数量只影响网格与瀑布；列表固定单列，文件夹与双列按分区排。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Text('封面宽度', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    '${_config.coverWidth.round()} px',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Slider(
                key: const Key('novel-shelf-cover-width'),
                value: _config.coverWidth,
                min: NovelShelfViewConfig.minCoverWidth,
                max: NovelShelfViewConfig.maxCoverWidth,
                divisions:
                    ((NovelShelfViewConfig.maxCoverWidth -
                                NovelShelfViewConfig.minCoverWidth) /
                            8)
                        .round(),
                label: '${_config.coverWidth.round()}',
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(coverWidth: value),
                ),
              ),
              Row(
                children: <Widget>[
                  Text('封面圆角', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    '${_config.coverRadius.round()} px',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Slider(
                key: const Key('novel-shelf-cover-radius'),
                value: _config.coverRadius,
                min: NovelShelfViewConfig.minCoverRadius,
                max: NovelShelfViewConfig.maxCoverRadius,
                divisions: 14,
                label: '${_config.coverRadius.round()}',
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(coverRadius: value),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('封面阴影'),
                subtitle: const Text('给封面加一层投影，深色主题下更明显'),
                value: _config.coverShadow,
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(coverShadow: value),
                ),
              ),
              const Divider(height: 24),
              Text('卡片上显示', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const Key('novel-shelf-show-tags'),
                contentPadding: EdgeInsets.zero,
                title: const Text('分类标签'),
                value: _config.showTags,
                onChanged: (value) =>
                    setState(() => _config = _config.copyWith(showTags: value)),
              ),
              SwitchListTile(
                key: const Key('novel-shelf-show-latest'),
                contentPadding: EdgeInsets.zero,
                title: const Text('最新章节'),
                value: _config.showLatestChapter,
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(showLatestChapter: value),
                ),
              ),
              SwitchListTile(
                key: const Key('novel-shelf-show-intro'),
                contentPadding: EdgeInsets.zero,
                title: const Text('简介'),
                subtitle: const Text('网格里只留两行，列表里更完整'),
                value: _config.showIntro,
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(showIntro: value),
                ),
              ),
              SwitchListTile(
                key: const Key('novel-shelf-show-updated'),
                contentPadding: EdgeInsets.zero,
                title: const Text('更新时间'),
                subtitle: const Text('书源给了更新时间就显示原文，否则显示最近阅读时间'),
                value: _config.showUpdateTime,
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(showUpdateTime: value),
                ),
              ),
              SwitchListTile(
                key: const Key('novel-shelf-group-series'),
                contentPadding: EdgeInsets.zero,
                title: const Text('按系列归组'),
                subtitle: Text(
                  widget.canGroupBySeries
                      ? '把同系列的书收成一组，排在书架最前面'
                      : '还没有系列：在书籍信息里给书设置系列后可用',
                ),
                value: _config.groupBySeries,
                onChanged: widget.canGroupBySeries
                    ? (value) => setState(
                        () => _config = _config.copyWith(groupBySeries: value),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              setState(() => _config = const NovelShelfViewConfig()),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('novel-shelf-layout-save'),
          onPressed: () => Navigator.of(context).pop(_config),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
