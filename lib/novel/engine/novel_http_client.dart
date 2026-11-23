/// 小说书源的 HTTP 传输层：dio 发请求、cookie_jar 记 Cookie、按站点编码解码。
///
/// 国内书源常用 GBK/GB2312，Dart 的 `utf8` 会整页乱码；这里用 `charset`
/// 包（纯 Dart）按 `charset` 选项 / Content-Type / `<meta charset>` 解码。
/// 测试注入 [NovelHttpTransport] 假实现即可完全离线。
library;

import 'dart:async';
import 'dart:convert';
import 'package:charset/charset.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

const String novelDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 一次书源请求。
class NovelHttpRequest {
  const NovelHttpRequest({
    required this.url,
    this.method = 'GET',
    this.headers = const <String, String>{},
    this.body,
    this.charset,
    this.retry = 0,
    this.useCookieJar = true,
    this.timeout = const Duration(seconds: 30),
  });

  final String url;
  final String method;
  final Map<String, String> headers;

  /// POST/PUT 的原始请求体（form / JSON / XML）；null = 无 body。
  final String? body;

  /// 显式站点编码（gbk / gb2312 / big5 / utf-8…）。
  final String? charset;
  final int retry;
  final bool useCookieJar;
  final Duration timeout;
}

/// 一次书源响应（纯数据，不暴露 dio 类型）。
class NovelHttpResponse {
  const NovelHttpResponse({
    required this.url,
    required this.statusCode,
    required this.body,
    this.headers = const <String, List<String>>{},
    this.charset,
    this.usedWebViewFallback = false,
  });

  final String url;
  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
  final String? charset;

  /// URL 选项里写了 `webView:true`；当前按普通 HTTP 抓，保留诊断位。
  final bool usedWebViewFallback;
}

/// 可注入的传输实现。
abstract interface class NovelHttpTransport {
  Future<NovelHttpResponse> send(NovelHttpRequest request);

  void close();
}

/// dio 生产实现。
class DioNovelHttpTransport implements NovelHttpTransport {
  DioNovelHttpTransport({Dio? dio, CookieJar? cookieJar})
    : _cookies = cookieJar ?? CookieJar(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              maxRedirects: 5,
              responseType: ResponseType.bytes,
              validateStatus: (_) => true,
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final cookies = await _cookies.loadForRequest(options.uri);
          if (cookies.isNotEmpty) {
            final jarCookie = cookies
                .map((cookie) => '${cookie.name}=${cookie.value}')
                .join('; ');
            final explicit = options.headers['Cookie']?.toString() ?? '';
            options.headers['Cookie'] = explicit.isEmpty
                ? jarCookie
                : '$jarCookie; $explicit';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final values = response.headers['set-cookie'];
          if (values != null && values.isNotEmpty) {
            final cookies = <Cookie>[];
            for (final value in values) {
              try {
                cookies.add(Cookie.fromSetCookieValue(value));
              } on Object {
                // 坏 Set-Cookie 单个忽略。
              }
            }
            if (cookies.isNotEmpty) {
              await _cookies.saveFromResponse(
                response.requestOptions.uri,
                cookies,
              );
            }
          }
          handler.next(response);
        },
      ),
    );
  }

  final Dio _dio;
  final CookieJar _cookies;

  /// 供源脚本的 `cookie.getCookie` 等同步读取。
  CookieJar get cookieJar => _cookies;

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    Object? lastError;
    for (var attempt = 0; attempt <= request.retry; attempt++) {
      try {
        final data = request.body;
        final headers = <String, String>{
          'User-Agent': novelDefaultUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,'
              'application/json;q=0.8,*/*;q=0.7',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          ...request.headers,
        };
        final contentType = _header(headers, 'content-type');
        if (data != null && contentType.isEmpty) {
          headers['Content-Type'] = _looksJson(data)
              ? 'application/json;charset=utf-8'
              : 'application/x-www-form-urlencoded;charset=utf-8';
        }
        final response = await _dio.request<List<int>>(
          request.url,
          data: data,
          options: Options(
            method: request.method.toUpperCase(),
            headers: headers,
            responseType: ResponseType.bytes,
            sendTimeout: request.timeout,
            receiveTimeout: request.timeout,
            followRedirects: true,
          ),
        );
        final bytes = response.data ?? const <int>[];
        final charset = _resolveCharset(
          explicit: request.charset,
          contentType: _header(response.headers.map, 'content-type'),
          bytes: bytes,
        );
        final body = _decode(bytes, charset);
        return NovelHttpResponse(
          url: response.realUri.toString(),
          statusCode: response.statusCode ?? 0,
          body: body,
          headers: <String, List<String>>{
            for (final entry in response.headers.map.entries)
              entry.key.toLowerCase(): entry.value,
          },
          charset: charset,
        );
      } on Object catch (error) {
        lastError = error;
        if (attempt < request.retry) {
          await Future<void>.delayed(
            Duration(milliseconds: 400 * (attempt + 1)),
          );
        }
      }
    }
    throw NovelHttpException('请求失败：${request.url}（$lastError）');
  }

  @override
  void close() => _dio.close(force: true);

  static String _header(Map<String, dynamic> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value.toString();
    }
    return '';
  }

  static bool _looksJson(String body) {
    final text = body.trimLeft();
    return (text.startsWith('{') && text.endsWith('}')) ||
        (text.startsWith('[') && text.endsWith(']'));
  }

  static String _resolveCharset({
    required String? explicit,
    required String contentType,
    required List<int> bytes,
  }) {
    final fromOption = explicit?.trim().toLowerCase();
    if (fromOption != null && fromOption.isNotEmpty) {
      return fromOption == 'escape' ? 'utf-8' : fromOption;
    }
    final fromHeader = RegExp(
      r'''charset\s*=\s*["']?([\w-]+)''',
      caseSensitive: false,
    ).firstMatch(contentType)?.group(1);
    if (fromHeader != null && _knownEncoding(fromHeader)) {
      return fromHeader.toLowerCase();
    }
    final meta = _metaCharset(bytes);
    if (meta != null) return meta;
    // 先严格 UTF-8，再 GBK 兜底；GBK 能“解码”几乎所有字节，不能先试。
    try {
      utf8.decode(bytes);
      return 'utf-8';
    } on Object {
      return 'gbk';
    }
  }

  static String? _metaCharset(List<int> bytes) {
    final window = bytes.take(4096).toList();
    final text = String.fromCharCodes(
      window.where((byte) => byte >= 0x20 || byte == 0x0A || byte == 0x0D),
    );
    final match = RegExp(
      r'''<meta[^>]+charset\s*=\s*["']?([\w-]+)''',
      caseSensitive: false,
    ).firstMatch(text);
    final value = match?.group(1)?.toLowerCase();
    return value != null && _knownEncoding(value) ? value : null;
  }

  static bool _knownEncoding(String name) {
    final encoding = Charset.getByName(name);
    return encoding != null;
  }

  static String _decode(List<int> bytes, String charset) {
    if (bytes.isEmpty) return '';
    final normalized = charset.toLowerCase().replaceAll('_', '-');
    if (normalized == 'utf-8' || normalized == 'utf8') {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
    final encoding = Charset.getByName(normalized) ?? gbk;
    try {
      return encoding.decode(bytes);
    } on Object {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
  }
}

/// 传输失败（页面转成可读错误，堆栈进日志）。
class NovelHttpException implements Exception {
  const NovelHttpException(this.message);

  final String message;

  @override
  String toString() => 'NovelHttpException: $message';
}
