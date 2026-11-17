/// 番剧模块的网页抓取封装（dio）。
///
/// 只做三件事：带默认 UA / Referer / Cookie 发请求、把响应收敛成字符串、
/// 保留状态码与 Set-Cookie。HTML/XPath 解析不在这里——那是 engine 的职责。
library;

import 'package:dio/dio.dart';

/// 默认 UA：桌面 Chrome。很多番剧站对空 UA 或 Dart 默认 UA 直接返回 403。
const String defaultAnimeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 一次抓取的请求参数。
class AnimeFetchOptions {
  const AnimeFetchOptions({
    this.method = 'GET',
    this.userAgent,
    this.referer,
    this.cookies = const <String, String>{},
    this.headers = const <String, String>{},
    this.formData,
  });

  final String method;

  /// 空/未设置时使用客户端默认 UA（[defaultAnimeUserAgent]）。
  final String? userAgent;

  /// 部分站点要求 Referer 与站点同源才会返回播放列表。
  final String? referer;

  /// 已登录/已过验证的 Cookie，按 `name: value` 传入。
  final Map<String, String> cookies;

  /// 额外请求头，优先级高于上面生成的默认头。
  final Map<String, String> headers;

  /// POST 表单体（Kazumi 的 `usePost` 规则用）。
  final Map<String, String>? formData;

  /// 生成最终请求头（纯函数，便于单测）。
  Map<String, String> toHeaders({required String defaultUserAgent}) {
    final requestUserAgent = userAgent?.trim() ?? '';
    final result = <String, String>{
      'User-Agent': requestUserAgent.isEmpty
          ? defaultUserAgent
          : requestUserAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
    final requestReferer = referer?.trim() ?? '';
    if (requestReferer.isNotEmpty) result['Referer'] = requestReferer;
    if (cookies.isNotEmpty) {
      result['Cookie'] = cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
    }
    result.addAll(headers);
    return result;
  }
}

/// 抓取结果——不暴露 dio 类型，engine/测试只依赖这个。
class AnimeHttpResponse {
  const AnimeHttpResponse({
    required this.statusCode,
    required this.body,
    this.url = '',
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final String body;

  /// 跟随重定向后的最终地址。
  final String url;

  final Map<String, List<String>> headers;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// 响应里的 Set-Cookie 原始值（供后续请求的 Cookie 头使用）。
  List<String> get setCookies => headers.entries
      .where((entry) => entry.key.toLowerCase() == 'set-cookie')
      .expand((entry) => entry.value)
      .toList(growable: false);

  @override
  String toString() => 'AnimeHttpResponse($statusCode, ${body.length} chars)';
}

/// 可替换的抓取接口——engine 依赖它，测试用假实现即可脱离网络。
abstract interface class AnimeHttpClient {
  Future<AnimeHttpResponse> fetch(String url, {AnimeFetchOptions options});
}

/// 基于 dio 的实现。
class AnimeWebClient implements AnimeHttpClient {
  AnimeWebClient({
    Dio? dio,
    this.defaultUserAgent = defaultAnimeUserAgent,
    this.timeout = const Duration(seconds: 20),
  }) : _dio = dio ?? Dio();

  final Dio _dio;
  final String defaultUserAgent;
  final Duration timeout;

  /// POST 表单需要显式声明 form-urlencoded，否则 dio 会把 Map 序列化成 JSON。
  /// 调用方自带 Content-Type 时尊重调用方。
  String? _formContentType(AnimeFetchOptions options) {
    if (options.formData == null) return null;
    final hasContentType = options.headers.keys.any(
      (key) => key.toLowerCase() == 'content-type',
    );
    return hasContentType ? null : Headers.formUrlEncodedContentType;
  }

  @override
  Future<AnimeHttpResponse> fetch(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'url', '必须是绝对 URL');
    }

    final response = await _dio.request<String>(
      uri.toString(),
      data: options.formData,
      options: Options(
        method: options.method,
        headers: options.toHeaders(defaultUserAgent: defaultUserAgent),
        contentType: _formContentType(options),
        responseType: ResponseType.plain,
        followRedirects: true,
        // 4xx/5xx 也作为正常响应返回：导入器要读状态码给出可诊断的错误，
        // 而不是让 dio 抛一个只有文本的 DioException。
        validateStatus: (status) => status != null,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );

    return AnimeHttpResponse(
      statusCode: response.statusCode ?? 0,
      body: response.data ?? '',
      url: response.realUri.toString(),
      headers: response.headers.map,
    );
  }
}
