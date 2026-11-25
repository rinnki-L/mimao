// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 「我的 → 键盘辅助」：配置阅读页的按键 → 动作映射。
///
/// 动作一律复用点击区那套 [NovelClickAction]（`novel_click_actions.dart`），
/// 不另造枚举；默认键位与改造前写死的一致。Home / End / Escape 是阅读页保留键
/// （滚动到顶/底、关菜单/退出），不在这张表里改。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
import 'package:mimao/novel/reader/novel_keyboard_assist.dart';

class NovelKeyboardPage extends StatefulWidget {
  const NovelKeyboardPage({super.key, required this.store});

  final NovelKeyboardAssistStore store;

  @override
  State<NovelKeyboardPage> createState() => _NovelKeyboardPageState();
}

class _NovelKeyboardPageState extends State<NovelKeyboardPage> {
  bool _loading = true;
  String? _error;
  NovelKeyboardConfig _config = NovelKeyboardConfig.defaults;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
      });
    } on Object catch (error) {
      debugPrint('novel: 读取键盘辅助失败: $error');
      if (!mounted) return;
      setState(() {
        _error = '读取键盘辅助失败：本地库暂时打不开。';
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

  Future<void> _save(NovelKeyboardConfig next) async {
    setState(() => _config = next);
    try {
      await widget.store.save(next);
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _addBinding() async {
    final binding = await showDialog<NovelKeyboardBinding>(
      context: context,
      builder: (_) => _BindingDialog(existing: _config.bindings),
    );
    if (binding == null) return;
    final next = <NovelKeyboardBinding>[
      ..._config.bindings.where(
        (item) => item.keys.toLowerCase() != binding.keys.toLowerCase(),
      ),
      binding,
    ];
    await _save(_config.copyWith(bindings: next));
    _toast('已添加 ${binding.keys} → ${binding.action.label}');
  }

  Future<void> _changeAction(
    NovelKeyboardBinding binding,
    NovelClickAction action,
  ) async {
    final next = <NovelKeyboardBinding>[
      for (final item in _config.bindings)
        item.keys == binding.keys ? item.copyWith(action: action) : item,
    ];
    await _save(_config.copyWith(bindings: next));
  }

  Future<void> _remove(NovelKeyboardBinding binding) async {
    final next = <NovelKeyboardBinding>[
      for (final item in _config.bindings)
        if (item.keys != binding.keys) item,
    ];
    await _save(_config.copyWith(bindings: next));
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复默认键位？'),
        content: const Text('会丢掉你加的自定义映射，回到「←→↑↓ / PageUp/Down / 空格」这套。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _save(
      NovelKeyboardConfig(
        bindings: novelDefaultKeyboardBindings,
        showHints: _config.showHints,
      ),
    );
    _toast('已恢复默认键位');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('键盘辅助'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            key: const Key('novel-keyboard-reset'),
            onPressed: _resetDefaults,
            child: const Text('恢复默认'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: NovelPageContent(
        maxWidth: 860,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: _loading
            ? const NovelLoadingState(label: '正在读取键盘辅助…')
            : _error != null
            ? NovelErrorState(
                message: _error!,
                hint: '可以重试一次；反复失败就退出应用重启，让本地库重新打开。',
                onRetry: _load,
              )
            : ListView(
                children: <Widget>[
                  _buildIntroCard(context),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '按键映射  ${_config.bindings.length}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        key: const Key('novel-keyboard-add'),
                        onPressed: _addBinding,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新增映射'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_config.bindings.isEmpty)
                    NovelEmptyState(
                      icon: Icons.keyboard_outlined,
                      title: '还没有按键映射',
                      message:
                          '加一条「按键组合 → 动作」，阅读页按下就生效。'
                          '默认的 ←→↑↓ 翻页/空格自动翻页仍在，除非你覆盖同一个键。',
                      action: FilledButton.tonalIcon(
                        onPressed: _addBinding,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新增第一条映射'),
                      ),
                    )
                  else
                    for (final binding in _config.bindings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildBindingCard(context, binding),
                      ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.keyboard_alt_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('桌面端快捷键', style: theme.textTheme.titleMedium),
              ),
              Switch(
                value: _config.showHints,
                onChanged: (value) => _save(_config.copyWith(showHints: value)),
              ),
              const SizedBox(width: 6),
              Text(
                '按键提示浮层',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '按键只在阅读页生效（宽窗口桌面端；手机外接键盘也能用）。'
            '动作复用点击区的动作表，没实现的动作（如 WebDAV 同步）不会出现在下拉里。'
            'Home / End / Esc 是保留键：滚动到顶/底、关菜单/退出。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindingCard(BuildContext context, NovelKeyboardBinding binding) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: MimaoShapes.sm,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(binding.keys, style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: 10),
          Icon(Icons.arrow_right_alt, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<NovelClickAction>(
                value: binding.action,
                isExpanded: true,
                onChanged: (value) {
                  if (value == null) return;
                  _changeAction(binding, value);
                },
                items: <DropdownMenuItem<NovelClickAction>>[
                  for (final action in novelKeyboardAssignableActions())
                    DropdownMenuItem<NovelClickAction>(
                      value: action,
                      child: Text(action.label),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '删除映射',
            onPressed: () => _remove(binding),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// 新增映射：按下真实按键捕获组合键，再选动作。
class _BindingDialog extends StatefulWidget {
  const _BindingDialog({required this.existing});

  final List<NovelKeyboardBinding> existing;

  @override
  State<_BindingDialog> createState() => _BindingDialogState();
}

class _BindingDialogState extends State<_BindingDialog> {
  final FocusNode _focus = FocusNode();
  String? _captured;
  String? _hint;
  NovelClickAction _action = NovelClickAction.nextPage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // 单按修饰键不算组合键。
    final modifiers = <LogicalKeyboardKey>{
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.alt,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.meta,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    if (modifiers.contains(key)) return KeyEventResult.handled;
    final hardware = HardwareKeyboard.instance;
    final spec = novelKeySpecOf(
      key,
      control: hardware.isControlPressed,
      shift: hardware.isShiftPressed,
      alt: hardware.isAltPressed,
      meta: hardware.isMetaPressed,
    );
    setState(() {
      if (spec == null) {
        _captured = null;
        _hint = '这个键不在支持列表里（方向键/翻页键/字母数字/F1-F12 可用）';
      } else {
        _captured = spec;
        _hint = null;
      }
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final conflict = _captured == null
        ? null
        : widget.existing
              .where(
                (item) => item.keys.toLowerCase() == _captured!.toLowerCase(),
              )
              .firstOrNull;
    return AlertDialog(
      title: const Text('新增按键映射'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Focus(
              focusNode: _focus,
              onKeyEvent: _onKey,
              child: Container(
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: MimaoShapes.sm,
                  border: Border.all(
                    color: _captured == null ? cs.outlineVariant : cs.primary,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      _captured ?? '按下要绑定的按键',
                      style: _captured == null
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hint ?? '支持 Ctrl/Shift/Alt/Meta 组合',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _hint == null ? cs.onSurfaceVariant : cs.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<NovelClickAction>(
              initialValue: _action,
              decoration: const InputDecoration(labelText: '动作'),
              items: <DropdownMenuItem<NovelClickAction>>[
                for (final action in novelKeyboardAssignableActions())
                  DropdownMenuItem<NovelClickAction>(
                    value: action,
                    child: Text(action.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _action = value);
              },
            ),
            if (conflict != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '${conflict.keys} 已经绑定了「${conflict.action.label}」，保存后会覆盖它。',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _captured == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(NovelKeyboardBinding(keys: _captured!, action: _action)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
