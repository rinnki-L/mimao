/// 播放补全端点组门面——audio_match / privilege_lite / get_model /
/// images_audio / krm_audio 五端点的组接口（music-api-expansion §4：
/// MusicXxxApi + KugouXxxApi，方法名带组前缀）。
library;

import 'package:mimao/music/api/audio_match.dart';
import 'package:mimao/music/api/get_model.dart';
import 'package:mimao/music/api/images_audio.dart';
import 'package:mimao/music/api/krm_audio.dart';
import 'package:mimao/music/api/privilege_lite.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

/// 播放补全端点组接口。
abstract interface class MusicPlaybackExtApi {
  /// 听歌识曲（audio_match.rs）。
  Future<List<MusicRecognitionMatch>> audioMatch(AudioMatchQuery query);

  /// 歌曲权益批量查询（privilege_lite.rs）。
  Future<List<MusicResourcePrivileges>> privilegeLite(PrivilegeLiteQuery query);

  /// 音效商城目录（get_model.rs，复用音效模型）。
  Future<MusicPage<MusicEffect>> getModel(GetModelQuery query);

  /// 歌曲关联歌手图片（images_audio.rs）；外层分组保持请求顺序（含空组）。
  Future<List<List<MusicAuthorImages>>> imagesAudio(ImagesAudioQuery query);

  /// 歌曲资料补全（krm_audio.rs）；100 个 id 自动按 50 顺序分块合并。
  Future<List<MusicSongPresentation>> krmAudio(KrmAudioQuery query);
}

/// [MusicPlaybackExtApi] 的酷狗实现：识曲/权益/资料走网关签名请求，
/// 音效商城走普通目录签名，歌手图片走公开 CDN 查询（clearDefaults）。
class KugouPlaybackExtApi implements MusicPlaybackExtApi {
  KugouPlaybackExtApi(this.session);

  final MusicSession session;

  @override
  Future<List<MusicRecognitionMatch>> audioMatch(AudioMatchQuery query) =>
      fetchAudioMatch(session, query);

  @override
  Future<List<MusicResourcePrivileges>> privilegeLite(
    PrivilegeLiteQuery query,
  ) => fetchPrivilegeLite(session, query);

  @override
  Future<MusicPage<MusicEffect>> getModel(GetModelQuery query) =>
      fetchGetModel(session, query);

  @override
  Future<List<List<MusicAuthorImages>>> imagesAudio(ImagesAudioQuery query) =>
      fetchImagesAudio(session, query);

  @override
  Future<List<MusicSongPresentation>> krmAudio(KrmAudioQuery query) =>
      fetchKrmAudio(session, query);
}
