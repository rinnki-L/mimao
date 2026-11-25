/// 标签分组规则的持久化 + 应用到书架。
///
/// 规则落 `novel_tag_group_rule`；应用时只改收藏行的 `groupName`，且只填空值
/// （手工/既有分组不覆盖）。收藏行是权威表，所以直接写同一张 `NovelDb`，
/// 不经过 `NovelCollectService`——那里面向页面操作，逐条 notify 在这里没必要。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/tags/novel_tag_rules.dart';

/// 标签规则仓库窄接口（页面与书架共用）。
abstract interface class NovelTagRuleStorage {
  Future<List<NovelTagRule>> loadAll();

  /// 新建（id == null）或按 id 更新；返回带 id 的规则。
  Future<NovelTagRule> save(NovelTagRule rule);

  Future<void> setEnabled(int id, bool enabled);

  Future<bool> delete(int id);

  /// 按当前启用规则给书架打标签（只填空分组）。
  Future<NovelTagApplyResult> applyToShelf();

  /// 用导入的规则整体替换自建规则（内置规则不存在，全量替换）。
  Future<void> replaceAll(Iterable<NovelTagRule> rules);
}

/// drift 实现。
class NovelTagRuleService implements NovelTagRuleStorage {
  NovelTagRuleService(this._db);

  final NovelDb _db;

  @override
  Future<List<NovelTagRule>> loadAll() async {
    final rows =
        await (_db.select(_db.novelTagGroupRules)
              ..orderBy(<OrderClauseGenerator<$NovelTagGroupRulesTable>>[
                (table) => OrderingTerm.asc(table.sortOrder),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    return <NovelTagRule>[for (final row in rows) _fromRow(row)];
  }

  @override
  Future<NovelTagRule> save(NovelTagRule rule) async {
    final now = DateTime.now();
    if (rule.id == null) {
      final order = await _nextSortOrder();
      final id = await _db
          .into(_db.novelTagGroupRules)
          .insert(
            NovelTagGroupRulesCompanion.insert(
              name: rule.name,
              pattern: rule.pattern,
              colorArgb: Value(rule.colorArgb),
              enabled: Value(rule.enabled),
              sortOrder: Value(order),
              updatedAt: now,
            ),
          );
      return rule.copyWith(id: id, sortOrder: order);
    }
    await (_db.update(
      _db.novelTagGroupRules,
    )..where((t) => t.id.equals(rule.id!))).write(
      NovelTagGroupRulesCompanion(
        name: Value(rule.name),
        pattern: Value(rule.pattern),
        colorArgb: Value(rule.colorArgb),
        enabled: Value(rule.enabled),
        sortOrder: Value(rule.sortOrder),
        updatedAt: Value(now),
      ),
    );
    return rule;
  }

  @override
  Future<void> setEnabled(int id, bool enabled) async {
    await (_db.update(
      _db.novelTagGroupRules,
    )..where((t) => t.id.equals(id))).write(
      NovelTagGroupRulesCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<bool> delete(int id) async {
    final deleted = await (_db.delete(
      _db.novelTagGroupRules,
    )..where((t) => t.id.equals(id))).go();
    return deleted > 0;
  }

  @override
  Future<void> replaceAll(Iterable<NovelTagRule> rules) async {
    final imported = <NovelTagRule>[
      for (final rule in rules)
        if (rule.isValid) rule,
    ];
    if (imported.isEmpty) return;
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.delete(_db.novelTagGroupRules).go();
      var order = 0;
      for (final rule in imported) {
        await _db
            .into(_db.novelTagGroupRules)
            .insert(
              NovelTagGroupRulesCompanion.insert(
                name: rule.name,
                pattern: rule.pattern,
                colorArgb: Value(rule.colorArgb),
                enabled: Value(rule.enabled),
                sortOrder: Value(rule.sortOrder == 0 ? order : rule.sortOrder),
                updatedAt: now,
              ),
            );
        order++;
      }
    });
  }

  @override
  Future<NovelTagApplyResult> applyToShelf() async {
    final rules = <NovelTagRule>[
      for (final rule in await loadAll())
        if (rule.enabled) rule,
    ];
    if (rules.isEmpty) return const NovelTagApplyResult();

    final rows = await _db.select(_db.novelCollectEntries).get();
    var matched = 0;
    var updated = 0;
    var kept = 0;
    final names = <String>{};
    await _db.transaction(() async {
      for (final row in rows) {
        final rule = matchNovelTagRule(
          rules: rules,
          kind: _kindOf(row.payload),
          title: row.title,
        );
        if (rule == null) continue;
        matched++;
        names.add(rule.name);
        final existing = row.groupName?.trim() ?? '';
        if (existing.isNotEmpty) {
          // 只加不减：手工分组与上一次规则写入的值都不覆盖。
          kept++;
          continue;
        }
        await (_db.update(_db.novelCollectEntries)
              ..where((t) => t.id.equals(row.id)))
            .write(NovelCollectEntriesCompanion(groupName: Value(rule.name)));
        updated++;
      }
    });
    return NovelTagApplyResult(
      matched: matched,
      updated: updated,
      kept: kept,
      affectedNames: names.toList()..sort(),
    );
  }

  /// 从收藏行的书籍快照里取分类标签；坏 JSON 当空串（不阻断整次应用）。
  static String _kindOf(String payload) {
    if (payload.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return '${decoded['kind'] ?? ''}';
    } on Object {
      // 坏快照不影响标题匹配。
    }
    return '';
  }

  Future<int> _nextSortOrder() async {
    final rows = await _db.select(_db.novelTagGroupRules).get();
    if (rows.isEmpty) return 0;
    return rows.map((row) => row.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  NovelTagRule _fromRow(NovelTagGroupRuleRow row) => NovelTagRule(
    id: row.id,
    name: row.name,
    pattern: row.pattern,
    colorArgb: row.colorArgb,
    enabled: row.enabled,
    sortOrder: row.sortOrder,
  );
}

/// 把 [NovelSummary] 转成一次匹配输入（详情页/预览用）。
NovelTagRule? matchNovelTagRuleForBook(
  NovelSummary book,
  Iterable<NovelTagRule> rules,
) => matchNovelTagRule(rules: rules, kind: book.kind, title: book.title);
