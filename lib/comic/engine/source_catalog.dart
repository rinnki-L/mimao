/// 漫画源仓库目录：读取 Venera 风格的 `index.json`，供 UI 浏览并按需导入。
///
/// Venera 官方源仓库是 [venera-app/venera-configs](https://github.com/venera-app/venera-configs)，
/// 根目录 `index.json` 是一个 JSON 数组，每条 `{name, fileName, key, version,
/// description?}`；`.js` 脚本是清单的同级文件（[fileName] 可含子目录）。
/// 本文件只做「发现 + 拼 URL + 校验」，`index.json` 是不可信输入：base URL 与
/// 脚本路径都做白名单/防穿越校验；真正的下载/解析/注册/落盘仍走
/// `EngineComicDataSource.importSource(url)`，不在这里重复实现。
///
/// 边界：只依赖本模块的 [ComicHttpClient]；不认识 UI、store 或执行池。
library;

import 'dart:convert';

import '../request/web_client.dart';

/// Venera 官方源清单的 jsdelivr 镜像（官方 App 内置默认值）。
///
/// 本机直连 github.com 会被 RST，故默认走 CDN；可改成任意同格式仓库地址。
const String defaultComicSourceIndexUrl =
    'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json';

/// 清单里一条源的描述（Venera `index.json` 的条目）。
class ComicSourceIndexEntry {
  const ComicSourceIndexEntry({
    required this.name,
    required this.fileName,
    required this.key,
    this.version = '',
    this.description = '',
    this.url = '',
  });

  factory ComicSourceIndexEntry.fromJson(Map<String, dynamic> json) {
    return ComicSourceIndexEntry(
      name: _string(json['name']),
      // 官方文档把字段写成 `filename`（小写 n），真实清单与代码都是 `fileName`。
      // 两者都认，兼容文档的笔误写法。
      fileName: _string(json['fileName']).isEmpty
          ? _string(json['filename'])
          : _string(json['fileName']),
      key: _string(json['key']),
      version: _string(json['version']),
      description: _string(json['description']),
      url: _string(json['url']),
    );
  }

  final String name;
  final String fileName;
  final String key;
  final String version;
  final String description;

  /// 清单可选的完整脚本 URL；Venera 约定「与 fileName 二选一」。
  final String url;

  /// 展示标题：清单缺 name 时回退 key（key 在本文件里必填校验）。
  String get displayName => name.isEmpty ? key : name;

  /// 展示用副标题：版本 + 可选描述。
  String get subtitle {
    final parts = <String>[
      if (version.isNotEmpty) 'v$version',
      if (description.isNotEmpty) description,
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

/// 一次清单读取的结果。
class ComicSourceIndexResult {
  const ComicSourceIndexResult({
    this.entries = const <ComicSourceIndexEntry>[],
    this.failures = const <String>[],
  });

  final List<ComicSourceIndexEntry> entries;
  final List<String> failures;

  bool get isEmpty => entries.isEmpty;

  @override
  String toString() =>
      'ComicSourceIndexResult(entries: ${entries.length}, '
      'failures: ${failures.length})';
}

/// 规范化清单地址：只接受不含凭据、query、fragment 的 http(s) 绝对地址。
Uri? normalizeIndexUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

/// 校验 `fileName` 是相对仓库根的安全路径（可含子目录，但不许绝对路径、
/// 盘符/协议、路径穿越、`?`/`#`/反斜杠，解码后也不许引入穿越）。
bool isSafeSourcePath(String fileName) {
  final value = fileName.trim();
  if (value.isEmpty) return false;
  // `%` 一律拒绝：清单里的文件名不该带百分号（真要传会被 resolve 再编码成
  // %25），且「先编码后校验」的穿越（如 %2E%2E）在这里挡死。另外注意
  // Uri.decodeComponent 对未编码的非 ASCII 输入会直接抛异常，不能用它兜底。
  if (value.contains('\\') ||
      value.startsWith('/') ||
      value.contains('://') ||
      value.contains('?') ||
      value.contains('#') ||
      value.contains('%')) {
    return false;
  }
  for (final segment in value.split('/')) {
    if (segment.isEmpty || segment == '.' || segment == '..') return false;
    // 带 scheme 的相对引用（`foo:bar.js`、单斜杠 `https:/evil.com/x.js`）
    // 不含 `://`，靠这里挡：resolve 会把它当 URI scheme 解析，origin 校验
    // 反而会先抛出难懂的 StateError。文件名里本来也不该有冒号。
    if (segment.contains(':')) return false;
  }
  return true;
}

String _string(dynamic value) => value == null ? '' : value.toString().trim();

/// 源仓库目录读取器：抓取并解析 `index.json`，构造每件源的可导入 URL。
class ComicSourceCatalog {
  ComicSourceCatalog({ComicHttpClient? client})
    : _client = client ?? ComicWebClient();

  final ComicHttpClient _client;

  /// 读取清单。非法地址、非 2xx、坏 JSON、坏条目都收敛进 [failures] 不抛异常，
  /// 与 `EngineComicDataSource` 的导入契约一致。
  Future<ComicSourceIndexResult> fetchIndex(
    String indexUrl, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    final uri = normalizeIndexUrl(indexUrl);
    if (uri == null) {
      return const ComicSourceIndexResult(
        failures: <String>['仓库地址不合法：只支持不含凭据的 http(s) 地址'],
      );
    }

    late final ComicHttpResponse response;
    try {
      response = await _client.fetch(indexUrl.trim(), options: options);
    } on Object catch (error) {
      return ComicSourceIndexResult(failures: <String>['读取源清单失败：$error']);
    }
    if (!response.isSuccessful) {
      return ComicSourceIndexResult(
        failures: <String>[
          '读取源清单失败：HTTP ${response.statusCode}（${indexUrl.trim()}）',
        ],
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      return ComicSourceIndexResult(
        failures: <String>['源清单不是合法 JSON：${error.message}'],
      );
    }
    if (decoded is! List) {
      return const ComicSourceIndexResult(
        failures: <String>['源清单格式错误：应为 JSON 数组'],
      );
    }

    final entries = <ComicSourceIndexEntry>[];
    final failures = <String>[];
    for (var i = 0; i < decoded.length; i++) {
      final raw = decoded[i];
      if (raw is! Map) {
        failures.add('清单第 ${i + 1} 条不是 JSON object');
        continue;
      }
      final entry = ComicSourceIndexEntry.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (entry.fileName.isEmpty && entry.url.isEmpty) {
        failures.add('清单第 ${i + 1} 条缺少 fileName/url');
        continue;
      }
      // key 是 UI 的勾选标识与「已导入」比对键：只许安全 token（Venera 约定
      // `^[a-zA-Z0-9_]+$`，放宽连字符），重复 key 保留首条避免 widget key 冲突。
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(entry.key)) {
        failures.add('清单第 ${i + 1} 条 key 不合法：${entry.key}');
        continue;
      }
      if (entries.any((e) => e.key == entry.key)) {
        failures.add('清单第 ${i + 1} 条 key 重复：${entry.key}');
        continue;
      }
      if (entry.fileName.isNotEmpty && !isSafeSourcePath(entry.fileName)) {
        failures.add('清单第 ${i + 1} 条 fileName 不合法：${entry.fileName}');
        continue;
      }
      entries.add(entry);
    }

    return ComicSourceIndexResult(
      entries: List<ComicSourceIndexEntry>.unmodifiable(entries),
      failures: List<String>.unmodifiable(failures),
    );
  }

  /// 由清单条目构造可直接交给 `importSource(url)` 的 `.js` 地址。
  ///
  /// 优先用条目自带的绝对 [ComicSourceIndexEntry.url]（须通过 http(s) 白名单），
  /// 否则把 `fileName` 相对 `index.json` 所在目录拼接。拼接后再校验结果仍在
  /// 同一 origin 且位于仓库目录内，防止清单里的相对路径逃逸到别处。
  String sourceUrl(String indexUrl, ComicSourceIndexEntry entry) {
    final index = normalizeIndexUrl(indexUrl);
    if (index == null) {
      throw ArgumentError.value(indexUrl, 'indexUrl', '仓库地址不合法');
    }
    if (entry.url.isNotEmpty) {
      final explicit = normalizeIndexUrl(entry.url);
      if (explicit == null) {
        throw ArgumentError.value(entry.url, 'entry.url', '脚本地址不合法');
      }
      return explicit.toString();
    }
    if (!isSafeSourcePath(entry.fileName)) {
      throw ArgumentError.value(entry.fileName, 'entry.fileName', '脚本路径不合法');
    }

    final path = index.path;
    final slash = path.lastIndexOf('/');
    final basePath = slash >= 0 ? path.substring(0, slash + 1) : '/';
    final base = index.replace(path: basePath);
    final resolved = base.resolve(entry.fileName);
    if (resolved.origin != base.origin ||
        !resolved.path.startsWith(base.path)) {
      throw ArgumentError.value(entry.fileName, 'entry.fileName', '脚本路径逃出仓库目录');
    }
    return resolved.toString();
  }
}
