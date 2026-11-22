/// 播放器状态内核（M4-P，MobX）——队列/当前曲目/快照/错误 + 进度写入 +
/// 听歌上报（L4：成功起播发 start，切歌/播完/停止/dispose 发 end）。
///
/// 只经契约 [MusicPlayerUi] 对外暴露（见 `player_ui_impl.dart`）；页面与
/// 入口不直接依赖本类。测试可以直接 `MusicPlayerStore(...)` 注入 fake
/// playbackApi / fake engine / 注入时钟，不触碰 media_kit。
library;

import 'dart:async';
import 'dart:math';

import 'package:mimao/music/api/listen_report_api.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_listen_report_models.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/player/play_mode.dart';
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
    MusicListenReportApi? listenReport,
    MusicSettings? settings,
    Random? random,
  }) : _engineFactory = engineFactory,
       _progressSink = progressSink,
       _clock = clock ?? DateTime.now,
       _listenReport = listenReport,
       _settings = settings,
       _randomOverride = random {
    // 构造期同步读设置（LazyMusicSettings 解析前返回默认值）；null → 默认。
    playMode = _settings?.playMode ?? PlayMode.listLoop;
  }

  final MusicPlaybackApi playbackApi;

  /// 惰性求值：首次 playSong 才调用；null = 播放未配置（测试/未接线）。
  final MusicPlaybackEngine Function()? _engineFactory;

  /// 进度写入口；null 时不写进度，其余功能照常。
  final ProgressSink? _progressSink;

  /// 注入时钟（节流判定；测试不真实等待）。
  final DateTime Function() _clock;

  /// 听歌上报缝；null 时不上报（测试/未接线）。
  final MusicListenReportApi? _listenReport;

  /// 本地设置（听歌上报开关）；null 视为允许上报。
  final MusicSettings? _settings;

  /// 随机播放用的随机源（测试可注入固定序列）。
  ///
  /// 允许多次赋值以兼容热重载：长生命周期单例新增字段时构造器不会重跑，
  /// 新字段可能仍是 null；由 [_random] getter 在首次访问时懒初始化，
  /// 避免 shuffle 模式下 `Null is not a subtype of Random` 崩溃。
  Random? _randomOverride;

  /// 随机源访问点：注入值优先，否则懒初始化一个默认 [Random]。
  Random get _random => _randomOverride ??= Random();

  /// 播放页读取的本地设置（歌词开关/显示模式）；null 视为默认值。
  MusicSettings? get settings => _settings;

  MusicPlaybackEngine? _engine;
  StreamSubscription<MusicPlaybackSnapshot>? _engineSubscription;
  DateTime? _lastProgressAt;
  bool _disposed = false;
  bool _completionWritten = false;

  // ---- 听歌上报会话（同一首歌 start→end 只报一对；换歌只 end 上一首）----

  /// 会话中的歌曲 key（song.id 优先，空则 hash）；null = 无未收尾会话。
  String? _reportSongKey;

  /// 会话歌曲的上报主键（id 非数字/≤0 的歌不建会话，start/end 都跳过）。
  int? _reportMixsongid;

  /// 本次会话已累计的播放毫秒数（暂停停表、切歌/播完/停止/dispose 结算）。
  int _reportPlayedMs = 0;

  /// 当前连续播放段的起始时刻（null = 未在计时）。
  DateTime? _reportPlayingSince;

  @observable
  ObservableList<MusicSong> queue = ObservableList<MusicSong>();

  @observable
  int index = -1;

  @observable
  MusicPlaybackSnapshot snapshot = const MusicPlaybackSnapshot();

  @observable
  bool isResolving = false;

  /// 播放模式（随机 / 单曲循环 / 列表循环），默认列表循环。
  @observable
  PlayMode playMode = PlayMode.listLoop;

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

  /// 用整个列表替换播放队列，并从 [startIndex] 首开始播。
  /// 空列表不做事；startIndex 越界时 clamp 到有效范围。
  @action
  Future<void> playList(
    List<MusicSong> songs, {
    int startIndex = 0,
    Duration startAt = Duration.zero,
  }) async {
    if (_disposed || songs.isEmpty) return;
    // 与 playSong 一致：无引擎只报错，不动现有队列。
    if (_ensureEngine() == null) {
      error = '播放未配置';
      return;
    }

    // 先结算上一首：此刻 queue/index 仍是旧值，进度与上报都落在旧歌上。
    if (currentSong != null) {
      _finishReportSession(completed: snapshot.completed);
      await _writeCurrentProgress();
      if (_disposed) return;
    }

    // 再整体换队列、落索引，最后按新索引起播（不重复结算上一首）。
    final target = startIndex < 0
        ? 0
        : (startIndex >= songs.length ? songs.length - 1 : startIndex);
    queue = ObservableList<MusicSong>.of(songs);
    index = target;
    await _start(
      songs[target],
      startAt: startAt,
      targetIndex: target,
      recordOutgoing: false,
    );
  }

  /// 切换播放模式：立即生效并尽力落盘（失败不影响本次会话）。
  @action
  void setPlayMode(PlayMode mode) {
    playMode = mode;
    final settings = _settings;
    if (settings == null) return;
    unawaited(_persistPlayMode(settings, mode));
  }

  Future<void> _persistPlayMode(MusicSettings settings, PlayMode mode) async {
    try {
      await settings.setPlayMode(mode);
    } on Object {
      // 持久化失败只影响下次启动的初值，不挡播放。
    }
  }

  @action
  Future<void> next() async {
    if (_disposed) return;
    if (queue.isEmpty) {
      await _stopAtEnd();
      return;
    }
    final target = _nextIndex();
    await _start(queue[target], targetIndex: target);
  }

  @action
  Future<void> previous() async {
    if (_disposed || queue.isEmpty) return;
    final target = _previousIndex();
    await _start(queue[target], targetIndex: target);
  }

  /// 按播放模式计算下一首下标（队列非空时调用）。
  int _nextIndex() {
    final length = queue.length;
    switch (playMode) {
      case PlayMode.repeatOne:
        return index < 0 ? 0 : index;
      case PlayMode.shuffle:
        return _randomOtherIndex();
      case PlayMode.listLoop:
        return index < 0 ? 0 : (index + 1) % length;
    }
  }

  /// 按播放模式计算上一首下标（队列非空时调用）。
  int _previousIndex() {
    final length = queue.length;
    switch (playMode) {
      case PlayMode.repeatOne:
        return index < 0 ? 0 : index;
      case PlayMode.shuffle:
        return _randomOtherIndex();
      case PlayMode.listLoop:
        if (index < 0) return 0;
        return index == 0 ? length - 1 : index - 1;
    }
  }

  /// 随机取一个不等于当前曲的下标；单曲队列重播当前。
  int _randomOtherIndex() {
    final length = queue.length;
    if (length <= 1) return index < 0 ? 0 : index;
    var candidate = _random.nextInt(length);
    if (candidate == index) candidate = (candidate + 1) % length;
    return candidate;
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
      // 暂停只停上报计时，不发 end（end 只在切歌/播完/停止/dispose）。
      _pauseReportClock();
      await _writeCurrentProgress();
    } else {
      await engine.play();
      if (_disposed) return;
      snapshot = snapshot.copyWith(playing: true);
      _resumeReportClock();
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

  /// 相对当前位置快进/快退（快捷键用），clamp 到 0~duration。
  /// 与 EchoMusic 的快进步长一致取 10 秒。
  Future<void> seekBy(Duration delta) {
    final target = snapshot.position + delta;
    final duration = snapshot.duration;
    final clamped = duration > Duration.zero && target > duration
        ? duration
        : (target < Duration.zero ? Duration.zero : target);
    return seekTo(clamped);
  }

  /// 循环切换播放模式（快捷键「切换播放模式」用）。
  @action
  Future<void> cyclePlayMode() async {
    final next = switch (playMode) {
      PlayMode.listLoop => PlayMode.repeatOne,
      PlayMode.repeatOne => PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.listLoop,
    };
    setPlayMode(next);
    _bumpLyricEpoch();
  }

  /// 歌词开关变化后需要让播放页 Observer 重建（settings 不是 observable）。
  /// 这里递增 epoch 并让 UI 通过 [settingsEpoch] 观察。
  @observable
  int settingsEpoch = 0;

  void _bumpLyricEpoch() => settingsEpoch++;

  /// 切换播放页歌词显示（写入本地设置并通知 UI 重建）。
  Future<void> toggleLyric() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.setLyricEnabled(!settings.lyricEnabled);
      _bumpLyricEpoch();
    } on Object {
      // 写盘失败不挡本次会话；不改变内存状态。
    }
  }

  /// 当前音量（0.0~1.0）；引擎尚未构造时返回默认满音量。
  @observable
  double volume = 1.0;

  /// 静音前的音量，用于「取消静音」还原。
  double _volumeBeforeMute = 1.0;

  @observable
  bool muted = false;

  /// 设置音量；同时解除静音。引擎不存在时只更新状态（首次起播后生效）。
  @action
  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    volume = clamped;
    if (clamped > 0) muted = false;
    final engine = _engine;
    if (engine == null) return;
    await engine.setVolume(clamped);
  }

  /// 音量增减（步长 0.1），clamp 到 0.0~1.0。快捷键「音量 +/-」调用。
  Future<void> adjustVolume(double delta) => setVolume(volume + delta);

  /// 静音切换：静音时记住当前音量，取消时还原。
  Future<void> toggleMute() async {
    if (muted) {
      muted = false;
      await setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0);
      return;
    }
    _volumeBeforeMute = volume;
    muted = true;
    await setVolume(0.0);
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
    // dispose 前结算听歌上报（end，completed 取当前快照；fire-and-forget）。
    _finishReportSession(completed: snapshot.completed);
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
      // 切歌：结算上一首的上报会话（end 只发上一首），再落历史进度。
      _finishReportSession(completed: snapshot.completed);
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
      if (_disposed) return;
      // 解析成功并起播 → 开听歌上报会话（start；同一首不重复 start）。
      _beginReportSession(song);
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

  /// 停止播放并标记「播完」（队列为空的兜底路径；三种播放模式正常播放
  /// 不走这里，改为按模式切歌）。
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
    // 队列到尾 = 播完：结算上报会话（completed=true）。
    _finishReportSession(completed: true);
    await _writeCurrentProgress();
  }

  void _onSnapshot(MusicPlaybackSnapshot next) {
    // 解析中旧曲仍在同一引擎播放：此时快照属于旧曲，不能记到新歌头上。
    if (_disposed || isResolving) return;
    final wasPlaying = snapshot.playing;
    if (next.playing && !wasPlaying) _resumeReportClock();
    if (!next.playing && wasPlaying) _pauseReportClock();
    snapshot = next;
    if (next.error != null && next.error!.isNotEmpty) {
      error = '播放失败：${next.error}';
    }
    if (next.completed) {
      final firstCompletion = !_completionWritten;
      if (firstCompletion) _completionWritten = true;
      // 播完：先结算上报（completed=快照 completed）；重复快照靠会话去重。
      _finishReportSession(completed: next.completed);
      if (firstCompletion) {
        if (!_disposed && currentSong != null) {
          // 按播放模式自动切歌；_start 的 recordOutgoing 顺带落一次进度。
          unawaited(this.next());
        } else {
          unawaited(_writeCurrentProgress());
        }
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

  // ---- 听歌上报（L4）：fire-and-forget，绝不挡播放 ----

  /// 进入播放状态：开始计时（已在计时则续用当前段）。
  void _resumeReportClock() {
    _reportPlayingSince ??= _clock();
  }

  /// 离开播放状态：把当前连续播放段并入累计时长（时钟倒退按 0 计）。
  void _pauseReportClock() {
    final since = _reportPlayingSince;
    if (since == null) return;
    _reportPlayingSince = null;
    final delta = _clock().difference(since).inMilliseconds;
    if (delta > 0) _reportPlayedMs += delta;
  }

  /// 成功起播后调用：为这首歌开上报会话并发 start。
  void _beginReportSession(MusicSong song) {
    final mixsongid = int.tryParse(song.id);
    if (mixsongid == null || mixsongid <= 0) {
      // 协议要求 u64 主键：非数字/≤0 的 id 不参与上报（start/end 都跳过）。
      _reportSongKey = null;
      _reportMixsongid = null;
      _reportPlayedMs = 0;
      _reportPlayingSince = null;
      return;
    }
    final key = _songKey(song);
    if (_reportSongKey == key) {
      return; // 同一首不重复 start（如播放中出错后重试成功）。
    }
    // 正常路径上一首已在切歌时收尾；防御性再收一次（换歌只 end 上一首）。
    _finishReportSession(completed: false);
    _reportSongKey = key;
    _reportMixsongid = mixsongid;
    _reportPlayedMs = 0;
    _reportPlayingSince = null;
    unawaited(
      _sendListenReport(
        MusicListenReportQuery(
          event: MusicListenReportEvent.start,
          mixsongid: mixsongid,
        ),
      ),
    );
  }

  /// 切歌/播完/停止/dispose 时调用：结算并上报 end（durationMs=本次已播时长）。
  void _finishReportSession({required bool completed}) {
    _pauseReportClock();
    final mixsongid = _reportMixsongid;
    if (_reportSongKey == null || mixsongid == null) return;
    _reportSongKey = null;
    _reportMixsongid = null;
    final durationMs = _reportPlayedMs;
    _reportPlayedMs = 0;
    unawaited(
      _sendListenReport(
        MusicListenReportQuery(
          event: MusicListenReportEvent.end,
          mixsongid: mixsongid,
          durationMs: durationMs < 0 ? 0 : durationMs,
          completed: completed,
        ),
      ),
    );
  }

  /// 上报一次事件；开关关闭/无 settings 视为 true/异常一律吞掉。
  Future<void> _sendListenReport(MusicListenReportQuery query) async {
    final api = _listenReport;
    if (api == null) return;
    try {
      final settings = _settings;
      if (settings != null) {
        await settings.ensureLoaded();
        if (!settings.listenReportEnabled) return;
      }
      await api.listenReport(query);
    } on Object {
      // 上报失败（含开关读取失败）不影响播放，也不重试。
    }
  }
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
