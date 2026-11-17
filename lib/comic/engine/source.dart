/// 漫画源脚本文档模型 + 导入（规则数据是数据，不自己写源）。
///
/// 一条 Venera 源就是一个 `.js` 文件，头部带 `name` / `key` / `version` /
/// `minAppVersion` / `url` 字段（社区约定，见 `_template_.js`）。这里只解析
/// 这些元数据用于展示与版本管理，脚本文本原样保存——我们不改、不写源。
library;

import 'dart:convert';

/// 一条已导入的漫画源。
class ComicSourceScript {
  const ComicSourceScript({
    required this.key,
    required this.script,
    this.name = '',
    this.version = '',
    this.minAppVersion = '',
    this.url = '',
    this.enabled = true,
  });

  /// 唯一标识（脚本里的 `key` 字段）。
  final String key;

  /// 源脚本文本，原样保存。
  final String script;

  final String name;
  final String version;
  final String minAppVersion;

  /// 更新地址（源仓库 raw URL）。
  final String url;

  /// 是否参与多源搜索（源管理页的开关；随 manifest 持久化）。
  final bool enabled;

  bool get isValid => key.trim().isNotEmpty && script.trim().isNotEmpty;

  /// URL 导入后把导入地址写进元数据、源管理切换启用状态时使用。
  ComicSourceScript copyWith({String? url, bool? enabled}) => ComicSourceScript(
    key: key,
    script: script,
    name: name,
    version: version,
    minAppVersion: minAppVersion,
    url: url ?? this.url,
    enabled: enabled ?? this.enabled,
  );

  /// 版本号比较（简单 segment 数值比较，非语义化版本也兼容）。
  static int compareVersion(String a, String b) {
    final left = _versionSegments(a);
    final right = _versionSegments(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  static List<int> _versionSegments(String version) => version
      .trim()
      .split(RegExp(r'[.\-_+]'))
      .map((part) => int.tryParse(part) ?? 0)
      .toList();

  @override
  String toString() => 'ComicSourceScript($key, v$version, $name)';
}

/// 一次导入的结果。
class ComicSourceImportResult {
  const ComicSourceImportResult({
    this.sources = const <ComicSourceScript>[],
    this.failures = const <String>[],
    this.duplicateCount = 0,
  });

  final List<ComicSourceScript> sources;
  final List<String> failures;

  /// 同名源被后一条覆盖的次数。
  final int duplicateCount;

  bool get isEmpty => sources.isEmpty;
  bool get isNotEmpty => sources.isNotEmpty;

  @override
  String toString() =>
      'ComicSourceImportResult(sources: ${sources.length}, '
      'failures: ${failures.length})';
}

/// 从脚本文本解析源元数据。
///
/// Venera 源字段写法不固定（`key = "x"` / `key: "x"` / 单引号），用宽松正则
/// 逐字段匹配。解析不出 key 时用调用方给的 [fallbackKey]（通常是文件名）。
ComicSourceScript parseSourceScript(String script, {String fallbackKey = ''}) {
  final text = script.replaceFirst('\uFEFF', '');
  String field(String name, {String fallback = ''}) {
    final pattern = RegExp(
      '(?:this\\.)?\\b$name\\s*[:=]\\s*["\'`]([^"\'`]+)["\'`]',
      multiLine: true,
    );
    return pattern.firstMatch(text)?.group(1)?.trim() ?? fallback;
  }

  final key = field('key', fallback: fallbackKey);
  return ComicSourceScript(
    key: key.trim(),
    script: script,
    name: field('name'),
    version: field('version'),
    minAppVersion: field('minAppVersion'),
    url: field('url'),
  );
}

/// 源导入器：脚本文本 → [ComicSourceScript]。
///
/// 输入可以是单条脚本，也可以是"多源打包"文本（多个 `class extends
/// ComicSource`，用分隔符 JSON 数组 / 带标记的拼接）。批量导入逐条容错：
/// 合法源照常返回，坏条目进 [ComicSourceImportResult.failures]。
class ComicSourceImporter {
  /// 解析单条脚本文本。
  ComicSourceImportResult parseSingle(
    String script, {
    String fallbackKey = '',
  }) {
    if (script.trim().isEmpty) {
      return const ComicSourceImportResult(failures: ['导入内容为空']);
    }
    if (!RegExp(r'\bclass\s+\w+\s+extends\s+ComicSource\b').hasMatch(script)) {
      return ComicSourceImportResult(
        failures: ['不是 Venera 源脚本：找不到 extends ComicSource 的类'],
      );
    }
    final source = parseSourceScript(script, fallbackKey: fallbackKey);
    if (source.key.trim().isEmpty) {
      return ComicSourceImportResult(failures: ['源缺少 key 字段']);
    }
    return ComicSourceImportResult(sources: <ComicSourceScript>[source]);
  }

  /// 解析一个 JSON 数组：元素是 `{key, name, script}` 或纯脚本文本。
  /// 也兼容直接是脚本文本（退化为 [parseSingle]）。
  ComicSourceImportResult parseJson(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const ComicSourceImportResult(failures: ['导入内容为空']);
    }
    final decoded = _tryDecode(text);
    if (decoded == null) return parseSingle(text);

    final entries = decoded is List ? decoded : <dynamic>[decoded];
    final byKey = <String, ComicSourceScript>{};
    final failures = <String>[];
    var duplicateCount = 0;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is String) {
        final result = parseSingle(entry, fallbackKey: 'source_${i + 1}');
        for (final source in result.sources) {
          if (byKey.containsKey(source.key)) duplicateCount++;
          byKey[source.key] = source;
        }
        failures.addAll(result.failures);
        continue;
      }
      if (entry is! Map) {
        failures.add('第 ${i + 1} 条不是脚本对象');
        continue;
      }
      final script = entry['script']?.toString() ?? '';
      final fallback = entry['key']?.toString() ?? 'source_${i + 1}';
      final result = parseSingle(script, fallbackKey: fallback);
      if (result.sources.isEmpty) {
        failures.add('第 ${i + 1} 条：${result.failures.join('; ')}');
        continue;
      }
      var source = result.sources.single;
      // 外层对象可覆盖元数据（订阅源常见写法）。
      source = ComicSourceScript(
        key: entry['key']?.toString() ?? source.key,
        script: source.script,
        name: entry['name']?.toString() ?? source.name,
        version: entry['version']?.toString() ?? source.version,
        minAppVersion:
            entry['minAppVersion']?.toString() ?? source.minAppVersion,
        url: entry['url']?.toString() ?? source.url,
      );
      if (byKey.containsKey(source.key)) duplicateCount++;
      byKey[source.key] = source;
    }

    return ComicSourceImportResult(
      sources: List<ComicSourceScript>.unmodifiable(byKey.values),
      failures: List<String>.unmodifiable(failures),
      duplicateCount: duplicateCount,
    );
  }

  Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
