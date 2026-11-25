/// 备份相关设置：加密开关、自动备份模式、设备名、上次自动备份结果。
///
/// kv 键集中在这里（与 `library_api.dart` 的阅读设置键同风格）；判定逻辑抽成
/// 纯函数 [shouldAutoBackup]，便于单测而不必起定时器。
library;

import 'dart:io';

import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/library_api.dart';

/// 备份文件是否加密。密码本身不进 kv（见 [novelBackupPasswordCredentialKey]）。
const String novelWebdavEncryptKey = 'webdav_encrypt';

/// 自动备份模式：`off` / `exit` / `daily`。
const String novelWebdavAutoModeKey = 'webdav_auto_mode';

/// 上次自动备份尝试的时间（ISO 8601）。
const String novelWebdavLastAutoAtKey = 'webdav_last_auto_at';

/// 上次自动备份结果的一句话（成功/失败 + 原因），给备份页显示。
const String novelWebdavLastAutoResultKey = 'webdav_last_auto_result';

/// 是否自动同步进度。
const String novelWebdavProgressAutoKey = 'webdav_progress_auto';

/// 上次成功备份的时间（ISO 8601），首页卡片据此显示"N 天前备份"。
const String novelWebdavLastBackupAtKey = 'webdav_last_backup_at';

/// 本机在备份里的显示名。
const String novelWebdavDeviceNameKey = 'webdav_device_name';

/// 自动备份模式。
enum NovelAutoBackupMode {
  off('off', '关闭'),
  onExit('exit', '每次退出时'),
  daily('daily', '每天一次');

  const NovelAutoBackupMode(this.key, this.label);

  final String key;
  final String label;

  static NovelAutoBackupMode parse(Object? raw) {
    final text = '${raw ?? ''}'.trim().toLowerCase();
    for (final value in values) {
      if (value.key == text) return value;
    }
    return off;
  }
}

/// 一次自动备份的判定：`daily` 用 24 小时而不是"跨过零点"——
/// 避开时区/DST 与"今天开过机就永远不备"的边界。
bool shouldAutoBackup({
  required NovelAutoBackupMode mode,
  DateTime? lastAt,
  required DateTime now,
}) => switch (mode) {
  NovelAutoBackupMode.off => false,
  NovelAutoBackupMode.onExit => true,
  NovelAutoBackupMode.daily =>
    lastAt == null || now.difference(lastAt) >= const Duration(hours: 24),
};

/// 上次自动备份结果的落库形状。
class NovelAutoBackupResult {
  const NovelAutoBackupResult({
    required this.at,
    required this.ok,
    this.message = '',
  });

  final DateTime at;
  final bool ok;
  final String message;

  String encode() =>
      '${ok ? 'ok' : 'fail'}|'
      '${at.toIso8601String()}|$message';

  static NovelAutoBackupResult? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length < 2) return null;
    final at = DateTime.tryParse(parts[1]);
    if (at == null) return null;
    return NovelAutoBackupResult(
      at: at,
      ok: parts[0] == 'ok',
      message: parts.length > 2 ? parts.sublist(2).join('|') : '',
    );
  }

  /// 界面上的一行话。
  String get label {
    final clock =
        '${at.year}-${_two(at.month)}-${_two(at.day)} '
        '${_two(at.hour)}:${_two(at.minute)}';
    return ok ? '上次自动备份：$clock 成功' : '上次自动备份：$clock 失败 · $message';
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 本机默认显示名（桌面用主机名，其它平台给个通用名）。
///
/// 只用于在预览页说清"这份备份来自哪台设备"，不参与任何主键。
String defaultNovelDeviceName() {
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    }
  } on Object {
    // 拿不到主机名就用兜底名。
  }
  return Platform.isAndroid ? 'Android' : '本机';
}

/// 备份设置的读写门面（薄包装，便于页面与自动备份共用同一套默认值）。
class NovelBackupSettings {
  const NovelBackupSettings({
    required this.mode,
    required this.encrypt,
    required this.progressAuto,
    required this.deviceName,
    this.lastAuto,
  });

  final NovelAutoBackupMode mode;
  final bool encrypt;
  final bool progressAuto;
  final String deviceName;
  final NovelAutoBackupResult? lastAuto;

  static Future<NovelBackupSettings> load(
    NovelPrefsApi prefs, {
    String? fallbackDeviceName,
  }) async {
    final rawName = await prefs.read(novelWebdavDeviceNameKey);
    final name = (rawName == null || rawName.trim().isEmpty)
        ? (fallbackDeviceName ?? defaultNovelDeviceName())
        : rawName.trim();
    return NovelBackupSettings(
      mode: NovelAutoBackupMode.parse(await prefs.read(novelWebdavAutoModeKey)),
      encrypt: (await prefs.read(novelWebdavEncryptKey)) == 'true',
      progressAuto: (await prefs.read(novelWebdavProgressAutoKey)) == 'true',
      deviceName: name,
      lastAuto: NovelAutoBackupResult.decode(
        await prefs.read(novelWebdavLastAutoResultKey),
      ),
    );
  }

  Future<void> save(NovelPrefsApi prefs) async {
    await prefs.write(novelWebdavAutoModeKey, mode.key);
    await prefs.write(novelWebdavEncryptKey, encrypt ? 'true' : 'false');
    await prefs.write(
      novelWebdavProgressAutoKey,
      progressAuto ? 'true' : 'false',
    );
    await prefs.write(novelWebdavDeviceNameKey, deviceName.trim());
  }
}

/// 记住备份密码时在安全存储里的键名。
const String novelBackupPasswordCredentialKey = 'mimao.novel.backup.password';

/// 备份密码的存取（与 WebDAV 密码分开：它们本来就可能是两个东西）。
Future<String> readNovelBackupPassword({
  NovelCredentialStore? credentials,
}) async {
  final store = credentials ?? NovelSecureCredentialStore();
  return (await store.read(novelBackupPasswordCredentialKey)) ?? '';
}

Future<void> writeNovelBackupPassword(
  String password, {
  NovelCredentialStore? credentials,
}) async {
  final store = credentials ?? NovelSecureCredentialStore();
  if (password.isEmpty) {
    await store.delete(novelBackupPasswordCredentialKey);
    return;
  }
  await store.write(novelBackupPasswordCredentialKey, password);
}
