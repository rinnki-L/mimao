// 键盘辅助：可配置的「按键组合 → 阅读动作」映射。
//
// 动作复用点击区那套 [NovelClickAction]（不新造动作枚举）；键位串形如
// `Ctrl+ArrowRight` / `Space` / `F5`，只认 [novelKeyboardKeyTable] 里列出的键
// （够阅读器用，且能稳定落库/往返）。默认表与改造前写死在阅读页的快捷键
// 完全一致，用户不动配置时行为不变。
//
// 默认表之外的 Home / End / Escape 仍是阅读页保留键（不是
// [NovelClickAction] 能表达的动作），不进这张可配置表。
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:mimao/novel/library_api.dart'
    show NovelPrefsApi, novelPrefKeyboardAssist;
import 'package:mimao/novel/reader/novel_click_actions.dart';

/// 一条按键映射。
class NovelKeyboardBinding {
  const NovelKeyboardBinding({
    required this.keys,
    required this.action,
    this.enabled = true,
  });

  /// 规范化键位串（`Ctrl+Shift+ArrowRight`）。
  final String keys;

  final NovelClickAction action;
  final bool enabled;

  NovelKeyboardBinding copyWith({
    String? keys,
    NovelClickAction? action,
    bool? enabled,
  }) => NovelKeyboardBinding(
    keys: keys ?? this.keys,
    action: action ?? this.action,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'keys': keys,
    'action': action.name,
    'enabled': enabled,
  };

  /// 坏数据返回 null（调用方跳过这一条）。
  static NovelKeyboardBinding? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final keys = '${raw['keys'] ?? ''}'.trim();
    if (keys.isEmpty) return null;
    final action = _actionByName('${raw['action'] ?? ''}');
    if (action == null) return null;
    final enabled = raw['enabled'];
    return NovelKeyboardBinding(
      keys: keys,
      action: action,
      enabled: enabled is bool ? enabled : true,
    );
  }

  static NovelClickAction? _actionByName(String name) {
    for (final action in NovelClickAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }
}

/// 键盘辅助整体配置。
class NovelKeyboardConfig {
  const NovelKeyboardConfig({
    this.bindings = novelDefaultKeyboardBindings,
    this.showHints = false,
  });

  final List<NovelKeyboardBinding> bindings;

  /// 「按键提示浮层」开关（桌面端可选；默认关）。
  final bool showHints;

  static const NovelKeyboardConfig defaults = NovelKeyboardConfig();

  NovelKeyboardConfig copyWith({
    List<NovelKeyboardBinding>? bindings,
    bool? showHints,
  }) => NovelKeyboardConfig(
    bindings: bindings ?? this.bindings,
    showHints: showHints ?? this.showHints,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'showHints': showHints,
    'bindings': <Object?>[for (final item in bindings) item.toJson()],
  };

  String encode() => jsonEncode(toJson());

  /// 容错解码：缺字段/坏条目回退默认，不让一条坏配置把阅读器卡住。
  static NovelKeyboardConfig decode(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return defaults;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return defaults;
      final list = decoded['bindings'];
      final bindings = <NovelKeyboardBinding>[];
      if (list is List) {
        for (final item in list) {
          final parsed = NovelKeyboardBinding.fromJson(item);
          if (parsed != null) bindings.add(parsed);
        }
      }
      return NovelKeyboardConfig(
        bindings: bindings.isEmpty
            ? novelDefaultKeyboardBindings
            : normalizedNovelKeyboardBindings(bindings),
        showHints: decoded['showHints'] == true,
      );
    } on Object {
      return defaults;
    }
  }
}

/// 模块 kv 版存储（与阅读设置分开：键位是设备偏好，不进主题包设置块）。
class NovelKeyboardAssistStore {
  NovelKeyboardAssistStore(this.prefs);

  final NovelPrefsApi? prefs;

  NovelKeyboardConfig _memory = NovelKeyboardConfig.defaults;

  Future<NovelKeyboardConfig> load() async {
    final api = prefs;
    if (api == null) return _memory;
    try {
      final raw = await api.read(novelPrefKeyboardAssist);
      final config = NovelKeyboardConfig.decode(raw);
      _memory = config;
      return config;
    } on Object {
      return _memory;
    }
  }

  Future<void> save(NovelKeyboardConfig config) async {
    _memory = config;
    final api = prefs;
    if (api == null) return;
    try {
      await api.write(novelPrefKeyboardAssist, config.encode());
    } on Object {
      // 写失败不影响本次阅读；下次进入仍是上一次成功保存的配置。
    }
  }
}

/// 可配置的键位表（键名小写 → Flutter 逻辑键）。
///
/// 只覆盖阅读器需要的键：方向键/翻页键/空格/Esc + 字母数字 + F1-F12。
final Map<String, LogicalKeyboardKey> novelKeyboardKeyTable =
    <String, LogicalKeyboardKey>{
      'arrowleft': LogicalKeyboardKey.arrowLeft,
      'arrowright': LogicalKeyboardKey.arrowRight,
      'arrowup': LogicalKeyboardKey.arrowUp,
      'arrowdown': LogicalKeyboardKey.arrowDown,
      'pageup': LogicalKeyboardKey.pageUp,
      'pagedown': LogicalKeyboardKey.pageDown,
      'home': LogicalKeyboardKey.home,
      'end': LogicalKeyboardKey.end,
      'space': LogicalKeyboardKey.space,
      'escape': LogicalKeyboardKey.escape,
      'enter': LogicalKeyboardKey.enter,
      'tab': LogicalKeyboardKey.tab,
      'backspace': LogicalKeyboardKey.backspace,
      'delete': LogicalKeyboardKey.delete,
      'insert': LogicalKeyboardKey.insert,
      'f1': LogicalKeyboardKey.f1,
      'f2': LogicalKeyboardKey.f2,
      'f3': LogicalKeyboardKey.f3,
      'f4': LogicalKeyboardKey.f4,
      'f5': LogicalKeyboardKey.f5,
      'f6': LogicalKeyboardKey.f6,
      'f7': LogicalKeyboardKey.f7,
      'f8': LogicalKeyboardKey.f8,
      'f9': LogicalKeyboardKey.f9,
      'f10': LogicalKeyboardKey.f10,
      'f11': LogicalKeyboardKey.f11,
      'f12': LogicalKeyboardKey.f12,
      for (final code in 'abcdefghijklmnopqrstuvwxyz0123456789'.split(''))
        code: LogicalKeyboardKey(code.codeUnitAt(0)),
    };

/// 反向表：逻辑键 → 规范键名（显示与落库用）。
final Map<int, String> novelKeyboardKeyNames = <int, String>{
  for (final entry in novelKeyboardKeyTable.entries)
    entry.value.keyId: entry.key,
};

/// 键位串的展示写法（方向键/翻页键按人习惯大写，字母数字保持小写）。
const Map<String, String> novelKeyboardKeyLabels = <String, String>{
  'arrowleft': 'ArrowLeft',
  'arrowright': 'ArrowRight',
  'arrowup': 'ArrowUp',
  'arrowdown': 'ArrowDown',
  'pageup': 'PageUp',
  'pagedown': 'PageDown',
  'home': 'Home',
  'end': 'End',
  'space': 'Space',
  'escape': 'Escape',
  'enter': 'Enter',
  'tab': 'Tab',
  'backspace': 'Backspace',
  'delete': 'Delete',
  'insert': 'Insert',
  'f1': 'F1',
  'f2': 'F2',
  'f3': 'F3',
  'f4': 'F4',
  'f5': 'F5',
  'f6': 'F6',
  'f7': 'F7',
  'f8': 'F8',
  'f9': 'F9',
  'f10': 'F10',
  'f11': 'F11',
  'f12': 'F12',
};

/// 把键位串解析成 [SingleActivator]；认不出返回 null（调用方跳过并提示）。
SingleActivator? novelShortcutFor(String keys) {
  final parts = keys
      .split('+')
      .map((part) => part.trim().toLowerCase())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  var control = false;
  var shift = false;
  var alt = false;
  var meta = false;
  LogicalKeyboardKey? key;
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    final isLast = i == parts.length - 1;
    switch (part) {
      case 'ctrl':
      case 'control':
        control = true;
      case 'shift':
        shift = true;
      case 'alt':
      case 'option':
        alt = true;
      case 'meta':
      case 'win':
      case 'cmd':
      case 'super':
        meta = true;
      default:
        if (!isLast) return null;
        key = novelKeyboardKeyTable[part];
        if (key == null) return null;
    }
  }
  if (key == null) return null;
  return SingleActivator(
    key,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );
}

/// 把一次按键事件归一成规范键位串（对话框捕获用）；认不出返回 null。
String? novelKeySpecOf(
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool meta = false,
}) {
  final name = novelKeyboardKeyNames[key.keyId];
  if (name == null) return null;
  final label = novelKeyboardKeyLabels[name] ?? name;
  final parts = <String>[
    if (control) 'Ctrl',
    if (shift) 'Shift',
    if (alt) 'Alt',
    if (meta) 'Meta',
    label,
  ];
  return parts.join('+');
}

/// 清洗一份配置：丢掉停用/不可用/认不出的条目，同键位只留第一条。
List<NovelKeyboardBinding> normalizedNovelKeyboardBindings(
  Iterable<NovelKeyboardBinding> bindings,
) {
  final result = <NovelKeyboardBinding>[];
  final seen = <String>{};
  final seenActivators = <SingleActivator>{};
  for (final item in bindings) {
    if (!item.enabled) continue;
    if (!item.action.available || item.action == NovelClickAction.none) {
      continue;
    }
    final activator = novelShortcutFor(item.keys);
    if (activator == null) continue;
    final spec = item.keys.trim().toLowerCase();
    if (!seen.add(spec)) continue;
    if (!seenActivators.add(activator)) continue;
    result.add(
      NovelKeyboardBinding(
        keys:
            novelKeySpecOf(
              activator.trigger,
              control: activator.control,
              shift: activator.shift,
              alt: activator.alt,
              meta: activator.meta,
            ) ??
            item.keys,
        action: item.action,
      ),
    );
  }
  return List<NovelKeyboardBinding>.unmodifiable(result);
}

/// 默认键位：与改造前阅读页写死的那套一致（←→↑↓ / PageUp/Down / 空格）。
const List<NovelKeyboardBinding>
novelDefaultKeyboardBindings = <NovelKeyboardBinding>[
  NovelKeyboardBinding(
    keys: 'ArrowLeft',
    action: NovelClickAction.previousPage,
  ),
  NovelKeyboardBinding(keys: 'ArrowRight', action: NovelClickAction.nextPage),
  NovelKeyboardBinding(keys: 'ArrowUp', action: NovelClickAction.previousPage),
  NovelKeyboardBinding(keys: 'ArrowDown', action: NovelClickAction.nextPage),
  NovelKeyboardBinding(keys: 'PageUp', action: NovelClickAction.previousPage),
  NovelKeyboardBinding(keys: 'PageDown', action: NovelClickAction.nextPage),
  NovelKeyboardBinding(keys: 'Space', action: NovelClickAction.autoPage),
];

/// 可选动作（下拉用）：已实现且不是「无动作」的点击区动作。
List<NovelClickAction> novelKeyboardAssignableActions() => <NovelClickAction>[
  for (final action in NovelClickAction.values)
    if (action.available && action != NovelClickAction.none) action,
];
