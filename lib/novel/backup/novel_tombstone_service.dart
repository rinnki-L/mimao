/// 删除墓碑：记录「哪台设备删了哪条书签/划线」，让删除能跨设备传播。
///
/// 没有墓碑时，合并只会做并集——一台设备删掉的书签会被另一台的旧副本复活。
/// 墓碑只是一行 `(kind, 自然键, deletedAt)`，同键覆盖保留最新一次删除。
///
/// 保留期见 [novelTombstoneRetention]：超过就清掉，否则这张表只会一直涨。
library;

import 'package:drift/drift.dart';

import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_plan.dart';
import 'package:mimao/novel/novel_db.dart';

/// drift 行 ↔ 备份模型的唯一转换口（写墓碑与导出快照共用同一套键）。
String novelTombstoneKeyOfBookmark(NovelBookmarkRow row) =>
    novelBackupAnchorKey(
      bookId: row.bookId,
      sourceKey: row.sourceKey,
      chapterIndex: row.chapterIndex,
      paragraph: row.paragraph,
      start: row.charOffset,
      end: row.charOffset,
    );

String novelTombstoneKeyOfMarking(NovelMarkingRow row) => novelBackupAnchorKey(
  bookId: row.bookId,
  sourceKey: row.sourceKey,
  chapterIndex: row.chapterIndex,
  paragraph: row.paragraph,
  start: row.startOffset,
  end: row.endOffset,
);

class NovelTombstoneService {
  NovelTombstoneService(this.db);

  final NovelDb db;

  /// 记一次删除；同键覆盖（只留最新删除时间）。
  Future<void> record({
    required String kind,
    required String key,
    String deviceId = '',
    DateTime? at,
  }) async {
    if (kind.isEmpty || key.isEmpty) return;
    final device = deviceId.isNotEmpty ? deviceId : await db.ensureDeviceId();
    await db
        .into(db.novelTombstoneEntries)
        .insertOnConflictUpdate(
          NovelTombstoneEntriesCompanion.insert(
            kind: kind,
            targetKey: key,
            deviceId: Value<String>(device),
            deletedAt: at ?? DateTime.now(),
          ),
        );
    await prune();
  }

  Future<void> recordBookmark(NovelBookmarkRow row, {DateTime? at}) => record(
    kind: novelTombstoneBookmark,
    key: novelTombstoneKeyOfBookmark(row),
    at: at,
  );

  Future<void> recordMarking(NovelMarkingRow row, {DateTime? at}) => record(
    kind: novelTombstoneMarking,
    key: novelTombstoneKeyOfMarking(row),
    at: at,
  );

  /// 当前仍有效的墓碑（已按保留期裁剪）。
  Future<List<NovelBackupTombstone>> load({DateTime? now}) async {
    final rows = await db.select(db.novelTombstoneEntries).get();
    return <NovelBackupTombstone>[
      for (final row in rows)
        NovelBackupTombstone(
          kind: row.kind,
          key: row.targetKey,
          deviceId: row.deviceId,
          deletedAt: row.deletedAt,
        ),
    ];
  }

  /// 清掉超过保留期的墓碑。
  Future<void> prune({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(
      novelBackupTombstoneRetention,
    );
    await (db.delete(
      db.novelTombstoneEntries,
    )..where((t) => t.deletedAt.isSmallerThanValue(cutoff))).go();
  }

  /// 撤销一次删除（撤销恢复时用）：把墓碑连同书签/划线一并还原。
  Future<void> forget(String kind, String key) async {
    await (db.delete(
      db.novelTombstoneEntries,
    )..where((t) => t.kind.equals(kind) & t.targetKey.equals(key))).go();
  }
}
