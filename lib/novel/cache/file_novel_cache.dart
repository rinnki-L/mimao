/// 正文缓存：`<应用支持目录>/novel_cache/<book>/<chapter>.json`，一章一文件。
///
/// 书源正文抓取慢且站点易变；缓存让重进章节不再走网络，也给后续离线下载留
/// 同一套仓储。构造/打开惰性，首次真实读写才触达 path_provider。
library;

import 'dart:convert';
import 'dart:io';

import 'package:mimao/novel/cache/novel_cache.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileNovelCache implements NovelCache {
  FileNovelCache(this.directory);

  final Directory directory;

  static Future<FileNovelCache> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return FileNovelCache(Directory(p.join(support.path, 'novel_cache')));
  }

  @override
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter) async {
    final file = _file(ref, chapter);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return NovelContent.fromJson(Map<String, Object?>.from(decoded));
      }
    } on Object {
      // 坏缓存当未命中，下次写入覆盖。
    }
    return null;
  }

  @override
  Future<void> write(
    NovelRef ref,
    NovelChapter chapter,
    NovelContent content,
  ) async {
    final file = _file(ref, chapter);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(content.toJson()));
    await temp.rename(file.path);
  }

  @override
  Future<void> clear(NovelRef ref) async {
    final folder = _bookDirectory(ref);
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  File _file(NovelRef ref, NovelChapter chapter) =>
      File(p.join(_bookDirectory(ref).path, '${_safe(chapter.id)}.json'));

  Directory _bookDirectory(NovelRef ref) =>
      Directory(p.join(directory.path, _safe(ref.id)));

  static String _safe(String value) => base64Url
      .encode(utf8.encode(value))
      .replaceAll('=', '')
      .replaceAll(RegExp(r'[/+]'), '_');
}
