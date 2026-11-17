/// 规则的本地存储：一条规则一个 JSON 文件。
///
/// 为什么不用 drift：规则是"可导入/可删除的整块文档"，以文件形式保存最贴近
/// 用户心智（能直接备份、复制、用文本编辑器改）；文件名由规则名编码得到，
/// 同名规则覆盖。默认目录在应用支持目录下的 `anime_rules/`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'rule.dart';

/// [RuleStore.loadAllDetailed] 的结果：可用规则 + 坏文件说明。
class RuleLoadResult {
  const RuleLoadResult({required this.rules, this.failures = const <String>[]});

  final List<AnimeRule> rules;
  final List<String> failures;
}

/// 规则文件仓库。
class RuleStore {
  RuleStore(this.directory);

  /// 规则文件所在目录。
  final Directory directory;

  /// 默认存储位置：`<应用支持目录>/anime_rules`。
  static Future<RuleStore> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return RuleStore(
      Directory('${support.path}${Platform.pathSeparator}anime_rules'),
    );
  }

  /// 保证目录存在（写入前调用；读取时目录不存在视为空仓库）。
  Future<void> ensureDirectory() async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  /// 读取全部规则；坏文件被跳过，原因见 [loadAllDetailed]。
  Future<List<AnimeRule>> loadAll() async {
    final result = await loadAllDetailed();
    return result.rules;
  }

  /// 读取全部规则，并返回坏文件的诊断信息。
  Future<RuleLoadResult> loadAllDetailed() async {
    if (!await directory.exists()) {
      return const RuleLoadResult(rules: []);
    }

    final List<FileSystemEntity> entities;
    try {
      entities = await directory.list().toList();
    } on FileSystemException catch (error) {
      return RuleLoadResult(
        rules: const [],
        failures: ['读取规则目录失败：${error.message}'],
      );
    }

    final files =
        entities
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final byName = <String, AnimeRule>{};
    final failures = <String>[];
    for (final file in files) {
      final fileName = file.uri.pathSegments.last;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          failures.add('$fileName：不是 JSON object');
          continue;
        }
        final rule = AnimeRule.fromJson(Map<String, dynamic>.from(decoded));
        if (rule.name.trim().isEmpty) {
          failures.add('$fileName：缺少 name');
          continue;
        }
        byName[rule.name.trim().toLowerCase()] = rule;
      } catch (error) {
        failures.add('$fileName：$error');
      }
    }

    return RuleLoadResult(
      rules: List<AnimeRule>.unmodifiable(byName.values),
      failures: List<String>.unmodifiable(failures),
    );
  }

  /// 保存一条规则（按名字覆盖同名文件）。
  Future<File> save(AnimeRule rule) async {
    await ensureDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_fileName(rule.name)}',
    );
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(rule.toJson())}\n',
      flush: true,
    );
    return file;
  }

  /// 批量保存（导入订阅后一次落盘）。
  Future<List<File>> saveAll(Iterable<AnimeRule> rules) async {
    final saved = <File>[];
    for (final rule in rules) {
      saved.add(await save(rule));
    }
    return saved;
  }

  /// 按规则名删除；返回是否真的删掉了文件。
  Future<bool> delete(String name) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_fileName(name)}',
    );
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// 某个规则名是否已存在。
  Future<bool> exists(String name) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_fileName(name)}',
    );
    return file.exists();
  }

  /// 规则名 → 安全文件名。用 percent-encoding 处理空格/中文/特殊字符，
  /// 额外转义 Windows 不允许的 `*`，并防住 `.`/`..`。
  String _fileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '规则名不能为空');
    }
    var encoded = Uri.encodeComponent(trimmed).replaceAll('*', '%2A');
    if (encoded == '.' || encoded == '..') {
      encoded = encoded.replaceAll('.', '%2E');
    }
    return '$encoded.json';
  }
}
