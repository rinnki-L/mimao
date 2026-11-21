/// 播放页「加到我喜欢/歌单」的测试替身。
///
/// UI 层测试只需 `import` 本文件并通过 [FakeSongCollection] 观察调用；
/// 纯内存、无网络，不依赖生产 API。
library;

import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/player/song_collection.dart';

class FakeSongCollection implements MusicSongCollection {
  FakeSongCollection({List<MusicUserPlaylist>? playlists, this.error})
    : playlists = playlists ?? <MusicUserPlaylist>[];

  /// loadEditablePlaylists 的返回值（可随时改写以模拟不同账号歌单）。
  List<MusicUserPlaylist> playlists;

  /// 非空时所有方法都抛它（模拟匿名/网络/加歌失败）。
  Object? error;

  /// 记录成功加入「我喜欢」的歌曲。
  final List<MusicSong> addedToFavorite = <MusicSong>[];

  /// 记录成功加入指定歌单的歌曲。
  final List<MusicSong> addedToPlaylists = <MusicSong>[];

  /// addSongToPlaylist 的最后一个目标歌单（便于断言加了哪张）。
  MusicUserPlaylist? lastTargetPlaylist;

  /// loadEditablePlaylists 调用次数。
  int loadCount = 0;

  @override
  Future<List<MusicUserPlaylist>> loadEditablePlaylists() async {
    loadCount++;
    final pending = error;
    if (pending != null) throw pending;
    return List<MusicUserPlaylist>.of(playlists);
  }

  @override
  Future<void> addSongToPlaylist(
    MusicSong song,
    MusicUserPlaylist playlist,
  ) async {
    final pending = error;
    if (pending != null) throw pending;
    addedToPlaylists.add(song);
    lastTargetPlaylist = playlist;
  }

  @override
  Future<void> addToFavorite(MusicSong song) async {
    final pending = error;
    if (pending != null) throw pending;
    addedToFavorite.add(song);
  }
}
