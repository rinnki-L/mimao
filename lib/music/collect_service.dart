import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:mimao/core/library.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_db.dart';
import 'package:mimao/music/music_projection.dart';

/// 一条收藏（权威行 + 可重建的曲目快照）。
class MusicCollectItem {
  const MusicCollectItem({
    required this.ref,
    required this.title,
    required this.coverUrl,
    required this.song,
    required this.collectedAt,
  });

  final MusicRef ref;
  final String title;
  final String? coverUrl;

  /// 收藏时落底的歌曲 JSON 反序列化结果；旧数据/坏数据为 null。
  final MusicSong? song;

  final DateTime collectedAt;

  /// 「我的」页展示用歌手名（无曲目快照时为空串）。
  String get artistText => song?.artistText ?? '';
}

/// 音乐收藏服务（实现 [MusicCollectApi] 的接口缝）。
///
/// 双记账：`music_collect` 是权威；每次写内部表后立即经
/// [syncMusicProjection] 把 `starred` 与公共列投影到统一书架。
///
/// 继承 [ChangeNotifier] 只服务于「我的」页的自动刷新：搜索页收藏后切过去
/// 能立刻看到新条目（服务不是内存状态源，通知不含任何数据）。
class MusicCollectService extends ChangeNotifier implements MusicCollectApi {
  MusicCollectService(this.db, this.library);

  final MusicDb db;
  final LibraryRepository library;

  @override
  Future<void> collect(MusicSong song) {
    return collectRef(
      musicRefOf(song),
      title: song.title,
      coverUrl: song.coverUrl.isEmpty ? null : song.coverUrl,
      song: song,
    );
  }

  /// 收藏（幂等）：已存在则更新元数据并刷新收藏时间。
  Future<void> collectRef(
    MusicRef ref, {
    required String title,
    String? coverUrl,
    MusicSong? song,
    DateTime? collectedAt,
  }) async {
    final at = collectedAt ?? DateTime.now();
    await db
        .into(db.musicCollectEntries)
        .insertOnConflictUpdate(
          MusicCollectEntriesCompanion.insert(
            id: ref.id,
            title: title,
            coverUrl: Value(coverUrl),
            payload: Value(song == null ? '{}' : jsonEncode(song.toJson())),
            collectedAt: at,
          ),
        );
    await syncMusicProjection(db: db, library: library, ref: ref);
    notifyListeners();
  }

  /// 取消收藏（幂等）。内部行删除后仍写最后一笔投影，把 starred 校正为 false；
  /// 若该曲有播放历史，历史行会继续作为投影标题/进度的权威。
  @override
  Future<void> remove(String songId) async {
    final ref = MusicRef(id: songId);
    final existing = await db.collectRow(ref);
    if (existing == null) return;
    await (db.delete(
      db.musicCollectEntries,
    )..where((t) => t.id.equals(ref.id))).go();
    await syncMusicProjection(
      db: db,
      library: library,
      ref: ref,
      fallbackTitle: existing.title,
      fallbackCoverUrl: existing.coverUrl,
      touchedAt: existing.collectedAt,
    );
    notifyListeners();
  }

  @override
  Future<bool> isCollected(String songId) async =>
      await db.collectRow(MusicRef(id: songId)) != null;

  @override
  Future<Set<String>> collectedIds() async {
    final rows = await db.select(db.musicCollectEntries).get();
    return <String>{for (final row in rows) row.id};
  }

  /// 收藏列表，按收藏时间倒序。
  Future<List<MusicCollectItem>> list() async {
    final rows = await (db.select(
      db.musicCollectEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.collectedAt)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  MusicCollectItem _fromRow(MusicCollectRow row) => MusicCollectItem(
    ref: MusicRef(id: row.id),
    title: row.title,
    coverUrl: row.coverUrl,
    song: musicSongFromPayload(row.payload),
    collectedAt: row.collectedAt,
  );
}
