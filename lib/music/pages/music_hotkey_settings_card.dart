// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，
// 与 music_module_settings.dart 同款说明。
/// 音乐快捷键设置卡：分「应用内快捷键」与「全局快捷键」两组，逐条可录制改键、
/// 清除、一键恢复默认。
///
/// 录制走 [HardwareKeyboard] 全局处理：进入录制态时按住修饰键 + 主键，抬起主键
/// 即完成一次录制。录制期间控制器暂停动作派发（避免误触）。系统级组合被占用/
/// 不支持时，注册失败原因由控制器的 issues notifier 展示。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/hotkey/music_hotkey_controller.dart';
import 'package:mimao/music/hotkey/music_hotkey_model.dart';

/// 设置页里的一张卡；由 [MusicModuleSettings] 注入控制器。
class MusicHotKeySettingsCard extends StatefulWidget {
  const MusicHotKeySettingsCard({super.key, required this.controller});

  final MusicHotKeyController controller;

  @override
  State<MusicHotKeySettingsCard> createState() =>
      _MusicHotKeySettingsCardState();
}

class _MusicHotKeySettingsCardState extends State<MusicHotKeySettingsCard> {
  /// 正在录制的绑定 id；null 表示未录制。
  String? _recordingId;
  KeyEventCallback? _recorderHandler;

  @override
  void dispose() {
    _stopRecording();
    super.dispose();
  }

  List<MusicHotKeyBinding> _scopeBindings(MusicHotKeyScope scope) => widget
      .controller
      .bindings
      .where((binding) => binding.scope == scope)
      .toList();

  void _startRecording(MusicHotKeyBinding binding) {
    _stopRecording();
    widget.controller.setRecording(true);
    setState(() => _recordingId = binding.id);

    final handler = _recorderHandler = (KeyEvent event) {
      // 只认按下、非合成事件；修饰键本身不单独成键。
      if (event is! KeyDownEvent || event.synthesized) return false;
      final pressed = HardwareKeyboard.instance.physicalKeysPressed;
      final key = event.physicalKey;
      if (_isModifier(key)) return true; // 吞掉，等用户按主键
      final modifiers = HotKeyModifier.values
          .where(
            (modifier) =>
                modifier.physicalKeys.any(pressed.contains) &&
                !modifier.physicalKeys.contains(key),
          )
          .toList();
      final recorded = HotKey(
        identifier: binding.id,
        key: key,
        modifiers: modifiers.isEmpty ? null : modifiers,
        scope: binding.scope.hotKeyScope,
      );
      _stopRecording();
      _applyRebind(binding, recorded);
      return true;
    };
    HardwareKeyboard.instance.addHandler(handler);
  }

  void _stopRecording() {
    final handler = _recorderHandler;
    if (handler != null) {
      HardwareKeyboard.instance.removeHandler(handler);
      _recorderHandler = null;
    }
    widget.controller.setRecording(false);
    if (_recordingId != null && mounted) {
      setState(() => _recordingId = null);
    } else {
      _recordingId = null;
    }
  }

  Future<void> _applyRebind(MusicHotKeyBinding binding, HotKey recorded) async {
    try {
      await widget.controller.rebind(
        scope: binding.scope,
        action: binding.action,
        recorded: recorded,
      );
      if (!mounted) return;
      setState(() {}); // 刷新展示文本
    } on MusicHotKeyConflictException catch (error) {
      if (!mounted) return;
      _showSnack('改键失败：${error.toString()}');
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack('改键失败：$error');
    }
  }

  Future<void> _clear(MusicHotKeyBinding binding) async {
    await widget.controller.clear(binding.scope, binding.action);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _resetAll() async {
    await widget.controller.resetToDefaults();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _resetAction(MusicHotKeyAction action) async {
    await widget.controller.resetAction(action);
    if (!mounted) return;
    setState(() {});
  }

  /// 切换全局快捷键开关；开时可能触发系统注册冲突，失败原因由 issues 展示。
  Future<void> _toggleGlobal(bool value) async {
    await widget.controller.setGlobalShortcutsEnabled(value);
    if (!mounted) return;
    setState(() {});
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.keyboard,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('快捷键', style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: _resetAll,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('恢复默认'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '点按键框后按下新组合即可修改；左侧「快捷键」在本窗口聚焦时生效（打字时自动让位），右侧「全局快捷键」在任何界面生效。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // EchoMusic 同款双列表头：功能 | 快捷键 | 全局快捷键 | 重置。
            _gridHeader(theme),
            const Divider(height: 1),
            ...MusicHotKeyAction.values.map(_actionRow),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.public),
              title: const Text('启用全局快捷键'),
              subtitle: const Text('应用在后台也可响应快捷键'),
              value: widget.controller.globalShortcutsEnabled,
              onChanged: _toggleGlobal,
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<List<String>>(
              valueListenable: widget.controller.issues,
              builder: (context, issues, _) {
                if (issues.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: MimaoShapes.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '部分快捷键未注册成功（可能被系统或其它应用占用）：',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        ...issues.map(
                          (line) => Text(
                            '· $line',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 表头：功能说明 / 快捷键 / 全局快捷键。
  Widget _gridHeader(ThemeData theme) => Row(
    children: <Widget>[
      Expanded(flex: 3, child: Text('功能', style: theme.textTheme.titleSmall)),
      Expanded(flex: 2, child: Text('快捷键', style: theme.textTheme.titleSmall)),
      Expanded(
        flex: 2,
        child: Text('全局快捷键', style: theme.textTheme.titleSmall),
      ),
      SizedBox(width: 40), // 重置列占位
    ],
  );

  /// 每个动作一行：名称 + 两列可录制按键框 + 重置按钮（EchoMusic 同款）。
  Widget _actionRow(MusicHotKeyAction action) {
    final local = _findBinding(MusicHotKeyScope.inApp, action);
    final global = _findBinding(MusicHotKeyScope.global, action);
    final defaultLocal = _defaultBinding(MusicHotKeyScope.inApp, action);
    final modified =
        local != null &&
        defaultLocal != null &&
        local.displayText != defaultLocal.displayText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              action.label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 2,
            child: local == null ? const SizedBox.shrink() : _keyCell(local),
          ),
          Expanded(
            flex: 2,
            child: global == null ? const SizedBox.shrink() : _keyCell(global),
          ),
          SizedBox(
            width: 40,
            child: modified
                ? IconButton(
                    tooltip: '恢复默认',
                    icon: const Icon(Icons.restore, size: 18),
                    onPressed: () => _resetAction(action),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  MusicHotKeyBinding? _findBinding(
    MusicHotKeyScope scope,
    MusicHotKeyAction action,
  ) {
    for (final binding in _scopeBindings(scope)) {
      if (binding.action == action) return binding;
    }
    return null;
  }

  MusicHotKeyBinding? _defaultBinding(
    MusicHotKeyScope scope,
    MusicHotKeyAction action,
  ) {
    for (final binding in defaultMusicHotKeyBindings) {
      if (binding.scope == scope && binding.action == action) return binding;
    }
    return null;
  }

  /// 单个可录制按键框（点击录制、× 清除）。
  Widget _keyCell(MusicHotKeyBinding binding) {
    final recording = _recordingId == binding.id;
    final globalDisabled =
        binding.scope == MusicHotKeyScope.global &&
        !widget.controller.globalShortcutsEnabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Expanded(
          child: InkWell(
            onTap: globalDisabled || recording
                ? null
                : () => _startRecording(binding),
            borderRadius: MimaoShapes.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: recording
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: MimaoShapes.sm,
              ),
              child: Text(
                recording ? '按键…' : binding.displayText,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: globalDisabled
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : recording
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
              ),
            ),
          ),
        ),
        if (!globalDisabled)
          IconButton(
            tooltip: '清除',
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: recording ? null : () => _clear(binding),
          ),
      ],
    );
  }
}

bool _isModifier(PhysicalKeyboardKey key) =>
    key == PhysicalKeyboardKey.controlLeft ||
    key == PhysicalKeyboardKey.controlRight ||
    key == PhysicalKeyboardKey.altLeft ||
    key == PhysicalKeyboardKey.altRight ||
    key == PhysicalKeyboardKey.shiftLeft ||
    key == PhysicalKeyboardKey.shiftRight ||
    key == PhysicalKeyboardKey.metaLeft ||
    key == PhysicalKeyboardKey.metaRight ||
    key == PhysicalKeyboardKey.capsLock ||
    key == PhysicalKeyboardKey.fn;
