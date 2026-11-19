/// 播放器状态内核（M4-P，MobX）——队列/当前曲目/快照/错误 + 进度写入。
///
/// 只经契约 [MusicPlayerUi] 对外暴露（见 `player_ui_impl.dart`）；页面与
/// 入口不直接依赖本类。测试可以直接 `MusicPlayerStore(...)` 注入 fake
/// playbackApi / fake engine / 注入时钟，不触碰 media_kit。
library;

import 'dart:async';

import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_progress.dart';
import 'package:mobx/mobx.dart';

part 'player_store.g.dart';

/// 播放中进度写入的节流间隔（契约：每 10 秒一次，不逐帧写）。
const Duration musicProgressInterval = Duration(seconds: 10);

class MusicPlayerStore = _MusicPlayerStore with _$MusicPlayerStore;

abstract class _MusicPlayerStore with Store {
  _MusicPlayerStore({
    required this.playbackApi,
    required MusicPlaybackEngine Function()? engineFactory,
    ProgressSink? progressSink,
    DateTime Function()? clock,
  }) : _engineFactory = engineFactory,
       _progressSink = progressSink,
       _clock = clock ?? DateTime.now;

  final MusicPlaybackApi playbackApi;

  /// 惰性求值：首次 playSong 才调用；null = 播放未配置（测试/未接线）。
  final MusicPlaybackEngine Function()? _engineFactory;

  /// 进度写入口；null 时不写进度，其余功能照常。
  final ProgressSink? _progressSink;

  /// 注入时钟（节流判定；测试不真实等待）。
  final DateTime Function() _clock;

  MusicPlaybackEngine? _engine;
  StreamSubscription<MusicPlaybackSnapshot>? _engineSubscription;
  DateTime? _lastProgressAt;
  bool _disposed = false;
  bool _completionWritten = false;

  @observable
  ObservableList<MusicSong> queue = ObservableList<MusicSong>();

  @observable
  int index = -1;

  @observable
  MusicPlaybackSnapshot snapshot = const MusicPlaybackSnapshot();

  @observable
  bool isResolving = false;

  /// 解析/播放失败的展示文案；null 表示无错误。
  @observable
  String? error;

  @computed
  MusicSong? get currentSong =>
      index >= 0 && index < queue.length ? queue[index] : null;

  /// 是否配置了引擎（null 时 mini player 不渲染、点歌显示「播放未配置」）。
  bool get canPlay => _engineFactory != null;

  @action
  Future<void> playSong(MusicSong song, {Duration startAt = Duration.zero}) =>
      _start(song, startAt: startAt);

  @action
  Future<void> playAt(int target) async {
    if (target < 0 || target >= queue.length) return;
    await _start(queue[target], targetIndex: target);
  }

  @action
  Future<void> next() async {
    if (_disposed || queue.isEmpty) return;
    if (index + 1 >= queue.length) {
      await _stopAtEnd();
      return;
    }
    await _start(queue[index + 1], targetIndex: index + 1);
  }

  @action
  Future<void> previous() async {
    if (_disposed || queue.isEmpty || index <= 0) return;
    await _start(queue[index - 1], targetIndex: index - 1);
  }

  @action
  Future<void> toggle() async {
    if (_disposed || currentSong == null) return;
    final engine = _ensureEngine();
    if (engine == null) {
      error = '播放未配置';
      return;
    }
    if (snapshot.playing) {
      await engine.pause();
      if (_disposed) return;
      snapshot = snapshot.copyWith(playing: false);
      await _writeCurrentProgress();
    } else {
      await engine.play();
      if (_disposed) return;
      snapshot = snapshot.copyWith(playing: true);
    }
  }

  @action
  Future<void> seekTo(Duration position) async {
    if (_disposed) return;
    final engine = _engine;
    if (engine == null) return;
    await engine.seek(position);
    if (_disposed) return;
    snapshot = snapshot.copyWith(position: position);
    await _writeCurrentProgress();
  }

  /// 失败态「重试」：重走同一首的解析链路（不重复入队）。
  @action
  Future<void> retry() async {
    final song = currentSong;
    if (song == null) return;
    await _start(song, targetIndex: index, recordOutgoing: false);
  }

  @action
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engineSubscription?.cancel();
    _engineSubscription = null;
    final engine = _engine;
    _engine = null;
    if (engine != null) unawaited(engine.dispose());
  }

  MusicPlaybackEngine? _ensureEngine() {
    if (_disposed) return null;
    final existing = _engine;
    if (existing != null) return existing;
    final factory = _engineFactory;
    if (factory == null) return null;
    final engine = factory();
    _engine = engine;
    _engineSubscription = engine.snapshots.listen(
      _onSnapshot,
      onError: (Object error) {
        if (_disposed) return;
        this.error = '播放失败：$error';
      },
    );
    return engine;
  }

  /// 解析地址 → open(startAt) → play；失败按 kind 映射文案。
  Future<void> _start(
    MusicSong song, {
    Duration startAt = Duration.zero,
    int? targetIndex,
    bool recordOutgoing = true,
  }) async {
    if (_disposed) return;
    final engine = _ensureEngine();
    if (engine == null) {
      error = '播放未配置';
      return;
    }

    // 换歌先把上一首的进度落一次，再改队列/索引。
    if (recordOutgoing && currentSong != null) {
      await _writeCurrentProgress();
    }
    if (targetIndex != null) {
      index = targetIndex;
    } else {
      final existing = queue.indexWhere(
        (item) => _songKey(item) == _songKey(song),
      );
      if (existing >= 0) {
        index = existing;
      } else {
        queue.add(song);
        index = queue.length - 1;
      }
    }

    isResolving = true;
    error = null;
    _completionWritten = false;
    snapshot = const MusicPlaybackSnapshot();
    try {
      final source = await playbackApi.resolvePlayback(song);
      if (_disposed) return;
      final url = source.primaryUrl;
      if (url == null) {
        throw const KugouApiException('business', '音乐服务未返回播放地址');
      }
      await engine.open(url, startAt: startAt);
      if (_disposed) return;
      await engine.play();
      // 新歌从此开始计 10 秒节流（换歌后应尽快落一笔历史）。
      _lastProgressAt = null;
    } on KugouApiException catch (failure) {
      if (_disposed) return;
      error = playbackErrorMessage(failure);
      snapshot = snapshot.copyWith(playing: false);
    } on Object catch (failure) {
      if (_disposed) return;
      error = '播放失败：$failure';
      snapshot = snapshot.copyWith(playing: false);
    } finally {
      if (!_disposed) isResolving = false;
    }
  }

  /// 队列到尾：停在最后一首并标记「播完」，不回绕。
  Future<void> _stopAtEnd() async {
    final engine = _engine;
    if (engine != null) {
      try {
        await engine.pause();
      } on Object {
        // 引擎已退出/未打开时 pause 失败不影响状态收敛。
      }
    }
    if (_disposed) return;
    snapshot = snapshot.copyWith(playing: false, completed: true);
    _completionWritten = true;
    await _writeCurrentProgress();
  }

  void _onSnapshot(MusicPlaybackSnapshot next) {
    // 解析中旧曲仍在同一引擎播放：此时快照属于旧曲，不能记到新歌头上。
    if (_disposed || isResolving) return;
    snapshot = next;
    if (next.error != null && next.error!.isNotEmpty) {
      error = '播放失败：${next.error}';
    }
    if (next.completed) {
      if (!_completionWritten) {
        _completionWritten = true;
        unawaited(_writeCurrentProgress());
      }
      return;
    }
    if (next.playing) {
      final now = _clock();
      final last = _lastProgressAt;
      if (last != null && now.difference(last) < musicProgressInterval) {
        return;
      }
      unawaited(_writeCurrentProgress());
    }
  }

  Future<void> _writeCurrentProgress() async {
    final song = currentSong;
    if (song == null) return;
    await _writeProgressFor(song, snapshot.position, snapshot.duration);
  }

  Future<void> _writeProgressFor(
    MusicSong song,
    Duration position,
    Duration duration,
  ) async {
    final sink = _progressSink;
    if (sink == null) return;
    _lastProgressAt = _clock();
    try {
      await sink(song, position, duration);
    } on Object {
      // 进度写入失败不挡播放。
    }
  }

  String _songKey(MusicSong song) => song.id.isNotEmpty ? song.id : song.hash;
}

/// 解析失败 → 用户文案（只认 kind；business 带错误码并解释）。
String playbackErrorMessage(KugouApiException failure) =>
    switch (failure.kind) {
      'authentication' => '请先登录酷狗账号后播放',
      'business' => '该曲目暂不可播（错误码 ${failure.code ?? '未知'}）',
      'input' => '曲目信息不完整',
      'http' => '网络错误，请稍后重试',
      'decode' => '音乐服务响应异常，请稍后重试',
      _ => '播放失败：${failure.message}',
    };
