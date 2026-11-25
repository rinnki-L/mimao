/// WebDAV 远端：配置、凭据存储、客户端与可读的错误分类。
///
/// 三条纪律：
/// 1. **网络失败必须给可读错误**——把 dio 的异常翻成
///    「账号或密码不对 / 路径不存在 / 连接超时 / 服务器拒绝」这类人话 + 下一步，
///    不要把 `DioException [bad response]: status code of 401` 直接甩到界面。
/// 2. **密码不进日志**：本文件任何路径都不打印配置对象，异常也只带状态码。
/// 3. **密码不进 kv**：落到系统安全存储（Windows DPAPI + 凭据管理器 /
///    Android Keystore）。只有安全存储不可用时才退回模块 kv，并明确告知用户
///    ——静默失败会让自动备份莫名其妙地不工作。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:mimao/novel/backup/credential_store.dart';
import 'package:mimao/novel/library_api.dart';

/// WebDAV 配置键（存 NovelPrefsApi；密码优先落安全存储）。
const String novelWebDavUrlKey = 'webdav_url';
const String novelWebDavUserKey = 'webdav_user';

/// 旧版明文密码键：只在迁移与"安全存储不可用"时读写。
const String novelWebDavPasswordKey = 'webdav_password';

/// 系统安全存储里的键名。
const String novelCredentialWebDavPassword = 'mimao.novel.webdav.password';

/// 密码现在存在哪。
enum NovelPasswordSource {
  /// 系统安全存储（正常路径）。
  secure,

  /// 安全存储不可用，退回模块 kv（会明确告警）。
  legacyKv,

  /// 没有密码（未设置）。
  none,
}

/// 一台 WebDAV 服务器上的配置。
class NovelWebDavConfig {
  const NovelWebDavConfig({
    required this.url,
    this.user = '',
    this.password = '',
    this.passwordSource = NovelPasswordSource.none,
  });

  /// 完整目录 + 文件名，例如
  /// `https://dav.example.com/mimao/novel-backup.json`。
  final String url;
  final String user;
  final String password;
  final NovelPasswordSource passwordSource;

  bool get isValid => Uri.tryParse(url)?.isAbsolute == true;

  bool get hasCredential => user.isNotEmpty || password.isNotEmpty;

  /// 进度专用包的地址：在主文件名的扩展名之前插 `-progress`。
  ///
  /// 例：`…/novel-backup.json` → `…/novel-backup-progress.json`。不另设配置项，
  /// 免得用户要同时维护两个地址。
  String get progressUrl => novelProgressUrlFor(url);

  /// 上一代远端内容留在 `.bak`，合并写坏时还有退路。
  String get backupUrl => '$url.bak';

  String get progressBackupUrl => '$progressUrl.bak';

  NovelWebDavConfig copyWith({
    String? url,
    String? user,
    String? password,
    NovelPasswordSource? passwordSource,
  }) => NovelWebDavConfig(
    url: url ?? this.url,
    user: user ?? this.user,
    password: password ?? this.password,
    passwordSource: passwordSource ?? this.passwordSource,
  );

  /// 刻意**不含密码**——这份 JSON 不该在任何地方落盘。
  Map<String, Object?> toJson() => <String, Object?>{'url': url, 'user': user};

  @override
  String toString() => 'NovelWebDavConfig($url, user: $user)';
}

/// 由主备份地址推导进度包地址。
String novelProgressUrlFor(String backupUrl) {
  final uri = Uri.tryParse(backupUrl);
  if (uri == null || uri.path.isEmpty) return backupUrl;
  final path = uri.path;
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  final insertAt = dot > slash ? dot : path.length;
  final next =
      '${path.substring(0, insertAt)}-progress'
      '${path.substring(insertAt)}';
  return uri.replace(path: next).toString();
}

/// 读配置；三项都空时返回 null（未配置）。
///
/// 顺手做一次迁移：旧版的明文 `webdav_password` 搬进安全存储并清掉 kv。
/// 安全存储写不进去时**不删** kv 里的旧值，配置标成
/// [NovelPasswordSource.legacyKv]，让界面把风险说出来。
Future<NovelWebDavConfig?> readNovelWebDavConfig(
  NovelPrefsApi prefs, {
  NovelCredentialStore? credentials,
}) async {
  final url = await prefs.read(novelWebDavUrlKey);
  if (url == null || url.trim().isEmpty) return null;
  final store = credentials ?? defaultNovelCredentialStore();
  final user = (await prefs.read(novelWebDavUserKey)) ?? '';

  var password = (await store.read(novelCredentialWebDavPassword)) ?? '';
  var source = password.isEmpty
      ? NovelPasswordSource.none
      : NovelPasswordSource.secure;

  final legacy = (await prefs.read(novelWebDavPasswordKey)) ?? '';
  if (password.isEmpty && legacy.isNotEmpty) {
    try {
      await store.write(novelCredentialWebDavPassword, legacy);
      await prefs.write(novelWebDavPasswordKey, '');
      password = legacy;
      source = NovelPasswordSource.secure;
    } on Object {
      // 安全存储不可用：先继续用旧值，别让用户以为密码丢了。
      password = legacy;
      source = NovelPasswordSource.legacyKv;
    }
  } else if (password.isEmpty && legacy.isEmpty) {
    source = NovelPasswordSource.none;
  }

  return NovelWebDavConfig(
    url: url.trim(),
    user: user,
    password: password,
    passwordSource: source,
  );
}

/// 保存配置：地址/用户名落模块 kv，密码优先落系统安全存储。
///
/// 返回实际落库后的配置（含 [NovelPasswordSource]）——调用方据此提示
/// "密码没能进安全存储"。
Future<NovelWebDavConfig> writeNovelWebDavConfig(
  NovelPrefsApi prefs,
  NovelWebDavConfig config, {
  NovelCredentialStore? credentials,
}) async {
  await prefs.write(novelWebDavUrlKey, config.url.trim());
  await prefs.write(novelWebDavUserKey, config.user);
  final store = credentials ?? defaultNovelCredentialStore();

  if (config.password.isEmpty) {
    await store.delete(novelCredentialWebDavPassword);
    await prefs.write(novelWebDavPasswordKey, '');
    return config.copyWith(passwordSource: NovelPasswordSource.none);
  }

  try {
    await store.write(novelCredentialWebDavPassword, config.password);
    await prefs.write(novelWebDavPasswordKey, '');
    return config.copyWith(passwordSource: NovelPasswordSource.secure);
  } on Object {
    // 安全存储不可用：退回 kv，但把状态标出来（界面会显示告警）。
    await prefs.write(novelWebDavPasswordKey, config.password);
    return config.copyWith(passwordSource: NovelPasswordSource.legacyKv);
  }
}

/// 清掉密码（安全存储 + 旧 kv 键）。
Future<void> clearNovelWebDavPassword(
  NovelPrefsApi prefs, {
  NovelCredentialStore? credentials,
}) async {
  final store = credentials ?? defaultNovelCredentialStore();
  try {
    await store.delete(novelCredentialWebDavPassword);
  } on Object {
    // 删不掉也要把 kv 里的旧值清干净。
  }
  await prefs.write(novelWebDavPasswordKey, '');
}

/// 失败类别——界面按这个决定给什么下一步。
enum NovelWebDavErrorKind {
  notConfigured('还没配置 WebDAV 地址'),
  unauthorized('账号或密码不对'),
  notFound('路径不存在'),
  timeout('连接超时'),
  unreachable('连不上服务器'),
  unsupported('服务器不支持这个操作'),
  server('服务器出错了'),
  badResponse('服务器返回了意外的响应'),
  unknown('同步失败');

  const NovelWebDavErrorKind(this.message);

  final String message;

  /// 可操作的下一步。
  String get hint => switch (this) {
    notConfigured => '在备份页填入完整的 http(s) 地址',
    unauthorized => '检查用户名与密码；部分网盘要用「应用专用密码」',
    notFound => '确认地址指向一个已存在的目录；有的网盘要先手动建目录',
    timeout => '网络慢或服务器无响应，稍后重试',
    unreachable => '检查网络、代理与证书；地址要能直接在浏览器打开',
    unsupported => '换一个支持 PUT/GET 的 WebDAV 目录，或改用本地备份',
    server => '多半是临时故障，稍后重试；反复失败请换服务',
    badResponse => '确认地址指向的是文件而不是网页目录',
    unknown => '看应用日志里的完整错误再判断',
  };
}

/// WebDAV 操作失败（带类别，界面上只显示 [message] + [hint]）。
class NovelWebDavException implements Exception {
  const NovelWebDavException(this.kind, {this.statusCode, this.detail = ''});

  final NovelWebDavErrorKind kind;
  final int? statusCode;

  /// 技术细节（只进日志，不进界面主文案）。
  final String detail;

  String get message => kind.message;

  String get hint => kind.hint;

  String get fullMessage => statusCode == null
      ? '${kind.message}（${kind.hint}）'
      : '${kind.message}（HTTP $statusCode · ${kind.hint}）';

  @override
  String toString() => 'NovelWebDavException(${kind.name}, $statusCode)';
}

/// WebDAV 客户端窄接口（可注入 fake）。
abstract interface class NovelWebDavClient {
  Future<void> put(String url, String body, NovelWebDavConfig config);

  Future<String> get(String url, NovelWebDavConfig config);
}

/// 生产实现：dio + Basic 认证，PUT 写文件、GET 读文件。
class DioNovelWebDavClient implements NovelWebDavClient {
  DioNovelWebDavClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              followRedirects: true,
            ),
          );

  final Dio _dio;

  Map<String, String> _headers(NovelWebDavConfig config) {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (config.user.isNotEmpty || config.password.isNotEmpty) {
      final credentials = base64Encode(
        utf8.encode('${config.user}:${config.password}'),
      );
      headers['Authorization'] = 'Basic $credentials';
    }
    return headers;
  }

  @override
  Future<void> put(String url, String body, NovelWebDavConfig config) async {
    await _guard(
      () => _dio.put<String>(
        url,
        data: body,
        options: Options(headers: _headers(config)),
      ),
      url,
    );
  }

  @override
  Future<String> get(String url, NovelWebDavConfig config) async {
    final response = await _guard(
      () => _dio.get<String>(
        url,
        options: Options(
          headers: _headers(config),
          responseType: ResponseType.plain,
        ),
      ),
      url,
    );
    return response?.data ?? '';
  }

  Future<Response<String>?> _guard(
    Future<Response<String>> Function() call,
    String url,
  ) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on NovelWebDavException {
      rethrow;
    } on Object catch (error) {
      throw NovelWebDavException(
        NovelWebDavErrorKind.unknown,
        detail: '$error @ $url',
      );
    }
  }

  NovelWebDavException _mapDioException(DioException error) {
    final status = error.response?.statusCode;
    final detail =
        '${error.type.name}${status == null ? '' : ' HTTP $status'}'
        '${error.message == null ? '' : ' ${error.message}'}';
    final kind = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => NovelWebDavErrorKind.timeout,
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate => NovelWebDavErrorKind.unreachable,
      DioExceptionType.badResponse => _kindForStatus(status),
      DioExceptionType.cancel ||
      DioExceptionType.unknown => NovelWebDavErrorKind.unknown,
    };
    return NovelWebDavException(kind, statusCode: status, detail: detail);
  }

  NovelWebDavErrorKind _kindForStatus(int? status) => switch (status) {
    401 || 403 => NovelWebDavErrorKind.unauthorized,
    404 => NovelWebDavErrorKind.notFound,
    405 || 501 => NovelWebDavErrorKind.unsupported,
    507 => NovelWebDavErrorKind.server,
    final code when code != null && code >= 500 => NovelWebDavErrorKind.server,
    _ => NovelWebDavErrorKind.badResponse,
  };
}
