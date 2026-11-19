import 'dart:async';

import 'package:mimao/anime/player/playback_engine.dart';

/// 单测用假后端：不拉起 libmpv、不联网，只记录调用并回放快照。
///
/// 行为对齐真实适配层的关键点（事件序列证据见
/// docs/anime-mpv-error-mask-diagnosis.md）：
///  - `open` 表示"打开并起播"（对应 `Player.open(..., play: true)`），
///    会把 playing 置 true 并推快照——真实 mpv 对坏地址也是**乐观起播**，
///    错误要 1.4–5s 后才经 `stream.error` 迟到（S1/S5 实测）；
///  - `open` 会清掉上一代的 error（对应真实 engine.open 的 `_error = null`）；
///  - 通过 [openFailures] 注入坏地址后，错误不立即上报，而是排队等
///    [flushPendingErrors] 手动投递——让测试能精确控制"错误迟到窗口"；
///  - `open` 换代时会**丢弃**尚未投递的旧代 pending 错误：对应 mpv
///    loadfile replace 对被替换加载的静默取消（S4/S6 实测，旧代错误从此
///    不再出现）。
class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackSnapshot> _snapshots =
      StreamController<PlaybackSnapshot>.broadcast();

  /// 脚本化坏地址：url → 错误文案。open 该地址时错误进 [pendingErrors]，
  /// 由测试择机 [flushPendingErrors] 投递（模拟真实引擎的错误迟到）。
  final Map<String, String> openFailures = <String, String>{};

  /// 已注入、尚未投递的错误文案队列（FIFO）。
  final List<String> pendingErrors = <String>[];

  final List<String> openedUrls = <String>[];

  /// 每次 open 收到的请求头（UA/Referer），供测试断言透传；fake 不真正使用它们。
  final List<Map<String, String>?> openedHeaders = <Map<String, String>?>[];

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

  /// 把 [pendingErrors] 里的错误逐条投递出去（每条推一个快照）。
  ///
  /// 与真实引擎一致：error 字段置上后保持（粘滞到下一次 open），期间
  /// 后续快照都会带着它。
  void flushPendingErrors() {
    while (pendingErrors.isNotEmpty) {
      error = pendingErrors.removeAt(0);
      emitSnapshot();
    }
  }

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    Map<String, String>? headers,
  }) async {
    openedUrls.add(url);
    openedHeaders.add(
      headers == null ? null : Map<String, String>.from(headers),
    );
    position = startAt;
    playing = true;
    completed = false;
    error = null;
    emitSnapshot();
    // mpv loadfile replace 静默取消被替换的加载：旧代尚未到达的错误从此
    // 不再出现（S4/S6 实测）。换代时先丢弃旧代 pending 再注入本代失败。
    pendingErrors.clear();
    final String? failure = openFailures[url];
    if (failure != null) {
      pendingErrors.add(failure);
    }
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
