// 朗读音频缓存（L2）：合成结果落盘，键为
// `(书, 章节, 段落, 音色, 语速)`；索引落 novel_tts_cache 表，容量按 LRU 淘汰。
//
// 只负责「找文件 / 登记文件 / 清理」；合成与播放由 [CachedNovelTtsEngine]
// 驱动，测试可直接用临时目录 + 内存库验证键与淘汰，不需要真实语音。

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../novel_db.dart'
    show
        $NovelTtsCacheEntriesTable,
        NovelDb,
        NovelTtsCacheEntriesCompanion,
        NovelTtsCacheRow;

/// 缓存键：可读、稳定；语速固定两位小数，避免 1.0 与 1.00 落成两条。
String novelTtsCacheKey({
  required String bookId,
  required String chapterKey,
  required int paragraph,
  required String voice,
  required double rate,
}) =>
    '${bookId.trim()}|${chapterKey.trim()}|$paragraph|'
    '${voice.trim().isEmpty ? 'auto' : voice.trim()}|'
    '${rate.toStringAsFixed(2)}';

/// 缓存占用统计（设置面板展示 / 测试断言）。
class NovelTtsCacheStats {
  const NovelTtsCacheStats({
    required this.count,
    required this.bytes,
    required this.maxBytes,
  });

  final int count;
  final int bytes;
  final int maxBytes;

  bool get overLimit => bytes > maxBytes;
}

class NovelTtsCache {
  NovelTtsCache({
    required this.db,
    required Future<Directory> Function() directory,
    this.maxBytes = defaultMaxBytes,
    DateTime Function()? clock,
  }) : _directory = directory,
       _clock = clock ?? DateTime.now;

  /// 默认上限 200 MB：按每分钟朗读约 1–2 MB 估算，够几十小时，又不至于
  /// 把用户的应用支持目录撑爆。
  static const int defaultMaxBytes = 200 * 1024 * 1024;

  final NovelDb db;
  final int maxBytes;
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  Future<Directory>? _directoryFuture;

  /// 生产构造：与应用库同目录的应用支持目录下的 `novel_tts_cache/`。
  /// 目录解析保持惰性（首段合成才触达 path_provider）。
  factory NovelTtsCache.app(NovelDb db, {int? maxBytes}) => NovelTtsCache(
    db: db,
    maxBytes: maxBytes ?? defaultMaxBytes,
    directory: () async {
      final base = await getApplicationSupportDirectory();
      return Directory(p.join(base.path, 'novel_tts_cache'));
    },
  );

  Future<Directory> _dir() =>
      _directoryFuture ??= _directory().then((directory) async {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        return directory;
      });

  /// 文件名 = 键的 sha256，避免 Windows 路径里的 `|` / 中文音色名。
  Future<String> pathFor(String cacheKey) async {
    final directory = await _dir();
    final name = sha256.convert(utf8.encode(cacheKey)).toString();
    return p.join(directory.path, '$name.wav');
  }

  /// 命中返回可用文件路径（并刷新 LRU）；文件丢了顺手删索引。
  Future<String?> find(String cacheKey) async {
    final query = db.select(db.novelTtsCacheEntries)
      ..where((t) => t.cacheKey.equals(cacheKey));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final file = File(row.path);
    if (!await file.exists()) {
      await _deleteKey(cacheKey);
      return null;
    }
    await (db.update(db.novelTtsCacheEntries)
          ..where((t) => t.cacheKey.equals(cacheKey)))
        .write(NovelTtsCacheEntriesCompanion(lastUsedAt: Value(_clock())));
    return row.path;
  }

  /// 登记一条刚合成好的文件；超过容量上限立刻淘汰最久未用的。
  Future<void> put({required String cacheKey, required String path}) async {
    final file = File(path);
    final bytes = await file.exists() ? await file.length() : 0;
    final now = _clock();
    await db
        .into(db.novelTtsCacheEntries)
        .insertOnConflictUpdate(
          NovelTtsCacheEntriesCompanion.insert(
            cacheKey: cacheKey,
            path: path,
            bytes: Value(bytes),
            createdAt: now,
            lastUsedAt: now,
          ),
        );
    await enforceLimit();
  }

  /// 按 lastUsedAt 从旧到新删，直到总字节数回到上限以内。
  /// 返回删除的条目数。
  Future<int> enforceLimit() async {
    final query = db.select(db.novelTtsCacheEntries)
      ..orderBy(<OrderingTerm Function($NovelTtsCacheEntriesTable)>[
        (t) => OrderingTerm.asc(t.lastUsedAt),
      ]);
    final rows = await query.get();
    var total = 0;
    for (final row in rows) {
      total += row.bytes;
    }
    var removed = 0;
    for (final row in rows) {
      if (total <= maxBytes) break;
      total -= row.bytes;
      await _deleteRow(row);
      removed++;
    }
    return removed;
  }

  Future<NovelTtsCacheStats> stats() async {
    final rows = await db.select(db.novelTtsCacheEntries).get();
    var bytes = 0;
    for (final row in rows) {
      bytes += row.bytes;
    }
    return NovelTtsCacheStats(
      count: rows.length,
      bytes: bytes,
      maxBytes: maxBytes,
    );
  }

  /// 清空索引与文件（设置面板的「清理朗读缓存」）。
  Future<int> clear() async {
    final rows = await db.select(db.novelTtsCacheEntries).get();
    for (final row in rows) {
      await _deleteRow(row);
    }
    return rows.length;
  }

  Future<void> _deleteKey(String cacheKey) async {
    await (db.delete(
      db.novelTtsCacheEntries,
    )..where((t) => t.cacheKey.equals(cacheKey))).go();
  }

  Future<void> _deleteRow(NovelTtsCacheRow row) async {
    await _deleteKey(row.cacheKey);
    try {
      final file = File(row.path);
      if (await file.exists()) await file.delete();
    } on Object {
      // 文件被占用/已删都不影响索引一致性。
    }
  }
}
