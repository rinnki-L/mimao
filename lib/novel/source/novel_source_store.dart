/// 小说书源仓库：一条源一个 `.json` 文件，放在应用支持目录 `novel_sources/`。
///
/// 与漫画源仓库同款思路：源是"可导入/可删除的整块文档"，文件形式便于备份和
/// 检查；完整书源 JSON 直接落盘，后续书源引擎切片读同一份即可，不需要再迁移。
/// 生产构造走 [NovelSourceStore.openDefault]（惰性，不碰 path_provider；构造期零 IO）；
/// 测试注入临时目录。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'novel_source_model.dart';

/// 书源存储的窄接口：页面/导入服务只依赖它，直接仓库与惰性门面都实现它。
abstract interface class NovelSourceStorage {
  Future<List<NovelBookSource>> loadAll();

  Future<int> saveAll(Iterable<NovelBookSource> sources);

  Future<void> setEnabled(String key, bool enabled);

  Future<bool> delete(String key);
}

class NovelSourceStore implements NovelSourceStorage {
  NovelSourceStore(this.directory);

  static const String manifestFileName = 'manifest.json';

  final Directory directory;

  /// 默认位置：`<应用支持目录>/novel_sources`。
  static Future<NovelSourceStore> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return NovelSourceStore(Directory(p.join(support.path, 'novel_sources')));
  }

  Future<void> ensureDirectory() async {
    if (!await directory.exists()) await directory.create(recursive: true);
  }

  File _sourceFile(String key) => File(p.join(directory.path, '$key.json'));

  File get _manifestFile => File(p.join(directory.path, manifestFileName));

  /// 读取全部书源：清单缺失/损坏时降级为扫描目录里的 `.json` 文件。
  @override
  Future<List<NovelBookSource>> loadAll() async {
    if (!await directory.exists()) return const <NovelBookSource>[];

    final manifest = await _readManifest();
    final sources = <NovelBookSource>[];
    for (final entry in manifest) {
      final file = _sourceFile(entry.key);
      if (!await file.exists()) continue;
      try {
        sources.add(
          NovelBookSource.fromJson(
            Map<String, Object?>.from(
              jsonDecode(await file.readAsString()) as Map,
            ),
          ),
        );
      } catch (_) {
        // 单条坏文件不影响其余源。
      }
    }

    // 清单没记录、但目录里有源文件（手工放入/清单写坏）——按正文补录。
    final indexed = sources.map((s) => s.key).toSet();
    final orphanFiles =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  p.extension(f.path) == '.json' &&
                  p.basenameWithoutExtension(f.path) != 'manifest',
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in orphanFiles) {
      final key = p.basenameWithoutExtension(file.path);
      if (indexed.contains(key)) continue;
      try {
        final source = NovelBookSource.fromJson(
          Map<String, Object?>.from(
            jsonDecode(await file.readAsString()) as Map,
          ),
        );
        sources.add(
          key == source.key
              ? source
              : NovelBookSource(
                  key: key,
                  name: source.name,
                  url: source.url,
                  type: source.type,
                  enabled: source.enabled,
                  raw: source.raw,
                ),
        );
        indexed.add(key);
      } catch (_) {
        // 单条坏文件不影响其余源。
      }
    }

    sources.sort((a, b) => a.name.compareTo(b.name));
    return List<NovelBookSource>.unmodifiable(sources);
  }

  /// 批量保存（导入用）：按 key 去重，同名覆盖；一次写盘更新清单。
  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async {
    final unique = <String, NovelBookSource>{};
    for (final source in sources) {
      if (source.key.isEmpty) continue;
      unique[source.key] = source;
    }
    if (unique.isEmpty) return 0;

    await ensureDirectory();
    const encoder = JsonEncoder.withIndent('  ');
    for (final source in unique.values) {
      await _sourceFile(
        source.key,
      ).writeAsString('${encoder.convert(source.toJson())}\n', flush: true);
    }
    final manifest = await _readManifest();
    final merged = <String, Map<String, Object?>>{
      for (final entry in manifest) entry.key: entry.toJson(),
    };
    for (final source in unique.values) {
      merged[source.key] = <String, Object?>{
        'key': source.key,
        'name': source.name,
        'url': source.url,
      };
    }
    await _manifestFile.writeAsString(
      '${encoder.convert(merged.values.toList())}\n',
      flush: true,
    );
    return unique.length;
  }

  /// 启停一条源。
  @override
  Future<void> setEnabled(String key, bool enabled) async {
    final sources = await loadAll();
    final target = sources.where((s) => s.key == key).toList();
    if (target.isEmpty) return;
    await saveAll(target.map((s) => s.copyWith(enabled: enabled)));
  }

  /// 删除一条源（文件 + 清单）；返回是否真的删掉。
  @override
  Future<bool> delete(String key) async {
    var removed = false;
    final file = _sourceFile(key);
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

  Future<List<_ManifestEntry>> _readManifest() async {
    try {
      if (!await _manifestFile.exists()) return const <_ManifestEntry>[];
      final decoded = jsonDecode(await _manifestFile.readAsString());
      if (decoded is! List) return const <_ManifestEntry>[];
      return decoded
          .whereType<Map>()
          .map(
            (e) => _ManifestEntry(
              key: '${e['key'] ?? ''}',
              name: '${e['name'] ?? ''}',
              url: '${e['url'] ?? ''}',
            ),
          )
          .where((e) => e.key.isNotEmpty)
          .toList();
    } catch (_) {
      return const <_ManifestEntry>[];
    }
  }

  Future<void> _writeManifest(List<_ManifestEntry> entries) async {
    const encoder = JsonEncoder.withIndent('  ');
    await _manifestFile.writeAsString(
      '${encoder.convert(entries.map((e) => e.toJson()).toList())}\n',
      flush: true,
    );
  }
}

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
