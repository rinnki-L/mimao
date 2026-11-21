// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 发现页 widget 测试替身：全部纯内存，不联网、不初始化播放器实现。
///
/// 覆盖页面契约里的每个注入点：MusicSearchExtApi / MusicDiscoveryApi /
/// MusicLyricApi / MusicPlayerUi / MusicCollectApi / MusicSearchHistoryApi，
/// 以及驱动 MusicStore 的 fake MusicApi。失败注入用「剩余失败次数」计数
/// （>0 时抛错并递减），支持「先失败、重试成功」的用例。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mimao/music/api/discovery_api.dart';
import 'package:mimao/music/api/everyday_style_recommend.dart';
import 'package:mimao/music/api/home_discover.dart';
import 'package:mimao/music/api/lyric.dart';
import 'package:mimao/music/api/lyric_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/personal_fm.dart';
import 'package:mimao/music/api/search.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/search_lyric.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/api/sidedt.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/lyric_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:mimao/music/player/player_ui.dart';

// ── 模型工厂 ──────────────────────────────────────────────────────────────

/// 曲目工厂：默认空封面（避免测试碰 Image.network 的真实网络层）。
MusicSong fakeSong({
  String id = '1',
  String hash = 'h1',
  String title = '歌曲',
  String artist = '歌手',
  String album = '专辑',
}) => MusicSong(
  id: id,
  hash: hash,
  title: title,
  artists: <MusicArtistRef>[MusicArtistRef(name: artist)],
  albumId: '9',
  albumTitle: album,
  durationMs: 181000,
  coverUrl: '',
  privilege: 0,
);

/// 发现组曲目工厂（SongSummary + 最小 SongMetadata）。
MusicDiscoverySong fakeDiscoverySong({
  required String id,
  required String hash,
  required String title,
  String artist = '推荐歌手',
  String album = '推荐专辑',
}) => MusicDiscoverySong(
  song: MusicDiscoverySongSummary(
    id: id,
    hash: hash,
    title: title,
    artists: <MusicArtistRef>[MusicArtistRef(name: artist)],
    albumId: '9',
    albumTitle: album,
    durationMs: 200000,
    coverUrl: '',
    privilege: 0,
  ),
  metadata: const MusicDiscoverySongMetadata(
    albumAudioRemark: '',
    sourceFileName: '',
    rights: MusicDiscoveryCatalogRights(),
    resources: <MusicDiscoveryAudioResource>[],
    videos: <MusicDiscoveryVideoReference>[],
    tags: <MusicDiscoverySongTag>[],
    ipTags: <MusicDiscoverySongTag>[],
    recommendation: MusicDiscoveryRecommendationText(
      headline: '',
      detail: '',
      rankLabel: null,
    ),
    artists: <MusicDiscoveryArtistDetail>[],
    relatedVersions: <MusicDiscoveryRelatedVersion>[],
  ),
);

/// FM 单曲工厂。
MusicPersonalFmSong fakeFmSong({
  required String id,
  required String hash,
  required String title,
}) => MusicPersonalFmSong(
  song: fakeDiscoverySong(id: id, hash: hash, title: title, artist: 'FM 歌手'),
  personalFm: const MusicPersonalFmMetadata(
    mark: 'mark',
    similarity: '0.9',
    algorithm: 'alg',
    climaxStartMs: 1000,
    climaxEndMs: 2000,
    climaxDurationMs: 1000,
  ),
);

/// homeDiscover 条目工厂。
MusicDiscoverItem fakeHomeItem({
  required String id,
  required String hash,
  required String title,
}) => MusicDiscoverItem(
  itemId: 'item-$id',
  algPath: 'test',
  startTime: null,
  song: fakeDiscoverySong(id: id, hash: hash, title: title),
);

MusicAlbumSummary fakeAlbum({int? id, String title = '测试专辑'}) =>
    MusicAlbumSummary(
      id: id,
      title: title,
      artists: <MusicArtistRef>[MusicArtistRef(id: 1, name: '专辑歌手')],
      coverUrl: '',
      songCount: 12,
      publishedAt: '2024-01-01',
    );

MusicArtistSummary fakeArtist({int? id, String name = '测试歌手'}) =>
    MusicArtistSummary(id: id, name: name, avatarUrl: '', fans: 99);

MusicPlaylistSummary fakePlaylist({
  String globalId = 'global-1',
  String title = '测试歌单',
}) => MusicPlaylistSummary(
  id: 3,
  globalId: globalId,
  title: title,
  creatorId: 'u1',
  creatorName: '创建者',
  coverUrl: '',
  songCount: 30,
);

MusicLyricHit fakeLyricHit({
  String songId = '77',
  String hash = 'hash77',
  String title = '歌词歌',
  int? lyricId = 3,
  String excerpt = '命中片段',
}) => MusicLyricHit(
  song: fakeSong(id: songId, hash: hash, title: title, artist: '歌词歌手'),
  lyricId: lyricId,
  excerpt: excerpt,
);

MusicLyricCandidate fakeCandidate({
  String sourceId = 'cid',
  String accessKey = 'ak',
}) => MusicLyricCandidate(
  sourceId: sourceId,
  accessKey: accessKey,
  artist: '候选歌手',
  nickname: '上传者',
  title: '候选歌',
  durationMs: 100,
  sourceLabel: '来源',
  language: '中文',
);

MusicSearchPromotion fakePromotion({String title = '默认词A'}) =>
    MusicSearchPromotion(
      id: null,
      title: title,
      mainTitle: '',
      subtitle: '',
      jumpType: '',
      encodedDestination: '',
    );

/// 风格标签工厂（wire 键 `default` → selected 的 0/1 码）。
MusicStyleTag fakeStyleTag({
  required String id,
  required String name,
  int selected = 0,
}) => MusicStyleTag(id: id, name: name, selected: selected);

/// 风格标签组工厂。
MusicStyleTagGroup fakeStyleGroup({
  String name = '风格',
  List<MusicStyleTag> tags = const <MusicStyleTag>[],
}) => MusicStyleTagGroup(name: name, child: tags);

/// 风格推荐响应工厂（标签目录 + 命中歌曲）。
MusicStyleRecommendations fakeStyleRecommendations({
  List<MusicStyleTagGroup> groups = const <MusicStyleTagGroup>[],
  List<MusicDiscoverySong> songs = const <MusicDiscoverySong>[],
}) => MusicStyleRecommendations(songs: songs, groups: groups);

MusicHotSearchGroup fakeHotGroup({
  String title = '飙升榜',
  String keyword = '热词B',
}) => MusicHotSearchGroup(
  title: title,
  keywords: <MusicHotKeyword>[
    MusicHotKeyword(
      keyword: keyword,
      reason: '大家都在搜',
      kind: null,
      icon: null,
      jumpUrl: '',
      jsonUrl: '',
    ),
  ],
);

MusicSuggestionGroup fakeSuggestionGroup({String text = '周杰伦'}) =>
    MusicSuggestionGroup(
      title: '歌曲',
      reportedCount: null,
      items: <MusicSearchSuggestion>[
        MusicSearchSuggestion(
          text: text,
          matches: null,
          heat: null,
          source: '',
          subtitle: '',
          tags: null,
          jump: null,
        ),
      ],
    );

// ── API 替身 ──────────────────────────────────────────────────────────────

/// 搜索扩展组替身；记录调用与最近一次查询参数。
class FakeSearchExtApi implements MusicSearchExtApi {
  FakeSearchExtApi({
    List<MusicSearchPromotion> promotions = const <MusicSearchPromotion>[],
    List<MusicHotSearchGroup> hotGroups = const <MusicHotSearchGroup>[],
    List<MusicSuggestionGroup> suggestionGroups =
        const <MusicSuggestionGroup>[],
    List<MusicAlbumSummary> albums = const <MusicAlbumSummary>[],
    List<MusicArtistSummary> artists = const <MusicArtistSummary>[],
    List<MusicPlaylistSummary> playlists = const <MusicPlaylistSummary>[],
    List<MusicLyricHit> lyricHits = const <MusicLyricHit>[],
    List<MusicLyricCandidate> lyricCandidates = const <MusicLyricCandidate>[],
    this.defaultFailuresLeft = 0,
    this.hotFailuresLeft = 0,
  }) : _promotions = promotions,
       _hotGroups = hotGroups,
       _suggestionGroups = suggestionGroups,
       _albums = albums,
       _artists = artists,
       _playlists = playlists,
       _lyricHits = lyricHits,
       _lyricCandidates = lyricCandidates;

  final List<MusicSearchPromotion> _promotions;
  final List<MusicHotSearchGroup> _hotGroups;
  final List<MusicSuggestionGroup> _suggestionGroups;
  final List<MusicAlbumSummary> _albums;
  final List<MusicArtistSummary> _artists;
  final List<MusicPlaylistSummary> _playlists;
  final List<MusicLyricHit> _lyricHits;
  final List<MusicLyricCandidate> _lyricCandidates;

  /// 失败注入：>0 时抛错并递减（重试可以恢复）。
  int defaultFailuresLeft;
  int hotFailuresLeft;

  int searchDefaultCalls = 0;
  int searchHotCalls = 0;
  int searchAlbumsCalls = 0;
  int searchArtistsCalls = 0;
  int searchPlaylistsCalls = 0;
  int searchLyricsCalls = 0;
  int searchSuggestCalls = 0;
  int searchLyricCalls = 0;

  String lastAlbumKeyword = '';
  String lastArtistKeyword = '';
  String lastPlaylistKeyword = '';
  String lastLyricsKeyword = '';
  String lastSuggestKeyword = '';
  MusicSearchLyricQuery? lastLyricQuery;

  @override
  Future<MusicSearchDefault> searchDefault() async {
    searchDefaultCalls++;
    if (defaultFailuresLeft > 0) {
      defaultFailuresLeft--;
      throw StateError('默认词挂了');
    }
    return MusicSearchDefault(promotions: _promotions);
  }

  @override
  Future<List<MusicHotSearchGroup>> searchHot() async {
    searchHotCalls++;
    if (hotFailuresLeft > 0) {
      hotFailuresLeft--;
      throw StateError('热搜挂了');
    }
    return _hotGroups;
  }

  @override
  Future<MusicPage<MusicAlbumSummary>> searchAlbums(
    SearchSongsQuery query,
  ) async {
    searchAlbumsCalls++;
    lastAlbumKeyword = query.keyword;
    return MusicPage<MusicAlbumSummary>(items: _albums);
  }

  @override
  Future<MusicPage<MusicArtistSummary>> searchArtists(
    SearchSongsQuery query,
  ) async {
    searchArtistsCalls++;
    lastArtistKeyword = query.keyword;
    return MusicPage<MusicArtistSummary>(items: _artists);
  }

  @override
  Future<MusicPage<MusicPlaylistSummary>> searchPlaylists(
    SearchSongsQuery query,
  ) async {
    searchPlaylistsCalls++;
    lastPlaylistKeyword = query.keyword;
    return MusicPage<MusicPlaylistSummary>(items: _playlists);
  }

  @override
  Future<MusicPage<MusicLyricHit>> searchLyrics(SearchSongsQuery query) async {
    searchLyricsCalls++;
    lastLyricsKeyword = query.keyword;
    return MusicPage<MusicLyricHit>(items: _lyricHits);
  }

  @override
  Future<MusicSearchSuggestions> searchSuggest(
    MusicSearchSuggestQuery query,
  ) async {
    searchSuggestCalls++;
    lastSuggestKeyword = query.keyword;
    return MusicSearchSuggestions(groups: _suggestionGroups);
  }

  @override
  Future<List<MusicLyricCandidate>> searchLyric(
    MusicSearchLyricQuery query,
  ) async {
    searchLyricCalls++;
    lastLyricQuery = query;
    return _lyricCandidates;
  }

  @override
  Future<MusicSideDtAcknowledgement> sideDt(MusicSideDtQuery query) async =>
      const MusicSideDtAcknowledgement(acknowledged: false);
}

/// 发现组替身：发现 sections + FM 批次队列 + 风格推荐批次。
class FakeDiscoveryApi implements MusicDiscoveryApi {
  FakeDiscoveryApi({
    List<MusicDiscoverItem> homeItems = const <MusicDiscoverItem>[],
    List<MusicDiscoverySong> dailySongs = const <MusicDiscoverySong>[],
    List<MusicDiscoverySong> aiSongs = const <MusicDiscoverySong>[],
    List<List<MusicPersonalFmSong>> fmBatches =
        const <List<MusicPersonalFmSong>>[],
    List<MusicStyleRecommendations> styleBatches =
        const <MusicStyleRecommendations>[],
    this.homeFailuresLeft = 0,
    this.dailyFailuresLeft = 0,
    this.aiFailuresLeft = 0,
    this.fmFailuresLeft = 0,
    this.styleFailuresLeft = 0,
  }) : _homeItems = homeItems,
       _dailySongs = dailySongs,
       _aiSongs = aiSongs,
       _fmBatches = fmBatches,
       _styleBatches = styleBatches;

  final List<MusicDiscoverItem> _homeItems;
  final List<MusicDiscoverySong> _dailySongs;
  final List<MusicDiscoverySong> _aiSongs;
  final List<List<MusicPersonalFmSong>> _fmBatches;
  final List<MusicStyleRecommendations> _styleBatches;

  int homeFailuresLeft;
  int dailyFailuresLeft;
  int aiFailuresLeft;
  int fmFailuresLeft;
  int styleFailuresLeft;

  int homeDiscoverCalls = 0;
  int dailyCalls = 0;
  int aiCalls = 0;
  int fmCalls = 0;
  int styleCalls = 0;
  int _fmCursor = 0;
  int _styleCursor = 0;
  MusicPersonalFmQuery? lastFmQuery;
  EverydayStyleRecommendQuery? lastStyleQuery;

  @override
  Future<MusicDiscoverRecommendations> homeDiscover(
    HomeDiscoverQuery query,
  ) async {
    homeDiscoverCalls++;
    if (homeFailuresLeft > 0) {
      homeFailuresLeft--;
      throw StateError('首页发现挂了');
    }
    return MusicDiscoverRecommendations(
      items: _homeItems,
      unmappedItems: const <Object?>[],
    );
  }

  @override
  Future<MusicDailyRecommendations> everydayRecommend() async {
    dailyCalls++;
    if (dailyFailuresLeft > 0) {
      dailyFailuresLeft--;
      throw StateError('每日推荐挂了');
    }
    return MusicDailyRecommendations(
      songs: _dailySongs,
      date: '2026-11-21',
      subtitle: '根据你的口味生成',
    );
  }

  @override
  Future<MusicStyleRecommendations> everydayStyleRecommend(
    EverydayStyleRecommendQuery query,
  ) async {
    styleCalls++;
    lastStyleQuery = query;
    if (styleFailuresLeft > 0) {
      styleFailuresLeft--;
      throw StateError('风格推荐挂了');
    }
    if (_styleBatches.isEmpty) {
      return const MusicStyleRecommendations(
        songs: <MusicDiscoverySong>[],
        groups: <MusicStyleTagGroup>[],
      );
    }
    // 每次调用推进一批（首载 → 选标签重取）；越界后停在最后一批，
    // 覆盖「重取回显同一份标签目录」的常见场景。
    final index = _styleCursor < _styleBatches.length
        ? _styleCursor
        : _styleBatches.length - 1;
    _styleCursor++;
    return _styleBatches[index];
  }

  @override
  Future<MusicFreeListenSongs> aiRecommendSongs() async {
    aiCalls++;
    if (aiFailuresLeft > 0) {
      aiFailuresLeft--;
      throw StateError('AI 畅听挂了');
    }
    return MusicFreeListenSongs(songs: _aiSongs, cardInfo: null);
  }

  @override
  Future<MusicPersonalFmSongs> personalFm(MusicPersonalFmQuery query) async {
    fmCalls++;
    lastFmQuery = query;
    if (fmFailuresLeft > 0) {
      fmFailuresLeft--;
      throw StateError('FM 挂了');
    }
    if (_fmBatches.isEmpty) {
      return const MusicPersonalFmSongs(
        songs: <MusicPersonalFmSong>[],
        batchMark: '',
        providerExtension: <String, Object?>{},
      );
    }
    // 每次调用推进一批；「换一批」即再次调用（action 仍为 play）。
    final index = _fmCursor < _fmBatches.length
        ? _fmCursor
        : _fmBatches.length - 1;
    _fmCursor++;
    return MusicPersonalFmSongs(
      songs: _fmBatches[index],
      batchMark: 'batch-$index',
      providerExtension: const <String, Object?>{},
    );
  }

  @override
  Future<List<MusicSongClimaxSegment>> songClimax(String hash) async =>
      const <MusicSongClimaxSegment>[];
}

/// 歌词组替身：返回固定的 base64 文档原文（测试里直接给 base64 串或坏串）。
class FakeLyricApi implements MusicLyricApi {
  FakeLyricApi(this.content, {this.format = 'lrc'});

  final String content;
  final String format;
  final List<MusicLyricDownloadQuery> queries = <MusicLyricDownloadQuery>[];

  @override
  Future<MusicLyricDownload> downloadLyric(
    MusicLyricDownloadQuery query,
  ) async {
    queries.add(query);
    return MusicLyricDownload(
      format: format,
      encoding: 'base64',
      content: content,
    );
  }
}

/// 播放 UI 替身：记录 playSong；播放页给一个可查找的占位。
class FakePlayerUi implements MusicPlayerUi {
  final List<MusicSong> played = <MusicSong>[];

  @override
  Widget? buildMiniPlayer(BuildContext context) => null;

  @override
  Widget buildPlayerPage(BuildContext context) =>
      const Scaffold(body: Center(child: Text('播放页占位')));

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

/// 收藏替身。
class FakeCollectApi implements MusicCollectApi {
  FakeCollectApi({Set<String> initialIds = const <String>{}})
    : ids = Set<String>.of(initialIds);

  final Set<String> ids;
  final List<MusicSong> collected = <MusicSong>[];
  final List<String> removed = <String>[];

  @override
  Future<void> collect(MusicSong song) async => collected.add(song);

  @override
  Future<void> remove(String songId) async => removed.add(songId);

  @override
  Future<bool> isCollected(String songId) async => ids.contains(songId);

  @override
  Future<Set<String>> collectedIds() async => ids.toSet();
}

/// 搜索历史替身。
class FakeSearchHistoryApi implements MusicSearchHistoryApi {
  FakeSearchHistoryApi({List<String> initial = const <String>[]})
    : words = List<String>.of(initial);

  final List<String> words;

  @override
  Future<void> record(String keyword) async => words.add(keyword);

  @override
  Future<List<String>> recent({int limit = 20}) async =>
      List<String>.of(words.take(limit));

  @override
  Future<void> clear() async => words.clear();
}

/// MusicApi 替身（只喂 MusicStore.searchSongs；返回按关键词生成的两首歌）。
class FakeMusicApi implements MusicApi {
  FakeMusicApi({this.throwOnSearch});

  final Object? throwOnSearch;
  int calls = 0;

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    calls++;
    final error = throwOnSearch;
    if (error != null) throw error;
    return MusicPage<MusicSong>(
      items: <MusicSong>[
        fakeSong(id: '101', hash: 'h101', title: '$keyword 之一', artist: '结果歌手'),
        fakeSong(id: '102', hash: 'h102', title: '$keyword 之二', artist: '结果歌手'),
      ],
    );
  }

  @override
  Future<KugouIdentity> ensureDevice() async => const KugouIdentity.empty();

  @override
  Future<KugouIdentity?> currentIdentity() async => null;
}

/// 测试里生成 base64 歌词文档的小工具（歌词正文 → base64）。
String base64Lyric(String text) => base64Encode(utf8.encode(text));
