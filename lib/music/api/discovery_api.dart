/// 发现/推荐端点组门面——规格 §4：`MusicDiscoveryApi` 接口 +
/// `KugouDiscoveryApi` 会话实现。UI/Store 只依赖本接口；端点函数
/// （fetchXxx）在各自文件里，便于逐端点单测。
library;

import 'package:mimao/music/api/ai_recommend_song.dart';
import 'package:mimao/music/api/everyday_recommend.dart';
import 'package:mimao/music/api/everyday_style_recommend.dart';
import 'package:mimao/music/api/home_discover.dart';
import 'package:mimao/music/api/personal_fm.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/song_climax.dart';
import 'package:mimao/music/models/discovery_models.dart';

/// 发现/推荐端点组（home_discover / everyday_recommend /
/// everyday_style_recommend / ai_recommend_song / personal_fm / song_climax）。
abstract interface class MusicDiscoveryApi {
  /// 首页发现推荐（home_discover）。
  Future<MusicDiscoverRecommendations> homeDiscover(HomeDiscoverQuery query);

  /// 每日推荐（everyday_recommend）。
  Future<MusicDailyRecommendations> everydayRecommend();

  /// 风格推荐（everyday_style_recommend）。
  Future<MusicStyleRecommendations> everydayStyleRecommend(
    EverydayStyleRecommendQuery query,
  );

  /// AI 免费畅听推荐（ai_recommend_song）。
  Future<MusicFreeListenSongs> aiRecommendSongs();

  /// 私人 FM（personal_fm；需要账号）。
  Future<MusicPersonalFmSongs> personalFm(MusicPersonalFmQuery query);

  /// 歌曲高潮区间（song_climax）。
  Future<List<MusicSongClimaxSegment>> songClimax(String hash);
}

/// 生产实现：把各端点函数装配到共享 [MusicSession] 上。
class KugouDiscoveryApi implements MusicDiscoveryApi {
  KugouDiscoveryApi(this.session);

  final MusicSession session;

  @override
  Future<MusicDiscoverRecommendations> homeDiscover(HomeDiscoverQuery query) =>
      fetchHomeDiscover(session, query);

  @override
  Future<MusicDailyRecommendations> everydayRecommend() =>
      fetchEverydayRecommend(session);

  @override
  Future<MusicStyleRecommendations> everydayStyleRecommend(
    EverydayStyleRecommendQuery query,
  ) => fetchEverydayStyleRecommend(session, query);

  @override
  Future<MusicFreeListenSongs> aiRecommendSongs() =>
      fetchAiRecommendSongs(session);

  @override
  Future<MusicPersonalFmSongs> personalFm(MusicPersonalFmQuery query) =>
      fetchPersonalFm(session, query);

  @override
  Future<List<MusicSongClimaxSegment>> songClimax(String hash) =>
      fetchSongClimax(session, hash);
}
