/// 音乐快捷键的本地设置缝：读/写用户重绑后的绑定列表。
///
/// 与 `music_settings.dart` 同款落盘策略——JSON 写在应用支持目录，构造不碰
/// path_provider（工厂 `MusicHotKeyFileSettings.openDefault` 才解析），读取失败
/// 回默认、写失败只影响持久化。独立接口而非塞进 [MusicSettings]：既有测试里
/// 四个 MusicSettings 假实现不用被迫补方法。
library;

import 'dart:convert';
import 'dart:io';

import 'package:mimao/music/hotkey/music_hotkey_model.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class MusicHotKeySettings {
  /// 当前绑定；[ensureLoaded] 之前返回出厂默认。
  List<MusicHotKeyBinding> get bindings;

  /// 是否启用系统级全局快捷键；与 EchoMusic 一致默认关闭——全局注册会抢占
  /// 系统组合键，必须用户显式打开。
  bool get globalShortcutsEnabled;

  Future<void> ensureLoaded();

  /// 整表替换写入（先改内存，再尽力落盘）。
  Future<void> setBindings(List<MusicHotKeyBinding> bindings);

  /// 写入「启用全局快捷键」开关。
  Future<void> setGlobalShortcutsEnabled(bool value);
}

/// 惰性解析的生产设置：注册期零插件调用，首个读写才构造文件实现。
class LazyMusicHotKeySettings implements MusicHotKeySettings {
  LazyMusicHotKeySettings(this._factory);

  final Future<MusicHotKeySettings> Function() _factory;

  MusicHotKeySettings? _delegate;
  Future<MusicHotKeySettings>? _resolving;

  Future<MusicHotKeySettings> _resolve() async {
    final existing = _delegate;
    if (existing != null) return existing;
    final resolving = _resolving ??= _factory().then(
      (settings) => _delegate = settings,
    );
    try {
      return await resolving;
    } finally {
      _resolving = null;
    }
  }

  @override
  List<MusicHotKeyBinding> get bindings =>
      List<MusicHotKeyBinding>.unmodifiable(
        _delegate?.bindings ?? defaultMusicHotKeyBindings,
      );

  @override
  bool get globalShortcutsEnabled => _delegate?.globalShortcutsEnabled ?? false;

  @override
  Future<void> ensureLoaded() async => (await _resolve()).ensureLoaded();

  @override
  Future<void> setBindings(List<MusicHotKeyBinding> bindings) async =>
      (await _resolve()).setBindings(bindings);

  @override
  Future<void> setGlobalShortcutsEnabled(bool value) async =>
      (await _resolve()).setGlobalShortcutsEnabled(value);
}

/// 内存实现：测试与「未接线」直接注入，不碰插件。
class InMemoryMusicHotKeySettings implements MusicHotKeySettings {
  InMemoryMusicHotKeySettings([List<MusicHotKeyBinding>? initial])
    : _bindings = initial == null
          ? List<MusicHotKeyBinding>.of(defaultMusicHotKeyBindings)
          : List<MusicHotKeyBinding>.of(initial);

  List<MusicHotKeyBinding> _bindings;
  bool _globalEnabled = false;

  @override
  List<MusicHotKeyBinding> get bindings =>
      List<MusicHotKeyBinding>.unmodifiable(_bindings);

  @override
  bool get globalShortcutsEnabled => _globalEnabled;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> setBindings(List<MusicHotKeyBinding> bindings) async {
    _bindings = List<MusicHotKeyBinding>.of(bindings);
  }

  @override
  Future<void> setGlobalShortcutsEnabled(bool value) async {
    _globalEnabled = value;
  }
}

/// 生产实现：`<应用支持目录>/music_settings/hotkeys.json`。
class MusicHotKeyFileSettings implements MusicHotKeySettings {
  MusicHotKeyFileSettings(this.directory);

  static Future<MusicHotKeyFileSettings> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return MusicHotKeyFileSettings(
      Directory('${support.path}${Platform.pathSeparator}music_settings'),
    );
  }

  final Directory directory;

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}hotkeys.json');

  List<MusicHotKeyBinding> _bindings = defaultMusicHotKeyBindings;
  bool _globalShortcutsEnabled = false;
  bool _loaded = false;
  Future<void>? _loading;

  @override
  List<MusicHotKeyBinding> get bindings =>
      List<MusicHotKeyBinding>.unmodifiable(_bindings);

  @override
  bool get globalShortcutsEnabled => _globalShortcutsEnabled;

  @override
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _bindings = decodeMusicHotKeyBindings(decoded['bindings']);
          final global = decoded['globalShortcutsEnabled'];
          if (global is bool) _globalShortcutsEnabled = global;
        }
      }
    } on Object {
      // 文件损坏/不可读：回默认绑定，不影响快捷键功能。
      _bindings = defaultMusicHotKeyBindings;
    } finally {
      _loaded = true;
    }
  }

  @override
  Future<void> setBindings(List<MusicHotKeyBinding> bindings) async {
    _bindings = List<MusicHotKeyBinding>.of(bindings);
    await _persist();
  }

  @override
  Future<void> setGlobalShortcutsEnabled(bool value) async {
    _globalShortcutsEnabled = value;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      final payload = <String, Object?>{
        'globalShortcutsEnabled': _globalShortcutsEnabled,
        'bindings': _bindings.map((e) => e.toJson()).toList(),
      };
      await _file.writeAsString('${encoder.convert(payload)}\n', flush: true);
    } on Object {
      // 写盘失败不挡本次会话的改键。
    }
  }
}
