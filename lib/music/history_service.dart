import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:mimao/core/library.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_db.dart';
import 'package:mimao/music/music_projection.dart';

/// 音乐播放历史服务——双记账的"打开点校正"主要发生在这里。
///
/// - [saveProgress] 是**持久化点**：先写内部 `music_history`，紧接着投影；
/// - [open] 是**打开点**：以内部库权威值覆盖投影（把漏写/写旧的投影校正回来）。
///
/// 继承 [ChangeNotifier] 只服务于「我的」页的自动刷新（见收藏服务同款说明）。
class MusicHistoryService extends ChangeNotifier implements MusicHistoryApi {
  MusicHistoryService(this.db, this.library);

  final MusicDb db;
  final LibraryRepository library;

  @override
  Future<void> open(MusicSong song) => openRef(musicRefOf(song));

  /// 打开某首歌（从时间线/历史点进播放）时的校正动作。
  ///
  /// 只在内部库确实有播放记录时写投影：没播过的歌不应因为"点开看了一眼"
  /// 就凭空出现在书架时间线里。
  Future<void> openRef(MusicRef ref) async {
    if (await db.historyRow(ref) == null) return;
    await syncMusicProjection(db: db, library: library, ref: ref);
  }

  @override
  Future<void> saveProgress(
    MusicSong song,
    Duration position,
    Duration duration,
  ) {
    return saveProgressRef(
      musicRefOf(song),
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      title: song.title,
      coverUrl: song.coverUrl.isEmpty ? null : song.coverUrl,
      song: song,
    );
  }

  /// 记录/更新播放进度（持久化点）。同曲重复写只更新一行，`playCount` 递增。
  Future<MusicHistoryItem> saveProgressRef(
    MusicRef ref, {
    required int positionMs,
    required int durationMs,
    required String title,
    String? coverUrl,
    MusicSong? song,
    DateTime? at,
  }) async {
    if (positionMs < 0 || durationMs < 0) {
      throw ArgumentError('播放进度不能为负数');
    }
    final openedAt = at ?? DateTime.now();
    final encoded = song == null ? null : jsonEncode(song.toJson());

    await db.transaction(() async {
      final existing = await db.historyRow(ref);
      if (existing == null) {
        await db
            .into(db.musicHistoryEntries)
            .insert(
              MusicHistoryEntriesCompanion.insert(
                id: ref.id,
                title: title,
                coverUrl: Value(coverUrl),
                positionMs: Value(positionMs),
                durationMs: Value(durationMs),
                openedAt: openedAt,
                playCount: const Value<int>(1),
                payload: Value(encoded ?? '{}'),
              ),
            );
      } else {
        // 播放次数只在「新一次播放」递增：首次建行，或从开头重新起播
        // （历史位置已明显靠后时位置回到 ≤1s）。播放中的 10 秒节流写、
        // 暂停/拖动/播完的持久化写都只推进度，不重复计数。
        final restarted = positionMs <= 1000 && existing.positionMs > 1000;
        // 时长未知的早期快照（duration=0）不覆盖已记录的时长，避免投影
        // 从「已听 N%」退化成「听过」。
        final keptDuration = durationMs > 0 ? durationMs : existing.durationMs;
        await (db.update(
          db.musicHistoryEntries,
        )..where((t) => t.id.equals(ref.id))).write(
          MusicHistoryEntriesCompanion(
            title: Value(title),
            coverUrl: Value(coverUrl),
            positionMs: Value(positionMs),
            durationMs: Value(keptDuration),
            openedAt: Value(openedAt),
            playCount: Value(existing.playCount + (restarted ? 1 : 0)),
            // 没有曲目快照时保留旧 payload，别把可重建的数据擦成 '{}'。
            payload: encoded == null ? const Value.absent() : Value(encoded),
          ),
        );
      }
    });
    await syncMusicProjection(db: db, library: library, ref: ref);
    notifyListeners();
    return MusicHistoryItem(
      song: song ?? _songFromValues(ref, title, coverUrl, durationMs),
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      openedAt: openedAt,
    );
  }

  @override
  Future<MusicHistoryItem?> latest(String songId) async {
    final row = await db.historyRow(MusicRef(id: songId));
    return row == null ? null : _fromRow(row);
  }

  /// 最近播放列表，按打开时间倒序（"继续播放"的数据源）。
  @override
  Future<List<MusicHistoryItem>> recent({int limit = 50}) async {
    final rows =
        await (db.select(db.musicHistoryEntries)
              ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
              ..limit(limit))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  MusicHistoryItem _fromRow(MusicHistoryRow row) => MusicHistoryItem(
    song:
        musicSongFromPayload(row.payload) ??
        _songFromValues(
          MusicRef(id: row.id),
          row.title,
          row.coverUrl,
          row.durationMs,
        ),
    position: Duration(milliseconds: row.positionMs),
    duration: Duration(milliseconds: row.durationMs),
    openedAt: row.openedAt,
  );

  MusicSong _songFromValues(
    MusicRef ref,
    String title,
    String? coverUrl,
    int durationMs,
  ) => MusicSong(
    id: ref.id,
    hash: '',
    title: title,
    artists: const <MusicArtistRef>[],
    albumId: '',
    albumTitle: '',
    durationMs: durationMs > 0 ? durationMs : null,
    coverUrl: coverUrl ?? '',
  );
}
