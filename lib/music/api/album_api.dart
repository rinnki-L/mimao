/// 专辑端点组接口——`MusicAlbumApi` / `KugouAlbumApi`（docs/music-api-expansion.md
/// 第 4 节的组门面约定；集成时并入 `KugouMusicApi`）。
library;

import 'package:mimao/music/api/album_detail.dart';
import 'package:mimao/music/api/album_dycover.dart';
import 'package:mimao/music/api/album_songs.dart';
import 'package:mimao/music/api/favorite_count.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/album_models.dart';

/// 专辑组：详情、动态封面、曲目分页、收藏计数。
abstract interface class MusicAlbumApi {
  /// 专辑详情（album_detail.rs）；无此专辑返回 null。
  Future<MusicAlbumDetail?> albumDetail(int id);

  /// 专辑动态封面（album_dycover.rs）；无可用封面返回 null。
  Future<MusicAlbumDynamicCover?> albumDycover(AlbumDycoverQuery query);

  /// 专辑曲目分页（album_songs.rs）。
  Future<MusicAlbumTracks> albumSongs(AlbumSongsQuery query);

  /// 批量收藏计数（favorite_count.rs）。
  Future<List<MusicAlbumFavoriteCount>> favoriteCount(List<int> ids);
}

/// 酷狗实现：全部转发给组内端点函数（传输/身份由 [MusicSession] 提供）。
class KugouAlbumApi implements MusicAlbumApi {
  KugouAlbumApi(this.session);

  final MusicSession session;

  @override
  Future<MusicAlbumDetail?> albumDetail(int id) =>
      fetchAlbumDetail(session, id);

  @override
  Future<MusicAlbumDynamicCover?> albumDycover(AlbumDycoverQuery query) =>
      fetchAlbumDycover(session, query);

  @override
  Future<MusicAlbumTracks> albumSongs(AlbumSongsQuery query) =>
      fetchAlbumSongs(session, query);

  @override
  Future<List<MusicAlbumFavoriteCount>> favoriteCount(List<int> ids) =>
      fetchFavoriteCount(session, ids);
}
