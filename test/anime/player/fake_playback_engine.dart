import 'dart:async';

import 'package:mimao/anime/player/playback_engine.dart';

/// 单测用假后端：不拉起 libmpv、不联网，只记录调用并回放快照。
///
/// 行为对齐真实适配层的关键点：`open` 表示"打开并起播"（对应
/// `Player.open(..., play: true)`），因此会把 playing 置 true 并推快照。
class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackSnapshot> _snapshots =
      StreamController<PlaybackSnapshot>.broadcast();

  final List<String> openedUrls = <String>[];
  final List<Duration> seeks = <Duration>[];
  int playCount = 0;
  int pauseCount = 0;
  double? lastSpeed;
  bool disposed = false;

  bool playing = false;
  bool buffering = false;
  bool completed = false;
  Duration position = Duration.zero;
  Duration duration = const Duration(seconds: 240);
  String? error;

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;

  /// 手动推一个快照（用当前字段值）。
  void emitSnapshot() {
    if (_snapshots.isClosed) return;
    _snapshots.add(
      PlaybackSnapshot(
        position: position,
        duration: duration,
        playing: playing,
        buffering: buffering,
        completed: completed,
        error: error,
      ),
    );
  }

  void complete() {
    completed = true;
    position = duration;
    playing = false;
    emitSnapshot();
  }

  @override
  Future<void> open(String url, {Duration startAt = Duration.zero}) async {
    openedUrls.add(url);
    position = startAt;
    playing = true;
    completed = false;
    error = null;
    emitSnapshot();
  }

  @override
  Future<void> play() async {
    playCount++;
    playing = true;
    emitSnapshot();
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    playing = false;
    emitSnapshot();
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    this.position = position;
    emitSnapshot();
  }

  @override
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _snapshots.close();
  }
}
