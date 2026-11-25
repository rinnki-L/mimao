/// 主题包的持久化：已导入/保存的主题列表（`novel_theme_package` 表）。
///
/// 只存包 JSON 原文 + 预览图 + 版本；列表页需要展示效果时现场解码/渲染，
/// 不把「解构后的设置」当第二权威。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/theme/novel_theme_package.dart';

/// 已保存的一份主题包。
class NovelThemePackageRecord {
  const NovelThemePackageRecord({
    required this.id,
    required this.name,
    required this.json,
    required this.version,
    this.previewPngBase64,
    required this.importedAt,
    this.appliedAt,
  });

  final int id;
  final String name;

  /// 完整包 JSON（列表页用它解码预览/应用）。
  final String json;

  final int version;
  final String? previewPngBase64;
  final DateTime importedAt;
  final DateTime? appliedAt;

  Uint8List? get previewPng {
    final data = previewPngBase64?.trim() ?? '';
    if (data.isEmpty) return null;
    try {
      return base64Decode(data);
    } on Object {
      return null;
    }
  }

  /// 解码成主题包；坏数据返回 null（列表里显示「包已损坏」）。
  NovelThemePackage? decode() {
    try {
      return NovelThemePackage.decode(json);
    } on NovelThemePackageException {
      return null;
    }
  }
}

/// 主题包仓库窄接口。
abstract interface class NovelThemePackageStorage {
  Future<List<NovelThemePackageRecord>> loadAll();

  /// 保存（同名覆盖）；返回落库后的记录。
  Future<NovelThemePackageRecord> save(NovelThemePackage package);

  Future<void> markApplied(int id);

  Future<bool> delete(int id);
}

/// drift 实现。
class NovelThemePackageService implements NovelThemePackageStorage {
  NovelThemePackageService(this._db);

  final NovelDb _db;

  @override
  Future<List<NovelThemePackageRecord>> loadAll() async {
    final rows =
        await (_db.select(_db.novelThemePackages)
              ..orderBy(<OrderClauseGenerator<$NovelThemePackagesTable>>[
                (table) => OrderingTerm.desc(table.importedAt),
                (table) => OrderingTerm.desc(table.id),
              ]))
            .get();
    return <NovelThemePackageRecord>[for (final row in rows) _fromRow(row)];
  }

  @override
  Future<NovelThemePackageRecord> save(NovelThemePackage package) async {
    final json = package.encode();
    final preview = package.previewPng == null
        ? null
        : base64Encode(package.previewPng!);
    final now = DateTime.now();
    final existing =
        await (_db.select(_db.novelThemePackages)
              ..where((t) => t.name.equals(package.name))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      await (_db.update(
        _db.novelThemePackages,
      )..where((t) => t.id.equals(existing.id))).write(
        NovelThemePackagesCompanion(
          packageJson: Value(json),
          packageVersion: Value(package.version),
          previewPngBase64: Value(preview),
          importedAt: Value(now),
        ),
      );
      final record = NovelThemePackageRecord(
        id: existing.id,
        name: package.name,
        json: json,
        version: package.version,
        previewPngBase64: preview,
        importedAt: now,
        appliedAt: existing.appliedAt,
      );
      return record;
    }
    final id = await _db
        .into(_db.novelThemePackages)
        .insert(
          NovelThemePackagesCompanion.insert(
            name: package.name,
            packageJson: json,
            packageVersion: Value(package.version),
            previewPngBase64: Value(preview),
            importedAt: now,
          ),
        );
    return NovelThemePackageRecord(
      id: id,
      name: package.name,
      json: json,
      version: package.version,
      previewPngBase64: preview,
      importedAt: now,
    );
  }

  @override
  Future<void> markApplied(int id) async {
    await (_db.update(_db.novelThemePackages)..where((t) => t.id.equals(id)))
        .write(NovelThemePackagesCompanion(appliedAt: Value(DateTime.now())));
  }

  @override
  Future<bool> delete(int id) async {
    final deleted = await (_db.delete(
      _db.novelThemePackages,
    )..where((t) => t.id.equals(id))).go();
    return deleted > 0;
  }

  NovelThemePackageRecord _fromRow(NovelThemePackageRow row) =>
      NovelThemePackageRecord(
        id: row.id,
        name: row.name,
        json: row.packageJson,
        version: row.packageVersion,
        previewPngBase64: row.previewPngBase64,
        importedAt: row.importedAt,
        appliedAt: row.appliedAt,
      );
}
