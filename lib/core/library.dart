import 'package:drift/drift.dart';

import 'contract.dart';
import 'db.dart';

/// 壳-facing 只读投影：公共列 + 模块写好的 progressText，**不含 payload**。
/// 壳层永不解析 payload（docs/architecture.md §3.1 规则④）。
class MediaEntryView {
  final String id;
  final MediaType type;
  final String sourceName;
  final String title;
  final String? coverUrl;
  final String progressText;
  final bool starred;
  final DateTime lastOpenedAt;

  const MediaEntryView({
    required this.id,
    required this.type,
    required this.sourceName,
    required this.title,
    required this.coverUrl,
    required this.progressText,
    required this.starred,
    required this.lastOpenedAt,
  });

  factory MediaEntryView.fromRow(MediaEntryRow row) => MediaEntryView(
    id: row.id,
    type: row.mediaType,
    sourceName: row.sourceName,
    title: row.title,
    coverUrl: row.coverUrl,
    progressText: row.progressText,
    starred: row.starred,
    lastOpenedAt: row.lastOpenedAt,
  );
}

/// 统一书架读写唯一 facade。
///
/// 模块只在两个时机调它（docs/architecture.md §3.1）：
///   ① 持久化点——把进度/收藏写进模块自己内部库的同一个函数里，紧接着 upsert；
///   ② 打开点——模块打开详情时用内部库权威值覆盖投影（校正）。
/// 绝不挂"内存状态变化"回调。
class LibraryRepository {
  final AppDb db;

  LibraryRepository(this.db);

  /// 我的时间线：最近打开的 N 条，可按类型/收藏筛选（demo 01「我的」页数据源）。
  Future<List<MediaEntryView>> timeline({
    int limit = 50,
    MediaType? type,
    bool starredOnly = false,
  }) async {
    final query = db.select(db.mediaEntries)
      ..orderBy([(t) => OrderingTerm.desc(t.lastOpenedAt)])
      ..limit(limit);
    if (type != null) {
      // 过滤走 SQL 底层类型（String）：GeneratedColumnWithTypeConverter 的
      // .equals() 接收转换前的 String，而 companion.insert 接收 MediaType。
      query.where((t) => t.mediaType.equals(type.name));
    }
    if (starredOnly) {
      query.where((t) => t.starred.equals(true));
    }
    final rows = await query.get();
    return [for (final row in rows) MediaEntryView.fromRow(row)];
  }

  /// 写入/校正一行投影。payload 原样透传——壳与 core 都不解释它。
  Future<void> upsert({
    required String id,
    required MediaType type,
    required String sourceName,
    required String title,
    String? coverUrl,
    required String payload,
    required String progressText,
    bool starred = false,
    DateTime? lastOpenedAt,
    DateTime? createdAt,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.mediaEntries)
        .insert(
          MediaEntriesCompanion.insert(
            id: id,
            mediaType: type,
            sourceName: sourceName,
            title: title,
            coverUrl: Value(coverUrl),
            payload: payload,
            progressText: progressText,
            starred: starred,
            lastOpenedAt: lastOpenedAt ?? now,
            createdAt: createdAt ?? now,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// 收藏切换（全局设置/`我的`页都用得到）。
  Future<void> setStarred(MediaEntryView entry, {required bool starred}) async {
    await (db.update(db.mediaEntries)..where(
          (t) =>
              t.id.equals(entry.id) &
              t.mediaType.equals(entry.type.name) &
              t.sourceName.equals(entry.sourceName),
        ))
        .write(MediaEntriesCompanion(starred: Value(starred)));
  }
}
