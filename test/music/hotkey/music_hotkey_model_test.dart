/// 音乐快捷键模型与落盘测试：默认值覆盖 6 动作 × 2 作用域、JSON 往返、
/// 损坏条目跳过、冲突检测。纯数据，不初始化 native 插件。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mimao/music/hotkey/music_hotkey_model.dart';
import 'package:mimao/music/hotkey/music_hotkey_settings.dart';

void main() {
  group('默认绑定', () {
    test('11 动作 × 2 作用域 = 22 条，id 唯一', () {
      expect(defaultMusicHotKeyBindings, hasLength(22));
      final ids = defaultMusicHotKeyBindings.map((e) => e.id).toSet();
      expect(ids, hasLength(22));
      for (final scope in MusicHotKeyScope.values) {
        final actions = defaultMusicHotKeyBindings
            .where((e) => e.scope == scope)
            .map((e) => e.action)
            .toSet();
        expect(actions, MusicHotKeyAction.values.toSet());
      }
    });

    test('基础组合 Ctrl+Space，全局 = 基础组合再加 Shift（Ctrl+Shift+Space）', () {
      final inAppPlay = defaultMusicHotKeyBindings.firstWhere(
        (e) =>
            e.scope == MusicHotKeyScope.inApp &&
            e.action == MusicHotKeyAction.playPause,
      );
      expect(inAppPlay.key, LogicalKeyboardKey.space);
      expect(inAppPlay.modifiers, <HotKeyModifier>[HotKeyModifier.control]);
      expect(inAppPlay.displayText, 'Ctrl+Space');

      final globalPlay = defaultMusicHotKeyBindings.firstWhere(
        (e) =>
            e.scope == MusicHotKeyScope.global &&
            e.action == MusicHotKeyAction.playPause,
      );
      expect(globalPlay.key, LogicalKeyboardKey.space);
      expect(globalPlay.modifiers, contains(HotKeyModifier.control));
      expect(globalPlay.modifiers, contains(HotKeyModifier.shift));
      expect(globalPlay.displayText, 'Ctrl+Shift+Space');

      // 每条全局绑定 = 对应应用内绑定 + Shift，主键不变。
      for (final action in MusicHotKeyAction.values) {
        final inApp = defaultMusicHotKeyBindings.firstWhere(
          (e) => e.scope == MusicHotKeyScope.inApp && e.action == action,
        );
        final global = defaultMusicHotKeyBindings.firstWhere(
          (e) => e.scope == MusicHotKeyScope.global && e.action == action,
        );
        expect(global.key, inApp.key, reason: '${action.label} 主键应一致');
        expect(
          global.modifiers.toSet().difference(inApp.modifiers.toSet()),
          <HotKeyModifier>{HotKeyModifier.shift},
          reason: '${action.label} 全局应只在应用内基础上多一个 Shift',
        );
      }
    });

    test('扩展动作键位对齐 EchoMusic（Ctrl+Alt 快进快退、Ctrl+K/L/P 等）', () {
      String localLabel(MusicHotKeyAction action) => defaultMusicHotKeyBindings
          .firstWhere(
            (e) => e.scope == MusicHotKeyScope.inApp && e.action == action,
          )
          .displayText;
      expect(localLabel(MusicHotKeyAction.seekBackward), 'Ctrl+Alt+Left');
      expect(localLabel(MusicHotKeyAction.seekForward), 'Ctrl+Alt+Right');
      expect(localLabel(MusicHotKeyAction.toggleLyric), 'Ctrl+K');
      expect(localLabel(MusicHotKeyAction.toggleFavorite), 'Ctrl+L');
      expect(localLabel(MusicHotKeyAction.togglePlayMode), 'Ctrl+P');
    });

    test('toHotKey 保留稳定 id，映射正确作用域', () {
      final binding = defaultMusicHotKeyBindings.first;
      final hotKey = binding.toHotKey();
      expect(hotKey.identifier, binding.id);
      expect(hotKey.scope, HotKeyScope.inapp);
    });
  });

  group('JSON 往返', () {
    test('每条默认绑定序列化后能原样读回', () {
      for (final binding in defaultMusicHotKeyBindings) {
        final decoded = MusicHotKeyBinding.fromJson(binding.toJson());
        expect(decoded, isNotNull, reason: '${binding.id} 应可反序列化');
        expect(decoded!.action, binding.action);
        expect(decoded.scope, binding.scope);
        expect(decoded.key, binding.key);
        expect(decoded.modifiers, binding.modifiers);
      }
    });

    test('整表编解码保留全部条目', () {
      final encoded = jsonEncode(<String, Object?>{
        'bindings': defaultMusicHotKeyBindings.map((e) => e.toJson()).toList(),
      });
      final decoded = decodeMusicHotKeyBindings(
        jsonDecode(encoded)['bindings'],
      );
      expect(decoded, hasLength(22));
    });

    test('损坏条目跳过；缺失动作回默认（兼容老配置文件）', () {
      final decoded = decodeMusicHotKeyBindings(<Object?>[
        <String, Object?>{'action': 'bogus', 'scope': 'inapp', 'key': {}},
        <String, Object?>{
          'action': 'next',
          'scope': 'system',
          'key': <String, Object?>{'keyId': LogicalKeyboardKey.keyN.keyId},
          'modifiers': <String>['control'],
        },
      ]);
      // bogus 被跳过；next 命中已有 id（global.next）原地替换 → 仍是 22 条。
      expect(decoded, hasLength(22));
      final next = decoded.firstWhere(
        (e) =>
            e.scope == MusicHotKeyScope.global &&
            e.action == MusicHotKeyAction.next,
      );
      expect(next.key, LogicalKeyboardKey.keyN);
      expect(next.modifiers, <HotKeyModifier>[HotKeyModifier.control]);
    });
  });

  group('冲突检测', () {
    MusicHotKeyBinding binding(
      MusicHotKeyScope scope,
      LogicalKeyboardKey key, [
      List<HotKeyModifier> modifiers = const <HotKeyModifier>[],
    ]) => MusicHotKeyBinding(
      action: MusicHotKeyAction.playPause,
      scope: scope,
      key: key,
      modifiers: modifiers,
    );

    test('同作用域同键同修饰 = 冲突', () {
      expect(
        musicHotKeyConflicts(
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.space),
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.space),
        ),
        isTrue,
      );
      expect(
        musicHotKeyConflicts(
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.keyP, const [
            HotKeyModifier.control,
          ]),
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.keyP, const [
            HotKeyModifier.control,
          ]),
        ),
        isTrue,
      );
    });

    test('不同作用域 / 不同键 / 不同修饰均不冲突', () {
      expect(
        musicHotKeyConflicts(
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.space),
          binding(MusicHotKeyScope.global, LogicalKeyboardKey.space),
        ),
        isFalse,
      );
      expect(
        musicHotKeyConflicts(
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.space),
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.keyP),
        ),
        isFalse,
      );
      expect(
        musicHotKeyConflicts(
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.space),
          binding(MusicHotKeyScope.inApp, LogicalKeyboardKey.space, const [
            HotKeyModifier.control,
          ]),
        ),
        isFalse,
      );
    });
  });

  group('文件设置', () {
    late Directory root;
    late MusicHotKeyFileSettings settings;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('mimao_hotkeys_');
      settings = MusicHotKeyFileSettings(root);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('无文件回默认；写入后新实例可读回', () async {
      await settings.ensureLoaded();
      expect(settings.bindings, hasLength(22));

      final changed = <MusicHotKeyBinding>[...settings.bindings]
        ..[0] = MusicHotKeyBinding(
          action: MusicHotKeyAction.playPause,
          scope: MusicHotKeyScope.inApp,
          key: LogicalKeyboardKey.keyX,
        );
      await settings.setBindings(changed);

      final reloaded = MusicHotKeyFileSettings(root);
      await reloaded.ensureLoaded();
      expect(
        reloaded.bindings
            .firstWhere((e) => e.action == MusicHotKeyAction.playPause)
            .key,
        LogicalKeyboardKey.keyX,
      );
    });

    test('全局快捷键开关默认关闭，开启后落盘可读回', () async {
      await settings.ensureLoaded();
      expect(settings.globalShortcutsEnabled, isFalse);
      await settings.setGlobalShortcutsEnabled(true);

      final reloaded = MusicHotKeyFileSettings(root);
      await reloaded.ensureLoaded();
      expect(reloaded.globalShortcutsEnabled, isTrue);
    });

    test('损坏文件回默认不崩', () async {
      final file = File('${root.path}${Platform.pathSeparator}hotkeys.json');
      await root.create(recursive: true);
      await file.writeAsString('{ broken json');
      final reloaded = MusicHotKeyFileSettings(root);
      await reloaded.ensureLoaded();
      expect(reloaded.bindings, hasLength(22));
      expect(reloaded.globalShortcutsEnabled, isFalse);
    });
  });
}
