/// 搜索扩展端点组接口（规格第 5 节 G1）——把 search.rs 扩容分支与
/// search_default/search_hot/search_suggest/search_lyric/sidedt 五个新端点
/// 收敛成一个可注入的组接口；页面与播放链路只依赖本文件。
library;

import 'package:mimao/music/api/search.dart';
import 'package:mimao/music/api/search_default.dart';
import 'package:mimao/music/api/search_hot.dart';
import 'package:mimao/music/api/search_lyric.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/sidedt.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/search_models.dart';

/// 搜索扩展端点组。
abstract interface class MusicSearchExtApi {
  /// 搜索专辑（search.rs Album 分支）。
  Future<MusicPage<MusicAlbumSummary>> searchAlbums(SearchSongsQuery query);

  /// 搜索歌手（search.rs Author 分支）。
  Future<MusicPage<MusicArtistSummary>> searchArtists(SearchSongsQuery query);

  /// 搜索歌单（search.rs Special 分支）。
  Future<MusicPage<MusicPlaylistSummary>> searchPlaylists(
    SearchSongsQuery query,
  );

  /// 搜索歌词命中（search.rs Lyric 分支）。
  Future<MusicPage<MusicLyricHit>> searchLyrics(SearchSongsQuery query);

  /// 默认搜索词（search_default.rs）。
  Future<MusicSearchDefault> searchDefault();

  /// 热搜榜（search_hot.rs）。
  Future<List<MusicHotSearchGroup>> searchHot();

  /// 搜索建议（search_suggest.rs）。
  Future<MusicSearchSuggestions> searchSuggest(MusicSearchSuggestQuery query);

  /// 歌词候选（search_lyric.rs；lyrics.kugou.com + clearDefaults）。
  Future<List<MusicLyricCandidate>> searchLyric(MusicSearchLyricQuery query);

  /// sidedt 安全上报（sidedt.rs；本地指纹 + verify_user_info 协议）。
  Future<MusicSideDtAcknowledgement> sideDt(MusicSideDtQuery query);
}

/// 酷狗实现：会话持有传输与身份，端点函数逐个转调。
class KugouSearchExtApi implements MusicSearchExtApi {
  KugouSearchExtApi(this.session);

  final MusicSession session;

  @override
  Future<MusicPage<MusicAlbumSummary>> searchAlbums(SearchSongsQuery query) =>
      fetchSearchAlbums(session, query);

  @override
  Future<MusicPage<MusicArtistSummary>> searchArtists(SearchSongsQuery query) =>
      fetchSearchArtists(session, query);

  @override
  Future<MusicPage<MusicPlaylistSummary>> searchPlaylists(
    SearchSongsQuery query,
  ) => fetchSearchPlaylists(session, query);

  @override
  Future<MusicPage<MusicLyricHit>> searchLyrics(SearchSongsQuery query) =>
      fetchSearchLyrics(session, query);

  @override
  Future<MusicSearchDefault> searchDefault() => fetchSearchDefault(session);

  @override
  Future<List<MusicHotSearchGroup>> searchHot() => fetchSearchHot(session);

  @override
  Future<MusicSearchSuggestions> searchSuggest(MusicSearchSuggestQuery query) =>
      fetchSearchSuggest(session, query);

  @override
  Future<List<MusicLyricCandidate>> searchLyric(MusicSearchLyricQuery query) =>
      fetchSearchLyric(session, query);

  @override
  Future<MusicSideDtAcknowledgement> sideDt(MusicSideDtQuery query) =>
      fetchSideDt(session, query);
}
