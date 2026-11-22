// 图片请求加载器：把"地址 + 请求头"（[ImageRequest]）解析成原始字节。
//
// 与 [ReaderImageCache](reader_cache.dart) 的分工：
// - 本文件只管"怎么按完整请求信息取一次字节"，含防盗链头与失败重试；
// - 缓存负责命中、去重、限量，不关心请求头。
//
// 旧契约 [ImageByteLoader] 只看 URL，无法携带 Referer / Cookie；本文件新增
// [ImageRequestLoader] 补上这一层，并让缓存通过 [ReaderImageCache.loadRequest]
// 走新契约，旧 `load(url)` 保持不变以便渐进迁移。
//
// 重试策略刻意区分"值不值得重试"：4xx（除 408/429）说明请求本身被拒绝，
// 立刻失败；5xx 与网络错误（连不上、超时、TLS 握手）多为瞬时问题，按指数
// 退避重试。退避可注入，测试用 0 延迟避免拖慢。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;

import 'reader_models.dart';

/// 图片加载失败。UI 可据 [isRetryable] 决定是否给"重试"按钮。
class ImageLoadException implements Exception {
  const ImageLoadException({
    required this.url,
    required this.statusCode,
    required this.message,
    required this.isRetryable,
  });

  final String url;

  /// HTTP 状态码；本地文件 / 网络层错误（连不上等）为 null。
  final int? statusCode;

  final String message;

  /// 是否值得重试：4xx（除 408/429）与本地文件错误为 false；
  /// 5xx、408/429 与网络层错误为 true。
  final bool isRetryable;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    return 'ImageLoadException$status ($url): $message';
  }
}

/// 按完整请求信息取字节的函数式加载器契约。
typedef ImageRequestLoader = Future<Uint8List> Function(ImageRequest request);

/// 无 UA 时补的桌面 Chrome UA（与旧 [defaultImageByteLoader](reader_cache.dart)
/// 一致：不少图片站对空 UA / 非浏览器 UA 直接 403）。
const String _desktopChromeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 默认指数退避：第 1 次重试等 1s，第 2 次 2s，第 3 次 4s……上限 60s。
Duration _defaultBackoff(int attempt) {
  // 先夹住位移，避免大 attempt 让 1 << n 溢出成负数。
  final exponent = attempt < 1 ? 0 : (attempt > 7 ? 7 : attempt - 1);
  final seconds = 1 << exponent;
  return Duration(seconds: seconds > 60 ? 60 : seconds);
}

/// 默认实现：用 [HttpClient] 按 [ImageRequest] 取字节。
///
/// - 注入 [ImageRequest.headers] 与 [ImageRequest.referer]；UA 缺省补桌面 Chrome UA，
///   Referer 缺省按图片地址同源推导（防盗链常见要求）。
/// - [maxRetries] 次重试，仅对可重试错误生效；退避由 [backoff] 决定（默认 1s/2s/4s）。
/// - 本地路径 / `file://` 直接 [File.readAsBytes]，不走网络、不重试。
/// - 非 200 抛 [ImageLoadException]；网络层错误同样包装成 [ImageLoadException]，
///   `statusCode` 为 null。
ImageRequestLoader defaultImageRequestLoader({
  int maxRetries = 2,
  String? userAgent,
  Duration Function(int attempt)? backoff,
}) {
  final effectiveBackoff = backoff ?? _defaultBackoff;
  final maxAttempts = maxRetries < 0 ? 1 : maxRetries + 1;

  return (ImageRequest request) async {
    final uri = Uri.tryParse(request.url);
    final isHttp =
        uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isHttp) {
      return _readLocal(request, uri);
    }

    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _loadHttpOnce(uri, request, userAgent);
      } on ImageLoadException catch (error) {
        if (!error.isRetryable || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(effectiveBackoff(attempt));
      } on IOException catch (error) {
        // 网络层错误（连接被拒、超时前的 socket 错误、TLS 握手等）：可重试。
        final wrapped = ImageLoadException(
          url: request.url,
          statusCode: null,
          message: error.toString(),
          isRetryable: true,
        );
        if (attempt >= maxAttempts) throw wrapped;
        await Future<void>.delayed(effectiveBackoff(attempt));
      }
    }
  };
}

/// 本地路径 / `file://`：直接读文件；失败包装成不可重试的 [ImageLoadException]。
Future<Uint8List> _readLocal(ImageRequest request, Uri? uri) async {
  String path;
  try {
    path = uri != null && uri.scheme == 'file' ? uri.toFilePath() : request.url;
  } on UnsupportedError catch (error) {
    throw ImageLoadException(
      url: request.url,
      statusCode: null,
      message: '无法解析本地图片路径：$error',
      isRetryable: false,
    );
  }
  try {
    return await File(path).readAsBytes();
  } on IOException catch (error) {
    throw ImageLoadException(
      url: request.url,
      statusCode: null,
      message: '本地图片读取失败：$error',
      isRetryable: false,
    );
  }
}

/// 单次 HTTP 取字节；非 200 抛带 isRetryable 的 [ImageLoadException]。
Future<Uint8List> _loadHttpOnce(
  Uri uri,
  ImageRequest request,
  String? userAgent,
) async {
  final client = HttpClient();
  try {
    final httpRequest = await client.getUrl(uri);
    _applyHeaders(httpRequest, uri, request, userAgent);
    final response = await httpRequest.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw _statusFailure(request.url, response.statusCode);
    }
    return await consolidateHttpClientResponseBytes(response);
  } finally {
    client.close();
  }
}

/// 4xx（除 408/429）是"请求本身不被接受"，不重试；5xx 与 408/429 值得重试。
ImageLoadException _statusFailure(String url, int statusCode) {
  final retryable = statusCode >= 500 || statusCode == 408 || statusCode == 429;
  return ImageLoadException(
    url: url,
    statusCode: statusCode,
    message: retryable
        ? '服务端暂时不可用（HTTP $statusCode）'
        : '图片请求被拒绝（HTTP $statusCode）',
    isRetryable: retryable,
  );
}

void _applyHeaders(
  HttpClientRequest httpRequest,
  Uri uri,
  ImageRequest request,
  String? userAgent,
) {
  for (final entry in request.headers.entries) {
    httpRequest.headers.set(entry.key, entry.value);
  }

  final hasUserAgent = request.headers.keys.any(
    (key) => key.toLowerCase() == HttpHeaders.userAgentHeader,
  );
  if (!hasUserAgent) {
    httpRequest.headers.set(
      HttpHeaders.userAgentHeader,
      userAgent ?? _desktopChromeUserAgent,
    );
  }

  final hasReferer = request.headers.keys.any(
    (key) => key.toLowerCase() == HttpHeaders.refererHeader,
  );
  if (request.referer != null) {
    httpRequest.headers.set(HttpHeaders.refererHeader, request.referer!);
  } else if (!hasReferer) {
    // 未显式指定时按图片地址同源推导——多数防盗链只校验同源。
    httpRequest.headers.set(
      HttpHeaders.refererHeader,
      '${uri.scheme}://${uri.authority}/',
    );
  }
}
