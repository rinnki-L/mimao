/// 快捷键控制器测试：注册/改键/清除/恢复默认/冲突拒绝/录制期抑制派发/收尾。
/// 注入内存设置 + 假注册器，全程不碰 hotkey_manager 的 native 实现。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mimao/music/hotkey/music_hotkey_controller.dart';
import 'package:mimao/music/hotkey/music_hotkey_model.dart';
import 'package:mimao/music/hotkey/music_hotkey_settings.dart';

/// 记录注册/反注册调用的假注册器。
class FakeRegistrar implements MusicHotKeyRegistrar {
  final Map<String, HotKey> registered = <String, HotKey>{};
  final List<String> log = <String>[];
  Object? failOnRegister;

  @override
  Future<void> register(
    HotKey hotKey, {
    required void Function(HotKey hotKey) onPressed,
  }) async {
    final failure = failOnRegister;
    if (failure != null) throw failure;
    registered[hotKey.identifier] = hotKey;
    log.add('register:${hotKey.identifier}');
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    registered.remove(hotKey.identifier);
    log.add('unregister:${hotKey.identifier}');
  }

  @override
  Future<void> unregisterAll() async {
    registered.clear();
    log.add('unregisterAll');
  }
}

void main() {
  late InMemoryMusicHotKeySettings settings;
  late FakeRegistrar registrar;
  late List<MusicHotKeyAction> actions;
  late MusicHotKeyController controller;

  setUp(() {
    settings = InMemoryMusicHotKeySettings();
    registrar = FakeRegistrar();
    actions = <MusicHotKeyAction>[];
    controller = MusicHotKeyController(
      settings: settings,
      registrar: registrar,
      onAction: actions.add,
    );
  });

  test('initialize 默认只注册 6 条快捷键（全局默认关闭），幂等', () async {
    await controller.initialize();
    // 6 条本地快捷键注册；6 条全局因开关关闭不注册。
    expect(registrar.registered, hasLength(6));
    expect(
      registrar.registered.keys.every((id) => id.startsWith('inapp.')),
      isTrue,
    );
    await controller.initialize();
    expect(registrar.registered, hasLength(6));
  });

  test('打开全局开关补注册 6 条全局键，关闭后反注册', () async {
    await controller.initialize();
    expect(settings.globalShortcutsEnabled, isFalse);

    await controller.setGlobalShortcutsEnabled(true);
    expect(registrar.registered, hasLength(12));
    expect(settings.globalShortcutsEnabled, isTrue);

    await controller.setGlobalShortcutsEnabled(false);
    expect(registrar.registered, hasLength(6));
    expect(
      registrar.registered.keys.every((id) => id.startsWith('inapp.')),
      isTrue,
    );
    expect(settings.globalShortcutsEnabled, isFalse);
  });

  test('触发按下派发对应动作', () async {
    await controller.initialize();
    // 假注册器把回调藏在 register 时；这里用一个能捕获 handler 的变体。
    final capturing = _CapturingRegistrar();
    final local = MusicHotKeyController(
      settings: InMemoryMusicHotKeySettings(),
      registrar: capturing,
      onAction: actions.add,
    );
    await local.initialize();
    capturing.fireFirst();
    expect(actions, <MusicHotKeyAction>[MusicHotKeyAction.playPause]);
    await local.dispose();
  });

  test('录制期抑制动作派发', () async {
    final capturing = _CapturingRegistrar();
    final local = MusicHotKeyController(
      settings: InMemoryMusicHotKeySettings(),
      registrar: capturing,
      onAction: actions.add,
    );
    await local.initialize();
    local.setRecording(true);
    capturing.fireFirst();
    expect(actions, isEmpty);
    await local.dispose();
  });

  test('shouldHandle 返回 false 时忽略按键（输入框打字场景）', () async {
    bool gate = true;
    final capturing = _CapturingRegistrar();
    final local = MusicHotKeyController(
      settings: InMemoryMusicHotKeySettings(),
      registrar: capturing,
      onAction: actions.add,
      shouldHandle: (_) => gate,
    );
    await local.initialize();
    capturing.fireFirst();
    expect(actions, hasLength(1));
    gate = false;
    capturing.fireSecond();
    expect(actions, hasLength(1)); // 未增加
    await local.dispose();
  });

  test('rebind 反注册旧键、注册新键并落盘', () async {
    await controller.initialize();
    final id = defaultMusicHotKeyBindings.first.id;
    await controller.rebind(
      scope: MusicHotKeyScope.inApp,
      action: MusicHotKeyAction.playPause,
      recorded: HotKey(
        identifier: id,
        key: LogicalKeyboardKey.keyX,
        scope: HotKeyScope.inapp,
      ),
    );
    expect(registrar.registered[id]!.key, LogicalKeyboardKey.keyX);
    expect(
      settings.bindings.firstWhere((b) => b.id == id).key,
      LogicalKeyboardKey.keyX,
    );
  });

  test('rebind 撞已占用组合：抛冲突异常且不改变绑定', () async {
    await controller.initialize();
    // 把「下一首」改成与「播放/暂停」相同的 Ctrl+Space（基础组合）。
    expect(
      () => controller.rebind(
        scope: MusicHotKeyScope.inApp,
        action: MusicHotKeyAction.next,
        recorded: HotKey(
          identifier: 'inapp.next',
          key: LogicalKeyboardKey.space,
          modifiers: <HotKeyModifier>[HotKeyModifier.control],
          scope: HotKeyScope.inapp,
        ),
      ),
      throwsA(isA<MusicHotKeyConflictException>()),
    );
    expect(
      settings.bindings
          .firstWhere((b) => b.action == MusicHotKeyAction.next)
          .key,
      LogicalKeyboardKey.arrowRight,
    );
  });

  test('clear 反注册并从绑定表移除', () async {
    await controller.initialize();
    await controller.clear(MusicHotKeyScope.global, MusicHotKeyAction.next);
    expect(
      settings.bindings.any(
        (b) =>
            b.scope == MusicHotKeyScope.global &&
            b.action == MusicHotKeyAction.next,
      ),
      isFalse,
    );
  });

  test('resetToDefaults 恢复 12 条绑定；按开关只重注册 6 条本地键', () async {
    await controller.initialize();
    await controller.rebind(
      scope: MusicHotKeyScope.inApp,
      action: MusicHotKeyAction.playPause,
      recorded: HotKey(
        identifier: 'inapp.playPause',
        key: LogicalKeyboardKey.keyX,
        scope: HotKeyScope.inapp,
      ),
    );
    await controller.resetToDefaults();
    expect(settings.bindings, hasLength(12));
    expect(registrar.registered, hasLength(6));
  });

  test('resetAction 只重置指定动作的两个作用域', () async {
    await controller.initialize();
    await controller.rebind(
      scope: MusicHotKeyScope.inApp,
      action: MusicHotKeyAction.playPause,
      recorded: HotKey(
        identifier: 'inapp.playPause',
        key: LogicalKeyboardKey.keyX,
        scope: HotKeyScope.inapp,
      ),
    );
    await controller.resetAction(MusicHotKeyAction.playPause);
    expect(
      settings.bindings
          .firstWhere(
            (b) =>
                b.scope == MusicHotKeyScope.inApp &&
                b.action == MusicHotKeyAction.playPause,
          )
          .key,
      LogicalKeyboardKey.space,
    );
  });

  test('注册失败收集到 issues，不抛', () async {
    registrar.failOnRegister = StateError('system busy');
    await controller.initialize();
    // 只有 6 条本地键尝试注册并失败。
    expect(controller.issues.value, hasLength(6));
    expect(controller.issues.value.first, contains('注册失败'));
  });

  test('dispose 反注册全部并幂等', () async {
    await controller.initialize();
    await controller.dispose();
    expect(registrar.registered, isEmpty);
    await controller.dispose();
    expect(registrar.registered, isEmpty);
  });
}

/// 能捕获并触发 keyDownHandler 的注册器，用于验证动作派发。
class _CapturingRegistrar implements MusicHotKeyRegistrar {
  final Map<String, void Function(HotKey)> _handlers =
      <String, void Function(HotKey)>{};
  final Map<String, HotKey> _keys = <String, HotKey>{};

  @override
  Future<void> register(
    HotKey hotKey, {
    required void Function(HotKey hotKey) onPressed,
  }) async {
    _handlers[hotKey.identifier] = onPressed;
    _keys[hotKey.identifier] = hotKey;
  }

  void fireFirst() => _handlers.values.first(_keys.values.first);

  void fireSecond() => _handlers.values.elementAt(1)(_keys.values.elementAt(1));

  @override
  Future<void> unregister(HotKey hotKey) async {}

  @override
  Future<void> unregisterAll() async {}
}
