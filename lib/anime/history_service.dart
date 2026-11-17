import 'package:drift/drift.dart';
import 'package:mimao/core/library.dart';

import 'anime_db.dart';
import 'anime_models.dart';
import 'anime_projection.dart';

/// 番剧观看历史服务——双记账的"打开点校正"主要发生在这里。
///
/// - [saveProgress] 是**持久化点**：先写内部 `anime_history`，紧接着投影；
/// - [open] 是**打开点**：以内部库权威值覆盖投影（把漏写/写旧的投影校正回来）。
class AnimeHistoryService {
  final AnimeDb db;
  final LibraryRepository library;

  AnimeHistoryService(this.db, this.library);

  /// 打开某部番（从时间线点进详情/播放器）时的校正动作。
  ///
  /// 只在内部库确实有观看记录时写投影：没有记录的作品不应因为"点开看了一眼
  /// 详情"就凭空出现在书架时间线里。
  Future<void> open(AnimeRef ref) async {
    if (await db.historyRow(ref) == null) return;
    await syncAnimeProjection(db: db, library: library, ref: ref);
  }

  /// 记录/更新观看进度（持久化点）。返回内部库的权威行。
  Future<AnimeWatchEntry> saveProgress(
    AnimeRef ref, {
    required String title,
    String? coverUrl,
    required int episode,
    int positionSec = 0,
    int durationSec = 0,
    DateTime? openedAt,
  }) async {
    if (episode < 0 || positionSec < 0 || durationSec < 0) {
      throw ArgumentError('观看进度不能为负数');
    }
    final at = openedAt ?? DateTime.now();
    await db
        .into(db.animeHistoryEntries)
        .insertOnConflictUpdate(
          AnimeHistoryEntriesCompanion.insert(
            id: ref.id,
            sourceName: ref.sourceName,
            title: title,
            coverUrl: Value(coverUrl),
            episode: Value(episode),
            positionSec: Value(positionSec),
            durationSec: Value(durationSec),
            openedAt: at,
          ),
        );
    await syncAnimeProjection(db: db, library: library, ref: ref);
    return AnimeWatchEntry(
      ref: ref,
      title: title,
      coverUrl: coverUrl,
      episode: episode,
      positionSec: positionSec,
      durationSec: durationSec,
      openedAt: at,
    );
  }

  Future<AnimeWatchEntry?> latest(AnimeRef ref) async {
    final row = await db.historyRow(ref);
    return row == null ? null : _fromRow(row);
  }

  /// 最近观看列表，按打开时间倒序（"继续观看"的数据源）。
  Future<List<AnimeWatchEntry>> recent({int limit = 20}) async {
    final rows =
        await (db.select(db.animeHistoryEntries)
              ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
              ..limit(limit))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  AnimeWatchEntry _fromRow(AnimeHistoryRow row) => AnimeWatchEntry(
    ref: AnimeRef(id: row.id, sourceName: row.sourceName),
    title: row.title,
    coverUrl: row.coverUrl,
    episode: row.episode,
    positionSec: row.positionSec,
    durationSec: row.durationSec,
    openedAt: row.openedAt,
  );
}
