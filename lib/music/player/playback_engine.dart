// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 本文件为契约层（MusicPlayerUi 需要 Widget 类型），与模块内其它文件同款说明。
/// 音乐播放内核契约（M4 播放线实现）。
///
/// 刻意与 `lib/anime/player/playback_engine.dart` 重复而不复用：铁律②禁止
/// music 目录 import anime，~40 行的接口重复是边界纪律的代价，不是疏忽。
///
/// 实现方（P 线）只允许在这里替换实现，不得改本文件的签名——契约提交已冻结。
library;

/// 播放快照：驱动 UI 与进度写入的唯一状态源。
class MusicPlaybackSnapshot {
  const MusicPlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.error,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool completed;

  /// 引擎层错误描述；null 表示无错误。
  final String? error;

  MusicPlaybackSnapshot copyWith({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? buffering,
    bool? completed,
    String? error,
  }) => MusicPlaybackSnapshot(
    position: position ?? this.position,
    duration: duration ?? this.duration,
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    completed: completed ?? this.completed,
    error: error ?? this.error,
  );
}

/// 音频引擎接口（media_kit 实现在 P 线）。
abstract interface class MusicPlaybackEngine {
  /// 状态流；订阅方负责在 dispose 后取消。
  Stream<MusicPlaybackSnapshot> get snapshots;

  Future<void> open(String url, {Duration startAt = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}
