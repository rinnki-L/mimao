/// 歌手端点组门面——`MusicArtistApi` 接口 + `KugouArtistApi` 实现。
///
/// 组合 artist_detail / artist_albums / artist_audios_new / artist_lists 四个
/// 端点（artist_follow / artist_unfollow 是社交关注动作，按规格排除不移植）。
/// 顶层 fetchXxx 函数见各端点文件；本文件只做装配。
library;

import 'package:mimao/music/api/artist_albums.dart';
import 'package:mimao/music/api/artist_audios_new.dart';
import 'package:mimao/music/api/artist_detail.dart';
import 'package:mimao/music/api/artist_lists.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/artist_models.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 歌手端点组接口。
abstract interface class MusicArtistApi {
  /// 歌手详情（data 缺省/空 object → null，不算失败）。
  Future<MusicArtistDetail?> artistDetail(int id);

  /// 歌手专辑分页（摘要复用共享 `MusicAlbumSummary`）。
  Future<MusicPage<MusicAlbumSummary>> artistAlbums(
    MusicArtistAlbumsQuery query,
  );

  /// 歌手歌曲分页（含音质/权限/版权事实）。
  Future<MusicPage<MusicArtistSong>> artistAudiosNew(
    MusicArtistAudiosQuery query,
  );

  /// 歌手目录（分组卡片 + 性别/类型筛选）。
  Future<MusicArtistDirectory> artistLists(MusicArtistListsQuery query);
}

/// 酷狗实现：端点函数 + 共享会话。
class KugouArtistApi implements MusicArtistApi {
  KugouArtistApi(this.session);

  final MusicSession session;

  @override
  Future<MusicArtistDetail?> artistDetail(int id) =>
      fetchArtistDetail(session, id);

  @override
  Future<MusicPage<MusicAlbumSummary>> artistAlbums(
    MusicArtistAlbumsQuery query,
  ) => fetchArtistAlbums(session, query);

  @override
  Future<MusicPage<MusicArtistSong>> artistAudiosNew(
    MusicArtistAudiosQuery query,
  ) => fetchArtistAudiosNew(session, query);

  @override
  Future<MusicArtistDirectory> artistLists(MusicArtistListsQuery query) =>
      fetchArtistLists(session, query);
}
