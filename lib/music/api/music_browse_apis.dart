/// 音乐模块的端点能力包——UI/装配层一次性拿到全部按域拆分的接口。
///
/// 设计动机：`MusicApi` 只保留「搜索单曲 + 设备身份」这个最小面；扩容后的
/// 14 个域各自有独立接口（发现/榜单/专辑/歌手/歌单读/歌单写/用户资料/
/// 用户库/登录/验证/歌词/播放扩展/音效/听歌上报）。把 15 个可选参数塞进
/// `MusicModule` 会很难读，因此用这个不可变包统一传递；生产实现由
/// `KugouMusicApi.browseApis` 惰性构造，测试可逐项注入 fake。
library;

import 'package:mimao/music/api/album_api.dart';
import 'package:mimao/music/api/artist_api.dart';
import 'package:mimao/music/api/auth_login_api.dart';
import 'package:mimao/music/api/discovery_api.dart';
import 'package:mimao/music/api/effects_api.dart';
import 'package:mimao/music/api/listen_report_api.dart';
import 'package:mimao/music/api/lyric_api.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/api/rank_api.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/api/user_profile_api.dart';
import 'package:mimao/music/api/verify_api.dart';

/// 全部音乐端点组接口。字段都可为 null：UI 按注入能力逐页显示。
class MusicBrowseApis {
  const MusicBrowseApis({
    this.searchExt,
    this.discovery,
    this.rank,
    this.album,
    this.artist,
    this.effects,
    this.playlistRead,
    this.playlistWrite,
    this.userProfile,
    this.userLibrary,
    this.auth,
    this.verify,
    this.lyric,
    this.playbackExt,
    this.listenReport,
  });

  final MusicSearchExtApi? searchExt;
  final MusicDiscoveryApi? discovery;
  final MusicRankApi? rank;
  final MusicAlbumApi? album;
  final MusicArtistApi? artist;
  final MusicEffectsApi? effects;
  final MusicPlaylistReadApi? playlistRead;
  final MusicPlaylistWriteApi? playlistWrite;
  final MusicUserProfileApi? userProfile;
  final MusicUserLibraryApi? userLibrary;
  final MusicAuthApi? auth;
  final MusicVerifyApi? verify;
  final MusicLyricApi? lyric;
  final MusicPlaybackExtApi? playbackExt;
  final MusicListenReportApi? listenReport;
}
