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
import 'package:mimao/music/api/images_audio.dart';
import 'package:mimao/music/api/krm_audio.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/api/privilege_lite.dart';
import 'package:mimao/music/models/album_models.dart'
    hide MusicPreviewRange; // 预览区间用播放补全组自己的版本
import 'package:mimao/music/models/artist_models.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
// 与 album_models 同名重合的目录事实类保留 album_models 版（曲目 metadata
// 用的是它），只放行播放补全组自己的差量模型。
import 'package:mimao/music/models/playback_ext_models.dart'
    hide
        MusicCatalogSongFacts,
        MusicCatalogRights,
        MusicEncodedMap,
        MusicQualityMap,
        MusicVoiceAd;
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

// ── FakePlaybackExtApi（L6：权益/资料/歌手图片）────────────────────────

/// 播放补全组 fake：记录三段查询入参。
class FakePlaybackExtApi implements MusicPlaybackExtApi {
  FakePlaybackExtApi({
    this.privileges = const <MusicResourcePrivileges>[],
    this.privilegeError,
    this.presentations = const <MusicSongPresentation>[],
    this.krmError,
    this.portraitGroups = const <List<MusicAuthorImages>>[],
    this.imagesError,
  });

  List<MusicResourcePrivileges> privileges;
  Object? privilegeError;
  List<MusicSongPresentation> presentations;
  Object? krmError;
  List<List<MusicAuthorImages>> portraitGroups;
  Object? imagesError;

  final List<PrivilegeLiteQuery> privilegeLog = <PrivilegeLiteQuery>[];
  final List<KrmAudioQuery> krmLog = <KrmAudioQuery>[];
  final List<ImagesAudioQuery> imagesLog = <ImagesAudioQuery>[];

  @override
  Future<List<MusicResourcePrivileges>> privilegeLite(
    PrivilegeLiteQuery query,
  ) async {
    privilegeLog.add(query);
    final error = privilegeError;
    if (error != null) throw error;
    return privileges;
  }

  @override
  Future<List<List<MusicAuthorImages>>> imagesAudio(
    ImagesAudioQuery query,
  ) async {
    imagesLog.add(query);
    final error = imagesError;
    if (error != null) throw error;
    return portraitGroups;
  }

  @override
  Future<List<MusicSongPresentation>> krmAudio(KrmAudioQuery query) async {
    krmLog.add(query);
    final error = krmError;
    if (error != null) throw error;
    return presentations;
  }
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
/// `hash`/`audioId` 供 L6 资料面板测试传入合法值（默认沿用旧的无意义值）。
MusicAlbumTrack albumTrackFixture(
  int position, {
  String title = '曲目',
  String songId = 'song-1',
  int disc = 1,
  String? hash,
  int? audioId,
}) => MusicAlbumTrack(
  song: MusicSong(
    id: songId,
    audioId: audioId,
    hash: hash ?? 'hash-$songId',
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
/// `hash` 供 L6 歌手写真测试传入合法值（默认沿用旧的无意义值）。
MusicArtistSong artistSongFixture({
  String id = 'as-1',
  String title = '热门歌',
  String? albumTitle = '专辑甲',
  String? hash,
}) => MusicArtistSong(
  id: id,
  hash: hash ?? 'hash-$id',
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

// ── L6 播放补全 fixtures：权益 / 资料 / 歌手图片 ──────────────────────

/// 32 位合法 hash（页面以它判断「要不要发起查询」）。
const String kValidHash = 'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';

/// 权益档位 fixture（上游不解释位义，页面只展示码值事实）。
MusicQualityVariant qualityVariantFixture({
  String quality = '128',
  int? bitRateBps = 128000,
  String extension = 'mp3',
}) => MusicQualityVariant(
  message: '',
  errorCode: null,
  hash: kValidHash,
  quality: quality,
  level: null,
  privilege: null,
  serviceStatus: 1,
  failureCode: null,
  paymentType: 0,
  priceUnits: null,
  durationMs: 213000,
  sizeBytes: 3400000,
  bitRateBps: bitRateBps,
  extension: extension,
  coverUrl: '',
);

/// 权益资源 fixture：默认 flac 主档位 + 320 音质行 + 预览区间 0:30–1:00。
MusicResourcePrivileges privilegeFixture({
  String quality = 'flac',
  int? bitRateBps = 900000,
  String extension = 'flac',
  int? resourceError,
  String resourceMessage = '',
  MusicPreviewRange? preview = const MusicPreviewRange(
    startMs: 30000,
    endMs: 60000,
  ),
  List<MusicQualityVariant> variants = const <MusicQualityVariant>[
    MusicQualityVariant(
      message: '',
      errorCode: null,
      hash: kValidHash,
      quality: '320',
      level: null,
      privilege: null,
      serviceStatus: 1,
      failureCode: null,
      paymentType: 0,
      priceUnits: null,
      durationMs: 213000,
      sizeBytes: 8500000,
      bitRateBps: 320000,
      extension: 'mp3',
      coverUrl: '',
    ),
  ],
}) => MusicResourcePrivileges(
  id: null,
  albumId: '7',
  songId: 9001,
  hash: kValidHash,
  displayName: '曲目一',
  artistText: '歌手A',
  albumTitle: '测试专辑',
  primary: qualityVariantFixture(
    quality: quality,
    bitRateBps: bitRateBps,
    extension: extension,
  ),
  variants: variants,
  oggStandard: null,
  oggHigh: null,
  preview: preview,
  qualityMap: null,
  resourceError: resourceError,
  resourceMessage: resourceMessage,
  language: '',
  presentationExtension: const <String, Object?>{},
);

/// 资料包 fixture：默认词曲/语言/发行/BPM 齐全（空字段场景逐个传空串）。
MusicSongPresentation presentationFixture({
  String id = '9001',
  String lyricist = '词人甲',
  String composer = '作曲乙',
  String language = '国语',
  String publishedAt = '2024-01-01',
  double? bpm = 96,
}) => MusicSongPresentation(
  id: id,
  title: '曲目一',
  albumId: '7',
  albumTitle: '测试专辑',
  coverUrl: '',
  artists: const <MusicPresentationArtist>[],
  information: MusicSongInformation(
    publishedAt: publishedAt,
    albumPublishedAt: null,
    language: language,
    lyricist: lyricist,
    composer: composer,
    bpm: bpm,
    tempoCode: null,
    tempoDescription: null,
  ),
);

/// 歌手写真 fixture：一个歌手、count 张带 https 地址的写真
///（url 用保留域名——widget 测试里网络请求不会真正完成，走占位/回退）。
List<List<MusicAuthorImages>> portraitGroupsFixture({int count = 2}) =>
    <List<MusicAuthorImages>>[
      <MusicAuthorImages>[
        MusicAuthorImages(
          artistId: '5',
          name: '歌手B',
          publishStatus: 1,
          resourceHash: kValidHash,
          avatar: '',
          avatarUrl: '',
          audioPublishDate: '',
          images: <String, List<MusicPortrait>>{
            'user': <MusicPortrait>[
              for (var i = 0; i < count; i++)
                MusicPortrait(
                  id: 'p$i',
                  fileHash: kValidHash,
                  url: 'https://img.example.com/portrait-$i.jpg',
                  filename: '写真$i.jpg',
                  publishTime: '',
                  source: null,
                ),
            ],
          },
        ),
      ],
    ];
