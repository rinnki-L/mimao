/// 规则导入：JSON 文本 → [AnimeRule]；以及从 http(s) URL 下载后导入。
///
/// KazumiRules 仓库里每条规则是一个 JSON object，也可能打包成数组
/// （订阅文件）。导入器两者都接受，并对坏条目逐条容错：合法规则照常返回，
/// 非法条目进入 [RuleImportResult.failures]。
library;

import 'dart:convert';

import '../request/web_client.dart';
import 'rule.dart';

/// KazumiRules 官方仓库的 jsdelivr 镜像根地址。
///
/// 本机与部分网络环境直连 github.com 会被 RST，故默认走 CDN；地址集中在此，
/// 需要时可改。用户也可在设置页填入任意同格式仓库地址。
const String defaultKazumiRulesBaseUrl =
    'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/';

/// 仓库清单里一条规则的元数据（Kazumi `index.json` 的条目）。
///
/// 注意：这只是"仓库里有什么"的目录信息，不含搜索/详情选择器。要真正导入，
/// 还需按 [RuleImporter.ruleUrl] 下载对应的 `{name}.json`。
class RuleIndexEntry {
  const RuleIndexEntry({
    required this.name,
    this.version = '',
    this.useNativePlayer = true,
    this.antiCrawlerEnabled = false,
    this.author = '',
    this.lastUpdate = 0,
  });

  factory RuleIndexEntry.fromJson(Map<String, dynamic> json) {
    return RuleIndexEntry(
      name: _indexString(json['name']),
      version: _indexString(json['version']),
      useNativePlayer: _indexBool(json['useNativePlayer'], fallback: true),
      antiCrawlerEnabled: _indexBool(json['antiCrawlerEnabled']),
      author: _indexString(json['author']),
      lastUpdate: _indexInt(json['lastUpdate']),
    );
  }

  final String name;
  final String version;
  final bool useNativePlayer;
  final bool antiCrawlerEnabled;
  final String author;
  final int lastUpdate;

  /// 人可读的更新时间；时间戳缺失/非法时显示「—」。
  String get lastUpdateLabel {
    if (lastUpdate <= 0) return '—';
    final date = DateTime.fromMillisecondsSinceEpoch(lastUpdate, isUtc: true);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

/// 一次仓库清单读取的结果。
class RuleIndexResult {
  const RuleIndexResult({
    this.entries = const <RuleIndexEntry>[],
    this.failures = const <String>[],
  });

  final List<RuleIndexEntry> entries;
  final List<String> failures;

  bool get isEmpty => entries.isEmpty;

  @override
  String toString() =>
      'RuleIndexResult(entries: ${entries.length}, failures: ${failures.length})';
}

/// 安全的规则文件名片段：只允许字母数字、点、下划线、连字符，且不含 `..`。
///
/// 规则名会被拼进 URL 路径，必须挡住路径穿越（`../`、`/`、`?`、`#`）。
bool isSafeRuleName(String name) {
  if (name.isEmpty) return false;
  if (name.contains('..')) return false;
  return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name);
}

/// 规范化仓库根地址。只接受 http(s)、host 非空、无 user-info/query/fragment，
/// 并补齐结尾 `/`，保证后续可以简单拼接 `index.json` / `{name}.json`。
///
/// 与 Kazumi 上游一致的白名单口径（边界约束 §二）：不可信的仓库地址不能携带
/// 凭据，也不能用 query/fragment 绕过路径构造。
Uri? normalizeRepositoryBaseUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  var path = uri.path;
  if (!path.endsWith('/')) path += '/';
  return uri.replace(path: path);
}

String _indexString(dynamic value) =>
    value == null ? '' : value.toString().trim();

bool _indexBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}

int _indexInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// 一次导入的结果。
class RuleImportResult {
  const RuleImportResult({
    required this.rules,
    this.failures = const <String>[],
    this.duplicateCount = 0,
  });

  final List<AnimeRule> rules;

  /// 每条失败原因（含条目序号/规则名），便于在设置页原样展示。
  final List<String> failures;

  /// 同名规则被后一条覆盖的次数（Kazumi 导入器同样保留最后一条）。
  final int duplicateCount;

  bool get isEmpty => rules.isEmpty;

  @override
  String toString() =>
      'RuleImportResult(rules: ${rules.length}, failures: ${failures.length})';
}

/// 规则导入器。
///
/// [client] 可注入假实现，网络层与解析层因此可以分开测试。
class RuleImporter {
  RuleImporter({AnimeHttpClient? client})
    : _client = client ?? AnimeWebClient();

  final AnimeHttpClient _client;

  /// 解析本地 JSON 文本（单个 object 或 object 数组）。
  RuleImportResult parseJson(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const RuleImportResult(rules: [], failures: ['导入内容为空']);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      return RuleImportResult(
        rules: const [],
        failures: ['不是合法 JSON：${error.message}'],
      );
    }

    final entries = decoded is List ? decoded : <dynamic>[decoded];
    final byName = <String, AnimeRule>{};
    final failures = <String>[];
    var duplicateCount = 0;

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry is! Map) {
        failures.add('第 ${index + 1} 条不是 JSON object');
        continue;
      }
      try {
        final rule = AnimeRule.fromJson(Map<String, dynamic>.from(entry));
        if (rule.name.trim().isEmpty) {
          failures.add('第 ${index + 1} 条规则缺少 name');
          continue;
        }
        if (!rule.hasUsableSelectors) {
          failures.add('规则「${rule.name}」没有可用的搜索/详情选择器');
          continue;
        }
        final key = rule.name.trim().toLowerCase();
        if (byName.containsKey(key)) duplicateCount++;
        byName[key] = rule;
      } catch (error) {
        failures.add('第 ${index + 1} 条规则解析失败：$error');
      }
    }

    return RuleImportResult(
      rules: List<AnimeRule>.unmodifiable(byName.values),
      failures: List<String>.unmodifiable(failures),
      duplicateCount: duplicateCount,
    );
  }

  /// 读取 Kazumi 格式仓库的 `index.json` 清单，供 UI 列出可导入规则。
  ///
  /// [baseUrl] 是仓库根地址，会先经 [normalizeRepositoryBaseUrl] 白名单校验；
  /// 非法地址直接返回 failures，不发请求。网络失败、非 2xx、坏 JSON 同样收敛
  /// 进 failures 而不抛异常（与 [importFromUrl] 同款契约）。
  Future<RuleIndexResult> fetchIndex(
    String baseUrl, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async {
    final uri = normalizeRepositoryBaseUrl(baseUrl);
    if (uri == null) {
      return RuleIndexResult(failures: ['仓库地址不合法：只支持不含凭据的 http(s) 地址']);
    }

    final indexUrl = uri.resolve('index.json').toString();
    late final AnimeHttpResponse response;
    try {
      response = await _client.fetch(indexUrl, options: options);
    } catch (error) {
      return RuleIndexResult(failures: ['读取规则清单失败：$error']);
    }
    if (!response.isSuccessful) {
      return RuleIndexResult(
        failures: ['读取规则清单失败：HTTP ${response.statusCode}（$indexUrl）'],
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      return RuleIndexResult(failures: ['规则清单不是合法 JSON：${error.message}']);
    }
    if (decoded is! List) {
      return const RuleIndexResult(failures: ['规则清单格式错误：应为 JSON 数组']);
    }

    final entries = <RuleIndexEntry>[];
    final failures = <String>[];
    for (var index = 0; index < decoded.length; index++) {
      final entry = decoded[index];
      if (entry is! Map) {
        failures.add('清单第 ${index + 1} 条不是 JSON object');
        continue;
      }
      final rule = RuleIndexEntry.fromJson(Map<String, dynamic>.from(entry));
      if (!isSafeRuleName(rule.name)) {
        failures.add('清单第 ${index + 1} 条规则名不合法：${rule.name}');
        continue;
      }
      entries.add(rule);
    }

    return RuleIndexResult(
      entries: List<RuleIndexEntry>.unmodifiable(entries),
      failures: List<String>.unmodifiable(failures),
    );
  }

  /// 把仓库根地址 + 规则名拼成可直接交给 [importFromUrl] 的 JSON URL。
  ///
  /// [name] 必须先是安全的单路径段，防止把外部清单里的恶意名字拼成路径穿越。
  String ruleUrl(String baseUrl, String name) {
    if (!isSafeRuleName(name)) {
      throw ArgumentError.value(name, 'name', '不是安全的规则文件名');
    }
    final uri = normalizeRepositoryBaseUrl(baseUrl);
    if (uri == null) {
      throw ArgumentError.value(baseUrl, 'baseUrl', '仓库地址不合法');
    }
    return uri.resolve('$name.json').toString();
  }

  /// 从 URL 下载规则 JSON 并解析。
  ///
  /// 网络失败、非 2xx、坏 JSON 都返回带 [RuleImportResult.failures] 的空结果，
  /// 不向调用方抛异常。
  Future<RuleImportResult> importFromUrl(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async {
    try {
      final response = await _client.fetch(url, options: options);
      if (!response.isSuccessful) {
        return RuleImportResult(
          rules: const [],
          failures: ['规则下载失败：HTTP ${response.statusCode}（$url）'],
        );
      }
      return parseJson(response.body);
    } catch (error) {
      return RuleImportResult(rules: const [], failures: ['规则下载失败：$error']);
    }
  }
}
