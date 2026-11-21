// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 榜单页测试夹具：fake [MusicRankApi] + fake [MusicPlayerUi]。
///
/// 全部离线内存实现（立即 resolve，无真实计时器/网络）；fixture 封面留空串，
/// 走页面的音符占位回退，避免 widget 测试触发图片网络加载。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/rank_api.dart';
import 'package:mimao/music/api/rank_audio.dart';
import 'package:mimao/music/api/song_ranking.dart';
import 'package:mimao/music/api/song_ranking_filter.dart';
import 'package:mimao/music/api/top_playlist.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/rank_models.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 榜单目录 fixture（rankList/rankTop 共用；soar 同时出现在两侧用于去重）。
const MusicRank rankSoar = MusicRank(
  id: 101,
  title: '飙升榜',
  coverUrl: '',
  description: '飙升榜简介',
  updateFrequency: '每天更新',
  publishedAt: '2026-11-20',
  category: 1,
);

const MusicRank rankHot = MusicRank(
  id: 102,
  title: '热歌榜',
  coverUrl: '',
  description: '热歌榜简介',
  updateFrequency: '每周更新',
  publishedAt: '2026-11-17',
  category: 1,
);

const MusicRank rankTopOnly = MusicRank(
  id: 103,
  title: '新歌推荐榜',
  coverUrl: '',
  description: '新歌推荐榜简介',
  updateFrequency: '每天更新',
  publishedAt: '2026-11-21',
  category: 2,
);

/// 详情页用的榜单（id 存在）与无 id 榜单（wire rankid 不可解析的兜底路径）。
const MusicRank rankWithId = rankSoar;

const MusicRank rankNoId = MusicRank(
  title: '无名榜',
  coverUrl: '',
  description: '',
  updateFrequency: '',
  publishedAt: null,
  category: null,
);

/// 榜单歌曲目录元数据最小对象（页面只消费 ranking/relatedVersions）。
MusicRankSongMetadata _meta({MusicRankPosition? ranking}) {
  return MusicRankSongMetadata(
    albumAudioRemark: '',
    sourceFileName: '',
    rights: const MusicRankCatalogRights(),
    resources: const <MusicRankResource>[],
    videos: const <MusicRankVideoReference>[],
    recommendation: const MusicRankRecommendationText(headline: ''),
    artists: const <MusicRankArtistDetail>[],
    relatedVersions: const <MusicRankRelatedVersion>[],
    ranking: ranking,
  );
}

/// 共享 MusicSong fixture（封面空串 → 音符占位，不触网）。
MusicSong testSong(
  String id,
  String title, {
  String artist = '',
  String album = '',
  int? durationMs,
}) {
  return MusicSong(
    id: id,
    audioId: 1,
    hash: 'hash-$id',
    title: title,
    artists: artist.isEmpty
        ? const <MusicArtistRef>[]
        : <MusicArtistRef>[MusicArtistRef(name: artist)],
    albumId: 'album-$id',
    albumTitle: album,
    coverUrl: '',
    durationMs: durationMs,
  );
}

/// rankAudio fixture：歌一（榜内位 1）、歌二（榜内位 7，验证取 ranking）、
/// 歌三（无 ranking，验证退回列表序号）。
List<MusicRankSong> rankAudioSongs() {
  return <MusicRankSong>[
    MusicRankSong(
      song: testSong(
        '9001',
        '榜单歌一',
        artist: '歌手甲',
        album: '专辑甲',
        durationMs: 213000,
      ),
      metadata: _meta(
        ranking: MusicRankPosition(
          rankId: '101',
          issue: '20261121',
          position: 1,
          publishedAt: '2026-11-21',
        ),
      ),
    ),
    MusicRankSong(
      song: testSong(
        '9002',
        '榜单歌二',
        artist: '歌手乙',
        album: '专辑乙',
        durationMs: 245000,
      ),
      metadata: _meta(
        ranking: MusicRankPosition(
          rankId: '101',
          issue: '20261121',
          position: 7,
          publishedAt: '2026-11-21',
        ),
      ),
    ),
    MusicRankSong(
      song: testSong(
        '9003',
        '榜单歌三',
        artist: '歌手丙',
        album: '专辑丙',
        durationMs: 187000,
      ),
      metadata: _meta(),
    ),
  ];
}

/// 新歌 fixture（chart.position 与列表序号不同，验证取 chart）。
List<MusicRankNewSong> newSongs() {
  return <MusicRankNewSong>[
    MusicRankNewSong(
      song: testSong(
        '8001',
        '新歌一',
        artist: '歌手丁',
        album: '专辑丁',
        durationMs: 200000,
      ),
      metadata: MusicRankNewSongMetadata(
        catalog: _meta(),
        chart: MusicRankSongChart(
          rankId: '21608',
          issue: '20261121',
          position: 5,
        ),
        defaultAliasCodes: const <int?>[0],
      ),
    ),
  ];
}

/// 新碟 fixture：华语/欧洲各有 1 张，日本/韩国分组为空（空分组不渲染标题）。
MusicTopAlbums topAlbumsFixture() {
  MusicTopAlbumCard card(String id, String title, String creator) {
    return MusicTopAlbumCard(
      id: id,
      title: title,
      creator: creator,
      coverUrl: '',
      songCount: 10,
      publishedAt: '2026-11-01',
      metadata: const MusicTopAlbumMetadata(description: '', specialTag: ''),
    );
  }

  return MusicTopAlbums(
    regions: <String, List<MusicTopAlbumCard>>{
      'chn': <MusicTopAlbumCard>[card('1', '华语新碟一', '华语歌手')],
      'eur': <MusicTopAlbumCard>[card('2', '欧洲新碟一', '欧洲歌手')],
      'jpn': const <MusicTopAlbumCard>[],
      'kor': const <MusicTopAlbumCard>[],
    },
  );
}

/// 榜单歌单/IP 卡片 fixture。
MusicRankPlaylistCard playlistCard(String id, String title, {int? playCount}) {
  return MusicRankPlaylistCard(
    id: id,
    title: title,
    creator: '创建者$id',
    coverUrl: '',
    metadata: MusicRankPlaylistMetadata(playCount: playCount),
  );
}

/// fake 榜单 API：记录调用与关键入参；`failures` 按「端点名 → 失败队列」
/// 逐次消费，队列耗尽后恢复成功（支持「只失败一次、重试成功」）。
class FakeRankApi implements MusicRankApi {
  FakeRankApi({
    Map<String, List<Object>> failures = const <String, List<Object>>{},
    this.rankAudioEmpty = false,
  }) : _failures = <String, List<Object>>{
         for (final entry in failures.entries)
           entry.key: <Object>[...entry.value],
       };

  final Map<String, List<Object>> _failures;

  /// rankAudio 返回空列表（空态用）。
  final bool rankAudioEmpty;

  /// 已调用的端点名（按调用顺序）。
  final List<String> calls = <String>[];

  final List<int> rankAudioRankIds = <int>[];
  final List<String> topPlaylistCategoryIds = <String>[];

  void _record(String method) {
    calls.add(method);
    final queue = _failures[method];
    if (queue != null && queue.isNotEmpty) {
      throw queue.removeAt(0);
    }
  }

  @override
  Future<List<MusicRank>> rankList() async {
    _record('rankList');
    return const <MusicRank>[rankSoar, rankHot];
  }

  @override
  Future<List<MusicRank>> rankTop() async {
    _record('rankTop');
    return const <MusicRank>[rankSoar, rankTopOnly];
  }

  @override
  Future<MusicRankSongs> rankAudio(MusicRankAudioQuery query) async {
    // 入参在失败判定前记录：失败的调用同样计入（断言「发过请求」）。
    rankAudioRankIds.add(query.rankId);
    _record('rankAudio');
    return MusicRankSongs(
      total: 3,
      songs: rankAudioEmpty ? const <MusicRankSong>[] : rankAudioSongs(),
    );
  }

  @override
  Future<MusicSongRanking> songRanking(MusicSongRankingQuery query) async {
    _record('songRanking');
    return const MusicSongRanking();
  }

  @override
  Future<MusicSongRankingFilter> songRankingFilter(
    MusicSongRankingFilterQuery query,
  ) async {
    _record('songRankingFilter');
    return const MusicSongRankingFilter();
  }

  @override
  Future<MusicTopAlbums> topAlbums() async {
    _record('topAlbums');
    return topAlbumsFixture();
  }

  @override
  Future<List<MusicRankPlaylistCard>> topIps() async {
    _record('topIps');
    return <MusicRankPlaylistCard>[playlistCard('900', 'IP 榜单一')];
  }

  @override
  Future<List<MusicRankPlaylistCard>> topPlaylists(
    MusicTopPlaylistQuery query,
  ) async {
    topPlaylistCategoryIds.add(query.categoryId);
    _record('topPlaylists');
    return <MusicRankPlaylistCard>[
      playlistCard('801', '推荐歌单一', playCount: 12345),
    ];
  }

  @override
  Future<MusicRankNewSongs> topSongs() async {
    _record('topSongs');
    return MusicRankNewSongs(total: 1, songs: newSongs());
  }
}

/// fake 播放 UI：记录 playSong/playList 的曲目与播放页构建次数。
class FakePlayerUi implements MusicPlayerUi {
  final List<MusicSong> played = <MusicSong>[];
  final List<List<MusicSong>> playedLists = <List<MusicSong>>[];
  final List<int> playedListStartIndexes = <int>[];
  final List<Duration> playedListStartAts = <Duration>[];
  int playerPageBuilds = 0;

  @override
  Widget? buildMiniPlayer(BuildContext context) => null;

  @override
  Widget buildPlayerPage(BuildContext context) {
    playerPageBuilds++;
    return const Scaffold(body: Center(child: Text('播放页测试桩')));
  }

  @override
  Future<void> playSong(
    MusicSong song, {
    Duration startAt = Duration.zero,
  }) async {
    played.add(song);
  }

  @override
  Future<void> playList(
    List<MusicSong> songs, {
    int startIndex = 0,
    Duration startAt = Duration.zero,
  }) async {
    playedLists.add(songs);
    playedListStartIndexes.add(startIndex);
    playedListStartAts.add(startAt);
  }

  @override
  void dispose() {}
}
