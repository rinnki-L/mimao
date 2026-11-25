/// 词典规则的持久化 + 查询。
///
/// 存储照 `NovelTxtRuleService` 的模式：首次读取把内置规则落库，之后以库为准。
/// 查询复用书源同一套链路（`AnalyzeUrl` 展开 + `LegadoRuleAnalyzer` 解析），
/// 不另写一套抓取/选择器；`@js:` 结果规则才按需创建 QuickJS 宿主。
library;

import 'package:drift/drift.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/dict/novel_dict_rule.dart';
import 'package:mimao/novel/engine/analyze_url.dart';
import 'package:mimao/novel/engine/content_text.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/js/legado_js_host.dart';
import 'package:mimao/novel/novel_db.dart';

/// 词典规则仓库窄接口（页面与查询共用；测试可注入内存实现）。
abstract interface class NovelDictRuleStorage {
  Future<List<NovelDictRule>> loadAll();

  /// 新建（id == null）或按 id 更新；返回带 id 的规则。
  Future<NovelDictRule> save(NovelDictRule rule);

  Future<void> setEnabled(int id, bool enabled);

  Future<bool> delete(int id);

  /// 用导入的规则整体替换（保留内置规则，其余先删后插）。
  Future<void> replaceAll(Iterable<NovelDictRule> rules);

  /// 恢复内置规则（保留用户自建规则，内置的按默认内容重写）。
  Future<void> restoreDefaults();
}

/// drift 实现，与书源/收藏共用同一个 [NovelDb]。
class NovelDictRuleService implements NovelDictRuleStorage {
  NovelDictRuleService(this._db);

  final NovelDb _db;
  bool _seeded = false;

  @override
  Future<List<NovelDictRule>> loadAll() async {
    await _ensureSeeded();
    final rows =
        await (_db.select(_db.novelDictRules)
              ..orderBy(<OrderClauseGenerator<$NovelDictRulesTable>>[
                (table) => OrderingTerm.asc(table.sortOrder),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    return <NovelDictRule>[for (final row in rows) _fromRow(row)];
  }

  Future<void> _ensureSeeded() async {
    if (_seeded) return;
    final existing = await _db.select(_db.novelDictRules).get();
    if (existing.isEmpty) {
      final now = DateTime.now();
      await _db.batch((batch) {
        for (final rule in novelDefaultDictRules) {
          batch.insert(
            _db.novelDictRules,
            NovelDictRulesCompanion.insert(
              name: rule.name,
              urlRule: rule.urlRule,
              showRule: Value(rule.showRule),
              enabled: Value(rule.enabled),
              builtin: const Value(true),
              sortOrder: Value(rule.sortOrder),
              updatedAt: now,
            ),
          );
        }
      });
    }
    _seeded = true;
  }

  @override
  Future<NovelDictRule> save(NovelDictRule rule) async {
    await _ensureSeeded();
    final now = DateTime.now();
    if (rule.id == null) {
      final order = await _nextSortOrder();
      final id = await _db
          .into(_db.novelDictRules)
          .insert(
            NovelDictRulesCompanion.insert(
              name: rule.name,
              urlRule: rule.urlRule,
              showRule: Value(rule.showRule),
              enabled: Value(rule.enabled),
              sortOrder: Value(order),
              updatedAt: now,
            ),
          );
      return rule.copyWith(id: id, sortOrder: order);
    }
    await (_db.update(
      _db.novelDictRules,
    )..where((t) => t.id.equals(rule.id!))).write(
      NovelDictRulesCompanion(
        name: Value(rule.name),
        urlRule: Value(rule.urlRule),
        showRule: Value(rule.showRule),
        enabled: Value(rule.enabled),
        sortOrder: Value(rule.sortOrder),
        updatedAt: Value(now),
      ),
    );
    return rule;
  }

  @override
  Future<void> setEnabled(int id, bool enabled) async {
    await _ensureSeeded();
    await (_db.update(_db.novelDictRules)..where((t) => t.id.equals(id))).write(
      NovelDictRulesCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<bool> delete(int id) async {
    final deleted = await (_db.delete(
      _db.novelDictRules,
    )..where((t) => t.id.equals(id))).go();
    return deleted > 0;
  }

  @override
  Future<void> replaceAll(Iterable<NovelDictRule> rules) async {
    await _ensureSeeded();
    final imported = <NovelDictRule>[
      for (final rule in rules)
        if (rule.isValid) rule,
    ];
    if (imported.isEmpty) return;
    final now = DateTime.now();
    await _db.transaction(() async {
      // 同名覆盖、其余自建规则清掉；内置规则原样保留。
      await (_db.delete(
        _db.novelDictRules,
      )..where((t) => t.builtin.equals(false))).go();
      for (final rule in imported) {
        final existing =
            await (_db.select(_db.novelDictRules)
                  ..where((t) => t.name.equals(rule.name))
                  ..limit(1))
                .getSingleOrNull();
        if (existing != null) {
          await (_db.update(
            _db.novelDictRules,
          )..where((t) => t.id.equals(existing.id))).write(
            NovelDictRulesCompanion(
              urlRule: Value(rule.urlRule),
              showRule: Value(rule.showRule),
              enabled: Value(rule.enabled),
              sortOrder: Value(rule.sortOrder),
              updatedAt: Value(now),
            ),
          );
        } else {
          await _db
              .into(_db.novelDictRules)
              .insert(
                NovelDictRulesCompanion.insert(
                  name: rule.name,
                  urlRule: rule.urlRule,
                  showRule: Value(rule.showRule),
                  enabled: Value(rule.enabled),
                  sortOrder: Value(rule.sortOrder),
                  updatedAt: now,
                ),
              );
        }
      }
    });
  }

  @override
  Future<void> restoreDefaults() async {
    await _ensureSeeded();
    final now = DateTime.now();
    final rows = await _db.select(_db.novelDictRules).get();
    await _db.transaction(() async {
      for (final rule in novelDefaultDictRules) {
        final match = rows.where((row) => row.builtin && row.name == rule.name);
        if (match.isEmpty) {
          await _db
              .into(_db.novelDictRules)
              .insert(
                NovelDictRulesCompanion.insert(
                  name: rule.name,
                  urlRule: rule.urlRule,
                  showRule: Value(rule.showRule),
                  enabled: Value(rule.enabled),
                  builtin: const Value(true),
                  sortOrder: Value(rule.sortOrder),
                  updatedAt: now,
                ),
              );
          continue;
        }
        final row = match.first;
        await (_db.update(
          _db.novelDictRules,
        )..where((t) => t.id.equals(row.id))).write(
          NovelDictRulesCompanion(
            urlRule: Value(rule.urlRule),
            showRule: Value(rule.showRule),
            enabled: Value(rule.enabled),
            sortOrder: Value(rule.sortOrder),
            builtin: const Value(true),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  Future<int> _nextSortOrder() async {
    final rows = await _db.select(_db.novelDictRules).get();
    if (rows.isEmpty) return 0;
    return rows.map((row) => row.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  NovelDictRule _fromRow(NovelDictRuleRow row) => NovelDictRule(
    id: row.id,
    name: row.name,
    urlRule: row.urlRule,
    showRule: row.showRule,
    enabled: row.enabled,
    sortOrder: row.sortOrder,
    builtin: row.builtin,
  );
}

/// 一次查词的可注入窄接口（页面/阅读器只认这个；测试注入 fake 不碰网络）。
abstract interface class NovelDictLookup {
  /// 按一条规则查词；失败收敛成带 [NovelDictResult.error] 的结果。
  Future<NovelDictResult> lookup(NovelDictRule rule, String word);

  /// 按规则顺序并发查全部启用规则。
  Future<List<NovelDictResult>> lookupAll(
    Iterable<NovelDictRule> rules,
    String word,
  );

  void close();
}

/// 生产实现：复用书源的 HTTP 传输与规则解析。
///
/// 词典规则不需要登录态，所以不建 CookieJar 之外的额外状态；`@js:` 结果
/// 规则才按需创建 [LegadoJsHost]，普通选择器规则完全不碰 QuickJS。
class NovelDictService implements NovelDictLookup {
  NovelDictService({
    NovelHttpTransport? transport,
    this.timeout = const Duration(seconds: 20),
  }) : _transport = transport ?? DioNovelHttpTransport();

  final NovelHttpTransport _transport;
  final Duration timeout;

  LegadoJsHost? _host;

  @override
  Future<NovelDictResult> lookup(NovelDictRule rule, String word) async {
    final query = normalizeNovelDictWord(word);
    if (query.isEmpty) {
      return NovelDictResult(ruleName: rule.name, error: '先选一段要查的词');
    }
    try {
      final needsJs = rule.showRuleNeedsJs;
      final analyze = await AnalyzeUrl.resolve(
        ruleUrl: expandNovelDictUrl(rule.urlRule, query),
        baseUrl: rule.urlRule,
        transport: _transport,
        jsRunner: needsJs ? _jsHost.evaluate : null,
        key: query,
        timeout: timeout,
      );
      final response = await analyze.fetch();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return NovelDictResult(
          ruleName: rule.name,
          error:
              '请求失败（HTTP ${response.statusCode}）：${analyze.url}\n'
              '站点可能改了地址，或者这条规则需要额外的请求参数。',
          url: analyze.url,
        );
      }
      var body = response.body;
      final showRule = rule.showRule.trim();
      if (showRule.isNotEmpty) {
        final analyzer = LegadoRuleAnalyzer(
          content: body,
          baseUrl: analyze.url,
          key: query,
          jsRunner: needsJs ? _jsHost.evaluate : null,
        );
        body = await analyzer.getString(showRule);
      }
      final text = body.contains('<') ? htmlToText(body) : body.trim();
      if (text.trim().isEmpty) {
        return NovelDictResult(
          ruleName: rule.name,
          error: showRule.isEmpty
              ? '站点返回了空内容'
              : '解析结果为空，检查 showRule 选择器是否还匹配这个站点',
          url: analyze.url,
        );
      }
      return NovelDictResult(ruleName: rule.name, text: text, url: analyze.url);
    } on Object catch (error) {
      return NovelDictResult(ruleName: rule.name, error: '查询失败：$error');
    }
  }

  @override
  Future<List<NovelDictResult>> lookupAll(
    Iterable<NovelDictRule> rules,
    String word,
  ) async {
    final enabled = <NovelDictRule>[
      for (final rule in rules)
        if (rule.enabled && rule.isValid) rule,
    ];
    if (enabled.isEmpty) return const <NovelDictResult>[];
    return Future.wait(<Future<NovelDictResult>>[
      for (final rule in enabled) lookup(rule, word),
    ]);
  }

  LegadoJsHost get _jsHost => _host ??= LegadoJsHost(transport: _transport);

  @override
  void close() {
    _host?.dispose();
    _host = null;
    _transport.close();
  }
}
