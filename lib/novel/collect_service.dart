import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:mimao/core/contract.dart' show MediaType;
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_projection.dart';

/// 小说收藏服务（实现 [NovelCollectApi] 的接口缝）。
///
/// 双记账：`novel_collect` 是权威；每次写内部表后立即经
/// [syncNovelProjection] 把 `starred` 与公共列投影到统一书架。
///
/// 继承 [ChangeNotifier] 只服务于「我的」页的自动刷新：搜索页收藏后切过去
/// 能立刻看到新条目（服务不是内存状态源，通知不含任何数据）。
class NovelCollectService extends ChangeNotifier implements NovelCollectApi {
  NovelCollectService(this.db, this.library);

  final NovelDb db;
  final LibraryRepository library;

  @override
  Future<void> collect(NovelSummary book) {
    return collectRef(
      novelRefOf(book),
      title: book.title,
      coverUrl: book.coverUrl.isEmpty ? null : book.coverUrl,
      book: book,
    );
  }

  /// 收藏（幂等）：已存在则更新元数据并刷新收藏时间。
  Future<void> collectRef(
    NovelRef ref, {
    required String title,
    String? coverUrl,
    NovelSummary? book,
    DateTime? collectedAt,
    String? groupName,
  }) async {
    final at = collectedAt ?? DateTime.now();
    final existing = await db.collectRow(ref);
    await db
        .into(db.novelCollectEntries)
        .insertOnConflictUpdate(
          NovelCollectEntriesCompanion.insert(
            id: ref.id,
            title: title,
            coverUrl: Value(coverUrl),
            // 没带新书籍快照时保留旧的 payload（对齐 history 的 Value.absent），
            // 否则重复收藏/纯元数据刷新会把 sourceKey/bookUrl/intro 等在线
            // 续读信息擦成 '{}'，造成潜伏的续读失败。
            payload: book == null
                ? const Value.absent()
                : Value(jsonEncode(book.toJson())),
            // 未显式给分组时保留原分组：重复收藏/更新元数据不该把用户分组清掉。
            groupName: Value(groupName ?? existing?.groupName),
            collectedAt: at,
          ),
        );
    await syncNovelProjection(db: db, library: library, ref: ref);
    notifyListeners();
  }

  /// 取消收藏（幂等）。
  ///
  /// 内部行删除后：仍有阅读历史 → 重投影把 starred 校正为 false，标题/封面
  /// 以历史行为权威；连历史也没有 → 投影行再无可重建的数据来源，直接摘掉，
  /// 不在统一书架留幽灵条目。
  @override
  Future<void> remove(String bookId) async {
    final ref = NovelRef(id: bookId);
    final existing = await db.collectRow(ref);
    if (existing == null) return;
    await (db.delete(
      db.novelCollectEntries,
    )..where((t) => t.id.equals(ref.id))).go();
    if (await db.historyRow(ref) != null) {
      await syncNovelProjection(db: db, library: library, ref: ref);
    } else {
      await library.delete(
        id: ref.id,
        type: MediaType.novel,
        sourceName: novelSourceName,
      );
    }
    notifyListeners();
  }

  @override
  Future<bool> isCollected(String bookId) async =>
      await db.collectRow(NovelRef(id: bookId)) != null;

  @override
  Future<Set<String>> collectedIds() async {
    final rows = await db.select(db.novelCollectEntries).get();
    return <String>{for (final row in rows) row.id};
  }

  /// 收藏列表，按收藏时间倒序。
  @override
  Future<List<NovelCollectItem>> list() async {
    final rows = await (db.select(
      db.novelCollectEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.collectedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  /// 设置一本书的分组；内部行不存在时什么都不做（不凭空造收藏）。
  @override
  Future<void> setGroup(String bookId, String? groupName) async {
    final normalized = _normalizeGroup(groupName);
    final existing = await db.collectRow(NovelRef(id: bookId));
    if (existing == null) return;
    await (db.update(db.novelCollectEntries)..where((t) => t.id.equals(bookId)))
        .write(NovelCollectEntriesCompanion(groupName: Value(normalized)));
    notifyListeners();
  }

  /// 批量设置分组（一次事务，避免选择模式逐本刷新）。
  @override
  Future<void> setGroupFor(Iterable<String> bookIds, String? groupName) async {
    final ids = bookIds.toSet().toList();
    if (ids.isEmpty) return;
    final normalized = _normalizeGroup(groupName);
    await db.transaction(() async {
      for (final id in ids) {
        final existing = await db.collectRow(NovelRef(id: id));
        if (existing == null) continue;
        await (db.update(db.novelCollectEntries)..where((t) => t.id.equals(id)))
            .write(NovelCollectEntriesCompanion(groupName: Value(normalized)));
      }
    });
    notifyListeners();
  }

  /// 已有分组名（去重、按名称排序）。
  @override
  Future<List<String>> groups() async {
    final rows = await db.select(db.novelCollectEntries).get();
    final names = <String>{
      for (final row in rows)
        if (row.groupName != null && row.groupName!.isNotEmpty) row.groupName!,
    }.toList()..sort();
    return names;
  }

  /// 重命名分组；[to] 为空串表示把成员移出分组。
  @override
  Future<void> renameGroup(String from, String to) async {
    final source = from.trim();
    if (source.isEmpty) return;
    final target = _normalizeGroup(to);
    await (db.update(db.novelCollectEntries)
          ..where((t) => t.groupName.equals(source)))
        .write(NovelCollectEntriesCompanion(groupName: Value(target)));
    notifyListeners();
  }

  /// 删除分组（只解除归属，书仍留在书架）。
  @override
  Future<void> deleteGroup(String name) => renameGroup(name, '');

  @override
  Future<void> setNote(String bookId, String note) async {
    final existing = await db.collectRow(NovelRef(id: bookId));
    if (existing == null) return;
    await (db.update(db.novelCollectEntries)..where((t) => t.id.equals(bookId)))
        .write(NovelCollectEntriesCompanion(note: Value(note.trim())));
    notifyListeners();
  }

  @override
  Future<void> setCustomCover(String bookId, String? path) async {
    final existing = await db.collectRow(NovelRef(id: bookId));
    if (existing == null) return;
    final normalized = _normalizeGroup(path);
    await (db.update(db.novelCollectEntries)..where((t) => t.id.equals(bookId)))
        .write(
          NovelCollectEntriesCompanion(customCoverPath: Value(normalized)),
        );
    notifyListeners();
  }

  /// 系列列表，按名称排序（同名理论上不会出现，[createSeries] 会复用）。
  @override
  Future<List<NovelSeriesItem>> series() async {
    final rows = await (db.select(
      db.novelSeriesEntries,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    return <NovelSeriesItem>[
      for (final row in rows)
        NovelSeriesItem(id: row.id, name: row.name, createdAt: row.createdAt),
    ];
  }

  /// 按名字取系列 id，没有就新建（大小写与空白都归一后再比）。
  @override
  Future<int> createSeries(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', '系列名不能为空');
    }
    final rows = await db.select(db.novelSeriesEntries).get();
    for (final row in rows) {
      if (row.name.trim() == normalized) return row.id;
    }
    return db
        .into(db.novelSeriesEntries)
        .insert(
          NovelSeriesEntriesCompanion.insert(
            name: normalized,
            createdAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> renameSeries(int id, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', '系列名不能为空');
    }
    await (db.update(
      db.novelSeriesEntries,
    )..where((t) => t.id.equals(id))).write(
      NovelSeriesEntriesCompanion(name: Value(normalized)),
    );
    notifyListeners();
  }

  @override
  Future<void> deleteSeries(int id) async {
    await db.transaction(() async {
      await (db.update(
        db.novelCollectEntries,
      )..where((t) => t.seriesId.equals(id))).write(
        const NovelCollectEntriesCompanion(seriesId: Value(null)),
      );
      await (db.delete(
        db.novelSeriesEntries,
      )..where((t) => t.id.equals(id))).go();
    });
    notifyListeners();
  }

  @override
  Future<void> setSeriesFor(Iterable<String> bookIds, int? seriesId) async {
    final ids = bookIds.toSet().toList();
    if (ids.isEmpty) return;
    // 系列不存在时不写悬挂外键（系列可能刚被另一处删掉）。
    if (seriesId != null) {
      final row = await (db.select(
        db.novelSeriesEntries,
      )..where((t) => t.id.equals(seriesId))).getSingleOrNull();
      if (row == null) return;
    }
    await db.transaction(() async {
      for (final id in ids) {
        final existing = await db.collectRow(NovelRef(id: id));
        if (existing == null) continue;
        await (db.update(db.novelCollectEntries)..where((t) => t.id.equals(id)))
            .write(NovelCollectEntriesCompanion(seriesId: Value(seriesId)));
      }
    });
    notifyListeners();
  }

  String? _normalizeGroup(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  NovelCollectItem _fromRow(NovelCollectRow row) => NovelCollectItem(
    ref: NovelRef(id: row.id),
    title: row.title,
    coverUrl: row.coverUrl,
    book: novelSummaryFromPayload(row.payload),
    groupName: row.groupName,
    note: row.note,
    customCoverPath: row.customCoverPath,
    seriesId: row.seriesId,
    collectedAt: row.collectedAt,
  );
}
