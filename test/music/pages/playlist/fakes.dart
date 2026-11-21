// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 歌单页（U4）测试替身：fake 用户库 / 歌单读写端点组 / 播放 UI。
///
/// 全部纯内存、无网络、无真实计时器；分页用 fake 侧的 chunkSize 切片模拟，
/// 与 wire 的 page/pageSize/total 回显语义对齐。
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

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
import 'package:mimao/music/pages/music_playlist_image_picker.dart';
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

  /// playlistTrackAllNew 回执里的 list_ver（缺省 null，与旧用例行为一致）。
  int? trackAllNewRevision;

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

  // 导入：记录查询对象；onImport 注入按动作分支的 Outcome（可返回未完成
  // 的 Future 模拟慢请求，缺省回任务创建），importError 注入失败。
  final List<MusicImportQuery> importQueries = <MusicImportQuery>[];
  Object? importError;
  Future<MusicImportOutcome> Function(MusicImportQuery query)? onImport;

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
      revision: trackAllNewRevision,
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
  Future<MusicImportOutcome> importPlaylist(MusicImportQuery query) async {
    importQueries.add(query);
    final pending = importError;
    if (pending != null) throw pending;
    final handler = onImport;
    if (handler != null) return handler(query);
    return const MusicImportCreatedOutcome(
      MusicImportTask(taskId: 1, title: '', message: ''),
    );
  }
}

/// 歌单写替身：记录全部八个写端点的入参；onXxx 让测试在写成功时联动改
/// 用户库/曲目替身的数据（模拟服务端生效后的刷新结果）。
class FakePlaylistWriteApi implements MusicPlaylistWriteApi {
  FakePlaylistWriteApi({this.addError, this.delError, this.onAdd, this.onDel});

  Object? addError;
  Object? delError;
  Object? updateError;
  Object? tracksAddError;
  Object? tracksDelError;
  Object? tracksSortError;
  Object? picUploadError;
  Object? sortError;

  /// 排序挂起缝：非空时排序请求挂到它完成（测试 busy 防重用）。
  Completer<MusicCloudTrackChange>? tracksSortHold;
  void Function(PlaylistAddQuery query)? onAdd;
  void Function(PlaylistDelQuery query)? onDel;
  void Function(PlaylistUpdateQuery query)? onUpdate;
  void Function(PlaylistTracksAddQuery query)? onTracksAdd;
  void Function(PlaylistTracksDelQuery query)? onTracksDel;
  void Function(PlaylistTracksSortQuery query)? onTracksSort;
  void Function(PlaylistPicUploadQuery query)? onPicUpload;

  final List<PlaylistAddQuery> addQueries = <PlaylistAddQuery>[];
  final List<PlaylistDelQuery> delQueries = <PlaylistDelQuery>[];
  final List<PlaylistUpdateQuery> updateQueries = <PlaylistUpdateQuery>[];
  final List<PlaylistSortQuery> sortQueries = <PlaylistSortQuery>[];
  final List<PlaylistTracksAddQuery> tracksAddQueries =
      <PlaylistTracksAddQuery>[];
  final List<PlaylistTracksDelQuery> tracksDelQueries =
      <PlaylistTracksDelQuery>[];
  final List<PlaylistTracksSortQuery> tracksSortQueries =
      <PlaylistTracksSortQuery>[];
  final List<PlaylistPicUploadQuery> picQueries = <PlaylistPicUploadQuery>[];

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
  }) async {
    updateQueries.add(query);
    onUpdate?.call(query);
    final pending = updateError;
    if (pending != null) throw pending;
    return const MusicPlaylistChange(
      cloudListId: 9001,
      coverUrl: 'http://imge.kugou.com/cover.png',
    );
  }

  @override
  Future<MusicPlaylistOrderChange> playlistSort(
    PlaylistSortQuery query, {
    String? seed,
    Random? random,
  }) async {
    sortQueries.add(query);
    final pending = sortError;
    if (pending != null) throw pending;
    return const MusicPlaylistOrderChange(
      positions: <MusicPlaylistOrderPosition>[],
    );
  }

  @override
  Future<MusicCloudTrackChange> playlistTracksAdd(
    PlaylistTracksAddQuery query,
  ) async {
    tracksAddQueries.add(query);
    onTracksAdd?.call(query);
    final pending = tracksAddError;
    if (pending != null) throw pending;
    return const MusicCloudTrackChange(songCount: 3);
  }

  @override
  Future<MusicCloudTrackChange> playlistTracksDel(
    PlaylistTracksDelQuery query,
  ) async {
    tracksDelQueries.add(query);
    onTracksDel?.call(query);
    final pending = tracksDelError;
    if (pending != null) throw pending;
    return const MusicCloudTrackChange(songCount: 1);
  }

  @override
  Future<MusicCloudTrackChange> playlistTracksSort(
    PlaylistTracksSortQuery query, {
    String? seed,
    Random? random,
  }) async {
    tracksSortQueries.add(query);
    onTracksSort?.call(query);
    final hold = tracksSortHold;
    if (hold != null) return hold.future;
    final pending = tracksSortError;
    if (pending != null) throw pending;
    return const MusicCloudTrackChange();
  }

  @override
  Future<MusicUploadedPlaylistCover> playlistPicUpload(
    PlaylistPicUploadQuery query,
  ) async {
    picQueries.add(query);
    onPicUpload?.call(query);
    final pending = picUploadError;
    if (pending != null) throw pending;
    return const MusicUploadedPlaylistCover(
      fileName: 'cover-test.png',
      reference: 'custom/cover-test.png',
    );
  }
}

/// 封面图片选择替身：返回预置的内存字节（null 模拟用户取消），
/// 绝不触碰 file_picker 插件。
class FakePlaylistImagePicker implements MusicPlaylistImagePicker {
  FakePlaylistImagePicker({this.bytes, this.error});

  Uint8List? bytes;
  Object? error;
  int calls = 0;

  @override
  Future<Uint8List?> pickPng() async {
    calls++;
    final pending = error;
    if (pending != null) throw pending;
    return bytes;
  }
}

/// 搜索调用记录（keyword + page/pageSize 回显）。
class SongSearchCall {
  const SongSearchCall(this.keyword, this.page, this.pageSize);

  final String keyword;
  final int page;
  final int pageSize;
}

/// 搜索歌曲替身（加歌页注入缝）：页表切片返回，`call` 撕下后即可作为
/// `Future<MusicPage<MusicSong>> Function(String, {page, pageSize})` 注入。
class FakeSongSearch {
  FakeSongSearch({List<List<MusicSong>>? pages, this.error})
    : pages = pages ?? const <List<MusicSong>>[];

  List<List<MusicSong>> pages;
  Object? error;
  final List<SongSearchCall> calls = <SongSearchCall>[];

  Future<MusicPage<MusicSong>> call(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    calls.add(SongSearchCall(keyword, page, pageSize));
    final pending = error;
    if (pending != null) throw pending;
    final index = page - 1;
    final items = index >= 0 && index < pages.length
        ? pages[index]
        : const <MusicSong>[];
    return MusicPage<MusicSong>(
      page: page,
      pageSize: pageSize,
      total: pages.fold<int>(0, (sum, pageItems) => sum + pageItems.length),
      items: items,
    );
  }
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
  int? revision = 1,
  int? sortIndex = 0,
  bool descriptionPresent = false,
  String description = '',
  bool tagsPresent = false,
  String tags = '',
}) => MusicUserPlaylist(
  cloudListId: cloudListId,
  globalId: globalId,
  creatorGlobalId: 'creator-gid',
  title: title,
  descriptionPresent: descriptionPresent,
  tagsPresent: tagsPresent,
  description: description,
  tags: tags,
  coverUrl: coverUrl,
  creatorId: 7,
  creatorName: creatorName,
  creatorListId: 3,
  songCount: songCount,
  revision: revision,
  sortIndex: sortIndex,
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
  int? fileId,
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
  fileId: fileId,
);

/// 搜索结果歌曲（加歌页/加歌流程用）。hash 固定 32 位、albumId/songId
/// 都是可解析整数——与 PlaylistTrackInput 的入参要求对齐。
MusicSong testSong({
  String id = '501',
  String title = '歌曲',
  String artist = '歌手',
  String albumId = '42',
  String albumTitle = '专辑',
  String? hash,
}) => MusicSong(
  id: id,
  audioId: 9000 + int.tryParse(id)!,
  hash: hash ?? 'h$id'.padLeft(32, '0'),
  title: title,
  artists: <MusicArtistRef>[MusicArtistRef(id: 1, name: artist)],
  albumId: albumId,
  albumTitle: albumTitle,
  durationMs: 200000,
  coverUrl: '',
);

/// 构造一段恰好通过 playlist_pic_upload 帧校验的 PNG 字节（签名 +
/// IHDR 长度/类型 + 13 字节 IHDR 数据 + CRC 占位），不读任何真实文件。
Uint8List fakePlaylistPngBytes() => Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG 签名
  0x00, 0x00, 0x00, 0x0D, // IHDR 长度 13
  0x49, 0x48, 0x44, 0x52, // 'IHDR'
  // 13 字节 IHDR 数据（10×10、8bit RGBA），页面/端点都不做图像解码。
  0x00, 0x0A, 0x00, 0x00, 0x00, 0x0A, 0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, // CRC 占位
]);

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
