/// 高亮规则的持久化：`novel_highlight_rule` 表的唯一读写口。
///
/// 页面与阅读控制器只依赖 [NovelHighlightRuleStorage] 窄接口，测试可注入
/// 内存实现；drift 细节留在本文件。写操作只做一件事：把规则原样落库
/// （坏数据回退在 [NovelHighlightRule.tryDecode]，不在这里猜）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/reader/novel_highlight_rules.dart';

/// 高亮规则仓库窄接口。
abstract interface class NovelHighlightRuleStorage {
  Future<List<NovelHighlightRule>> loadAll();

  /// 新建（[NovelHighlightRule.id] 为空）或按 id 更新；返回带 id 的规则。
  Future<NovelHighlightRule> save(NovelHighlightRule rule);

  Future<void> setEnabled(int id, bool enabled);

  Future<bool> delete(int id);
}

/// drift 实现，与阅读器共用同一个 [NovelDb]。
class NovelHighlightRuleService implements NovelHighlightRuleStorage {
  NovelHighlightRuleService(this._db);

  final NovelDb _db;

  @override
  Future<List<NovelHighlightRule>> loadAll() async {
    final query = _db.select(_db.novelHighlightRules)
      ..orderBy(<OrderClauseGenerator<$NovelHighlightRulesTable>>[
        (table) => OrderingTerm.asc(table.enabled),
        (table) => OrderingTerm.asc(table.name),
      ]);
    final rows = await query.get();
    return List<NovelHighlightRule>.unmodifiable(rows.map(_fromRow));
  }

  @override
  Future<NovelHighlightRule> save(NovelHighlightRule rule) async {
    final now = DateTime.now();
    final rawJson = jsonEncode(rule.raw);
    if (rule.id == null) {
      final id = await _db
          .into(_db.novelHighlightRules)
          .insert(
            NovelHighlightRulesCompanion.insert(
              bookId: Value(rule.bookId),
              name: Value(rule.name),
              pattern: rule.pattern,
              foregroundLight: rule.foregroundLightArgb,
              backgroundLight: Value(rule.backgroundLightArgb),
              foregroundDark: rule.foregroundDarkArgb,
              backgroundDark: Value(rule.backgroundDarkArgb),
              underline: Value(rule.underline),
              bold: Value(rule.bold),
              enabled: Value(rule.enabled),
              raw: Value(rawJson),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return rule.copyWith(id: id);
    }
    await (_db.update(
      _db.novelHighlightRules,
    )..where((table) => table.id.equals(rule.id!))).write(
      NovelHighlightRulesCompanion(
        bookId: Value(rule.bookId),
        name: Value(rule.name),
        pattern: Value(rule.pattern),
        foregroundLight: Value(rule.foregroundLightArgb),
        backgroundLight: Value(rule.backgroundLightArgb),
        foregroundDark: Value(rule.foregroundDarkArgb),
        backgroundDark: Value(rule.backgroundDarkArgb),
        underline: Value(rule.underline),
        bold: Value(rule.bold),
        enabled: Value(rule.enabled),
        raw: Value(rawJson),
        updatedAt: Value(now),
      ),
    );
    return rule;
  }

  @override
  Future<void> setEnabled(int id, bool enabled) async {
    await (_db.update(
      _db.novelHighlightRules,
    )..where((table) => table.id.equals(id))).write(
      NovelHighlightRulesCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<bool> delete(int id) async {
    final removed = await (_db.delete(
      _db.novelHighlightRules,
    )..where((table) => table.id.equals(id))).go();
    return removed > 0;
  }

  NovelHighlightRule _fromRow(NovelHighlightRuleRow row) {
    Map<String, Object?> raw = const <String, Object?>{};
    try {
      final decoded = jsonDecode(row.raw);
      if (decoded is Map) raw = Map<String, Object?>.from(decoded);
    } on Object {
      // 原始 JSON 损坏不影响规则本身。
    }
    return NovelHighlightRule(
      id: row.id,
      bookId: row.bookId,
      name: row.name.isEmpty ? row.pattern : row.name,
      pattern: row.pattern,
      foregroundLightArgb: row.foregroundLight,
      backgroundLightArgb: row.backgroundLight,
      foregroundDarkArgb: row.foregroundDark,
      backgroundDarkArgb: row.backgroundDark,
      underline: row.underline,
      bold: row.bold,
      enabled: row.enabled,
      raw: raw,
    );
  }
}
