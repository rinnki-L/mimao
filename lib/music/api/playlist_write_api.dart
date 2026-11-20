/// 歌单写端点组门面——`MusicPlaylistWriteApi` / `KugouPlaylistWriteApi`。
///
/// 覆盖 EchoMusicNext 的 playlist_add / playlist_del / playlist_update /
/// playlist_sort / playlist_tracks_add / playlist_tracks_del /
/// playlist_tracks_sort / playlist_pic_upload 八个写端点；端点实现见各
/// `playlist_*.dart`（一端点一文件）。`seed`/`random` 是信封 seed 的测试
/// 注入缝（生产传缺省），与 register_dev 的同名参数同语义。
library;

import 'dart:math';

import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/playlist_del.dart';
import 'package:mimao/music/api/playlist_pic_upload.dart';
import 'package:mimao/music/api/playlist_sort.dart';
import 'package:mimao/music/api/playlist_tracks_add.dart';
import 'package:mimao/music/api/playlist_tracks_del.dart';
import 'package:mimao/music/api/playlist_tracks_sort.dart';
import 'package:mimao/music/api/playlist_update.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 歌单写端点组接口。
abstract interface class MusicPlaylistWriteApi {
  Future<MusicPlaylistChange> playlistAdd(
    PlaylistAddQuery query, {
    Random? random,
  });

  Future<MusicPlaylistChange> playlistDel(
    PlaylistDelQuery query, {
    String? seed,
    Random? random,
  });

  Future<MusicPlaylistChange> playlistUpdate(
    PlaylistUpdateQuery query, {
    String? seed,
    Random? random,
  });

  Future<MusicPlaylistOrderChange> playlistSort(
    PlaylistSortQuery query, {
    String? seed,
    Random? random,
  });

  Future<MusicCloudTrackChange> playlistTracksAdd(PlaylistTracksAddQuery query);

  Future<MusicCloudTrackChange> playlistTracksDel(PlaylistTracksDelQuery query);

  Future<MusicCloudTrackChange> playlistTracksSort(
    PlaylistTracksSortQuery query, {
    String? seed,
    Random? random,
  });

  Future<MusicUploadedPlaylistCover> playlistPicUpload(
    PlaylistPicUploadQuery query,
  );
}

/// 酷狗实现：薄委托到各端点顶层函数。
class KugouPlaylistWriteApi implements MusicPlaylistWriteApi {
  KugouPlaylistWriteApi(this.session);

  final MusicSession session;

  @override
  Future<MusicPlaylistChange> playlistAdd(
    PlaylistAddQuery query, {
    Random? random,
  }) => fetchPlaylistAdd(session, query, random: random);

  @override
  Future<MusicPlaylistChange> playlistDel(
    PlaylistDelQuery query, {
    String? seed,
    Random? random,
  }) => fetchPlaylistDel(session, query, seed: seed, random: random);

  @override
  Future<MusicPlaylistChange> playlistUpdate(
    PlaylistUpdateQuery query, {
    String? seed,
    Random? random,
  }) => fetchPlaylistUpdate(session, query, seed: seed, random: random);

  @override
  Future<MusicPlaylistOrderChange> playlistSort(
    PlaylistSortQuery query, {
    String? seed,
    Random? random,
  }) => fetchPlaylistSort(session, query, seed: seed, random: random);

  @override
  Future<MusicCloudTrackChange> playlistTracksAdd(
    PlaylistTracksAddQuery query,
  ) => fetchPlaylistTracksAdd(session, query);

  @override
  Future<MusicCloudTrackChange> playlistTracksDel(
    PlaylistTracksDelQuery query,
  ) => fetchPlaylistTracksDel(session, query);

  @override
  Future<MusicCloudTrackChange> playlistTracksSort(
    PlaylistTracksSortQuery query, {
    String? seed,
    Random? random,
  }) => fetchPlaylistTracksSort(session, query, seed: seed, random: random);

  @override
  Future<MusicUploadedPlaylistCover> playlistPicUpload(
    PlaylistPicUploadQuery query,
  ) => fetchPlaylistPicUpload(session, query);
}
