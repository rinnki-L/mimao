// 播放内核与解码后端之间的最小契约（B 线）。
//
// 本文件刻意不 import media_kit：controller / UI / 单测只依赖这层接口，
// 真实解码在 media_kit_playback_engine.dart 里适配。这样单测不必拉起
// libmpv、也不碰真实网络——验收要求"不强依赖真实视频解码"。

/// 后端某一时刻的播放快照。上层只读它，不直接摸具体 Player。
class PlaybackSnapshot {
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool completed;

  /// 非空表示后端报错（地址无效 / 网络断开 / 解码失败…）。
  final String? error;

  const PlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.error,
  });
}

/// 视频后端的最小能力面：打开 / 播放 / 暂停 / 跳转 / 倍速 / 释放。
///
/// m3u8 与直链都只是 `open(url)` 的 URL 差异，不在接口上分叉。
abstract interface class PlaybackEngine {
  /// 播放状态流。实现方负责在状态变化时推送完整快照。
  Stream<PlaybackSnapshot> get snapshots;

  /// 打开一个 m3u8 / 直链地址并从 [startAt] 起播。
  ///
  /// [headers] 是规则级请求头（UA / Referer 等），后端据此设置播放器 HTTP
  /// header；默认 null / 空 map 表示不附加任何头，现有调用点行为不变。
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    Map<String, String>? headers,
  });

  Future<void> play();

  Future<void> pause();

  /// 跳转；调用方负责把目标钳制在 [0, duration] 内。
  Future<void> seek(Duration position);

  Future<void> setSpeed(double speed);

  Future<void> dispose();
}
