/// 歌单读端点组门面——playlist_detail / playlist_track_all /
/// playlist_track_all_new / playlist_tags / import_playlist 五个端点的
/// 组接口与酷狗实现（docs/music-api-expansion.md §4/§5）。
///
/// 端点翻译分文件维护；本文件只做接口声明与 `MusicSession` 装配，
/// 供集成者组合进 `KugouMusicApi`。
library;

import 'package:mimao/music/api/import_playlist.dart';
import 'package:mimao/music/api/playlist_detail.dart';
import 'package:mimao/music/api/playlist_tags.dart';
import 'package:mimao/music/api/playlist_track_all.dart';
import 'package:mimao/music/api/playlist_track_all_new.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';

/// 歌单读组接口（只读；歌单写端点由 G8 的 MusicPlaylistWriteApi 负责）。
abstract interface class MusicPlaylistReadApi {
  /// 公开歌单详情（批量，最多 100 个 global_collection_id）。
  Future<List<MusicPlaylistDetail>> playlistDetail(
    MusicPlaylistDetailQuery query,
  );

  /// 公开歌单曲目分页（1..=200）。
  Future<MusicPage<MusicPlaylistTrack>> playlistTrackAll(
    MusicPlaylistTrackAllQuery query,
  );

  /// 账号云歌单曲目分页（1..=300；必须账号）。
  Future<MusicCloudPlaylistTracks> playlistTrackAllNew(
    MusicPlaylistTrackAllNewQuery query,
  );

  /// 歌单标签分类树（children 一层）。
  Future<List<MusicPlaylistTagCategory>> playlistTags();

  /// 歌单导入（链接/截图/状态/明细/计数，按动作返回对应 Outcome）。
  Future<MusicImportOutcome> importPlaylist(MusicImportQuery query);
}

/// 酷狗实现：把组方法映射到各端点的顶层 fetchXxx。
class KugouPlaylistReadApi implements MusicPlaylistReadApi {
  KugouPlaylistReadApi(this.session);

  final MusicSession session;

  @override
  Future<List<MusicPlaylistDetail>> playlistDetail(
    MusicPlaylistDetailQuery query,
  ) => fetchPlaylistDetail(session, query);

  @override
  Future<MusicPage<MusicPlaylistTrack>> playlistTrackAll(
    MusicPlaylistTrackAllQuery query,
  ) => fetchPlaylistTrackAll(session, query);

  @override
  Future<MusicCloudPlaylistTracks> playlistTrackAllNew(
    MusicPlaylistTrackAllNewQuery query,
  ) => fetchPlaylistTrackAllNew(session, query);

  @override
  Future<List<MusicPlaylistTagCategory>> playlistTags() =>
      fetchPlaylistTags(session);

  @override
  Future<MusicImportOutcome> importPlaylist(MusicImportQuery query) =>
      fetchImportPlaylist(session, query);
}
