/// 音乐快捷键控制器：把 [MusicHotKeyBinding] 注册到 hotkey_manager，收到按键后
/// 派发动作；负责改键、恢复默认与生命周期收尾。
///
/// 注册器 [MusicHotKeyRegistrar] 是窄接口——生产用 [HotKeyManagerRegistrar]
/// 包住 `hotkey_manager`，测试注入内存假件，因此控制器的单测不碰任何 native
/// 插件（CI 无 nativeapi 二进制也能跑）。
library;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mimao/music/hotkey/music_hotkey_model.dart';
import 'package:mimao/music/hotkey/music_hotkey_settings.dart';

/// 注册器缝：只暴露控制器需要的三个操作。
abstract interface class MusicHotKeyRegistrar {
  /// 注册一条快捷键，[onPressed] 在按下时触发。
  Future<void> register(
    HotKey hotKey, {
    required void Function(HotKey hotKey) onPressed,
  });

  Future<void> unregister(HotKey hotKey);

  Future<void> unregisterAll();
}

/// 生产注册器：委托给 hotkey_manager 单例。
class HotKeyManagerRegistrar implements MusicHotKeyRegistrar {
  HotKeyManagerRegistrar({HotKeyManager? manager})
    : _manager = manager ?? HotKeyManager.instance;

  final HotKeyManager _manager;

  @override
  Future<void> register(
    HotKey hotKey, {
    required void Function(HotKey hotKey) onPressed,
  }) => _manager.register(hotKey, keyDownHandler: onPressed);

  @override
  Future<void> unregister(HotKey hotKey) => _manager.unregister(hotKey);

  @override
  Future<void> unregisterAll() => _manager.unregisterAll();
}

/// 改键冲突异常：设置页据此给出「与 XXX 冲突」的提示并回滚。
class MusicHotKeyConflictException implements Exception {
  const MusicHotKeyConflictException(this.conflictingAction);

  final MusicHotKeyAction conflictingAction;

  @override
  String toString() => '快捷键与「${conflictingAction.label}」冲突';
}

/// 快捷键控制器。
class MusicHotKeyController {
  MusicHotKeyController({
    required MusicHotKeySettings settings,
    required MusicHotKeyRegistrar registrar,
    required void Function(MusicHotKeyAction action) onAction,

    /// 派发前的额外门槛；返回 false 则本次按键被忽略。应用内快捷键用它过滤
    /// 「正在输入框打字」——hotkey_manager 的 inapp 快捷键不消费文本输入，
    /// 不自行过滤会在搜索框敲空格时误触发播放/暂停（包文档明确要求调用方过滤）。
    bool Function(MusicHotKeyScope scope)? shouldHandle,
  }) : _settings = settings,
       _registrar = registrar,
       _onAction = onAction,
       _shouldHandle = shouldHandle ?? ((_) => true);

  final MusicHotKeySettings _settings;
  final MusicHotKeyRegistrar _registrar;
  final void Function(MusicHotKeyAction action) _onAction;
  final bool Function(MusicHotKeyScope scope) _shouldHandle;

  /// 已成功注册的 HotKey（按稳定标识索引），改键/销毁时按它反注册。
  final Map<String, HotKey> _registered = <String, HotKey>{};

  /// 注册问题（如全局快捷键被系统占用/平台不支持）。设置页监听后展示。
  final ValueNotifier<List<String>> issues = ValueNotifier<List<String>>(
    <String>[],
  );

  bool _initialized = false;
  bool _disposed = false;

  /// 正在录制改键：此时按键只用于捕获，不派发动作（避免录制空格时误播/暂停）。
  bool _recording = false;
  bool get isRecording => _recording;
  void setRecording(bool value) => _recording = value;

  List<MusicHotKeyBinding> get bindings => _settings.bindings;

  /// 是否启用全局快捷键（EchoMusic 同款开关，默认关闭）。
  bool get globalShortcutsEnabled => _settings.globalShortcutsEnabled;

  /// 首次使用：读盘 → 全量注册。重复调用幂等。
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    await _settings.ensureLoaded();
    await _registerAll();
  }

  /// 打开/关闭全局快捷键：关时反注册所有 global 键，开时补注册。
  /// 与 EchoMusic 一致——全局注册会抢占系统组合键，必须显式开启。
  Future<void> setGlobalShortcutsEnabled(bool value) async {
    if (_disposed) return;
    if (value == _settings.globalShortcutsEnabled) return;
    if (!value) {
      for (final entry in _registered.entries.toList()) {
        if (entry.key.startsWith('system.')) {
          await _registrar.unregister(entry.value);
          _registered.remove(entry.key);
        }
      }
      // 关掉后不再显示旧的全局注册失败提示。
      issues.value = issues.value
          .where((line) => !line.startsWith('全局「'))
          .toList();
    } else {
      final problems = <String>[];
      for (final binding in bindings) {
        if (binding.scope == MusicHotKeyScope.global &&
            !_registered.containsKey(binding.id)) {
          await _registerOne(binding, problems);
        }
      }
      _mergeProblems(problems);
    }
    await _settings.setGlobalShortcutsEnabled(value);
  }

  Future<void> _registerAll() async {
    final problems = <String>[];
    for (final binding in bindings) {
      // 全局快捷键默认不注册——必须由用户显式打开开关。
      if (binding.scope == MusicHotKeyScope.global &&
          !_settings.globalShortcutsEnabled) {
        continue;
      }
      await _registerOne(binding, problems);
    }
    issues.value = problems;
  }

  void _mergeProblems(List<String> fresh) {
    if (fresh.isEmpty) return;
    issues.value = <String>[...issues.value, ...fresh];
  }

  Future<void> _registerOne(
    MusicHotKeyBinding binding,
    List<String> problems,
  ) async {
    final hotKey = binding.toHotKey();
    try {
      await _registrar.register(
        hotKey,
        onPressed: (_) {
          if (_recording) return;
          if (!_shouldHandle(binding.scope)) return;
          _onAction(binding.action);
        },
      );
      _registered[binding.id] = hotKey;
    } on Object catch (error) {
      final scope = binding.scope == MusicHotKeyScope.global ? '全局' : '快捷键';
      problems.add('$scope「${binding.action.label}」注册失败：$error');
    }
  }

  /// 重绑一条快捷键。校验冲突 → 反注册旧键 → 注册新键 → 落盘。
  /// 任一步失败都不改变已保存的绑定（内存列表只在注册成功后更新）。
  Future<void> rebind({
    required MusicHotKeyScope scope,
    required MusicHotKeyAction action,
    required HotKey recorded,
  }) async {
    if (_disposed) return;
    final current = bindings;
    final index = current.indexWhere(
      (b) => b.scope == scope && b.action == action,
    );
    if (index < 0) return;
    final updated = current[index].rebindWith(recorded);
    for (var i = 0; i < current.length; i++) {
      if (i == index) continue;
      if (musicHotKeyConflicts(current[i], updated)) {
        throw MusicHotKeyConflictException(current[i].action);
      }
    }

    final id = current[index].id;
    final oldHotKey = _registered[id];
    if (oldHotKey != null) {
      await _registrar.unregister(oldHotKey);
      _registered.remove(id);
    }
    final problems = <String>[];
    // 全局开关关闭时只存绑定，不实际注册（用户开启开关时再补注册）。
    if (scope != MusicHotKeyScope.global || _settings.globalShortcutsEnabled) {
      await _registerOne(updated, problems);
    }
    _mergeIssues(scope, action, problems);

    final next = List<MusicHotKeyBinding>.of(current)..[index] = updated;
    await _settings.setBindings(next);
  }

  /// 清空某条绑定（设为无键）——用于用户想暂时禁用某动作。
  Future<void> clear(MusicHotKeyScope scope, MusicHotKeyAction action) async {
    if (_disposed) return;
    final current = bindings;
    final index = current.indexWhere(
      (b) => b.scope == scope && b.action == action,
    );
    if (index < 0) return;
    final id = current[index].id;
    final oldHotKey = _registered.remove(id);
    if (oldHotKey != null) {
      await _registrar.unregister(oldHotKey);
    }
    final next = List<MusicHotKeyBinding>.of(current)..removeAt(index);
    await _settings.setBindings(next);
  }

  /// 恢复某动作的默认键（本地 + 全局两条），与 EchoMusic 行尾「重置」一致。
  Future<void> resetAction(MusicHotKeyAction action) async {
    if (_disposed) return;
    final current = bindings;
    var next = List<MusicHotKeyBinding>.of(current);
    for (final scope in MusicHotKeyScope.values) {
      final idx = next.indexWhere(
        (b) => b.scope == scope && b.action == action,
      );
      if (idx < 0) continue;
      final old = _registered.remove(next[idx].id);
      if (old != null) await _registrar.unregister(old);
      final isDefault = defaultMusicHotKeyBindings.any(
        (d) => d.scope == scope && d.action == action,
      );
      if (!isDefault) {
        next.removeAt(idx);
        continue;
      }
      next[idx] = defaultMusicHotKeyBindings.firstWhere(
        (d) => d.scope == scope && d.action == action,
      );
      if (scope != MusicHotKeyScope.global ||
          _settings.globalShortcutsEnabled) {
        final problems = <String>[];
        await _registerOne(next[idx], problems);
        // 恢复默认后清掉该行的旧失败提示。
        final prefix =
            '${scope == MusicHotKeyScope.global ? '全局' : '快捷键'}「${action.label}」';
        issues.value = issues.value
            .where((l) => !l.startsWith(prefix))
            .toList();
        _mergeProblems(problems);
      }
    }
    await _settings.setBindings(next);
  }

  /// 恢复出厂默认：卸载全部自定义注册，按默认表重注册并落盘。
  Future<void> resetToDefaults() async {
    if (_disposed) return;
    await _registrar.unregisterAll();
    _registered.clear();
    await _settings.setBindings(defaultMusicHotKeyBindings);
    await _registerAll();
  }

  void _mergeIssues(
    MusicHotKeyScope scope,
    MusicHotKeyAction action,
    List<String> fresh,
  ) {
    if (fresh.isEmpty) return;
    // 只替换同一 scope/action 的旧问题，避免改一条把别的错误提示冲掉。
    final prefix =
        '${scope == MusicHotKeyScope.global ? '全局' : '快捷键'}「${action.label}」';
    final kept = issues.value
        .where((line) => !line.startsWith(prefix))
        .toList();
    issues.value = <String>[...kept, ...fresh];
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _registrar.unregisterAll();
    _registered.clear();
    issues.dispose();
  }
}
