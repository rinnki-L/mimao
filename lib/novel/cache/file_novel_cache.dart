/// 正文缓存：`<应用支持目录>/novel_cache/<book>/<chapter>.json`，一章一文件。
///
/// 书源正文抓取慢且站点易变；缓存让重进章节不再走网络，也给后续离线下载留
/// 同一套仓储。构造/打开惰性，首次真实读写才触达 path_provider。
///
/// 缓存有 TTL 与文件数上限：TTL 让"修好书源规则后仍命中旧正文"的问题在
/// 一段有限时间内自愈；上限防止缓存随阅读量单调增长。二者都可用构造参数
/// 覆盖，测试可注入短 TTL / 小上限。
library;

import 'dart:convert';
import 'dart:io';

import 'package:mimao/novel/cache/novel_cache.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 默认缓存有效期：7 天。
const Duration kDefaultNovelCacheTtl = Duration(days: 7);

/// 默认缓存文件上限（单本书目录外的全书总量粗粒度控制）。
const int kDefaultNovelCacheMaxFiles = 5000;

/// 惰性默认缓存：装配期不碰 path_provider（测试无插件环境也不挂起）。
class DefaultNovelCache implements NovelCache {
  Future<FileNovelCache>? _cache;

  final Duration ttl;
  final int maxFiles;

  DefaultNovelCache({
    this.ttl = kDefaultNovelCacheTtl,
    this.maxFiles = kDefaultNovelCacheMaxFiles,
  });

  Future<FileNovelCache> get _instance {
    final cache = _cache;
    if (cache != null) return cache;
    final opened = FileNovelCache.openDefault(ttl: ttl, maxFiles: maxFiles);
    _cache = opened;
    // 打开失败（插件/路径故障）不永久缓存失败的 Future，下一轮可重试。
    opened.then(
      (_) {},
      onError: (Object _) {
        if (identical(_cache, opened)) _cache = null;
      },
    );
    return opened;
  }

  @override
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter) async =>
      (await _instance).read(ref, chapter);

  @override
  Future<void> write(
    NovelRef ref,
    NovelChapter chapter,
    NovelContent content,
  ) async => (await _instance).write(ref, chapter, content);

  @override
  Future<void> clear(NovelRef ref) async => (await _instance).clear(ref);
}

class FileNovelCache implements NovelCache {
  FileNovelCache(
    this.directory, {
    this.ttl = kDefaultNovelCacheTtl,
    this.maxFiles = kDefaultNovelCacheMaxFiles,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final Directory directory;

  /// 缓存有效期；<= 0 表示永不过期（测试可注入）。
  final Duration ttl;

  /// 全书缓存文件数上限；<= 0 表示不限制。
  final int maxFiles;

  /// 可注入的时钟，便于测试 TTL（默认当前时间）。
  final DateTime Function() now;

  static Future<FileNovelCache> openDefault({
    Duration ttl = kDefaultNovelCacheTtl,
    int maxFiles = kDefaultNovelCacheMaxFiles,
  }) async {
    final support = await getApplicationSupportDirectory();
    return FileNovelCache(
      Directory(p.join(support.path, 'novel_cache')),
      ttl: ttl,
      maxFiles: maxFiles,
    );
  }

  @override
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter) async {
    final file = _file(ref, chapter);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        // 新格式是带 cachedAt 的包封；旧格式（裸 NovelContent JSON）兼容读取，
        // 视为新鲜——不因为一次升级就把用户已有缓存全清空。
        final envelope = decoded['cachedAt'] is int ? decoded : null;
        if (envelope != null) {
          final cachedAt = DateTime.fromMillisecondsSinceEpoch(
            envelope['cachedAt'] as int,
          );
          if (_expired(cachedAt)) {
            // 过期即删除，逼下一次走网络重抓。
            await file.delete();
            return null;
          }
        }
        final payload = envelope != null ? envelope['content'] : decoded;
        if (payload is Map) {
          return NovelContent.fromJson(Map<String, Object?>.from(payload));
        }
      }
    } on Object {
      // 坏缓存当未命中，下次写入覆盖。
    }
    return null;
  }

  bool _expired(DateTime cachedAt) {
    if (ttl <= Duration.zero) return false;
    return now().difference(cachedAt) > ttl;
  }

  @override
  Future<void> write(
    NovelRef ref,
    NovelChapter chapter,
    NovelContent content,
  ) async {
    final file = _file(ref, chapter);
    await file.parent.create(recursive: true);
    final envelope = <String, Object?>{
      'cachedAt': now().millisecondsSinceEpoch,
      'content': content.toJson(),
    };
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(envelope));
    await temp.rename(file.path);
    await _enforceLimit();
  }

  /// 超出上限时，按修改时间从旧到新删除最旧的缓存文件，直到降到上限内。
  Future<void> _enforceLimit() async {
    if (maxFiles <= 0 || !directory.existsSync()) return;
    final files = <File>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && p.extension(entity.path) == '.json') {
        files.add(entity);
      }
    }
    if (files.length <= maxFiles) return;
    final withTime = <({File file, DateTime modified})>[
      for (final file in files)
        (file: file, modified: await file.lastModified()),
    ]..sort((a, b) => a.modified.compareTo(b.modified));
    final overflow = files.length - maxFiles;
    for (final entry in withTime.take(overflow)) {
      try {
        await entry.file.delete();
      } on Object {
        // 单个删除失败不影响其它。
      }
    }
    // 顺带清理空目录。
    await for (final entity in directory.list(recursive: true)) {
      if (entity is Directory &&
          entity.path != directory.path &&
          entity.listSync().isEmpty) {
        try {
          await entity.delete();
        } on Object {
          // ignore
        }
      }
    }
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
