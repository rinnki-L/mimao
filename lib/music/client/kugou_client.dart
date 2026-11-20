/// 酷狗网关传输层——EchoMusicNext `crates/echo-api/src/util/request.rs` 的
/// `send_endpoint` 翻译（docs/architecture.md §4.3：`music/client/` ← util）。
///
/// 职责：默认参数注入（appid/clientver/clienttime/dfid/mid/uuid）→ 账号字段
/// → 端点参数覆盖 → signature → origin 主机选择 → 固定 UA/头 → 字节响应。
/// Rust 的 request_* 变体在这里收敛为 `cloud`/`clearDefaults` 两个布尔
/// （对应 `send_endpoint` 的实参，注释里逐条标注）。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'kugou_error.dart';
import 'kugou_identity.dart';
import 'signature.dart';

/// 端点主机（request.rs `Origin`，逐值对齐）。
enum KugouOrigin {
  gateway,
  deviceLogout,
  sumComment,
  qrLogin,
  lyrics,
  relationUser,
  climax,
  artistImages,
  effectsCatalog,
  mcloudService,
  videoCollect,
  tracker,
  verification,
  userService,
  registration,
  vip,
  loginRetry,
}

/// 网关默认主机（request.rs `ApiClient::new` 的 base_url）。
const String kugouGatewayBaseUrl = 'https://gateway.kugou.com';

/// 默认 UA（request.rs send_endpoint 的兜底值）。
const String kugouDefaultUserAgent =
    'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';

/// origin → 主机（request.rs 的 match 块逐行对齐）。
String kugouOriginHost(KugouOrigin origin) => switch (origin) {
  KugouOrigin.lyrics => 'https://lyrics.kugou.com',
  KugouOrigin.relationUser => 'https://relationuser.kugou.com',
  KugouOrigin.climax => 'https://expendablekmrcdn.kugou.com',
  KugouOrigin.artistImages => 'https://expendablekmr.kugou.com',
  KugouOrigin.effectsCatalog => 'http://mobilecdngz.kugou.com',
  KugouOrigin.mcloudService => 'https://mcloudservice.kugou.com',
  KugouOrigin.videoCollect => 'https://collectservice.kugou.com',
  KugouOrigin.gateway ||
  KugouOrigin.deviceLogout ||
  KugouOrigin.sumComment => kugouGatewayBaseUrl,
  KugouOrigin.tracker => 'https://trackercdngz.kugou.com',
  KugouOrigin.verification => 'https://verifyservice.kugou.com',
  KugouOrigin.userService ||
  KugouOrigin.registration => 'https://userservice.kugou.com',
  KugouOrigin.qrLogin => 'https://login-user.kugou.com',
  KugouOrigin.vip => 'https://kugouvip.kugou.com',
  KugouOrigin.loginRetry => 'https://loginserviceretry.kugou.com',
};

/// 这些 origin 走 web 签名（request.rs：QrLogin | DeviceLogout | SumComment）。
const Set<KugouOrigin> _kWebSignatureOrigins = <KugouOrigin>{
  KugouOrigin.qrLogin,
  KugouOrigin.deviceLogout,
  KugouOrigin.sumComment,
};

/// registration 端点的固定参数顺序（request.rs `ORDER`，signature 恒最后）。
const List<String> _kRegistrationOrder = <String>[
  'dfid',
  'mid',
  'uuid',
  'appid',
  'clientver',
  'clienttime',
  'part',
  'platid',
  'p',
];

/// 一个端点的完整描述（request.rs `Endpoint`）。
class KugouEndpoint {
  const KugouEndpoint({
    required this.origin,
    required this.path,
    required this.method,
    this.router,
    this.params = const <String, String>{},
    this.body = const <int>[],
    this.headers = const <(String, String)>[],
  });

  final KugouOrigin origin;
  final String path;

  /// x-router 头（网关背后区分真实服务用）。
  final String? router;
  final String method;
  final Map<String, String> params;
  final List<int> body;
  final List<(String, String)> headers;
}

/// 传输层返回：字节 + HTTP 状态 + 响应头（request.rs `HttpResponse`；非 2xx
/// 已在 [KugouClient.sendEndpoint] 按 Rust receive() 语义抛 http 异常）。
class KugouHttpResponse {
  const KugouHttpResponse({
    required this.bytes,
    required this.statusCode,
    this.headers = const <String, String>{},
  });

  final Uint8List bytes;
  final int statusCode;

  /// 响应头（同名多值取第一个；第三方登录轮询需要读取跳转头）。
  final Map<String, String> headers;
}

/// 网关客户端。无状态：身份（[KugouIdentity]）每次调用显式传入，
/// 客户端自身不持有 token/设备指纹。
class KugouClient {
  KugouClient({Dio? dio, this.now})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              // 按字节收响应，交给端点层统一解释（可能是 JSON，也可能是信封密文）。
              responseType: ResponseType.bytes,
              // 与 Rust 一致：非 2xx 抛 http 异常（receive() 语义），字节不透传。
              validateStatus: (int? status) => true,
              // Rust reqwest Policy::none：重定向会带着签名与设备头外流到
              // 非预期主机（上游注释），一律不跟随。
              followRedirects: false,
              maxRedirects: 0,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Dio _dio;

  /// 单测注入时钟（clienttime 参数）。
  final DateTime Function()? now;

  /// send_endpoint 核心翻译。`cloud`/`clearDefaults` 对应 Rust 各 request_*
  /// 变体：request→(false,false)、request_cloud/grade/mcloud→(true,…)、
  /// lyric search/effects/images/import→(false,true)。骨架端点都是 (false,false)。
  Future<KugouHttpResponse> sendEndpoint(
    KugouIdentity identity,
    KugouEndpoint endpoint, {
    bool cloud = false,
    bool clearDefaults = false,
  }) async {
    if (!identity.isUsable) {
      throw identityNotUsableError(identity);
    }
    final timestamp = _unixSeconds().toString();

    // 精确的 lite 协议默认值；端点参数可覆盖（如 search 的 clientver=201）。
    final defaults = <String, String>{
      'appid': '3116',
      'clientver': '11440',
      'clienttime': timestamp,
      'dfid': identity.dfid,
      'mid': identity.mid,
      // lite Android 传输固定 uuid='-'；注册过的设备 UUID 只给显式使用的端点。
      'uuid': '-',
    };
    if (cloud && endpoint.origin != KugouOrigin.videoCollect) {
      defaults.remove('uuid');
    }
    if (clearDefaults) {
      defaults.clear();
    }
    final injectAccount =
        (!cloud || endpoint.origin == KugouOrigin.videoCollect) &&
        !clearDefaults;
    if (injectAccount && identity.token.isNotEmpty) {
      defaults['token'] = identity.token;
    }
    if (injectAccount && identity.userId != 0) {
      defaults['userid'] = identity.userId.toString();
    }
    defaults.addAll(endpoint.params);

    if (!cloud) {
      final signed = (_kWebSignatureOrigins.contains(endpoint.origin)
          ? kugouSignatureWeb(defaults, endpoint.body)
          : kugouSignatureAndroid(defaults, endpoint.body));
      defaults['signature'] = signed;
    }

    final query = _orderedQuery(defaults, endpoint);
    final host = kugouOriginHost(endpoint.origin);

    final headers = <String, String>{
      'User-Agent': kugouDefaultUserAgent,
      'dfid': identity.dfid,
      'mid': identity.mid,
    };
    for (final (name, value) in endpoint.headers) {
      if (name.toLowerCase() == 'user-agent') {
        headers['User-Agent'] = value;
        continue;
      }
      if (name.toLowerCase() == 'content-type') {
        continue; // content-type 由 body 分支统一决定
      }
      headers[name] = value;
    }
    if (defaults.containsKey('clienttime')) {
      headers['clienttime'] = defaults['clienttime']!;
    }
    if (endpoint.router != null) {
      headers['x-router'] = endpoint.router!;
    }
    if (endpoint.body.isNotEmpty) {
      // Rust：Content-Type 取端点声明值，缺省 application/json。
      String? declared;
      for (final (name, value) in endpoint.headers) {
        if (name.toLowerCase() == 'content-type') declared = value;
      }
      headers['Content-Type'] = declared ?? 'application/json';
    }

    final response = await _dio.request<List<int>>(
      '$host${endpoint.path}',
      data: endpoint.body.isEmpty ? null : Uint8List.fromList(endpoint.body),
      options: Options(
        method: endpoint.method,
        headers: headers,
        responseType: ResponseType.bytes,
        // 先放行非 2xx 拿到响应对象，再按 Rust receive() 语义统一抛 http。
        validateStatus: (int? status) => true,
      ),
      queryParameters: query,
    );
    final statusCode = response.statusCode ?? 0;
    _ensureSuccess(statusCode);
    return KugouHttpResponse(
      bytes: Uint8List.fromList(response.data ?? <int>[]),
      statusCode: statusCode,
      headers: _responseHeaders(response),
    );
  }

  /// 裸传输（无身份默认参数、无签名注入）——只给固定主机的特殊端点用：
  /// CSCC 上报（`http://d.kugou.com`）、头像/歌单封面上传、动态封面。
  ///
  /// 对应 request.rs 的 `request_cscc` / `upload_avatar` /
  /// `upload_playlist_png` / `album_dynamic_cover`：URL、参数、头、body 全部
  /// 由调用方按上游逐字提供；仍然复用非 2xx → http 的统一语义。
  Future<KugouHttpResponse> sendRaw({
    required String url,
    String method = 'GET',
    Map<String, String> params = const <String, String>{},
    List<int> body = const <int>[],
    Map<String, String> headers = const <String, String>{},
    bool allowNon2xx = false,
  }) async {
    final response = await _dio.request<List<int>>(
      url,
      data: body.isEmpty ? null : Uint8List.fromList(body),
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.bytes,
        validateStatus: (int? status) => true,
      ),
      queryParameters: params,
    );
    final statusCode = response.statusCode ?? 0;
    if (!allowNon2xx) _ensureSuccess(statusCode);
    return KugouHttpResponse(
      bytes: Uint8List.fromList(response.data ?? <int>[]),
      statusCode: statusCode,
      headers: _responseHeaders(response),
    );
  }

  Map<String, String> _responseHeaders(Response<List<int>> response) {
    final output = <String, String>{};
    response.headers.forEach((name, values) {
      if (values.isNotEmpty) output[name] = values.first;
    });
    return output;
  }

  void _ensureSuccess(int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      // 只保留状态码与类别，不带响应体（可能含凭证/隐私）。
      throw KugouApiException('http', '音乐服务 HTTP 状态异常：$statusCode');
    }
  }

  /// registration 端点用固定顺序（defaults→端点参数→signature 最后），
  /// 其余端点按 BTreeMap 的字典序（request.rs 的 query 组装）。
  Map<String, String> _orderedQuery(
    Map<String, String> defaults,
    KugouEndpoint endpoint,
  ) {
    if (endpoint.origin != KugouOrigin.registration) {
      final sorted = <String, String>{};
      for (final key in defaults.keys.toList()..sort()) {
        sorted[key] = defaults[key]!;
      }
      return sorted;
    }
    final ordered = <String, String>{};
    for (final key in _kRegistrationOrder) {
      final value = defaults[key];
      if (value != null) ordered[key] = value;
    }
    for (final key in defaults.keys.toList()..sort()) {
      if (key == 'signature' || _kRegistrationOrder.contains(key)) continue;
      ordered[key] = defaults[key]!;
    }
    final signature = defaults['signature'];
    if (signature != null) ordered['signature'] = signature;
    return ordered;
  }

  int _unixSeconds() {
    final instant = now?.call() ?? DateTime.now();
    return instant.millisecondsSinceEpoch ~/ 1000;
  }
}
