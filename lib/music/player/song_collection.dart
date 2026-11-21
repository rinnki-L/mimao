/// 播放器「收藏当前歌曲」能力——把曲目加入「我喜欢」或指定云歌单。
///
/// 账号收藏是云歌单：酷狗把「我喜欢」存在账号云歌单里（wire `is_def == 2`），
/// 不在本地库里。本文件只暴露 [MusicSongCollection] 契约与生产实现
/// [KugouSongCollection]；播放页/迷你条通过注入拿到能力，不直接认识 API。
library;

import 'package:mimao/music/api/playlist_tracks_add.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 把当前歌曲加到「我喜欢」或指定歌单的能力（生产由酷狗云歌单 API 实现）。
abstract class MusicSongCollection {
  /// 拉取当前账号可编辑的歌单列表（含「我喜欢」）。
  /// 匿名/失败时抛异常，由调用方提示。
  Future<List<MusicUserPlaylist>> loadEditablePlaylists();

  /// 把 [song] 加到 [playlist]（playlist.cloudListId 非空）。
  /// 缺 song 关键字段或加歌失败时抛异常。
  Future<void> addSongToPlaylist(MusicSong song, MusicUserPlaylist playlist);

  /// 便捷：把 [song] 加到「我喜欢」（内部定位 defaultKind==2 的歌单）。
  /// 找不到「我喜欢」歌单或加歌失败时抛异常。
  Future<void> addToFavorite(MusicSong song);
}

/// 酷狗云歌单实现：读账号歌单（[MusicUserLibraryApi]）+ 加歌
/// （[MusicPlaylistWriteApi]）。
class KugouSongCollection implements MusicSongCollection {
  KugouSongCollection(this.library, this.write);

  final MusicUserLibraryApi library;
  final MusicPlaylistWriteApi write;

  /// 「我喜欢」的云歌单默认种类码（wire `is_def`）。实测 `is_def == 1`
  /// 是空的「默认收藏」，`is_def == 2` 才是「我喜欢」。
  static const int _favoriteDefaultKind = 2;

  /// 标题兜底（旧账号/字段缺失时 `is_def` 可能不可用）。
  static const String _favoriteTitle = '我喜欢';

  /// 歌单分页取一页拉满（端点上限 200），足够覆盖普通账号的歌单数。
  static const int _pageSize = 200;

  @override
  Future<List<MusicUserPlaylist>> loadEditablePlaylists() async {
    final result = await library.userPlaylist(
      const MusicUserPlaylistQuery(page: 1, pageSize: _pageSize),
    );
    // 只保留能写的歌单：显式 editable == false 的收藏/他人歌单排除，
    // 没有 cloudListId 的条目也无从加歌。
    return <MusicUserPlaylist>[
      for (final playlist in result.page.items)
        if (playlist.editable != false && playlist.cloudListId != null)
          playlist,
    ];
  }

  @override
  Future<void> addSongToPlaylist(
    MusicSong song,
    MusicUserPlaylist playlist,
  ) async {
    final cloudListId = playlist.cloudListId;
    if (cloudListId == null) {
      throw const KugouApiException('input', '歌单信息不完整');
    }
    // 加歌端点需要 int 型 album_id / mixsongid；MusicSong 里是 String，
    // 缺 hash 或 id 不是数字时无法映射，直接报「信息不完整」。
    final albumId = int.tryParse(song.albumId);
    final songId = int.tryParse(song.id);
    if (song.title.isEmpty ||
        song.hash.isEmpty ||
        albumId == null ||
        songId == null) {
      throw const KugouApiException('input', '歌曲信息不完整');
    }
    await write.playlistTracksAdd(
      PlaylistTracksAddQuery(
        cloudListId: cloudListId,
        tracks: <PlaylistTrackInput>[
          PlaylistTrackInput(
            title: song.title,
            hash: song.hash,
            albumId: albumId,
            songId: songId,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> addToFavorite(MusicSong song) async {
    final playlists = await loadEditablePlaylists();
    final favorite = _findFavorite(playlists);
    if (favorite == null) {
      throw const KugouApiException('not_found', '未找到「我喜欢」歌单');
    }
    await addSongToPlaylist(song, favorite);
  }

  /// 定位「我喜欢」：优先 `is_def == 2`，再按标题兜底；都没有返回 null。
  MusicUserPlaylist? _findFavorite(List<MusicUserPlaylist> playlists) {
    for (final playlist in playlists) {
      if (playlist.defaultKind == _favoriteDefaultKind &&
          playlist.cloudListId != null) {
        return playlist;
      }
    }
    for (final playlist in playlists) {
      if (playlist.title == _favoriteTitle && playlist.cloudListId != null) {
        return playlist;
      }
    }
    return null;
  }
}
