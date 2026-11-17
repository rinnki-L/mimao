import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:mimao/anime/player/playback_engine.dart';

/// media_kit 适配层——唯一 import 解码后端的产品文件。
///
/// m3u8 与直链都走 [Player.open]：libmpv 自己按 URL 选 HLS/HTTP 流程，
/// 我们不做格式分叉。错误从 `stream.error` 转成 [PlaybackSnapshot.error]，
/// 由 controller 翻成 UI 的错误态。
class MediaKitPlaybackEngine implements PlaybackEngine {
  MediaKitPlaybackEngine({Player? player})
    : _player = player ?? _createPlayer() {
    _listen();
  }

  static Player _createPlayer() {
    // media_kit 要求使用前初始化 libmpv；本调用幂等，放在这里让调用方
    // （demo / 集成方）不必记住初始化顺序。
    MediaKit.ensureInitialized();
    return Player();
  }

  final Player _player;

  /// 供 media_kit_video 的 `VideoController` 绑定视频输出。
  Player get player => _player;

  final StreamController<PlaybackSnapshot> _snapshots =
      StreamController<PlaybackSnapshot>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  String? _error;
  bool _disposed = false;

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;

  void _listen() {
    _subscriptions.addAll(<StreamSubscription<Object?>>[
      _player.stream.playing.listen((value) {
        _playing = value;
        _emit();
      }),
      _player.stream.position.listen((value) {
        _position = value;
        _emit();
      }),
      _player.stream.duration.listen((value) {
        _duration = value;
        _emit();
      }),
      _player.stream.buffering.listen((value) {
        _buffering = value;
        _emit();
      }),
      _player.stream.completed.listen((value) {
        _completed = value;
        _emit();
      }),
      _player.stream.error.listen((message) {
        _error = message;
        _emit();
      }),
    ]);
  }

  void _emit() {
    if (_disposed || _snapshots.isClosed) return;
    _snapshots.add(
      PlaybackSnapshot(
        position: _position,
        duration: _duration,
        playing: _playing,
        buffering: _buffering,
        completed: _completed,
        error: _error,
      ),
    );
  }

  @override
  Future<void> open(String url, {Duration startAt = Duration.zero}) async {
    _position = startAt;
    _duration = Duration.zero;
    _completed = false;
    _error = null;
    _emit();
    await _player.open(
      Media(url, start: startAt > Duration.zero ? startAt : null),
      play: true,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _snapshots.close();
    await _player.dispose();
  }
}
