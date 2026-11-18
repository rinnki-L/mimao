/// 上游契约冒烟 · 番剧规则仓库（CI 定时监控 + 本地诊断两用）。
///
/// 用生产代码原样（RuleImporter + 真 dio 网络栈）打真实 KazumiRules 官方
/// 清单（`index.json` + `{name}.json`，XPath 番剧规则），验证上游格式仍是
/// `fetchIndex` / `ruleUrl` / `importFromUrl` 认识的样子。
///
/// 退出码：0 = 契约成立；1 = 契约不成立；2 = 网络失败（重试耗尽）。
/// CI 里作非门禁监控岗（continue-on-error），红了只报警不挡合并。
///
/// 注意：直接 import rule_importer.dart 而不用 engine.dart barrel——barrel
/// 会把 rule_store.dart 的 path_provider 拖进来（→ flutter/dart:ui），纯
/// `dart run` 跑不了。
library;

import 'dart:io';

import 'package:mimao/anime/engine/rule_importer.dart';
import 'package:mimao/anime/request/web_client.dart';

const int _maxAttempts = 3;

const Duration _retryGap = Duration(seconds: 2);

void _out(String message) => stdout.writeln(message);

Never _fail(int code, String message) {
  _out('SMOKE FAIL($code): $message');
  exit(code);
}

Future<AnimeHttpResponse> _fetchWithRetry(
  AnimeHttpClient client,
  String url,
) async {
  Object? lastError;
  for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
    try {
      final response = await client.fetch(url);
      if (response.isSuccessful) return response;
      lastError = StateError('HTTP ${response.statusCode}');
    } on Object catch (error) {
      lastError = error;
    }
    _out('attempt $attempt/$_maxAttempts failed: $lastError');
    if (attempt < _maxAttempts) await Future<void>.delayed(_retryGap);
  }
  throw StateError('重试 $_maxAttempts 次后仍失败：$lastError');
}

Future<void> main() async {
  final client = AnimeWebClient();
  final importer = RuleImporter(client: client);
  const base = defaultKazumiRulesBaseUrl;

  // 0) 网络先探：区分「网络失败」与「契约不成立」。
  try {
    await _fetchWithRetry(client, '${base}index.json');
  } on Object catch (error) {
    _fail(2, 'network: $error');
  }

  // 1) 生产解析路径读清单。
  final result = await importer.fetchIndex(base);
  _out(
    'index: ${result.entries.length} entries, '
    '${result.failures.length} failures',
  );
  for (final failure in result.failures) {
    _out('failure: $failure');
  }
  if (result.failures.isNotEmpty) {
    _fail(1, 'contract: 清单存在被校验器拒绝的条目（见上）');
  }
  if (result.entries.isEmpty) {
    _fail(1, 'contract: 清单为空——上游改了结构或换了清单地址');
  }

  // 2) 每条规则名都能拼出合法的 {name}.json 地址。
  for (final entry in result.entries) {
    try {
      importer.ruleUrl(base, entry.name);
    } on Object catch (error) {
      _fail(1, 'contract: ruleUrl 拒绝了真实条目 ${entry.name}：$error');
    }
  }

  // 3) 抽样下载第一条规则 JSON，确认真规则仍能被生产解析器接受。
  final first = result.entries.first;
  final sampleUrl = importer.ruleUrl(base, first.name);
  final imported = await importer.importFromUrl(sampleUrl);
  if (imported.rules.isEmpty) {
    _fail(
      1,
      'contract: 样例规则 $sampleUrl 解析失败：'
      '${imported.failures.join('；')}',
    );
  }

  _out('sample: ${first.name} v${first.version}');
  _out('  url: $sampleUrl');
  _out('  parsed rule: ${imported.rules.single.name}');
  for (final entry in result.entries.take(3)) {
    _out('entry: ${entry.name} v${entry.version}');
  }
  _out('SMOKE OK');
}
