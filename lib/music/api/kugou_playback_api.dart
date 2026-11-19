/// 播放解析门面的酷狗实现（M4-P）。
///
/// 链路与上游 `song_url_auth_merge.rs::execute` 一致：
/// `user_verify → song_auth → tracker`；注入 [authorization] 时跳过第一步
/// （上游 `Some(value) if !value.is_empty()` 分支）。
///
/// 两个校验提前失败、不发网络：hash 必须 32 位十六进制；`song.id`
/// （= `album_audio_id`）必须可解析为整数。**不得回退 `audioId`**——协议里
/// `Audioid` 与 `MixSongID` 是两个键，混用会把授权/地址算到别的曲目上。
library;

import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/api/song_auth.dart';
import 'package:mimao/music/api/song_url_auth.dart';
import 'package:mimao/music/api/user_verify.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';

class KugouPlaybackApi implements MusicPlaybackApi {
  KugouPlaybackApi(this._client, this._api);

  final KugouClient _client;
  final MusicApi _api;

  @override
  Future<MusicPlaybackSource> resolvePlayback(
    MusicSong song, {
    MusicQuality quality = MusicQuality.higher,
    String? authorization,
  }) async {
    final normalizedHash = song.hash.toLowerCase();
    _validateHash(normalizedHash);
    final songId = int.tryParse(song.id);
    if (songId == null) {
      // 只认 MixSongID；不尝试 audioId。
      throw const KugouApiException('input', '曲目信息不完整');
    }
    final albumId = int.tryParse(song.albumId);
    if (albumId == null) {
      throw const KugouApiException('input', '曲目信息不完整');
    }

    final identity = await _api.ensureDevice();
    final String userAuth;
    if (authorization != null && authorization.isNotEmpty) {
      userAuth = authorization;
    } else {
      userAuth = (await userVerify(_client, identity)).authorization;
    }
    final songAuthorization = await songAuthorize(
      _client,
      identity,
      hash: normalizedHash,
      songId: songId,
      userAuth: userAuth,
    );

    try {
      return await resolveSongUrl(
        _client,
        identity,
        hash: normalizedHash,
        albumId: albumId,
        songId: songId,
        quality: quality,
        songAuth: songAuthorization,
      );
    } on KugouApiException catch (error) {
      // 只对默认质量做一次 320→128 回退：同一登录态下换音质不会把
      // authentication/input/http 变成成功。
      if (error.kind != 'business' || quality != MusicQuality.higher) {
        rethrow;
      }
      return resolveSongUrl(
        _client,
        identity,
        hash: normalizedHash,
        albumId: albumId,
        songId: songId,
        quality: MusicQuality.standard,
        songAuth: songAuthorization,
      );
    }
  }

  /// 上游 `execute` 同款校验：32 位 ASCII 十六进制。
  static void _validateHash(String hash) {
    final isHex = RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hash);
    if (!isHex) {
      throw const KugouApiException('input', '歌曲 hash 无效');
    }
  }
}
