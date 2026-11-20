// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// U3 目录详情页测试的 fake 与最小 fixture：不联网、无真实计时器
/// （gate 用 Completer 手工放行）。只实现页面消费的接口。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/music/api/album_api.dart';
import 'package:mimao/music/api/album_dycover.dart';
import 'package:mimao/music/api/album_songs.dart';
import 'package:mimao/music/api/artist_albums.dart';
import 'package:mimao/music/api/artist_api.dart';
import 'package:mimao/music/api/artist_audios_new.dart';
import 'package:mimao/music/api/artist_lists.dart';
import 'package:mimao/music/models/album_models.dart';
import 'package:mimao/music/models/artist_models.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/player/player_ui.dart';

// ── FakeAlbumApi ────────────────────────────────────────────────────────

/// 专辑组 fake：记录分页请求页码；`gateSongsPage(page)` 可挂起某页的
/// 返回（Completer），用于断言「请求中防重复」。
class FakeAlbumApi implements MusicAlbumApi {
  FakeAlbumApi({
    this.detail,
    this.detailError,
    this.songsPages = const <int, MusicAlbumTracks>{},
    this.songsError,
    this.dycoverError,
    this.favoriteCounts = const <MusicAlbumFavoriteCount>[],
  });

  MusicAlbumDetail? detail;
  Object? detailError;
  Map<int, MusicAlbumTracks> songsPages;
  Object? songsError;
  Object? dycoverError;
  List<MusicAlbumFavoriteCount> favoriteCounts;

  /// 按到达顺序记录 albumSongs 的页码。
  final List<int> songsPageLog = <int>[];
  final List<AlbumDycoverQuery> dycoverLog = <AlbumDycoverQuery>[];
  final List<List<int>> favoriteLog = <List<int>>[];

  final Map<int, Completer<MusicAlbumTracks>> _songGates =
      <int, Completer<MusicAlbumTracks>>{};

  /// 挂起某页请求：albumSongs 返回未完成的 Future，直到 [completeSongsPage]。
  void gateSongsPage(int page) {
    _songGates.putIfAbsent(page, Completer<MusicAlbumTracks>.new);
  }

  void completeSongsPage(int page) {
    final gate = _songGates.remove(page);
    if (gate != null) {
      gate.complete(
        songsPages[page] ??
            const MusicAlbumTracks(
              page: MusicPage<MusicAlbumTrack>(items: <MusicAlbumTrack>[]),
            ),
      );
    }
  }

  @override
  Future<MusicAlbumDetail?> albumDetail(int id) async {
    final error = detailError;
    if (error != null) throw error;
    return detail;
  }

  @override
  Future<MusicAlbumTracks> albumSongs(AlbumSongsQuery query) async {
    songsPageLog.add(query.page);
    final gate = _songGates[query.page];
    if (gate != null) return gate.future;
    final error = songsError;
    if (error != null) throw error;
    return songsPages[query.page] ??
        MusicAlbumTracks(
          page: MusicPage<MusicAlbumTrack>(
            page: query.page,
            pageSize: query.pageSize,
            total: 0,
            items: const <MusicAlbumTrack>[],
          ),
        );
  }

  @override
  Future<MusicAlbumDynamicCover?> albumDycover(AlbumDycoverQuery query) async {
    dycoverLog.add(query);
    final error = dycoverError;
    if (error != null) throw error;
    return null;
  }

  @override
  Future<List<MusicAlbumFavoriteCount>> favoriteCount(List<int> ids) async {
    favoriteLog.add(ids);
    return favoriteCounts;
  }
}

// ── FakeArtistApi ───────────────────────────────────────────────────────

/// 歌手组 fake：记录专辑/歌曲分页页码与目录查询参数。
class FakeArtistApi implements MusicArtistApi {
  FakeArtistApi({
    this.detail,
    this.detailError,
    this.albumsPages = const <int, MusicPage<MusicAlbumSummary>>{},
    this.albumsError,
    this.songsPages = const <int, MusicPage<MusicArtistSong>>{},
    this.songsError,
    this.listsError,
    this.lists,
  });

  MusicArtistDetail? detail;
  Object? detailError;
  Map<int, MusicPage<MusicAlbumSummary>> albumsPages;
  Object? albumsError;
  Map<int, MusicPage<MusicArtistSong>> songsPages;
  Object? songsError;
  Object? listsError;
  MusicArtistDirectory? lists;

  final List<int> albumsPageLog = <int>[];
  final List<int> songsPageLog = <int>[];
  final List<MusicArtistListsQuery> listsLog = <MusicArtistListsQuery>[];

  @override
  Future<MusicArtistDetail?> artistDetail(int id) async {
    final error = detailError;
    if (error != null) throw error;
    return detail;
  }

  @override
  Future<MusicPage<MusicAlbumSummary>> artistAlbums(
    MusicArtistAlbumsQuery query,
  ) async {
    albumsPageLog.add(query.page);
    final error = albumsError;
    if (error != null) throw error;
    return albumsPages[query.page] ??
        MusicPage<MusicAlbumSummary>(
          page: query.page,
          pageSize: query.pageSize,
          total: 0,
          items: const <MusicAlbumSummary>[],
        );
  }

  @override
  Future<MusicPage<MusicArtistSong>> artistAudiosNew(
    MusicArtistAudiosQuery query,
  ) async {
    songsPageLog.add(query.page);
    final error = songsError;
    if (error != null) throw error;
    return songsPages[query.page] ??
        MusicPage<MusicArtistSong>(
          page: query.page,
          pageSize: query.pageSize,
          total: 0,
          items: const <MusicArtistSong>[],
        );
  }

  @override
  Future<MusicArtistDirectory> artistLists(MusicArtistListsQuery query) async {
    listsLog.add(query);
    final error = listsError;
    if (error != null) throw error;
    return lists ??
        const MusicArtistDirectory(
          groups: <MusicArtistGroup>[],
          sexFilters: <MusicArtistFilter>[],
          typeFilters: <MusicArtistFilter>[],
        );
  }
}

// ── FakePlayerUi ────────────────────────────────────────────────────────

/// 播放 UI fake：记录 playSong 的曲目；播放页给可识别的标记文本。
class FakePlayerUi implements MusicPlayerUi {
  final List<MusicSong> played = <MusicSong>[];

  @override
  Widget? buildMiniPlayer(BuildContext context) => null;

  @override
  Widget buildPlayerPage(BuildContext context) =>
      const Scaffold(body: Center(child: Text('fake-player')));

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

// ── Fixtures ────────────────────────────────────────────────────────────

MusicAlbumDetail albumDetailFixture({
  String title = '测试专辑',
  List<MusicArtistRef>? artists,
  String coverUrl = '',
  String publishedAt = '2024-01-01',
}) => MusicAlbumDetail(
  id: 7,
  title: title,
  artists:
      artists ?? const <MusicArtistRef>[MusicArtistRef(id: 42, name: '歌手A')],
  coverUrl: coverUrl,
  publishedAt: publishedAt,
  publisher: '发行厂牌',
  description: '这是一张测试专辑的简介。',
  language: '国语',
  category: '流行',
);

/// 专辑曲目 fixture：disc/position 默认递增；coverUrl 留空走占位（测试不联网）。
MusicAlbumTrack albumTrackFixture(
  int position, {
  String title = '曲目',
  String songId = 'song-1',
  int disc = 1,
}) => MusicAlbumTrack(
  song: MusicSong(
    id: songId,
    hash: 'hash-$songId',
    title: title,
    artists: const <MusicArtistRef>[MusicArtistRef(id: 42, name: '歌手A')],
    albumId: '7',
    albumTitle: '测试专辑',
    durationMs: 213000,
    coverUrl: '',
  ),
  metadata: MusicCatalogSongFacts(resources: const <MusicAudioResource>[]),
  disc: disc,
  position: position,
);

MusicAlbumTracks tracksPage(
  int page, {
  int? total,
  List<MusicAlbumTrack> tracks = const <MusicAlbumTrack>[],
}) => MusicAlbumTracks(
  page: MusicPage<MusicAlbumTrack>(
    page: page,
    pageSize: 30,
    total: total,
    items: tracks,
  ),
  discCount: 1,
);

MusicAlbumSummary albumSummaryFixture(int id, String title) =>
    MusicAlbumSummary(
      id: id,
      title: title,
      artists: const <MusicArtistRef>[MusicArtistRef(id: 5, name: '歌手B')],
      coverUrl: '',
      publishedAt: '2023-06-01',
    );

MusicPage<MusicAlbumSummary> albumsPage(
  int page, {
  int? total,
  List<MusicAlbumSummary> albums = const <MusicAlbumSummary>[],
}) => MusicPage<MusicAlbumSummary>(
  page: page,
  pageSize: 30,
  total: total,
  items: albums,
);

MusicArtistDetail artistDetailFixture({String name = '歌手B'}) =>
    MusicArtistDetail(
      id: 5,
      name: name,
      avatarUrl: '',
      description: '这是一位测试歌手的简介。',
      birthday: '1990-01-01',
      fans: 1234,
      albumCount: 2,
      mvCount: 1,
    );

/// 歌手歌曲 fixture（平铺结构）：durationMs 毫秒原样透传。
MusicArtistSong artistSongFixture({
  String id = 'as-1',
  String title = '热门歌',
  String? albumTitle = '专辑甲',
}) => MusicArtistSong(
  id: id,
  hash: 'hash-$id',
  title: title,
  artists: const <MusicArtistRef>[MusicArtistRef(id: 5, name: '歌手B')],
  albumId: '10',
  albumTitle: albumTitle,
  durationMs: 224000,
  coverUrl: '',
  metadata: const MusicArtistSongFacts(resources: <MusicAudioResource>[]),
);

MusicPage<MusicArtistSong> artistSongsPage(
  int page, {
  int? total,
  List<MusicArtistSong> songs = const <MusicArtistSong>[],
}) => MusicPage<MusicArtistSong>(
  page: page,
  pageSize: 30,
  total: total,
  items: songs,
);

/// 带一组性别筛选与两个分组的目录（供筛选 chip 测试）。
MusicArtistDirectory directoryFixture() => MusicArtistDirectory(
  groups: <MusicArtistGroup>[
    MusicArtistGroup(
      label: '华语男歌手',
      artists: <MusicArtistCard>[
        MusicArtistCard(
          id: '5',
          title: '目录歌手甲',
          creator: '',
          coverUrl: '',
          metadata: const MusicArtistCardMetadata(
            introduction: '',
            dynamicFrameUrl: '',
          ),
        ),
      ],
    ),
  ],
  sexFilters: <MusicArtistFilter>[
    const MusicArtistFilter(id: '0', label: '全部', category: 0, musician: 0),
    const MusicArtistFilter(id: '1', label: '男歌手', category: 1, musician: 0),
  ],
  typeFilters: <MusicArtistFilter>[
    const MusicArtistFilter(id: '0', label: '全部', category: 0, musician: 0),
    const MusicArtistFilter(id: '3', label: '音乐人', category: 0, musician: 3),
  ],
);
