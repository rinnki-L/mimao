// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与小说其他页面同款说明。
/// 首页模块管理面板：开关、上下移、增删自定义分组卡片。
///
/// 从 `novel_home_page.dart` 拆出。面板只编辑一份 [NovelHomeModuleConfig]，
/// 落库与刷新由页面做。排序用上下移按钮而不是拖拽：面板本身是滚动列表，
/// 拖拽与滚动会抢手势，按钮在桌面/触屏都稳。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/home/home_module_config.dart';

/// 打开首页模块管理；返回 null 表示取消。
Future<NovelHomeModuleConfig?> showNovelHomeModuleManager(
  BuildContext context, {
  required NovelHomeModuleConfig config,
  required List<String> availableGroups,
}) => showDialog<NovelHomeModuleConfig>(
  context: context,
  builder: (_) =>
      _NovelHomeModuleManager(config: config, availableGroups: availableGroups),
);

class _NovelHomeModuleManager extends StatefulWidget {
  const _NovelHomeModuleManager({
    required this.config,
    required this.availableGroups,
  });

  final NovelHomeModuleConfig config;
  final List<String> availableGroups;

  @override
  State<_NovelHomeModuleManager> createState() =>
      _NovelHomeModuleManagerState();
}

class _NovelHomeModuleManagerState extends State<_NovelHomeModuleManager> {
  late NovelHomeModuleConfig _config = widget.config;

  Future<void> _addGroup() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _AddGroupDialog(availableGroups: widget.availableGroups),
    );
    if (name == null || name.isEmpty) return;
    final before = _config.modules.length;
    final next = _config.addCustomGroup(name);
    if (next.modules.length == before) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('「$name」已经有一张卡片了')));
      }
      return;
    }
    setState(() => _config = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final modules = _config.modules;
    return AlertDialog(
      title: const Text('首页模块'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '关掉的模块不会显示，顺序就是首页的上下顺序。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: modules.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final module = modules[index];
                  final canDelete = !module.kind.isSingleton;
                  return ListTile(
                    key: Key('novel-home-module-${module.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Switch(
                      value: module.enabled,
                      onChanged: (value) => setState(
                        () => _config = _config.setEnabled(module.id, value),
                      ),
                    ),
                    title: Text(
                      module.kind == NovelHomeModuleKind.customGroup
                          ? '分组卡片 · ${module.groupName}'
                          : module.kind.label,
                    ),
                    subtitle: Text(
                      module.enabled ? '显示中' : '已隐藏',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: '上移',
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          onPressed: index == 0
                              ? null
                              : () => setState(
                                  () =>
                                      _config = _config.move(index, index - 1),
                                ),
                        ),
                        IconButton(
                          tooltip: '下移',
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          onPressed: index == modules.length - 1
                              ? null
                              : () => setState(
                                  () =>
                                      _config = _config.move(index, index + 1),
                                ),
                        ),
                        IconButton(
                          tooltip: canDelete ? '删除卡片' : '内置模块不能删除',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: canDelete
                              ? () => setState(
                                  () =>
                                      _config = _config.removeModule(module.id),
                                )
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('novel-home-module-add-group'),
                onPressed: _addGroup,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加分组卡片'),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => setState(
            () => _config = const NovelHomeModuleConfig(
              NovelHomeModuleConfig.defaults,
            ),
          ),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('novel-home-module-save'),
          onPressed: () => Navigator.of(context).pop(_config),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 「添加分组卡片」对话框。
///
/// 单独成 StatefulWidget 是为了让 TextEditingController 的生命周期跟着
/// 对话框自己的 State 走：在 showDialog 的 builder 里 new 一个 controller
/// 再在 await 之后 dispose，会在退场动画期间用到已释放的 controller。
class _AddGroupDialog extends StatefulWidget {
  const _AddGroupDialog({required this.availableGroups});

  final List<String> availableGroups;

  @override
  State<_AddGroupDialog> createState() => _AddGroupDialogState();
}

class _AddGroupDialogState extends State<_AddGroupDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('添加分组卡片'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.availableGroups.isNotEmpty) ...<Widget>[
            Text('已有的书架分组', style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final group in widget.availableGroups)
                  ActionChip(
                    label: Text(group),
                    onPressed: () => Navigator.of(context).pop(group),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            key: const Key('novel-home-module-group-name'),
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '分组名',
              hintText: '输入要展示在首页的书架分组',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            widget.availableGroups.isEmpty
                ? '书架还没有分组。先在书架里把书「加入分组」，这里就能挑到。'
                : '每张卡片展示一个书架分组的封面横条。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('novel-home-module-group-add'),
          onPressed: _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
