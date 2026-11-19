/// 播放解析门面（P 线实现）。
///
/// 页面与入口只依赖本接口；具体端点实现（user_verify → song_auth → tracker）
/// 住 `api/` 与 `player/`，可在不动本文件的前提下替换。
library;

import 'package:mimao/music/models/music_models.dart';

abstract interface class MusicPlaybackApi {
  /// 解析一首歌的可播地址。失败抛 `KugouApiException`
  /// （`authentication` 时 UI 应提示「请先登录」）。
  ///
  /// [authorization] 非空时跳过 user_verify（复用/测试用）。
  Future<MusicPlaybackSource> resolvePlayback(
    MusicSong song, {
    MusicQuality quality = MusicQuality.higher,
    String? authorization,
  });
}
