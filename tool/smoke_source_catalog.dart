/// 上游契约冒烟 · 漫画源仓库（CI 定时监控 + 本地诊断两用）。
///
/// 用生产代码原样（ComicSourceCatalog + 真 dio 网络栈）打真实 Venera 官方
/// 清单，验证「上游此刻的格式」仍是我们解析器认识的样子。与离线单测互补：
/// 单测证明解析器符合调研时的格式，本脚本证明它符合上游**现在**的格式。
///
/// 退出码：0 = 契约成立；1 = 契约不成立（清单为空 / 条目或 URL 校验失败 /
/// 样例脚本无法按 Venera 源解析）——需要适配；2 = 网络失败（重试耗尽）——
/// 多半是 CDN/网络问题，重跑即可。CI 里作非门禁监控岗（continue-on-error），
/// 红了只报警不挡合并。
///
/// 注意：直接 import 具体文件而不用 engine.dart barrel——barrel 会把
/// source_store.dart 的 path_provider 拖进来（→ flutter/dart:ui），纯
/// `dart run` 跑不了。本脚本只允许依赖纯 Dart 的引擎文件。
library;

import 'dart:io';

import 'package:mimao/comic/engine/source.dart';
import 'package:mimao/comic/engine/source_catalog.dart';
import 'package:mimao/comic/request/web_client.dart';

/// 网络抖动重试次数（指数退避不必，固定间隔足够）。
const int _maxAttempts = 3;

const Duration _retryGap = Duration(seconds: 2);

void _out(String message) => stdout.writeln(message);

Never _fail(int code, String message) {
  _out('SMOKE FAIL($code): $message');
  exit(code);
}

/// 带重试的抓取：异常/非 2xx 都算一次失败尝试，耗尽后抛出。
Future<ComicHttpResponse> _fetchWithRetry(
  ComicHttpClient client,
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
  final client = ComicWebClient();
  final catalog = ComicSourceCatalog(client: client);

  // 0) 网络先探：区分「网络失败」（exit 2）与「契约不成立」（exit 1）。
  try {
    await _fetchWithRetry(client, defaultComicSourceIndexUrl);
  } on Object catch (error) {
    _fail(2, 'network: $error');
  }

  // 1) 生产解析路径读清单。
  final result = await catalog.fetchIndex(defaultComicSourceIndexUrl);
  _out(
    'index: ${result.entries.length} entries, '
    '${result.failures.length} failures',
  );
  for (final failure in result.failures) {
    _out('failure: $failure');
  }
  // 上游不会发我们校验器拒绝的条目（Venera 自己的解析器先挡一轮）；
  // 一旦出现，说明上游格式漂移或我们校验过严，都是要处理的契约变化。
  if (result.failures.isNotEmpty) {
    _fail(1, 'contract: 清单存在被校验器拒绝的条目（见上）');
  }
  if (result.entries.isEmpty) {
    _fail(1, 'contract: 清单为空——上游改了结构或换了清单地址');
  }

  // 2) 每条条目都能拼出合法的仓库内 .js 地址。
  for (final entry in result.entries) {
    try {
      catalog.sourceUrl(defaultComicSourceIndexUrl, entry);
    } on Object catch (error) {
      _fail(1, 'contract: sourceUrl 拒绝了真实条目 ${entry.key}：$error');
    }
  }

  // 3) 抽样下载第一条源脚本，确认真 .js 仍能按 Venera 源解析。
  final first = result.entries.first;
  final sampleUrl = catalog.sourceUrl(defaultComicSourceIndexUrl, first);
  late final ComicHttpResponse sample;
  try {
    sample = await _fetchWithRetry(client, sampleUrl);
  } on Object catch (error) {
    _fail(2, 'network: 样例脚本 $sampleUrl：$error');
  }
  final parsed = ComicSourceImporter().parseSingle(sample.body);
  if (parsed.sources.isEmpty) {
    _fail(
      1,
      'contract: 样例脚本 $sampleUrl 无法按 Venera 源解析：'
      '${parsed.failures.join('；')}',
    );
  }

  // 摘要 + 通过。
  _out('sample: ${first.displayName} [${first.key}] ${first.subtitle}');
  _out('  url: $sampleUrl');
  _out('  parsed key: ${parsed.sources.single.key}');
  for (final entry in result.entries.take(3)) {
    _out('entry: ${entry.displayName} [${entry.key}] ${entry.subtitle}');
  }
  _out('SMOKE OK');
}
