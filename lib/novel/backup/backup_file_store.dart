/// 本地备份文件的落脚点：撤销 journal、恢复前快照、远端 `.bak` 的本地副本。
///
/// 走接口是为了单测：测试注入内存实现，绝不碰 `path_provider`（`LESSON.md`：
/// testWidgets 里碰真实 IO 会让 pumpAndSettle 永久挂住）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class NovelBackupFileStore {
  /// 读文件；不存在返回 null。
  Future<String?> read(String name);

  Future<void> write(String name, String content);

  /// 现有文件名（不含目录）。
  Future<List<String>> list();

  Future<void> delete(String name);
}

/// 内存实现（测试用）。
class NovelMemoryBackupFileStore implements NovelBackupFileStore {
  NovelMemoryBackupFileStore([Map<String, String>? seed])
    : _files = <String, String>{...?seed};

  final Map<String, String> _files;

  @override
  Future<String?> read(String name) async => _files[name];

  @override
  Future<void> write(String name, String content) async {
    _files[name] = content;
  }

  @override
  Future<List<String>> list() async => _files.keys.toList(growable: false);

  @override
  Future<void> delete(String name) async {
    _files.remove(name);
  }
}

/// 应用支持目录下的 `novel_backup/`。
///
/// 注意：`getApplicationSupportDirectory()` 返回的路径**已经带应用名**，再拼
/// 一层会变成孤儿目录（`LESSON.md` §七）。这里只拼一个 `novel_backup`。
class NovelSupportBackupFileStore implements NovelBackupFileStore {
  NovelSupportBackupFileStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;
  Future<Directory>? _directory;

  Future<Directory> _dir() async {
    final cached = _directory;
    if (cached != null) return cached;
    final support = await _supportDirectory();
    final dir = Directory(p.join(support.path, 'novel_backup'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _directory = Future<Directory>.value(dir);
  }

  @override
  Future<String?> read(String name) async {
    final file = File(p.join((await _dir()).path, name));
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String name, String content) async {
    final file = File(p.join((await _dir()).path, name));
    await file.writeAsString(content, flush: true);
  }

  @override
  Future<List<String>> list() async {
    final dir = await _dir();
    final entries = await dir.list().toList();
    return <String>[
      for (final entry in entries)
        if (entry is File) p.basename(entry.path),
    ]..sort();
  }

  @override
  Future<void> delete(String name) async {
    final file = File(p.join((await _dir()).path, name));
    if (await file.exists()) await file.delete();
  }
}
