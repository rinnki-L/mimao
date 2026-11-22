/// 书源导入服务：下载书源文件（Legado JSON）→ 解析 → 落本地仓库。
///
/// [NovelSourceFetcher] 是可以注入的窄接口：生产用 [DioNovelSourceFetcher]
/// （dio 自动解压 gzip 并按 charset 解码），测试注入假实现，全程离线。
/// [NovelSourceImporter] 是页面唯一依赖的门面，深链 `yuedu://…importonline?src=`
/// 和手动粘贴地址都走同一个 [importFromLink] 入口。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

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
    this.message,
  });

  /// 实际落库的源条数。
  final int saved;

  /// 文件里的源总条数（含被过滤的重复/空源）。
  final int total;
  final String sourceUrl;
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

/// 书源导入门面。
class NovelSourceImporter {
  NovelSourceImporter(this.store, this.fetcher);

  final NovelSourceStorage store;
  final NovelSourceFetcher fetcher;

  /// 从 `yuedu://` 深链或手动粘贴的源地址导入。
  Future<NovelSourceImportResult> importFromLink(String link) async {
    final url =
        parseImportSourceUrl(link) ??
        (isFetchableSourceUrl(link) ? link : null);
    if (url == null) {
      throw const NovelSourceImportException('不是有效的书源导入链接');
    }
    return importFromUrl(url);
  }

  /// 直接从书源文件地址导入。
  Future<NovelSourceImportResult> importFromUrl(String url) async {
    if (!isFetchableSourceUrl(url)) {
      throw const NovelSourceImportException('书源地址必须是 http(s) 链接');
    }

    late final String text;
    late final String finalUrl;
    try {
      final fetched = await fetcher.fetch(url);
      text = fetched.text;
      finalUrl = fetched.finalUrl;
    } on Object catch (error) {
      throw NovelSourceImportException('下载书源失败：$error');
    }

    final List<Map<String, dynamic>> rawSources;
    try {
      rawSources = parseLegadoSources(text);
    } on Object catch (error) {
      throw NovelSourceImportException('书源文件解析失败：$error');
    }

    final sources = <NovelBookSource>[];
    for (final raw in rawSources) {
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
      total: rawSources.length,
      sourceUrl: finalUrl,
      message: '已导入 $saved 个书源',
    );
  }
}
