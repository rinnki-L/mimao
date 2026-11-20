/// 用户库端点组门面——听歌历史、云歌单、偏好、已购与验证码回执
/// （docs/architecture.md §4.3：`music/api/<group>_api.dart` 聚合本组端点）。
///
/// 协议实现分布在各端点文件（注释逐条对应 Rust）；本门面只做会话装配，
/// 供 `KugouMusicApi` 组合（集成者负责）。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_history.dart';
import 'package:mimao/music/api/user_playlist.dart';
import 'package:mimao/music/api/user_preference.dart';
import 'package:mimao/music/api/user_preference_update.dart';
import 'package:mimao/music/api/user_purchased_albums.dart';
import 'package:mimao/music/api/user_purchased_songs.dart';
import 'package:mimao/music/api/verify_user_info.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';

export 'package:mimao/music/api/user_history.dart'
    show MusicUserHistoryQuery, fetchUserHistory;
export 'package:mimao/music/api/user_playlist.dart'
    show MusicUserPlaylistQuery, fetchUserPlaylist;
export 'package:mimao/music/api/user_preference.dart'
    show fetchUserPreference, kugouSendPreferenceProtocol;
export 'package:mimao/music/api/user_preference_update.dart'
    show MusicPreferenceUpdateQuery, fetchUserPreferenceUpdate;
export 'package:mimao/music/api/user_purchased_albums.dart'
    show MusicUserPagedQuery, fetchUserPurchasedAlbums;
export 'package:mimao/music/api/user_purchased_songs.dart'
    show fetchUserPurchasedSongs;
export 'package:mimao/music/api/verify_user_info.dart'
    show
        MusicVerifyUserInfoQuery,
        MusicVerifyFingerprint,
        fetchVerifyUserInfo,
        kugouGenerateVerifyFingerprint,
        kugouSimulateAesCbcBase64;

/// 用户库端点组接口。
abstract interface class MusicUserLibraryApi {
  /// 最近听歌历史（`module/user_history.rs`；需要账号）。
  Future<MusicHistoryPage> userHistory(MusicUserHistoryQuery query);

  /// 账号云歌单分页（`module/user_playlist.rs`；需要账号）。
  Future<MusicUserPlaylists> userPlaylist(MusicUserPlaylistQuery query);

  /// 当前账号偏好（`module/user_preference.rs`；需要账号）。
  Future<MusicPreferences> userPreference();

  /// 偏好差量写入（`module/user_preference_update.rs`；需要账号）。
  Future<MusicPreferenceAcknowledgement> userPreferenceUpdate(
    MusicPreferenceUpdateQuery query,
  );

  /// 已购专辑分页（`module/user_purchased_albums.rs`；需要账号）。
  Future<MusicPage<MusicPurchasedAlbum>> userPurchasedAlbums(
    MusicUserPagedQuery query,
  );

  /// 已购单曲分页（`module/user_purchased_songs.rs`；需要账号）。
  Future<MusicPage<MusicPurchasedSong>> userPurchasedSongs(
    MusicUserPagedQuery query,
  );

  /// 验证码提交回执（`module/verify_user_info.rs`；SID/EDT 本地模拟）。
  Future<MusicVerifyAcknowledgement> verifyUserInfo(
    MusicVerifyUserInfoQuery query,
  );
}

/// 生产实现：端点函数负责协议，本类只提供共享会话缝。
class KugouUserLibraryApi implements MusicUserLibraryApi {
  KugouUserLibraryApi(this.session);

  final MusicSession session;

  @override
  Future<MusicHistoryPage> userHistory(MusicUserHistoryQuery query) =>
      fetchUserHistory(session, query);

  @override
  Future<MusicUserPlaylists> userPlaylist(MusicUserPlaylistQuery query) =>
      fetchUserPlaylist(session, query);

  @override
  Future<MusicPreferences> userPreference() => fetchUserPreference(session);

  @override
  Future<MusicPreferenceAcknowledgement> userPreferenceUpdate(
    MusicPreferenceUpdateQuery query,
  ) => fetchUserPreferenceUpdate(session, query);

  @override
  Future<MusicPage<MusicPurchasedAlbum>> userPurchasedAlbums(
    MusicUserPagedQuery query,
  ) => fetchUserPurchasedAlbums(session, query);

  @override
  Future<MusicPage<MusicPurchasedSong>> userPurchasedSongs(
    MusicUserPagedQuery query,
  ) => fetchUserPurchasedSongs(session, query);

  @override
  Future<MusicVerifyAcknowledgement> verifyUserInfo(
    MusicVerifyUserInfoQuery query,
  ) => fetchVerifyUserInfo(session, query);
}
