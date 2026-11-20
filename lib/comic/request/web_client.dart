/// 漫画模块的网页抓取封装（dio + cookie_jar）。
///
/// 只做四件事：带默认 UA / Referer / Cookie 发请求、维护 cookie_jar、
/// 把响应收敛成纯数据 [ComicHttpResponse]、保留 Set-Cookie 与字节体。
/// HTML 解析与源脚本执行不在这里——那是 engine/js_bridge 的职责。
library;

import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'challenge.dart';
import 'cookie_store.dart';

/// 默认 UA：桌面 Chrome。多数漫画站对空 UA / Dart 默认 UA 直接 403。
const String defaultComicUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 一次抓取的请求参数。
class ComicFetchOptions {
  const ComicFetchOptions({
    this.method = 'GET',
    this.userAgent,
    this.referer,
    this.headers = const <String, String>{},
    this.data,
    this.useCookieJar = true,
  });

  final String method;

  /// 空/未设置时使用客户端默认 UA（[defaultComicUserAgent]）。
  final String? userAgent;

  /// 部分站点要求 Referer 与站点同源才会返回图片。
  final String? referer;

  /// 额外请求头，优先级高于下面生成的默认头。
  final Map<String, String> headers;

  /// 请求体（POST/PUT 的 form 或 JSON 字符串）。
  final Object? data;

  /// 是否让 cookie_jar 自动带上/保存 Cookie（源脚本显式 setCookies 时仍生效）。
  final bool useCookieJar;

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
    result.addAll(headers);
    return result;
  }
}

/// 抓取结果——不暴露 dio 类型，engine / 测试只依赖这个。
class ComicHttpResponse {
  const ComicHttpResponse({
    required this.statusCode,
    required this.body,
    this.bodyBytes = const <int>[],
    this.url = '',
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final String body;

  /// 原始字节体（`Network.fetchBytes` / `fetch().arrayBuffer()` 用）。
  final List<int> bodyBytes;

  /// 跟随重定向后的最终地址。
  final String url;

  final Map<String, List<String>> headers;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// 响应里的 Set-Cookie 原始值。
  List<String> get setCookies => headers.entries
      .where((entry) => entry.key.toLowerCase() == 'set-cookie')
      .expand((entry) => entry.value)
      .toList(growable: false);

  @override
  String toString() => 'ComicHttpResponse($statusCode, ${body.length} chars)';
}

/// 可替换的抓取接口——js_bridge 依赖它，测试用假实现即可脱离网络。
abstract interface class ComicHttpClient {
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  });

  /// 供 `Network.setCookies` 使用：按 URL 域名写入 Cookie。
  Future<void> setCookies(String url, Map<String, String> cookies);

  /// 供 `Network.getCookies` 使用：取出该 URL 可见的 Cookie。
  List<Map<String, String>> getCookies(String url);

  /// 供 `Network.deleteCookies` 使用。
  Future<void> deleteCookies(String url);
}

/// 判断响应是否是 Cloudflare 托管挑战（需要 WebView 过一次验证）。
///
/// 首选信号是 `cf-mitigated: challenge`（ykmh 实测有）；老部署可能没有该头，
/// 再用 `server: cloudflare` + 挑战页特征兜底。
bool isCloudflareChallenge(ComicHttpResponse response) {
  if (response.statusCode != 403) return false;
  final mitigated = _headerValue(response.headers, 'cf-mitigated');
  if (mitigated != null && mitigated.toLowerCase().contains('challenge')) {
    return true;
  }
  final server = _headerValue(response.headers, 'server')?.toLowerCase() ?? '';
  if (!server.contains('cloudflare')) return false;
  final body = response.body;
  return body.contains('Just a moment') ||
      body.contains('_cf_chl_opt') ||
      body.contains('challenge-platform');
}

String? _headerValue(Map<String, List<String>> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value.join(', ');
  }
  return null;
}

/// 基于 dio + cookie_jar 的实现。
class ComicWebClient implements ComicHttpClient {
  ComicWebClient({
    Dio? dio,
    CookieJar? cookieJar,
    this.challengeSolver,
    this.proxyRule,
    this.defaultUserAgent = defaultComicUserAgent,
    this.timeout = const Duration(seconds: 20),
  }) : _dio = dio ?? _buildDio(proxyRule),
       _cookieJar = cookieJar ?? ComicCookieJar();

  final Dio _dio;
  final CookieJar _cookieJar;
  final ComicChallengeSolver? challengeSolver;

  /// `HttpClient.findProxy` 规则（每次请求回调，实时反映设置）。
  final String Function(Uri)? proxyRule;
  final String defaultUserAgent;
  final Duration timeout;

  /// 未注入 Dio 时按代理规则建默认客户端；注入了（测试假 adapter）就不碰。
  static Dio _buildDio(String Function(Uri)? proxyRule) {
    final dio = Dio();
    if (proxyRule != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = proxyRule;
          return client;
        },
      );
    }
    return dio;
  }

  bool _jarReady = false;

  /// 等待持久化 Cookie 加载完成，并把落盘 Cookie 水合进同步缓存。
  ///
  /// 生产在装配期 await 一次；此后 [getCookies] 这类同步 API 才能看到
  /// 上次启动保存的登录态 / `cf_clearance`。
  Future<void> ready() async {
    if (_jarReady) return;
    final jar = _cookieJar;
    if (jar is ComicCookieJar) {
      await jar.ensureLoaded();
      _syncCookieCache
        ..clear()
        ..addAll(jar.allCookies);
    }
    _jarReady = true;
  }

  Future<List<Cookie>> _loadCookies(Uri uri) async {
    try {
      return await _cookieJar.loadForRequest(uri);
    } catch (_) {
      return <Cookie>[];
    }
  }

  Future<void> _saveCookies(Uri uri, List<String> rawCookies) async {
    if (rawCookies.isEmpty) return;
    final cookies = <Cookie>[];
    for (final raw in rawCookies) {
      try {
        cookies.add(Cookie.fromSetCookieValue(raw));
      } catch (_) {
        // 单个畸形 Set-Cookie 不该拖垮整次请求。
      }
    }
    if (cookies.isEmpty) return;
    try {
      await _cookieJar.saveFromResponse(uri, cookies);
    } catch (_) {
      // Cookie 持久化失败不影响正文抓取。
    }
    // 同步缓存：Venera 的 Network.getCookies 是同步 API，源脚本紧接着
    // fetch/setCookies 读取时必须能看到刚从响应落下的 Cookie。
    _rememberCookies(uri, cookies);
  }

  @override
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    await ready();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'url', '必须是绝对 URL');
    }

    var response = await _send(uri, options);
    // Cloudflare 托管挑战：打开内嵌 WebView 过一次验证，拿 cf_clearance 后
    // 用同一请求重试一次。没装求解器/用户取消时保持原 403，交给源脚本报错。
    final solver = challengeSolver;
    if (solver == null || !isCloudflareChallenge(response)) return response;
    final pass = await solver.solve(uri);
    if (pass == null) return response;
    await _applyChallengePass(uri, pass);
    response = await _send(uri, options);
    return response;
  }

  /// 真正发一次请求（不含挑战重试）。
  Future<ComicHttpResponse> _send(Uri uri, ComicFetchOptions options) async {
    final headers = options.toHeaders(defaultUserAgent: defaultUserAgent);
    _normalizeAcceptEncoding(headers);
    _applyChallengeUserAgent(uri, headers);
    if (options.useCookieJar) {
      final cookies = await _loadCookies(uri);
      if (cookies.isNotEmpty) {
        // 已有的显式 Cookie 优先（源脚本可覆盖 jar）。
        headers.putIfAbsent(
          'Cookie',
          () => cookies.map((c) => '${c.name}=${c.value}').join('; '),
        );
      }
    }

    final response = await _dio.request<List<int>>(
      uri.toString(),
      data: options.data,
      options: Options(
        method: options.method,
        headers: headers,
        responseType: ResponseType.bytes,
        followRedirects: true,
        // 4xx/5xx 作为正常响应返回：源脚本要读 status 自己决定重试/抛错。
        validateStatus: (status) => status != null,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );

    final rawCookies = (response.headers['set-cookie'] ?? <String>[]).toList();
    await _saveCookies(response.realUri, rawCookies);

    final bytes = response.data ?? <int>[];
    return ComicHttpResponse(
      statusCode: response.statusCode ?? 0,
      body: _decodeBody(bytes, response.headers),
      bodyBytes: bytes,
      url: response.realUri.toString(),
      headers: response.headers.map,
    );
  }

  /// 过挑战的浏览器 UA：`cf_clearance` 与 UA 绑定，源脚本自带的 UA 会被
  /// 覆盖，否则重试必然继续 403（对齐 Venera 的 CloudflareInterceptor）。
  void _applyChallengeUserAgent(Uri uri, Map<String, String> headers) {
    final jar = _cookieJar;
    if (jar is! ComicCookieJar) return;
    final userAgent = jar.userAgentFor(uri.host);
    if (userAgent == null || userAgent.isEmpty) return;
    headers.removeWhere((key, _) => key.toLowerCase() == 'user-agent');
    headers['User-Agent'] = userAgent;
  }

  /// 把挑战凭证写进 Cookie 库（落盘）并记录 UA。
  Future<void> _applyChallengePass(Uri uri, ComicChallengePass pass) async {
    final cookies = <Cookie>[];
    for (final raw in pass.cookies) {
      try {
        final cookie = Cookie(raw.name, raw.value)
          ..path = raw.path
          ..secure = raw.secure
          ..httpOnly = raw.httpOnly;
        final domain = raw.domain;
        if (domain != null && domain.isNotEmpty) cookie.domain = domain;
        final expires = raw.expires;
        if (expires != null) cookie.expires = expires;
        cookies.add(cookie);
      } on Object {
        // 单条非法 Cookie 跳过，不影响其余凭证。
      }
    }
    if (cookies.isNotEmpty) {
      try {
        await _cookieJar.saveFromResponse(uri, cookies);
      } on Object {
        // 写 jar 失败仍尝试重试；下次请求会重新触发挑战。
      }
      _rememberCookies(uri, cookies);
    }
    final userAgent = pass.userAgent;
    final jar = _cookieJar;
    if (userAgent != null && userAgent.isNotEmpty && jar is ComicCookieJar) {
      await jar.setUserAgentFor(uri.host, userAgent);
    }
  }

  /// 源脚本常照浏览器广告 `gzip, deflate, br, zstd`，但 dart:io 只会自动
  /// 解压 gzip：服务端真回 br/zstd 时正文是压缩字节，解析结果为空且不抛错
  /// （manhuaren 搜索 200 却 0 条的根因）。把 Accept-Encoding 收敛为 gzip，
  /// 服务端就只回我们能解压的编码。
  void _normalizeAcceptEncoding(Map<String, String> headers) {
    for (final key in headers.keys.toList(growable: false)) {
      if (key.toLowerCase() == 'accept-encoding') {
        headers[key] = 'gzip';
      }
    }
  }

  /// 依据 Content-Type 的 charset 解码；缺省 UTF-8，失败回退 latin1。
  String _decodeBody(List<int> bytes, Headers responseHeaders) {
    if (bytes.isEmpty) return '';
    var charset = 'utf-8';
    final contentType = responseHeaders.value('content-type') ?? '';
    final match = RegExp(
      r'charset\s*=\s*([\w-]+)',
      caseSensitive: false,
    ).firstMatch(contentType);
    if (match != null) charset = match.group(1)!.toLowerCase();
    try {
      return switch (charset) {
        // GBK 码表不在 Dart 核心库；UTF-8 兜底（源脚本可用 Convert.decodeGbk）。
        'latin1' ||
        'iso-8859-1' => bytes.map((b) => String.fromCharCode(b)).join(),
        _ => utf8.decode(bytes, allowMalformed: true),
      };
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  @override
  Future<void> setCookies(String url, Map<String, String> cookies) async {
    await ready();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return;
    final parsed = <Cookie>[];
    for (final entry in cookies.entries) {
      try {
        parsed.add(Cookie(entry.key, entry.value));
      } catch (_) {
        // 跳过非法 Cookie 名。
      }
    }
    if (parsed.isEmpty) return;
    await _cookieJar.saveFromResponse(uri, parsed);
    _rememberCookies(uri, parsed);
  }

  @override
  List<Map<String, String>> getCookies(String url) {
    // CookieJar.loadForRequest 是异步的；同步 API 用缓存保证 Venera 语义
    // （getCookies 同步返回）。缓存由 fetch/setCookies 填充。
    return List<Map<String, String>>.unmodifiable(
      _syncCookieCache
          .where((c) => _matchesUrl(c, url))
          .map((c) => <String, String>{'name': c.name, 'value': c.value}),
    );
  }

  @override
  Future<void> deleteCookies(String url) async {
    await ready();
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await _cookieJar.delete(uri);
    _syncCookieCache.removeWhere((c) => _matchesUrl(c, url));
  }

  final List<Cookie> _syncCookieCache = <Cookie>[];

  /// 用落库的 Cookie 更新同步快照：同域同名覆盖，避免重复项无限增长。
  void _rememberCookies(Uri uri, List<Cookie> cookies) {
    for (final cookie in cookies) {
      final host = uri.host;
      final domain = cookie.domain;
      // CookieJar 对显式 setCookies 的 Cookie 可能不带 domain；补上 host
      // 让同步 getCookies 能按 URL 域名匹配到。
      if (domain == null || domain.isEmpty) cookie.domain = host;
      _syncCookieCache.removeWhere(
        (c) =>
            c.name == cookie.name && _cookieDomain(c) == _cookieDomain(cookie),
      );
      _syncCookieCache.add(cookie);
    }
  }

  String _cookieDomain(Cookie cookie) => cookie.domain?.toLowerCase() ?? '';

  bool _matchesUrl(Cookie cookie, String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final domain = _cookieDomain(cookie);
    final host = uri.host.toLowerCase();
    // _rememberCookies 会给无 domain 的 Cookie 补上 host；这里仍对空串兜底，
    // 不匹配任何 URL，避免把 cookie_jar 的边界语义放宽成「匹配所有域」。
    if (domain.isEmpty) return false;
    return host == domain || host.endsWith('.$domain');
  }
}
