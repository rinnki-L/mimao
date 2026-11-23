/// 订阅源 / 替换规则的本地仓库：与书源仓库同款「一条规则一个 `.json`」。
///
/// - 书源：`<应用支持目录>/novel_sources/`
/// - 订阅源：`<应用支持目录>/novel_rss_sources/`
/// - 替换规则：`<应用支持目录>/novel_replace_rules/`
///
/// 三个仓库各自独立落盘，导入时按类型分流，互不覆盖。生产构造用 `.lazy()`：
/// 装配期零 IO，第一次真实读写才解析 path_provider；测试注入临时目录。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'novel_rule_model.dart';

/// 订阅源仓库的窄接口。
abstract interface class NovelRssSourceStorage {
  Future<List<NovelRssSource>> loadAll();

  Future<int> saveAll(Iterable<NovelRssSource> sources);

  Future<void> setEnabled(String key, bool enabled);

  Future<bool> delete(String key);
}

/// 替换规则仓库的窄接口。
abstract interface class NovelReplaceRuleStorage {
  Future<List<NovelReplaceRule>> loadAll();

  Future<int> saveAll(Iterable<NovelReplaceRule> rules);

  Future<void> setEnabled(String key, bool enabled);

  Future<bool> delete(String key);
}

class NovelRssSourceStore implements NovelRssSourceStorage {
  NovelRssSourceStore(Directory directory)
    : _store = _RuleDirectoryStore<NovelRssSource>(
        directory,
        keyOf: (source) => source.key,
        nameOf: (source) => source.name,
        subtitleOf: (source) => source.url,
        toJson: (source) => source.toJson(),
        fromJson: NovelRssSource.fromJson,
        withEnabled: (source, enabled) => source.copyWith(enabled: enabled),
      );

  NovelRssSourceStore.lazy()
    : _store = _RuleDirectoryStore<NovelRssSource>.lazy(
        'novel_rss_sources',
        keyOf: (source) => source.key,
        nameOf: (source) => source.name,
        subtitleOf: (source) => source.url,
        toJson: (source) => source.toJson(),
        fromJson: NovelRssSource.fromJson,
        withEnabled: (source, enabled) => source.copyWith(enabled: enabled),
      );

  final _RuleDirectoryStore<NovelRssSource> _store;

  @override
  Future<List<NovelRssSource>> loadAll() => _store.loadAll();

  @override
  Future<int> saveAll(Iterable<NovelRssSource> sources) =>
      _store.saveAll(sources);

  @override
  Future<void> setEnabled(String key, bool enabled) =>
      _store.setEnabled(key, enabled);

  @override
  Future<bool> delete(String key) => _store.delete(key);
}

class NovelReplaceRuleStore implements NovelReplaceRuleStorage {
  NovelReplaceRuleStore(Directory directory)
    : _store = _RuleDirectoryStore<NovelReplaceRule>(
        directory,
        keyOf: (rule) => rule.key,
        nameOf: (rule) => rule.name,
        subtitleOf: (rule) => rule.pattern,
        toJson: (rule) => rule.toJson(),
        fromJson: NovelReplaceRule.fromJson,
        withEnabled: (rule, enabled) => rule.copyWith(enabled: enabled),
      );

  NovelReplaceRuleStore.lazy()
    : _store = _RuleDirectoryStore<NovelReplaceRule>.lazy(
        'novel_replace_rules',
        keyOf: (rule) => rule.key,
        nameOf: (rule) => rule.name,
        subtitleOf: (rule) => rule.pattern,
        toJson: (rule) => rule.toJson(),
        fromJson: NovelReplaceRule.fromJson,
        withEnabled: (rule, enabled) => rule.copyWith(enabled: enabled),
      );

  final _RuleDirectoryStore<NovelReplaceRule> _store;

  @override
  Future<List<NovelReplaceRule>> loadAll() => _store.loadAll();

  @override
  Future<int> saveAll(Iterable<NovelReplaceRule> rules) =>
      _store.saveAll(rules);

  @override
  Future<void> setEnabled(String key, bool enabled) =>
      _store.setEnabled(key, enabled);

  @override
  Future<bool> delete(String key) => _store.delete(key);
}

/// 一条规则一个文件的通用仓库（清单 + 目录扫描补录，与 `NovelSourceStore` 同款容错）。
class _RuleDirectoryStore<T> {
  _RuleDirectoryStore(
    Directory directory, {
    required this.keyOf,
    required this.nameOf,
    required this.subtitleOf,
    required this.toJson,
    required this.fromJson,
    required this.withEnabled,
  }) : _directory = directory,
       _loader = null;

  _RuleDirectoryStore.lazy(
    String folderName, {
    required this.keyOf,
    required this.nameOf,
    required this.subtitleOf,
    required this.toJson,
    required this.fromJson,
    required this.withEnabled,
  }) : _directory = null,
       _loader = _supportDirectoryLoader(folderName);

  static const String manifestFileName = 'manifest.json';

  final Directory? _directory;
  final Future<Directory> Function()? _loader;
  Directory? _resolved;

  final String Function(T item) keyOf;
  final String Function(T item) nameOf;
  final String Function(T item) subtitleOf;
  final Map<String, Object?> Function(T item) toJson;
  final T Function(Map<String, Object?> json) fromJson;
  final T Function(T item, bool enabled) withEnabled;

  Future<Directory> _dir() async {
    final current = _resolved ?? _directory;
    if (current != null) return current;
    final loader = _loader;
    if (loader == null) throw StateError('规则仓库没有目录来源');
    final resolved = await loader();
    _resolved = resolved;
    return resolved;
  }

  File _fileFor(Directory dir, String key) =>
      File(p.join(dir.path, '$key.json'));

  Future<List<T>> loadAll() async {
    final dir = await _dir();
    if (!await dir.exists()) return <T>[];

    final manifest = await _readManifest(dir);
    final items = <T>[];
    final indexed = <String>{};
    for (final entry in manifest) {
      final file = _fileFor(dir, entry.key);
      if (!await file.exists()) continue;
      try {
        items.add(fromJson(_decode(await file.readAsString())));
        indexed.add(entry.key);
      } on Object {
        // 单条坏文件不影响其余规则。
      }
    }

    // 清单没记录、但目录里有文件（手工放入/清单写坏）——按正文补录。
    final orphans =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  p.extension(file.path) == '.json' &&
                  p.basenameWithoutExtension(file.path) != 'manifest',
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in orphans) {
      final key = p.basenameWithoutExtension(file.path);
      if (indexed.contains(key)) continue;
      try {
        items.add(fromJson(_decode(await file.readAsString())));
        indexed.add(key);
      } on Object {
        // 单条坏文件不影响其余规则。
      }
    }

    items.sort((a, b) => nameOf(a).compareTo(nameOf(b)));
    return List<T>.unmodifiable(items);
  }

  Future<int> saveAll(Iterable<T> input) async {
    final unique = <String, T>{};
    for (final item in input) {
      final key = keyOf(item);
      if (key.isEmpty) continue;
      unique[key] = item;
    }
    if (unique.isEmpty) return 0;

    final dir = await _dir();
    if (!await dir.exists()) await dir.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    for (final entry in unique.entries) {
      await _fileFor(
        dir,
        entry.key,
      ).writeAsString('${encoder.convert(toJson(entry.value))}\n', flush: true);
    }

    final merged = <String, Map<String, Object?>>{
      for (final entry in await _readManifest(dir)) entry.key: entry.toJson(),
    };
    for (final entry in unique.entries) {
      merged[entry.key] = <String, Object?>{
        'key': entry.key,
        'name': nameOf(entry.value),
        'url': subtitleOf(entry.value),
      };
    }
    await File(p.join(dir.path, manifestFileName)).writeAsString(
      '${encoder.convert(merged.values.toList())}\n',
      flush: true,
    );
    return unique.length;
  }

  Future<void> setEnabled(String key, bool enabled) async {
    final items = await loadAll();
    final target = items.where((item) => keyOf(item) == key).toList();
    if (target.isEmpty) return;
    await saveAll(target.map((item) => withEnabled(item, enabled)));
  }

  Future<bool> delete(String key) async {
    final dir = await _dir();
    var removed = false;
    final file = _fileFor(dir, key);
    if (await file.exists()) {
      await file.delete();
      removed = true;
    }
    final manifest = await _readManifest(dir);
    final updated = manifest.where((entry) => entry.key != key).toList();
    if (updated.length != manifest.length) {
      await _writeManifest(dir, updated);
      removed = true;
    }
    return removed;
  }

  Future<List<_ManifestEntry>> _readManifest(Directory dir) async {
    try {
      final file = File(p.join(dir.path, manifestFileName));
      if (!await file.exists()) return const <_ManifestEntry>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const <_ManifestEntry>[];
      return decoded
          .whereType<Map>()
          .map(
            (entry) => _ManifestEntry(
              key: '${entry['key'] ?? ''}',
              name: '${entry['name'] ?? ''}',
              url: '${entry['url'] ?? ''}',
            ),
          )
          .where((entry) => entry.key.isNotEmpty)
          .toList();
    } on Object {
      return const <_ManifestEntry>[];
    }
  }

  Future<void> _writeManifest(
    Directory dir,
    List<_ManifestEntry> entries,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    await File(p.join(dir.path, manifestFileName)).writeAsString(
      '${encoder.convert(entries.map((entry) => entry.toJson()).toList())}\n',
      flush: true,
    );
  }

  Map<String, Object?> _decode(String text) =>
      Map<String, Object?>.from(jsonDecode(text) as Map);
}

Future<Directory> Function() _supportDirectoryLoader(String folderName) =>
    () async {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, folderName));
    };

class _ManifestEntry {
  const _ManifestEntry({
    required this.key,
    required this.name,
    required this.url,
  });

  final String key;
  final String name;
  final String url;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'name': name,
    'url': url,
  };
}
