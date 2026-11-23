// 章节内阅读位置的持久化点（页内页码 / 滚动比例）。
//
// 历史库 `novel_history` 只记章级进度（chapterIndex 1 起），页内位置单独
// 落在模块 kv：一个 JSON map（bookId → 位置），按容量淘汰最旧条目。
// 这样不必改 drift schema，也不会把页内位置混进 core 投影。

import 'dart:convert';

import 'package:mimao/novel/library_api.dart'
    show NovelPrefsApi, novelPrefReaderPositions;

class NovelReaderPosition {
  const NovelReaderPosition({
    required this.chapterUrl,
    required this.chapterIndex,
    this.chapterId = '',
    this.page = 1,
    this.pageCount = 1,
    this.scrollRatio = 0,
  });

  /// 章节地址/稳定 id，用来判断保存位置是否还是同一章。
  final String chapterUrl;
  final String chapterId;

  /// 0 起章下标（引擎口径）。
  final int chapterIndex;

  /// 1 起页码 + 当前章总页数。
  final int page;
  final int pageCount;

  /// 滚动模式下的滚动比例 0..1。
  final double scrollRatio;

  bool matches({
    required String chapterUrl,
    required String chapterId,
    required int chapterIndex,
  }) {
    if (this.chapterIndex != chapterIndex) return false;
    final saved = this.chapterUrl.isNotEmpty ? this.chapterUrl : this.chapterId;
    if (saved.isEmpty) return true;
    return saved == chapterUrl || saved == chapterId;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'chapterUrl': chapterUrl,
    'chapterId': chapterId,
    'chapterIndex': chapterIndex,
    'page': page,
    'pageCount': pageCount,
    'scrollRatio': scrollRatio,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };

  static NovelReaderPosition? fromJson(Map<String, Object?> json) {
    final index = json['chapterIndex'];
    if (index is! num) return null;
    return NovelReaderPosition(
      chapterUrl: '${json['chapterUrl'] ?? ''}',
      chapterId: '${json['chapterId'] ?? ''}',
      chapterIndex: index.toInt(),
      page: (json['page'] is num) ? (json['page']! as num).round() : 1,
      pageCount: (json['pageCount'] is num)
          ? (json['pageCount']! as num).round()
          : 1,
      scrollRatio: (json['scrollRatio'] is num)
          ? (json['scrollRatio']! as num).toDouble()
          : 0,
    );
  }
}

/// 模块 kv 版位置存储；[prefs] 为空时退化为内存（测试/未接线）。
class NovelReaderPositionStore {
  NovelReaderPositionStore(this.prefs, {this.capacity = 200});

  final NovelPrefsApi? prefs;
  final int capacity;

  static const String key = novelPrefReaderPositions;

  Map<String, Object?>? _memory;

  Future<Map<String, Object?>> _readAll() async {
    final cached = _memory;
    if (cached != null) return cached;
    final api = prefs;
    if (api == null) return _memory = <String, Object?>{};
    try {
      final raw = await api.read(key);
      if (raw == null || raw.isEmpty) return _memory = <String, Object?>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _memory = Map<String, Object?>.from(decoded);
      }
    } on Object {
      // 坏数据当空处理。
    }
    return _memory = <String, Object?>{};
  }

  Future<NovelReaderPosition?> load(String bookId) async {
    if (bookId.isEmpty) return null;
    final all = await _readAll();
    final raw = all[bookId];
    if (raw is! Map) return null;
    return NovelReaderPosition.fromJson(Map<String, Object?>.from(raw));
  }

  Future<void> save(String bookId, NovelReaderPosition position) async {
    if (bookId.isEmpty) return;
    final all = await _readAll();
    all[bookId] = position.toJson();
    _trim(all);
    await _write(all);
  }

  Future<void> clear(String bookId) async {
    if (bookId.isEmpty) return;
    final all = await _readAll();
    if (all.remove(bookId) == null) return;
    await _write(all);
  }

  void _trim(Map<String, Object?> all) {
    if (all.length <= capacity) return;
    final entries = all.entries.toList()
      ..sort((a, b) {
        final ta = a.value is Map ? (a.value! as Map)['updatedAt'] : 0;
        final tb = b.value is Map ? (b.value! as Map)['updatedAt'] : 0;
        return (ta is num ? ta.toInt() : 0).compareTo(
          tb is num ? tb.toInt() : 0,
        );
      });
    final overflow = all.length - capacity;
    for (var i = 0; i < overflow; i++) {
      all.remove(entries[i].key);
    }
  }

  Future<void> _write(Map<String, Object?> all) async {
    final api = prefs;
    if (api == null) return;
    try {
      await api.write(key, jsonEncode(all));
    } on Object {
      // 写失败不影响本次阅读。
    }
  }
}
