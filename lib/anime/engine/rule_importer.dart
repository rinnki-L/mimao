/// 规则导入：JSON 文本 → [AnimeRule]；以及从 http(s) URL 下载后导入。
///
/// KazumiRules 仓库里每条规则是一个 JSON object，也可能打包成数组
/// （订阅文件）。导入器两者都接受，并对坏条目逐条容错：合法规则照常返回，
/// 非法条目进入 [RuleImportResult.failures]。
library;

import 'dart:convert';

import '../request/web_client.dart';
import 'rule.dart';

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

  bool get isNotEmpty => rules.isNotEmpty;

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
