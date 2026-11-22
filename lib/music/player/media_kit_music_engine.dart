/// media_kit 纯音频引擎（M4-P）。
///
/// 刻意与 `lib/anime/player/media_kit_playback_engine.dart` 重复而不复用：
/// music 目录不得 import anime（铁律②）。视频版多一个 `VideoController`
/// 绑定，这里只建 `Player`（纯音频）；`media_kit_libs_video` 已含音频解码，
/// 不新增依赖。
library;

import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:mimao/music/player/playback_engine.dart';

class MediaKitMusicEngine implements MusicPlaybackEngine {
  MediaKitMusicEngine({Player? player}) : _player = player ?? _createPlayer() {
    _listen();
  }

  static Player _createPlayer() {
    // media_kit 使用前必须初始化 libmpv；幂等，放在构造点让调用方不必
    // 记住顺序。构造只发生在首次 playSong（store 惰性求值工厂），
    // 模块注册/buildHome 不会触碰它。
    MediaKit.ensureInitialized();
    return Player();
  }

  final Player _player;

  final StreamController<MusicPlaybackSnapshot> _snapshots =
      StreamController<MusicPlaybackSnapshot>.broadcast();
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
  Stream<MusicPlaybackSnapshot> get snapshots => _snapshots.stream;

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
      MusicPlaybackSnapshot(
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
    // play:false——起播由 store 的 play() 显式驱动，调用序列可测。
    await _player.open(
      Media(url, start: startAt > Duration.zero ? startAt : null),
      play: false,
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

  // 本仓音量契约是 0.0~1.0，media_kit 是 0.0~100.0——在引擎边界换算，
  // 不把媒体内核的量纲泄漏给上层。
  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume * 100.0);
  }

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
