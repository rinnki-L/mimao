/// 规则引擎（A 线）到页面数据源（D 线）的适配器。
///
/// 把 [AnimeRuleEngine] 的结构化输出桥接成 [AnimeDataSource] 的
/// [AnimeSummary] / [AnimeDetail]，让搜索页与详情页无需认识 XPath 或规则模型。
/// 本文件只依赖 `anime/data/*` 与 `anime/engine/*`：不碰 UI、播放器、core 服务。
///
/// 已知能力边界：Kazumi 规则不含「周更新时间表」数据，[schedule] 恒返回空列表，
/// 时间表页会显示空态（详见 lib/anime/data/README.md）。
library;

import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/rule_anime_mapper.dart';
import 'package:mimao/anime/engine/engine.dart';

/// 一次搜索/详情抓取里的一条诊断说明。
///
/// [ruleName] 指向出问题的规则（加载规则本身失败时用一个固定占位名），
/// [message] 是人类可读的原因，供 UI/日志解释「为什么没有结果」。
class RuleSourceDiagnostic {
  const RuleSourceDiagnostic({required this.ruleName, required this.message});

  final String ruleName;
  final String message;

  @override
  String toString() => 'RuleSourceDiagnostic($ruleName: $message)';
}

/// 用规则引擎驱动 [AnimeDataSource] 的实现。
class RuleAnimeDataSource implements AnimeDataSource {
  /// 可注入构造：网络、解析、规则列表都可替换，便于离线单测。
  RuleAnimeDataSource({required this.engine, required this.loadRules});

  /// 从本地规则仓库构造：每次调用都重新读盘，设置页刚导入的规则下次即生效。
  factory RuleAnimeDataSource.fromStore(
    RuleStore store, {
    AnimeRuleEngine? engine,
  }) {
    return RuleAnimeDataSource(
      engine: engine ?? AnimeRuleEngine(),
      loadRules: store.loadAll,
    );
  }

  final AnimeRuleEngine engine;
  final Future<List<AnimeRule>> Function() loadRules;

  final List<RuleSourceDiagnostic> _diagnostics = <RuleSourceDiagnostic>[];

  /// 最近一次 [search] / [detail] / [schedule] 的诊断；每次调用开始时清空。
  List<RuleSourceDiagnostic> get lastDiagnostics =>
      List<RuleSourceDiagnostic>.unmodifiable(_diagnostics);

  /// 加载规则本身失败时使用的占位规则名。
  static const String _loadFailureRuleName = '（规则加载）';

  @override
  Future<List<AnimeSummary>> search(String keyword) async {
    _resetDiagnostics();
    // 空关键词不发任何请求：搜索页初始态不应把空查询打到所有站点。
    if (keyword.trim().isEmpty) return const <AnimeSummary>[];

    final List<AnimeRule> rules;
    try {
      rules = await loadRules();
    } catch (error) {
      _diagnostics.add(
        const RuleSourceDiagnostic(
          ruleName: _loadFailureRuleName,
          message: '加载规则失败',
        ),
      );
      _diagnostics.add(
        RuleSourceDiagnostic(ruleName: _loadFailureRuleName, message: '$error'),
      );
      return const <AnimeSummary>[];
    }
    if (rules.isEmpty) return const <AnimeSummary>[];

    // 并发等所有规则，但按规则顺序拼装结果——顺序不随网络完成先后漂移。
    final parts = await Future.wait(
      rules.map((rule) => _searchOne(rule, keyword)),
    );

    final results = <AnimeSummary>[];
    for (final part in parts) {
      _diagnostics.addAll(part.diagnostics);
      results.addAll(part.items);
    }
    return results;
  }

  /// 单条规则的搜索：异常与坏规则都收敛到本规则自己的诊断，不影响其它源。
  Future<({List<AnimeSummary> items, List<RuleSourceDiagnostic> diagnostics})>
  _searchOne(AnimeRule rule, String keyword) async {
    final ruleName = ruleDisplayName(rule);
    final diagnostics = <RuleSourceDiagnostic>[];

    final RuleParseResult<RuleSearchResult> parsed;
    try {
      parsed = await engine.search(rule, keyword);
    } catch (error) {
      diagnostics.add(
        RuleSourceDiagnostic(ruleName: ruleName, message: '搜索请求失败：$error'),
      );
      return (items: <AnimeSummary>[], diagnostics: diagnostics);
    }

    for (final message in parsed.diagnostics) {
      diagnostics.add(
        RuleSourceDiagnostic(ruleName: ruleName, message: message),
      );
    }

    final items = <AnimeSummary>[];
    final seenIds = <String>{};
    for (final hit in parsed.items) {
      final summary = summaryFromRule(rule, hit);
      if (summary == null) {
        diagnostics.add(
          RuleSourceDiagnostic(
            ruleName: ruleName,
            message: '搜索结果缺少标题或详情地址，已跳过：${hit.title}',
          ),
        );
        continue;
      }
      if (!seenIds.add(summary.id)) {
        diagnostics.add(
          RuleSourceDiagnostic(
            ruleName: ruleName,
            message: '重复结果已跳过：${summary.id}',
          ),
        );
        continue;
      }
      items.add(summary);
    }

    return (items: items, diagnostics: diagnostics);
  }

  @override
  Future<AnimeDetail> detail(AnimeSummary item) async {
    _resetDiagnostics();
    final sourceName = item.sourceName;
    if (sourceName == null || sourceName.isEmpty) {
      _diagnostics.add(
        const RuleSourceDiagnostic(
          ruleName: '',
          message: '条目没有 sourceName，无法定位规则',
        ),
      );
      return _emptyDetail(item, sourceName: sourceName);
    }

    final List<AnimeRule> rules;
    try {
      rules = await loadRules();
    } catch (error) {
      _diagnostics.add(
        RuleSourceDiagnostic(ruleName: sourceName, message: '加载规则失败：$error'),
      );
      return _emptyDetail(item, sourceName: sourceName);
    }

    final rule = _findRule(rules, sourceName);
    if (rule == null) {
      _diagnostics.add(
        RuleSourceDiagnostic(ruleName: sourceName, message: '找不到对应规则，返回空详情'),
      );
      return _emptyDetail(item, sourceName: sourceName);
    }
    return _detailWithRule(rule, item);
  }

  /// 先精确匹配规则名，再大小写不敏感匹配。
  AnimeRule? _findRule(List<AnimeRule> rules, String sourceName) {
    for (final rule in rules) {
      if (rule.name == sourceName) return rule;
    }
    final lowered = sourceName.toLowerCase();
    for (final rule in rules) {
      if (rule.name.toLowerCase() == lowered) return rule;
    }
    return null;
  }

  Future<AnimeDetail> _detailWithRule(AnimeRule rule, AnimeSummary item) async {
    final ruleName = ruleDisplayName(rule);
    final RuleParseResult<RuleEpisode> parsed;
    try {
      parsed = await engine.detail(rule, item.detailUrl);
    } catch (error) {
      _diagnostics.add(
        RuleSourceDiagnostic(ruleName: ruleName, message: '详情请求失败：$error'),
      );
      return _emptyDetail(item, sourceName: ruleName);
    }

    for (final message in parsed.diagnostics) {
      _diagnostics.add(
        RuleSourceDiagnostic(ruleName: ruleName, message: message),
      );
    }
    if (parsed.items.isEmpty) {
      if (parsed.diagnostics.isEmpty) {
        _diagnostics.add(
          const RuleSourceDiagnostic(ruleName: '', message: '详情页没有剧集'),
        );
      }
      return _emptyDetail(item, sourceName: ruleName);
    }
    return detailFromRule(
      rule,
      item,
      parsed.items,
      detailCover: parsed.coverUrl,
    );
  }

  /// 无规则 / 抓不到剧集时的返回值：标题封面地址仍取 item，其余留空。
  AnimeDetail _emptyDetail(AnimeSummary item, {String? sourceName}) {
    return AnimeDetail(
      title: item.title,
      coverUrl: item.coverUrl,
      detailUrl: item.detailUrl,
      description: '',
      sourceName: sourceName ?? item.sourceName,
      tags: const <String>[],
      episodes: const <AnimeEpisode>[],
    );
  }

  /// 列出同一部番剧在所有规则下可观看的条目（详情页「换源/选规则」用）。
  ///
  /// 对每个已装规则按 [keyword] 再搜一次，取「标题最相近」的一条命中：
  /// 先精确去空格大小写匹配标题，再退到包含关系，最后才取该规则第一条结果
  /// （规则站点搜索通常把最相关项排在前面）。本条目所在规则始终纳入，
  /// 且排在首位；每条规则至多贡献一个来源，避免换源列表爆长。
  @override
  Future<List<AnimeSummary>> watchSources(
    AnimeSummary item, {
    required String keyword,
  }) async {
    _resetDiagnostics();
    final List<AnimeRule> rules;
    try {
      rules = await loadRules();
    } on Object {
      return <AnimeSummary>[item];
    }
    if (rules.isEmpty) return <AnimeSummary>[item];

    final parts = await Future.wait(
      rules.map((rule) => _watchSourceOne(rule, keyword)),
    );

    final sources = <AnimeSummary>[];
    // 当前条目所在规则一定在列且排首位。
    sources.add(item);
    final current = (item.sourceName ?? '').toLowerCase();
    for (final part in parts) {
      if (part == null) continue;
      final name = (part.sourceName ?? '').toLowerCase();
      if (name == current) continue;
      // 同一 sourceName 只保留一个来源。
      if (sources.any((s) => (s.sourceName ?? '').toLowerCase() == name)) {
        continue;
      }
      sources.add(part);
    }
    return sources;
  }

  /// 单规则里挑出与标题最相近的一条命中；无命中返回 null。
  Future<AnimeSummary?> _watchSourceOne(AnimeRule rule, String keyword) async {
    final RuleParseResult<RuleSearchResult> parsed;
    try {
      parsed = await engine.search(rule, keyword);
    } on Object {
      return null;
    }
    final mapped = <AnimeSummary>[];
    for (final hit in parsed.items) {
      final summary = summaryFromRule(rule, hit);
      if (summary != null) mapped.add(summary);
    }
    if (mapped.isEmpty) return null;

    final needle = keyword.trim().toLowerCase();
    if (needle.isEmpty) return mapped.first;
    for (final summary in mapped) {
      if (summary.title.trim().toLowerCase() == needle) return summary;
    }
    for (final summary in mapped) {
      if (summary.title.toLowerCase().contains(needle) ||
          needle.contains(summary.title.toLowerCase())) {
        return summary;
      }
    }
    return mapped.first;
  }

  @override
  Future<List<AnimeScheduleSection>> schedule() async {
    _resetDiagnostics();
    // Kazumi 规则没有周时间表数据；不访问网络，也不伪造内容。
    return const <AnimeScheduleSection>[];
  }

  void _resetDiagnostics() {
    _diagnostics.clear();
  }
}
