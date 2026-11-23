/// 书源导入服务：下载书源文件（Legado JSON）→ 解析 → 落本地仓库。
///
/// [NovelSourceFetcher] 是可以注入的窄接口：生产用 [DioNovelSourceFetcher]
/// （dio 自动解压 gzip 并按 charset 解码），测试注入假实现，全程离线。
/// [NovelSourceImporter] 是页面唯一依赖的门面，深链 `yuedu://…importonline?src=`
/// 和手动粘贴地址都走同一个 [importFromLink] 入口。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'novel_rule_model.dart';
import 'novel_rule_store.dart';
import 'novel_source_model.dart';
import 'novel_source_store.dart';

/// 书源文件抓取结果。
class NovelSourceFetchResult {
  const NovelSourceFetchResult({required this.text, required this.finalUrl});

  final String text;
  final String finalUrl;
}

/// 抓取窄接口（可注入 fake）。
abstract interface class NovelSourceFetcher {
  Future<NovelSourceFetchResult> fetch(String url);
}

/// 生产抓取器：dio 跟重定向、自动解 gzip/deflate、按响应 charset 解码。
class DioNovelSourceFetcher implements NovelSourceFetcher {
  DioNovelSourceFetcher({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              maxRedirects: 5,
              headers: const <String, String>{
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
                'Accept': 'application/json, text/plain, */*',
              },
              responseType: ResponseType.bytes,
            ),
          );

  final Dio _dio;

  @override
  Future<NovelSourceFetchResult> fetch(String url) async {
    final response = await _dio.get<List<int>>(url);
    final bytes = response.data;
    if (bytes == null) throw const FormatException('书源文件为空');

    // 目标站点的书源文件均为 UTF-8；allowMalformed 让个别坏字节不整文件失败。
    final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
    return NovelSourceFetchResult(
      text: text,
      finalUrl: response.realUri.toString(),
    );
  }
}

/// 一次导入的结果。
class NovelSourceImportResult {
  const NovelSourceImportResult({
    required this.saved,
    required this.total,
    required this.sourceUrl,
    this.kind = NovelRuleKind.bookSource,
    this.message,
  });

  /// 实际落库的规则条数。
  final int saved;

  /// 文件里的规则总条数（含被过滤的重复/空条目）。
  final int total;
  final String sourceUrl;

  /// 这次导入落到了哪一类仓库。
  final NovelRuleKind kind;
  final String? message;

  bool get isEmpty => saved == 0;
}

/// 导入失败：携带可读原因，页面直接展示（堆栈进日志）。
class NovelSourceImportException implements Exception {
  const NovelSourceImportException(this.message);

  final String message;

  @override
  String toString() => 'NovelSourceImportException: $message';
}

/// 规则导入门面：书源 / 订阅源 / 替换规则共用同一个下载与解析入口。
class NovelSourceImporter {
  NovelSourceImporter(
    this.store,
    this.fetcher, {
    this.rssStore,
    this.replaceStore,
  });

  final NovelSourceStorage store;
  final NovelRssSourceStorage? rssStore;
  final NovelReplaceRuleStorage? replaceStore;
  final NovelSourceFetcher fetcher;

  /// 从 `yuedu://` 深链或手动粘贴的规则地址导入。
  ///
  /// [kind] 为导入时手选的类型（null = 自动识别）：深链 host 指明的类型优先
  /// （一键导入链接自带类型），其次手选，最后按文件内容识别。
  Future<NovelSourceImportResult> importFromLink(
    String link, {
    NovelRuleKind? kind,
  }) async {
    final parsed = parseNovelRuleLink(link);
    final url = parsed?.url ?? (isFetchableSourceUrl(link) ? link : null);
    if (url == null) {
      throw const NovelSourceImportException('不是有效的规则导入链接');
    }
    return importFromUrl(url, kind: parsed?.kind ?? kind);
  }

  /// 直接从规则文件地址导入。
  Future<NovelSourceImportResult> importFromUrl(
    String url, {
    NovelRuleKind? kind,
  }) async {
    if (!isFetchableSourceUrl(url)) {
      throw const NovelSourceImportException('规则地址必须是 http(s) 链接');
    }

    late final String text;
    late final String finalUrl;
    try {
      final fetched = await fetcher.fetch(url);
      text = fetched.text;
      finalUrl = fetched.finalUrl;
    } on Object catch (error) {
      throw NovelSourceImportException('下载规则文件失败：$error');
    }

    final List<Map<String, dynamic>> rawItems;
    try {
      rawItems = parseLegadoSources(text);
    } on Object catch (error) {
      throw NovelSourceImportException('规则文件解析失败：$error');
    }
    if (rawItems.isEmpty) {
      throw const NovelSourceImportException('规则文件里没有可用的规则');
    }

    final resolved = kind ?? detectNovelRuleKindInFile(rawItems);
    if (resolved == null) {
      throw const NovelSourceImportException(
        '无法识别规则类型；请在导入时手动选择书源 / 订阅源 / 替换规则',
      );
    }

    return switch (resolved) {
      NovelRuleKind.bookSource => _importBookSources(rawItems, finalUrl),
      NovelRuleKind.rssSource => _importRssSources(rawItems, finalUrl),
      NovelRuleKind.replaceRule => _importReplaceRules(rawItems, finalUrl),
    };
  }

  Future<NovelSourceImportResult> _importBookSources(
    List<Map<String, dynamic>> rawItems,
    String finalUrl,
  ) async {
    final sources = <NovelBookSource>[];
    for (final raw in rawItems) {
      final source = NovelBookSource.fromLegado(raw);
      if (source.url.isEmpty) continue;
      sources.add(source);
    }
    if (sources.isEmpty) {
      throw const NovelSourceImportException('书源文件里没有可用的书源');
    }
    final saved = await store.saveAll(sources);
    return NovelSourceImportResult(
      saved: saved,
      total: rawItems.length,
      sourceUrl: finalUrl,
      message: '已导入 $saved 个书源',
    );
  }

  Future<NovelSourceImportResult> _importRssSources(
    List<Map<String, dynamic>> rawItems,
    String finalUrl,
  ) async {
    final rssStore = this.rssStore;
    if (rssStore == null) {
      throw const NovelSourceImportException('订阅源仓库未接线，无法保存订阅源');
    }
    final sources = <NovelRssSource>[];
    for (final raw in rawItems) {
      final source = NovelRssSource.fromLegado(raw);
      if (source.url.isEmpty) continue;
      sources.add(source);
    }
    if (sources.isEmpty) {
      throw const NovelSourceImportException('订阅源文件里没有可用的订阅源');
    }
    final saved = await rssStore.saveAll(sources);
    return NovelSourceImportResult(
      saved: saved,
      total: rawItems.length,
      sourceUrl: finalUrl,
      kind: NovelRuleKind.rssSource,
      message: '已导入 $saved 个订阅源',
    );
  }

  Future<NovelSourceImportResult> _importReplaceRules(
    List<Map<String, dynamic>> rawItems,
    String finalUrl,
  ) async {
    final replaceStore = this.replaceStore;
    if (replaceStore == null) {
      throw const NovelSourceImportException('替换规则仓库未接线，无法保存替换规则');
    }
    final rules = <NovelReplaceRule>[];
    for (final raw in rawItems) {
      final rule = NovelReplaceRule.fromLegado(raw);
      if (rule.pattern.isEmpty) continue;
      rules.add(rule);
    }
    if (rules.isEmpty) {
      throw const NovelSourceImportException('替换规则文件里没有可用的规则');
    }
    final saved = await replaceStore.saveAll(rules);
    return NovelSourceImportResult(
      saved: saved,
      total: rawItems.length,
      sourceUrl: finalUrl,
      kind: NovelRuleKind.replaceRule,
      message: '已导入 $saved 条替换规则',
    );
  }
}
