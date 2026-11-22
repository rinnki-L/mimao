// ignore_for_file: deprecated_member_use — hotkey_manager 0.4.0 的 legacy.dart
// 同时导出已弃用的 KeyModifier 等；本文件只取 HotKey/HotKeyModifier/HotKeyScope
// 等现行符号，不触碰弃用项。
/// 音乐快捷键的数据模型：动作、两种作用域、可重绑的绑定与落盘格式。
///
/// 一套绑定同时描述「应用内快捷键」([MusicHotKeyScope.inApp]) 与
/// 「全局快捷键」([MusicHotKeyScope.global])，区别只在注册时传给
/// `hotKey_manager` 的 scope——inapp 只在应用聚焦时生效，global 是系统级。
/// 默认值逐条对照 EchoMusic：Ctrl+Space 播放/暂停、Ctrl+←→ 切歌、
/// Ctrl+Alt+←→ 快进快退、Ctrl+K 歌词、Ctrl+↑↓ 音量、Ctrl+M 静音、
/// Ctrl+L 收藏、Ctrl+P 播放模式；全局 = 基础组合再加 Shift。
/// 修饰键统一写 Ctrl / Alt / Shift（Cmd 键一律显示为 Ctrl）；用户可在设置里逐条改。
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// 可被快捷键触发的播放器动作。两种作用域共用同一套动作，模型统一。
/// 动作集对齐 EchoMusic 的 ShortcutCommand（去掉本应用无对应实现的桌面歌词
/// /侧边栏/Mini 模式等，保留全部有真实落点的动作）。
enum MusicHotKeyAction {
  playPause('播放 / 暂停'),
  previous('上一首'),
  next('下一首'),
  seekBackward('快退'),
  seekForward('快进'),
  toggleLyric('播放页歌词开关'),
  volumeUp('音量 +'),
  volumeDown('音量 -'),
  toggleMute('静音'),
  toggleFavorite('收藏当前歌曲'),
  togglePlayMode('切换播放模式');

  const MusicHotKeyAction(this.label);

  /// 设置页展示用的中文名（对齐 EchoMusic 的 shortcutItems 文案）。
  final String label;
}

/// 快捷键作用域：本地（窗口聚焦时生效）vs 系统全局。
/// 术语对齐 EchoMusic 设置页：本地就叫「快捷键」，系统级叫「全局快捷键」。
enum MusicHotKeyScope {
  inApp('inapp', '快捷键'),
  global('system', '全局快捷键');

  const MusicHotKeyScope(this.wireName, this.label);

  /// 与 `hotkey_manager` 的 `HotKeyScope.name` 对齐，便于落盘/调试。
  final String wireName;

  /// 设置页分组标题。
  final String label;

  HotKeyScope get hotKeyScope => switch (this) {
    inApp => HotKeyScope.inapp,
    global => HotKeyScope.system,
  };
}

/// 一条可重绑的快捷键：动作 + 作用域 + 主键 + 修饰键集合。
@immutable
class MusicHotKeyBinding {
  const MusicHotKeyBinding({
    required this.action,
    required this.scope,
    required this.key,
    this.modifiers = const <HotKeyModifier>[],
  });

  /// 稳定标识：作用域 + 动作。重绑只换按键，标识不变，注册器据此替换旧键。
  String get id => '${scope.wireName}.${action.name}';

  final MusicHotKeyAction action;
  final MusicHotKeyScope scope;
  final KeyboardKey key;

  /// 空列表表示无修饰键（如应用内的空格播放）。
  final List<HotKeyModifier> modifiers;

  /// 转成 `hotkey_manager` 注册用的 HotKey（保留本绑定的稳定标识）。
  HotKey toHotKey() => HotKey(
    identifier: id,
    key: key,
    modifiers: modifiers.isEmpty ? null : List<HotKeyModifier>.of(modifiers),
    scope: scope.hotKeyScope,
  );

  /// 用录制到的 HotKey 覆盖主键/修饰键，动作与作用域保持不变。
  MusicHotKeyBinding rebindWith(HotKey hotKey) => MusicHotKeyBinding(
    action: action,
    scope: scope,
    key: hotKey.key,
    modifiers: hotKey.modifiers ?? const <HotKeyModifier>[],
  );

  /// 展示文本沿用 EchoMusic 的紧凑写法：`Ctrl+Shift+Space`。
  /// 修饰键顺序固定，展示不随录制顺序抖动。
  String get displayText {
    final parts = <String>[
      for (final modifier in _orderedModifiers) _modifierLabel(modifier),
      _keyLabel(key),
    ];
    return parts.join('+');
  }

  List<HotKeyModifier> get _orderedModifiers {
    // 与 EchoMusic orderTokensForDisplay(win32) 一致：Ctrl → Shift → Alt → Win。
    const order = <HotKeyModifier>[
      HotKeyModifier.control,
      HotKeyModifier.shift,
      HotKeyModifier.alt,
      HotKeyModifier.meta,
      HotKeyModifier.capsLock,
      HotKeyModifier.fn,
    ];
    return order.where(modifiers.contains).toList();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'action': action.name,
    'scope': scope.wireName,
    'key': _keyToJson(key),
    'modifiers': modifiers.map((e) => e.name).toList(),
  };

  /// 反序列化；任一段非法返回 null（设置文件损坏时整条丢弃回默认值）。
  static MusicHotKeyBinding? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final actionName = raw['action'];
    final scopeWire = raw['scope'];
    final key = _keyFromJson(raw['key']);
    if (actionName is! String || scopeWire is! String || key == null) {
      return null;
    }
    MusicHotKeyAction? action;
    for (final candidate in MusicHotKeyAction.values) {
      if (candidate.name == actionName) {
        action = candidate;
        break;
      }
    }
    MusicHotKeyScope? scope;
    for (final candidate in MusicHotKeyScope.values) {
      if (candidate.wireName == scopeWire) {
        scope = candidate;
        break;
      }
    }
    if (action == null || scope == null) return null;
    final modifiers = <HotKeyModifier>[];
    final rawModifiers = raw['modifiers'];
    if (rawModifiers is List) {
      for (final name in rawModifiers) {
        if (name is! String) continue;
        for (final candidate in HotKeyModifier.values) {
          if (candidate.name == name) {
            modifiers.add(candidate);
            break;
          }
        }
      }
    }
    return MusicHotKeyBinding(
      action: action,
      scope: scope,
      key: key,
      modifiers: modifiers,
    );
  }

  static Map<String, Object?> _keyToJson(KeyboardKey key) {
    if (key is LogicalKeyboardKey) {
      return <String, Object?>{'keyId': key.keyId};
    }
    return <String, Object?>{
      'usageCode': (key as PhysicalKeyboardKey).usbHidUsage,
    };
  }

  static KeyboardKey? _keyFromJson(Object? raw) {
    if (raw is! Map) return null;
    final keyId = raw['keyId'];
    if (keyId is int) {
      final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
      if (key != null) return key;
    }
    final usageCode = raw['usageCode'];
    if (usageCode is int) {
      return PhysicalKeyboardKey.findKeyByCode(usageCode);
    }
    return null;
  }

  static String _modifierLabel(HotKeyModifier modifier) => switch (modifier) {
    HotKeyModifier.control => 'Ctrl',
    HotKeyModifier.alt => 'Alt',
    HotKeyModifier.shift => 'Shift',
    HotKeyModifier.meta => 'Win',
    HotKeyModifier.capsLock => 'Caps',
    HotKeyModifier.fn => 'Fn',
  };

  static String _keyLabel(KeyboardKey key) {
    // 统一走 HotKey.logicalKey（包内已处理 Physical → Logical 的换算），
    // 不依赖 Flutter 版本间不稳定的 PhysicalKeyboardKey.logicalKey getter。
    // 主键标签沿用 EchoMusic 的 SPECIAL_KEY_LABELS：Space / Left / Right / Up / Down。
    final logical = HotKey(key: key).logicalKey;
    return switch (logical) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.arrowLeft => 'Left',
      LogicalKeyboardKey.arrowRight => 'Right',
      LogicalKeyboardKey.arrowUp => 'Up',
      LogicalKeyboardKey.arrowDown => 'Down',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.escape => 'Escape',
      _ => _logicalKeyLabel(logical),
    };
  }

  /// 逻辑键的可读名：优先取 keyLabel 扩展，退化到 debugName。
  static String _logicalKeyLabel(LogicalKeyboardKey logical) {
    final label = logical.keyLabel;
    if (label.isNotEmpty && label != logical.debugName) return label;
    final name = logical.debugName;
    if (name == null) return '未知键';
    // debugName 形如 "Key A" / "Digit 1"，取最后一段可读部分。
    return name.split(' ').last;
  }
}

/// 两种作用域共用的主键常量（逻辑键，跨左右物理键稳定）。
abstract final class _K {
  static const space = LogicalKeyboardKey.space;
  static const left = LogicalKeyboardKey.arrowLeft;
  static const right = LogicalKeyboardKey.arrowRight;
  static const up = LogicalKeyboardKey.arrowUp;
  static const down = LogicalKeyboardKey.arrowDown;
  static const k = LogicalKeyboardKey.keyK;
  static const l = LogicalKeyboardKey.keyL;
  static const m = LogicalKeyboardKey.keyM;
  static const p = LogicalKeyboardKey.keyP;
}

/// 修饰键组合，全部以 Ctrl 为基础（EchoMusic 的 Cmd 在 Windows 就是 Ctrl，
/// 本应用统一写成 Ctrl）；全局 = 基础组合再加 Shift。
const _ctrl = <HotKeyModifier>[HotKeyModifier.control];
const _ctrlShift = <HotKeyModifier>[
  HotKeyModifier.control,
  HotKeyModifier.shift,
];
const _ctrlAlt = <HotKeyModifier>[HotKeyModifier.control, HotKeyModifier.alt];
const _ctrlAltShift = <HotKeyModifier>[
  HotKeyModifier.control,
  HotKeyModifier.alt,
  HotKeyModifier.shift,
];

/// 出厂默认绑定：11 动作 × 2 作用域 = 22 条，键位逐条对照 EchoMusic
/// `DEFAULT_SHORTCUT_LABELS` / `DEFAULT_GLOBAL_SHORTCUT_LABELS`（Cmd→Ctrl、
/// Option→Alt、Shift→Shift）：
///   播放 Ctrl+Space / 切歌 Ctrl+←→ / 快进快退 Ctrl+Alt+←→ /
///   歌词 Ctrl+K / 音量 Ctrl+↑↓ / 静音 Ctrl+M / 收藏 Ctrl+L / 模式 Ctrl+P；
///   全局一律在基础组合上再加 Shift。
const List<MusicHotKeyBinding> defaultMusicHotKeyBindings =
    <MusicHotKeyBinding>[
      // ── 快捷键（窗口聚焦时生效）──
      MusicHotKeyBinding(
        action: MusicHotKeyAction.playPause,
        scope: MusicHotKeyScope.inApp,
        key: _K.space,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.previous,
        scope: MusicHotKeyScope.inApp,
        key: _K.left,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.next,
        scope: MusicHotKeyScope.inApp,
        key: _K.right,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.seekBackward,
        scope: MusicHotKeyScope.inApp,
        key: _K.left,
        modifiers: _ctrlAlt,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.seekForward,
        scope: MusicHotKeyScope.inApp,
        key: _K.right,
        modifiers: _ctrlAlt,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.toggleLyric,
        scope: MusicHotKeyScope.inApp,
        key: _K.k,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.volumeUp,
        scope: MusicHotKeyScope.inApp,
        key: _K.up,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.volumeDown,
        scope: MusicHotKeyScope.inApp,
        key: _K.down,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.toggleMute,
        scope: MusicHotKeyScope.inApp,
        key: _K.m,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.toggleFavorite,
        scope: MusicHotKeyScope.inApp,
        key: _K.l,
        modifiers: _ctrl,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.togglePlayMode,
        scope: MusicHotKeyScope.inApp,
        key: _K.p,
        modifiers: _ctrl,
      ),
      // ── 全局快捷键（基础组合 + Shift）──
      MusicHotKeyBinding(
        action: MusicHotKeyAction.playPause,
        scope: MusicHotKeyScope.global,
        key: _K.space,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.previous,
        scope: MusicHotKeyScope.global,
        key: _K.left,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.next,
        scope: MusicHotKeyScope.global,
        key: _K.right,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.seekBackward,
        scope: MusicHotKeyScope.global,
        key: _K.left,
        modifiers: _ctrlAltShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.seekForward,
        scope: MusicHotKeyScope.global,
        key: _K.right,
        modifiers: _ctrlAltShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.toggleLyric,
        scope: MusicHotKeyScope.global,
        key: _K.k,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.volumeUp,
        scope: MusicHotKeyScope.global,
        key: _K.up,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.volumeDown,
        scope: MusicHotKeyScope.global,
        key: _K.down,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.toggleMute,
        scope: MusicHotKeyScope.global,
        key: _K.m,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.toggleFavorite,
        scope: MusicHotKeyScope.global,
        key: _K.l,
        modifiers: _ctrlShift,
      ),
      MusicHotKeyBinding(
        action: MusicHotKeyAction.togglePlayMode,
        scope: MusicHotKeyScope.global,
        key: _K.p,
        modifiers: _ctrlShift,
      ),
    ];

/// 把落盘数组读回绑定列表：逐条解析，非法条目跳过；再以默认值为底合并，
/// 保证以后新增动作时老配置文件也自动补齐新默认键（兼容标识即契约）。
List<MusicHotKeyBinding> decodeMusicHotKeyBindings(Object? raw) {
  final result = <MusicHotKeyBinding>[...defaultMusicHotKeyBindings];
  if (raw is! List) return result;
  final parsed = <MusicHotKeyBinding>[];
  for (final item in raw) {
    final binding = MusicHotKeyBinding.fromJson(item);
    if (binding == null) continue;
    final index = result.indexWhere((existing) => existing.id == binding.id);
    if (index >= 0) {
      result[index] = binding;
    } else {
      parsed.add(binding);
    }
  }
  return <MusicHotKeyBinding>[...result, ...parsed];
}

/// 两条绑定是否占用同一个组合（同作用域 + 同主键 + 同修饰键集合）。
/// 用于改键时拒绝冲突——系统只会把按键派发给其中一个，静默冲突最难排查。
bool musicHotKeyConflicts(MusicHotKeyBinding a, MusicHotKeyBinding b) {
  if (a.scope != b.scope) return false;
  // 统一经 HotKey.logicalKey 归一化主键，逻辑键/物理键混合录制也能正确比对。
  if (HotKey(key: a.key).logicalKey.keyId !=
      HotKey(key: b.key).logicalKey.keyId) {
    return false;
  }
  final aMods = a.modifiers.toSet();
  final bMods = b.modifiers.toSet();
  return aMods.length == bMods.length && aMods.containsAll(bMods);
}
