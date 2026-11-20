import 'package:drift/drift.dart';

import 'db.dart';

/// 应用设置 kv 读写（与统一库同 DB，不加新依赖——docs/architecture.md §3.3）。
/// 各模块自己的设置仍走各自上游惯例，不进这里。
class SettingsRepository {
  final AppDb db;

  SettingsRepository(this.db);

  Future<String?> get(String key) async {
    final rows = await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals(key))).get();
    return rows.isEmpty ? null : rows.first.value;
  }

  Future<String?> getOr(String key, String fallback) async =>
      await get(key) ?? fallback;

  Future<void> set(String key, String value) async {
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: key, value: value),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// 便捷布尔读写：统一以字符串 'true'/'false' 落库，缺省走 [fallback]。
  Future<bool> getBool(String key, {bool fallback = false}) async {
    final value = await get(key);
    if (value == null) return fallback;
    return value.toLowerCase() == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      set(key, value ? 'true' : 'false');
}
