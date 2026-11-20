// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 歌单页（U4）测试替身：fake 用户库 / 歌单读写端点组 / 播放 UI。
///
/// 全部纯内存、无网络、无真实计时器；分页用 fake 侧的 chunkSize 切片模拟，
/// 与 wire 的 page/pageSize/total 回显语义对齐。
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mimao/music/api/import_playlist.dart';
import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/playlist_del.dart';
import 'package:mimao/music/api/playlist_detail.dart';
import 'package:mimao/music/api/playlist_pic_upload.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_sort.dart';
import 'package:mimao/music/api/playlist_track_all.dart';
import 'package:mimao/music/api/playlist_track_all_new.dart';
import 'package:mimao/music/api/playlist_tracks_add.dart';
import 'package:mimao/music/api/playlist_tracks_del.dart';
import 'package:mimao/music/api/playlist_tracks_sort.dart';
import 'package:mimao/music/api/playlist_update.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 用户库替身：`items` 按 [chunkSize] 切片分页，total 恒为 items.length。
/// `error` 非空时每次调用都抛（可测试中途改回 null 验证重试）。
class FakeUserLibraryApi implements MusicUserLibraryApi {
  FakeUserLibraryApi({this.chunkSize = 3, this.error});

  final List<MusicUserPlaylist> items = <MusicUserPlaylist>[];
  final int chunkSize;
  Object? error;
  final List<MusicUserPlaylistQuery> queries = <MusicUserPlaylistQuery>[];

  @override
  Future<MusicUserPlaylists> userPlaylist(MusicUserPlaylistQuery query) async {
    queries.add(query);
    final pending = error;
    if (pending != null) throw pending;
    final start = (query.page - 1) * chunkSize;
    if (start >= items.length) {
      return _page(query, const <MusicUserPlaylist>[]);
    }
    final end = start + chunkSize > items.length
        ? items.length
        : start + chunkSize;
    return _page(query, items.sublist(start, end));
  }

  MusicUserPlaylists _page(
    MusicUserPlaylistQuery query,
    List<MusicUserPlaylist> pageItems,
  ) => MusicUserPlaylists(
    page: MusicPage<MusicUserPlaylist>(
      page: query.page,
      pageSize: query.pageSize,
      total: items.length,
      items: pageItems,
    ),
    userId: 42,
    totalRevision: 1,
    collectionCount: 0,
    albumCount: 0,
  );

  @override
  Future<MusicHistoryPage> userHistory(MusicUserHistoryQuery query) =>
      _unsupported();

  @override
  Future<MusicPreferences> userPreference() => _unsupported();

  @override
  Future<MusicPreferenceAcknowledgement> userPreferenceUpdate(
    MusicPreferenceUpdateQuery query,
  ) => _unsupported();

  @override
  Future<MusicPage<MusicPurchasedAlbum>> userPurchasedAlbums(
    MusicUserPagedQuery query,
  ) => _unsupported();

  @override
  Future<MusicPage<MusicPurchasedSong>> userPurchasedSongs(
    MusicUserPagedQuery query,
  ) => _unsupported();

  @override
  Future<MusicVerifyAcknowledgement> verifyUserInfo(
    MusicVerifyUserInfoQuery query,
  ) => _unsupported();
}

/// 歌单读替身：记录三类查询；页表是「第 N 页 → 条目」的静态切片。
class FakePlaylistReadApi implements MusicPlaylistReadApi {
  FakePlaylistReadApi({
    this.detailError,
    this.trackAllError,
    this.trackAllNewError,
  });

  Object? detailError;
  Object? trackAllError;
  Object? trackAllNewError;

  List<MusicPlaylistDetail> details = const <MusicPlaylistDetail>[];
  List<List<MusicPlaylistTrack>> trackAllPages =
      const <List<MusicPlaylistTrack>>[];
  List<List<MusicPlaylistTrack>> trackAllNewPages =
      const <List<MusicPlaylistTrack>>[];

  final List<MusicPlaylistDetailQuery> detailQueries =
      <MusicPlaylistDetailQuery>[];
  final List<MusicPlaylistTrackAllQuery> trackAllQueries =
      <MusicPlaylistTrackAllQuery>[];
  final List<MusicPlaylistTrackAllNewQuery> trackAllNewQueries =
      <MusicPlaylistTrackAllNewQuery>[];

  @override
  Future<List<MusicPlaylistDetail>> playlistDetail(
    MusicPlaylistDetailQuery query,
  ) async {
    detailQueries.add(query);
    final pending = detailError;
    if (pending != null) throw pending;
    return details;
  }

  @override
  Future<MusicPage<MusicPlaylistTrack>> playlistTrackAll(
    MusicPlaylistTrackAllQuery query,
  ) async {
    trackAllQueries.add(query);
    final pending = trackAllError;
    if (pending != null) throw pending;
    return _trackPage(query.page, query.pageSize, trackAllPages);
  }

  @override
  Future<MusicCloudPlaylistTracks> playlistTrackAllNew(
    MusicPlaylistTrackAllNewQuery query,
  ) async {
    trackAllNewQueries.add(query);
    final pending = trackAllNewError;
    if (pending != null) throw pending;
    return MusicCloudPlaylistTracks(
      page: _trackPage(query.page, query.pageSize, trackAllNewPages),
      cloudListId: query.cloudListId,
    );
  }

  MusicPage<MusicPlaylistTrack> _trackPage(
    int page,
    int pageSize,
    List<List<MusicPlaylistTrack>> pages,
  ) {
    final index = page - 1;
    final pageItems = index >= 0 && index < pages.length
        ? pages[index]
        : const <MusicPlaylistTrack>[];
    final total = pages.fold<int>(
      0,
      (sum, pageItems) => sum + pageItems.length,
    );
    return MusicPage<MusicPlaylistTrack>(
      page: page,
      pageSize: pageSize,
      total: total,
      items: pageItems,
    );
  }

  @override
  Future<List<MusicPlaylistTagCategory>> playlistTags() => _unsupported();

  @override
  Future<MusicImportOutcome> importPlaylist(MusicImportQuery query) =>
      _unsupported();
}

/// 歌单写替身：记录 add/del 入参；onAdd/onDel 让测试在写成功时联动改
/// 用户库替身的数据（模拟服务端生效后的刷新结果）。
class FakePlaylistWriteApi implements MusicPlaylistWriteApi {
  FakePlaylistWriteApi({this.addError, this.delError, this.onAdd, this.onDel});

  Object? addError;
  Object? delError;
  void Function(PlaylistAddQuery query)? onAdd;
  void Function(PlaylistDelQuery query)? onDel;

  final List<PlaylistAddQuery> addQueries = <PlaylistAddQuery>[];
  final List<PlaylistDelQuery> delQueries = <PlaylistDelQuery>[];

  @override
  Future<MusicPlaylistChange> playlistAdd(
    PlaylistAddQuery query, {
    Random? random,
  }) async {
    addQueries.add(query);
    onAdd?.call(query);
    final pending = addError;
    if (pending != null) throw pending;
    return const MusicPlaylistChange(cloudListId: 9001);
  }

  @override
  Future<MusicPlaylistChange> playlistDel(
    PlaylistDelQuery query, {
    String? seed,
    Random? random,
  }) async {
    delQueries.add(query);
    onDel?.call(query);
    final pending = delError;
    if (pending != null) throw pending;
    return const MusicPlaylistChange();
  }

  @override
  Future<MusicPlaylistChange> playlistUpdate(
    PlaylistUpdateQuery query, {
    String? seed,
    Random? random,
  }) => _unsupported();

  @override
  Future<MusicPlaylistOrderChange> playlistSort(
    PlaylistSortQuery query, {
    String? seed,
    Random? random,
  }) => _unsupported();

  @override
  Future<MusicCloudTrackChange> playlistTracksAdd(
    PlaylistTracksAddQuery query,
  ) => _unsupported();

  @override
  Future<MusicCloudTrackChange> playlistTracksDel(
    PlaylistTracksDelQuery query,
  ) => _unsupported();

  @override
  Future<MusicCloudTrackChange> playlistTracksSort(
    PlaylistTracksSortQuery query, {
    String? seed,
    Random? random,
  }) => _unsupported();

  @override
  Future<MusicUploadedPlaylistCover> playlistPicUpload(
    PlaylistPicUploadQuery query,
  ) => _unsupported();
}

/// 播放 UI 替身：记录 playSong；播放页是固定文案锚点（断言 push 生效）。
class FakePlayerUi implements MusicPlayerUi {
  final List<MusicSong> played = <MusicSong>[];

  @override
  Widget? buildMiniPlayer(BuildContext context) => null;

  @override
  Widget buildPlayerPage(BuildContext context) =>
      const Scaffold(body: Center(child: Text('播放页测试锚点')));

  @override
  Future<void> playSong(
    MusicSong song, {
    Duration startAt = Duration.zero,
  }) async {
    played.add(song);
  }

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// 模型工厂（MusicUserPlaylist 构造参数多，收敛在工厂里）。
// ---------------------------------------------------------------------------

MusicUserPlaylist testPlaylist({
  int? cloudListId = 101,
  String globalId = 'g-101',
  String title = '歌单',
  String creatorName = '我',
  int? songCount = 12,
  bool? editable = true,
  bool? isPrivate = false,
  String coverUrl = '',
  MusicCloudPlaylistKind kind = MusicCloudPlaylistKind.owned,
}) => MusicUserPlaylist(
  cloudListId: cloudListId,
  globalId: globalId,
  creatorGlobalId: 'creator-gid',
  title: title,
  descriptionPresent: false,
  tagsPresent: false,
  description: '',
  tags: '',
  coverUrl: coverUrl,
  creatorId: 7,
  creatorName: creatorName,
  creatorListId: 3,
  songCount: songCount,
  revision: 1,
  sortIndex: 0,
  sourceCode: 1,
  kind: kind,
  kindCode: kind == MusicCloudPlaylistKind.owned ? 0 : 1,
  editable: editable,
  private: isPrivate,
  published: null,
  deleted: false,
  dropped: false,
  customCover: false,
  defaultKind: 0,
  flagCodes: const MusicPlaylistFlagCodes(
    editable: 1,
    private: 0,
    published: 0,
    deleted: 0,
    dropped: 0,
    customCover: 0,
  ),
  createdAtSeconds: null,
  updatedAtSeconds: null,
);

MusicPlaylistTrack testTrack({
  String id = '1',
  String title = '曲目',
  String artist = '歌手',
  int? durationMs = 200000,
  String coverUrl = '',
}) => MusicPlaylistTrack(
  song: MusicSong(
    id: id,
    audioId: 9000,
    hash: 'hash-$id-hash-$id-hash-$id-hash',
    title: title,
    artists: <MusicArtistRef>[MusicArtistRef(id: 1, name: artist)],
    albumId: '42',
    albumTitle: '专辑',
    durationMs: durationMs,
    coverUrl: coverUrl,
  ),
  metadata: MusicPlaylistTrackMetadata(sourceFileName: title),
);

MusicPlaylistDetail testDetail({
  String globalId = 'g-9',
  String title = '线上标题',
  String creatorName = '创作者',
  int? songCount = 30,
  String description = '',
}) => MusicPlaylistDetail(
  globalId: globalId,
  title: title,
  description: description,
  coverUrl: '',
  creatorName: creatorName,
  creatorAvatarUrl: '',
  songCount: songCount,
  publishedAt: '',
);

Never _unsupported() => throw UnimplementedError('测试未覆盖该方法');
