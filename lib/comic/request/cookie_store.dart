/// 漫画源的 Cookie 持久化。
///
/// 源脚本的登录态、Cloudflare `cf_clearance` 等都在 Cookie 里；原来的
/// `CookieJar()` 只活在进程内，重启就丢，Cloudflare 过挑战也会白过。
/// 这里用 [DefaultCookieJar] 的 RFC 语义 + 一个 JSON 文件落盘：
/// - 域名 Cookie / 主机 Cookie 分表保存（与 cookie_jar 内部结构一致）；
/// - 额外保存每个主机过挑战时用的 WebView UA（`cf_clearance` 与 UA 绑定）；
/// - 写入走临时文件 + rename，避免半截文件把登录态写坏。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 文件里保存的 Cookie + 每主机 UA。
class ComicCookieJar extends DefaultCookieJar {
  ComicCookieJar({this.file, super.ignoreExpires = false});

  /// 落盘文件；null = 纯内存（测试/降级）。
  final File? file;

  /// 默认位置：`<应用支持目录>/comic_cookies.json`（与 comic_sources 同级）。
  static Future<ComicCookieJar> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return ComicCookieJar(
      file: File(p.join(support.path, 'comic_cookies.json')),
    );
  }

  bool _loaded = false;
  Future<void>? _loading;
  final Map<String, String> _userAgents = <String, String>{};
  Timer? _persistTimer;

  /// 幂等加载；坏文件按空库处理，不挡启动。
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final f = file;
      if (f != null && await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) {
          _restore(decoded['domain'], domainCookies);
          _restore(decoded['host'], hostCookies);
          final ua = decoded['ua'];
          if (ua is Map) {
            _userAgents.clear();
            for (final entry in ua.entries) {
              _userAgents[entry.key.toString()] = entry.value.toString();
            }
          }
        }
      }
    } on Object {
      // 坏文件/无权限：空库继续，下次写入会覆盖。
    } finally {
      _loaded = true;
    }
  }

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    await ensureLoaded();
    return super.loadForRequest(uri);
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) async {
    await ensureLoaded();
    await super.saveFromResponse(uri, cookies);
    schedulePersist();
  }

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) async {
    await ensureLoaded();
    await super.delete(uri, withDomainSharedCookie);
    schedulePersist();
  }

  @override
  Future<void> deleteAll() async {
    await ensureLoaded();
    await super.deleteAll();
    _userAgents.clear();
    schedulePersist();
  }

  /// 全部已知 Cookie（含域名表与主机表），用于给同步 API 水合缓存。
  /// 从文件恢复的 host-only Cookie 没有 domain 字段，这里按所在表的 key
  /// 补上 host——否则同步 `getCookies` 的域名匹配会漏掉它。
  List<Cookie> get allCookies => <Cookie>[
    for (final domainEntry in domainCookies.entries)
      for (final paths in domainEntry.value.values)
        for (final saved in paths.values)
          _withDomain(saved.cookie, domainEntry.key),
    for (final hostEntry in hostCookies.entries)
      for (final paths in hostEntry.value.values)
        for (final saved in paths.values)
          _withDomain(saved.cookie, hostEntry.key),
  ];

  Cookie _withDomain(Cookie cookie, String domain) {
    final current = cookie.domain;
    if (current == null || current.isEmpty) cookie.domain = domain;
    return cookie;
  }

  /// 某主机过挑战时记录的 UA；没有返回 null。
  String? userAgentFor(String host) => _userAgents[host.toLowerCase()];

  /// 记录挑战 UA 并立即落盘（Clearance 与 UA 绑定，丢失就失效）。
  Future<void> setUserAgentFor(String host, String userAgent) async {
    _userAgents[host.toLowerCase()] = userAgent;
    await persist();
  }

  /// 延迟落盘：一次页面请求可能连续 Set-Cookie，避免每个都写盘。
  void schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(persist());
    });
  }

  /// 立即落盘（挑战通过等关键节点调用）。
  Future<void> persist() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    final f = file;
    if (f == null) return;
    try {
      final payload = <String, Object?>{
        'version': 1,
        'domain': _snapshot(domainCookies),
        'host': _snapshot(hostCookies),
        'ua': _userAgents,
      };
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
    } on Object {
      // 落盘失败不挡请求；下次变更会重试。
    }
  }

  Map<String, Object?> _snapshot(
    Map<String, Map<String, Map<String, SerializableCookie>>> source,
  ) => source.map(
    (domain, paths) => MapEntry<String, Object?>(
      domain,
      paths.map(
        (path, cookies) => MapEntry<String, Object?>(
          path,
          cookies.map(
            (name, cookie) => MapEntry<String, Object?>(name, cookie.toJson()),
          ),
        ),
      ),
    ),
  );

  void _restore(
    Object? raw,
    Map<String, Map<String, Map<String, SerializableCookie>>> target,
  ) {
    if (raw is! Map) return;
    target.clear();
    for (final domainEntry in raw.entries) {
      final paths = domainEntry.value;
      if (paths is! Map) continue;
      final pathMap = <String, Map<String, SerializableCookie>>{};
      for (final pathEntry in paths.entries) {
        final cookies = pathEntry.value;
        if (cookies is! Map) continue;
        final cookieMap = <String, SerializableCookie>{};
        for (final cookieEntry in cookies.entries) {
          try {
            cookieMap[cookieEntry.key.toString()] = SerializableCookie.fromJson(
              cookieEntry.value.toString(),
            );
          } on Object {
            // 单条坏 Cookie 跳过。
          }
        }
        if (cookieMap.isNotEmpty) pathMap[pathEntry.key.toString()] = cookieMap;
      }
      if (pathMap.isNotEmpty) target[domainEntry.key.toString()] = pathMap;
    }
  }
}
