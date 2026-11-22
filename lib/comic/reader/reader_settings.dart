// 阅读偏好持久化：key 前缀 `reader.*`，走 core 的统一 app_settings kv
//（布尔统一存 'true'/'false'，与 SettingsRepository 的惯例一致）。
//
// 窄接口 [ReaderSettingsStore] 让控制器与面板不认识 drift；生产实现读
// [SettingsRepository]，测试用 [InMemoryReaderSettingsStore]。

import 'package:mimao/core/settings.dart';

import 'reader_models.dart';

/// 阅读偏好存取窄接口。load 失败（库打不开等）由调用方兜底默认值。
abstract interface class ReaderSettingsStore {
  Future<ReaderSettings> load();

  /// 写失败不抛出（fire-and-forget 场景多），由实现自行收敛为日志。
  Future<void> save(ReaderSettings settings);
}

/// 生产实现：app_settings kv，key 命名沿用模块的 `domain.key` 惯例。
class SettingsReaderSettingsStore implements ReaderSettingsStore {
  SettingsReaderSettingsStore(this._settings);

  final SettingsRepository _settings;

  static const String _kMode = 'reader.mode';
  static const String _kPreload = 'reader.preloadCount';
  static const String _kTap = 'reader.tapToTurn';
  static const String _kDoubleTap = 'reader.doubleTapZoom';

  @override
  Future<ReaderSettings> load() async {
    const fallback = ReaderSettings();
    try {
      final modeName = await _settings.get(_kMode);
      final mode = ReaderMode.values
          .where((m) => m.name == modeName)
          .firstOrNull;
      final preload = int.tryParse((await _settings.get(_kPreload)) ?? '');
      return ReaderSettings(
        mode: mode ?? fallback.mode,
        preloadCount: preload ?? fallback.preloadCount,
        tapToTurn: await _settings.getBool(_kTap, fallback: fallback.tapToTurn),
        doubleTapZoom: await _settings.getBool(
          _kDoubleTap,
          fallback: fallback.doubleTapZoom,
        ),
      ).normalized();
    } on Object {
      // 设置读取失败不该挡住阅读：回默认值。
      return fallback;
    }
  }

  @override
  Future<void> save(ReaderSettings settings) async {
    final normalized = settings.normalized();
    await _settings.set(_kMode, normalized.mode.name);
    await _settings.set(_kPreload, '${normalized.preloadCount}');
    await _settings.setBool(_kTap, normalized.tapToTurn);
    await _settings.setBool(_kDoubleTap, normalized.doubleTapZoom);
  }
}

/// 测试/离线用内存版（生产不接线；惯例同 reader_cache.dart 的 MemoryByteStore）。
class InMemoryReaderSettingsStore implements ReaderSettingsStore {
  ReaderSettings value;

  InMemoryReaderSettingsStore([this.value = const ReaderSettings()]);

  @override
  Future<ReaderSettings> load() async => value;

  @override
  Future<void> save(ReaderSettings settings) async => value = settings;
}
