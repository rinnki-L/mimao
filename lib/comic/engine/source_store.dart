/// 漫画源脚本的本地存储：一条源一个 `.js` 文件。
///
/// 为什么不用 drift：源是"可导入/可删除的整块脚本文档"，文件形式最贴近用户
/// 心智（能直接备份、复制、用编辑器改），且与上游 Venera 的源目录一致。
/// 文件名由源 key 编码得到，同名覆盖；默认目录 `<支持目录>/comic_sources/`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'source.dart';

/// 存储里一条源的元信息清单项（脚本正文单独存文件）。
class ComicSourceManifestEntry {
  const ComicSourceManifestEntry({
    required this.key,
    required this.name,
    required this.version,
    required this.minAppVersion,
    required this.url,
    this.enabled = true,
  });

  final String key;
  final String name;
  final String version;
  final String minAppVersion;
  final String url;

  /// 是否参与多源搜索；旧 manifest 无该字段时读为 true（向后兼容）。
  final bool enabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'name': name,
    'version': version,
    'minAppVersion': minAppVersion,
    'url': url,
    'enabled': enabled,
  };

  factory ComicSourceManifestEntry.fromJson(Map<String, dynamic> json) =>
      ComicSourceManifestEntry(
        key: json['key']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        version: json['version']?.toString() ?? '',
        minAppVersion: json['minAppVersion']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      );
}

/// 加载结果：可用源 + 坏文件说明。
class ComicSourceLoadResult {
  const ComicSourceLoadResult({
    this.sources = const <ComicSourceScript>[],
    this.failures = const <String>[],
  });

  final List<ComicSourceScript> sources;
  final List<String> failures;

  bool get isEmpty => sources.isEmpty;
}

/// 源仓库。
class ComicSourceStore {
  ComicSourceStore(this.directory);

  /// 与脚本同目录的元信息清单文件名。
  static const String manifestFileName = 'manifest.json';

  final Directory directory;

  /// 默认位置：`<应用支持目录>/comic_sources`。
  static Future<ComicSourceStore> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return ComicSourceStore(Directory(p.join(support.path, 'comic_sources')));
  }

  Future<void> ensureDirectory() async {
    if (!await directory.exists()) await directory.create(recursive: true);
  }

  File _scriptFile(String key) =>
      File(p.join(directory.path, '${_fileName(key)}.js'));

  File get _manifestFile => File(p.join(directory.path, manifestFileName));

  /// 读取全部源（脚本正文 + 清单元数据）。
  Future<ComicSourceLoadResult> loadAllDetailed() async {
    if (!await directory.exists()) {
      return const ComicSourceLoadResult();
    }
    final manifest = await _readManifest();
    final entries = manifest.where((e) => e.key.isNotEmpty).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final sources = <ComicSourceScript>[];
    final failures = <String>[];
    for (final entry in entries) {
      final file = _scriptFile(entry.key);
      if (!await file.exists()) {
        failures.add('${entry.key}：清单存在但脚本缺失');
        continue;
      }
      final script = await file.readAsString();
      sources.add(
        ComicSourceScript(
          key: entry.key,
          script: script,
          name: entry.name,
          version: entry.version,
          minAppVersion: entry.minAppVersion,
          url: entry.url,
          enabled: entry.enabled,
        ),
      );
    }

    // 兼容：目录里有 .js 但清单没记录（手工放入）——按脚本自身元数据补录。
    final indexed = sources.map((s) => s.key).toSet();
    final orphanScripts =
        directory
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path) == '.js')
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in orphanScripts) {
      final key = p.basenameWithoutExtension(file.path);
      if (indexed.contains(key)) continue;
      final script = await file.readAsString();
      final source = parseSourceScript(script, fallbackKey: key);
      sources.add(source);
      indexed.add(key);
    }

    return ComicSourceLoadResult(
      sources: List<ComicSourceScript>.unmodifiable(sources),
      failures: List<String>.unmodifiable(failures),
    );
  }

  Future<List<ComicSourceScript>> loadAll() async =>
      (await loadAllDetailed()).sources;

  /// 保存一条源（按 key 覆盖同名文件，并更新清单）。
  Future<void> save(ComicSourceScript source) async {
    if (!source.isValid) {
      throw ArgumentError.value(source.key, 'source', '源 key/正文不能为空');
    }
    await ensureDirectory();
    await _scriptFile(source.key).writeAsString(source.script, flush: true);
    final manifest = await _readManifest();
    final entry = ComicSourceManifestEntry(
      key: source.key,
      name: source.name,
      version: source.version,
      minAppVersion: source.minAppVersion,
      url: source.url,
      enabled: source.enabled,
    );
    final updated = manifest.where((e) => e.key != source.key).toList()
      ..add(entry)
      ..sort((a, b) => a.key.compareTo(b.key));
    await _writeManifest(updated);
  }

  /// 批量保存。
  Future<void> saveAll(Iterable<ComicSourceScript> sources) async {
    for (final source in sources) {
      await save(source);
    }
  }

  /// 按 key 删除；返回是否真的删掉了。
  Future<bool> delete(String key) async {
    final file = _scriptFile(key);
    var removed = false;
    if (await file.exists()) {
      await file.delete();
      removed = true;
    }
    final manifest = await _readManifest();
    final updated = manifest.where((e) => e.key != key).toList();
    if (updated.length != manifest.length) {
      await _writeManifest(updated);
      removed = true;
    }
    return removed;
  }

  Future<bool> exists(String key) => _scriptFile(key).exists();

  /// 版本体检：清单里的版本是否落后于传入版本。
  bool isOlder(ComicSourceScript current, String newVersion) =>
      ComicSourceScript.compareVersion(current.version, newVersion) < 0;

  Future<List<ComicSourceManifestEntry>> _readManifest() async {
    try {
      if (!await _manifestFile.exists()) return <ComicSourceManifestEntry>[];
      final decoded = jsonDecode(await _manifestFile.readAsString());
      if (decoded is! List) return <ComicSourceManifestEntry>[];
      return decoded
          .whereType<Map>()
          .map(
            (e) =>
                ComicSourceManifestEntry.fromJson(Map<String, dynamic>.from(e)),
          )
          .where((e) => e.key.isNotEmpty)
          .toList();
    } catch (_) {
      return <ComicSourceManifestEntry>[];
    }
  }

  Future<void> _writeManifest(List<ComicSourceManifestEntry> entries) async {
    const encoder = JsonEncoder.withIndent('  ');
    await _manifestFile.writeAsString(
      '${encoder.convert(entries.map((e) => e.toJson()).toList())}\n',
      flush: true,
    );
  }

  String _fileName(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(key, 'key', '源 key 不能为空');
    }
    var encoded = Uri.encodeComponent(trimmed).replaceAll('*', '%2A');
    if (encoded == '.' || encoded == '..') {
      encoded = encoded.replaceAll('.', '%2E');
    }
    return encoded;
  }
}
