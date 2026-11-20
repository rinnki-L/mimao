/// 榜单端点组接口——docs/music-api-expansion.md §5 G3：
/// `MusicRankApi` + `KugouRankApi`（rank_list / rank_top / rank_audio /
/// song_ranking / song_ranking_filter / top_album / top_ip / top_playlist /
/// top_song 共 9 个端点的组门面）。
library;

import 'package:mimao/music/api/rank_audio.dart';
import 'package:mimao/music/api/rank_list.dart';
import 'package:mimao/music/api/rank_top.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/song_ranking.dart';
import 'package:mimao/music/api/song_ranking_filter.dart';
import 'package:mimao/music/api/top_album.dart';
import 'package:mimao/music/api/top_ip.dart';
import 'package:mimao/music/api/top_playlist.dart';
import 'package:mimao/music/api/top_song.dart';
import 'package:mimao/music/models/rank_models.dart';

/// 榜单组端点集合（集成者把本接口组合进 KugouMusicApi）。
abstract interface class MusicRankApi {
  /// 排行榜总目录（rank_list.rs）。
  Future<List<MusicRank>> rankList();

  /// 推荐榜单（rank_top.rs）。
  Future<List<MusicRank>> rankTop();

  /// 榜单歌曲列表（rank_audio.rs）。
  Future<MusicRankSongs> rankAudio(MusicRankAudioQuery query);

  /// 播放页歌曲排名成就（song_ranking.rs）。
  Future<MusicSongRanking> songRanking(MusicSongRankingQuery query);

  /// 播放页榜单筛选入口（song_ranking_filter.rs）。
  Future<MusicSongRankingFilter> songRankingFilter(
    MusicSongRankingFilterQuery query,
  );

  /// 新碟榜单（top_album.rs；regions 含 chn/eur/jpn/kor 全部分组）。
  Future<MusicTopAlbums> topAlbums();

  /// IP 榜单（top_ip.rs；仅保留 type==1 的歌单条目）。
  Future<List<MusicRankPlaylistCard>> topIps();

  /// 分类推荐歌单（top_playlist.rs）。
  Future<List<MusicRankPlaylistCard>> topPlaylists(MusicTopPlaylistQuery query);

  /// 新歌首发（top_song.rs；固定新歌榜 21608）。
  Future<MusicRankNewSongs> topSongs();
}

/// 酷狗实现：委托同目录的 fetchXxx 端点函数（共享 MusicSession）。
class KugouRankApi implements MusicRankApi {
  KugouRankApi(this.session);

  final MusicSession session;

  @override
  Future<List<MusicRank>> rankList() => fetchRankList(session);

  @override
  Future<List<MusicRank>> rankTop() => fetchRankTop(session);

  @override
  Future<MusicRankSongs> rankAudio(MusicRankAudioQuery query) =>
      fetchRankAudio(session, query);

  @override
  Future<MusicSongRanking> songRanking(MusicSongRankingQuery query) =>
      fetchSongRanking(session, query);

  @override
  Future<MusicSongRankingFilter> songRankingFilter(
    MusicSongRankingFilterQuery query,
  ) => fetchSongRankingFilter(session, query);

  @override
  Future<MusicTopAlbums> topAlbums() => fetchTopAlbums(session);

  @override
  Future<List<MusicRankPlaylistCard>> topIps() => fetchTopIps(session);

  @override
  Future<List<MusicRankPlaylistCard>> topPlaylists(
    MusicTopPlaylistQuery query,
  ) => fetchTopPlaylists(session, query);

  @override
  Future<MusicRankNewSongs> topSongs() => fetchTopSongs(session);
}
