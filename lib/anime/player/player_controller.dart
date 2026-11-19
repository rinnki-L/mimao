import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/playback_engine.dart';

/// 一集：展示号 + 标题 + 可播放地址（m3u8 或直链）。
///
/// A 线（规则引擎）联调时由剧集列表映射成它。[headers] 是该集播放时要带的
/// 规则级请求头（UA/Referer），默认空 map 保持既有调用点行为不变。
/// [roadIndex]/[roadName] 标记该集所属线路，播放页据此渲染线路选择器。
class Episode {
  final int number;
  final String title;
  final String url;

  /// 规则级请求头；空 map 表示不带自定义头。
  final Map<String, String> headers;

  /// 线路序号（从 1 开始）与线路名；默认对应单线路。
  final int roadIndex;
  final String roadName;

  const Episode({
    required this.number,
    required this.title,
    required this.url,
    this.headers = const <String, String>{},
    this.roadIndex = 1,
    this.roadName = '',
  });
}

/// 播放页/控制器的粗粒度状态，UI 只按它切换加载态与错误态。
enum PlayerStatus { idle, loading, playing, paused, completed, error }

/// 播放控制器：唯一持有播放状态的地方。
///
/// 依赖的是 [PlaybackEngine] 接口而不是 media_kit——单测注入假后端即可，
/// 不需要真实解码；UI 通过 [ChangeNotifier] 重建。
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.engine,
    required List<Episode> episodes,
    ProgressRecorder? progressRecorder,
    this.onProgress,
    int initialIndex = 0,
  }) : _episodes = List<Episode>.unmodifiable(episodes),
       _recorder = progressRecorder,
       _index = initialIndex {
    if (episodes.isEmpty) {
      throw ArgumentError.value(episodes, 'episodes', '剧集列表不能为空');
    }
    RangeError.checkValidIndex(initialIndex, episodes, 'initialIndex');
    _subscription = engine.snapshots.listen(_onSnapshot);
  }

  static const double minSpeed = 0.5;
  static const double maxSpeed = 3.0;

  /// UI 倍速菜单的预设值，全部落在 [minSpeed, maxSpeed] 内。
  static const List<double> speedPresets = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
  ];

  final PlaybackEngine engine;
  final List<Episode> _episodes;
  final ProgressRecorder? _recorder;

  /// 播放进度回调：每次后端快照上报 `(position, total)`，单位 Duration。
  /// 集成方接 UI 进度条/时间表时用；持久化仍走 [ProgressRecorder] 的持久化点。
  final void Function(Duration position, Duration total)? onProgress;

  late final StreamSubscription<PlaybackSnapshot> _subscription;

  int _index;
  PlayerStatus _status = PlayerStatus.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _buffering = false;
  String? _errorMessage;
  bool _completionPersisted = false;
  bool _disposed = false;

  List<Episode> get episodes => _episodes;
  int get index => _index;
  int get episodeCount => _episodes.length;
  Episode get currentEpisode => _episodes[_index];
  PlayerStatus get status => _status;
  bool get isPlaying => _status == PlayerStatus.playing;
  bool get isLoading =>
      _status == PlayerStatus.idle || _status == PlayerStatus.loading;
  bool get buffering => _buffering;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;
  String? get errorMessage => _errorMessage;
  bool get hasPrevious => _index > 0;
  bool get hasNext => _index < _episodes.length - 1;

  /// 打开当前集起播。`resumeAt` 供"从上次进度继续"用（校正点/详情页联调）。
  Future<void> start({Duration? resumeAt}) async {
    if (_disposed) return;
    final episode = currentEpisode;
    _status = PlayerStatus.loading;
    _errorMessage = null;
    _duration = Duration.zero;
    _position = resumeAt ?? Duration.zero;
    _completionPersisted = false;
    _notify();
    try {
      await engine.open(
        episode.url,
        startAt: _position,
        headers: episode.headers.isEmpty ? null : episode.headers,
      );
    } catch (error) {
      _fail(error);
    }
  }

  /// 当前剧集所有可用线路（按剧集列表里首次出现的顺序去重）。
  /// 单线路时只有一个元素，播放页据此隐藏线路选择器。
  List<({int roadIndex, String roadName})> get availableRoads {
    final seen = <int>{};
    final roads = <({int roadIndex, String roadName})>[];
    for (final episode in _episodes) {
      if (seen.add(episode.roadIndex)) {
        roads.add((roadIndex: episode.roadIndex, roadName: episode.roadName));
      }
    }
    return roads;
  }

  /// 当前播放集所属线路序号。
  int get currentRoadIndex => currentEpisode.roadIndex;

  /// 切线路：用新线路里「与当前同集数」的剧集重建播放地址（找不到时回退到
  /// 该线路第 1 集）。复用 [loadEpisode] 的进度落盘 + open + [_fail] 路径，
  /// 不引入新的错误态/重试语义。
  Future<void> switchRoad(int roadIndex) async {
    if (_disposed) return;
    final currentNumber = currentEpisode.number;
    var target = _episodes.indexWhere(
      (episode) =>
          episode.roadIndex == roadIndex && episode.number == currentNumber,
    );
    if (target < 0) {
      target = _episodes.indexWhere(
        (episode) => episode.roadIndex == roadIndex,
      );
    }
    if (target < 0) return; // 未知线路：UI 只会列出存在的线路，静默忽略。
    await _loadIndex(target);
  }

  /// 切集。越界直接 [RangeError]，状态保持不变（验收点：切集索引边界）。
  ///
  /// 切集是**持久化点**：先落旧集进度，再换源起播。
  Future<void> loadEpisode(int index, {Duration? startAt}) async {
    RangeError.checkValidIndex(index, _episodes, 'index');
    await _loadIndex(index, startAt: startAt);
  }

  /// loadEpisode / switchRoad 共用的切集实现：落进度 → 换源起播 → 错误态。
  Future<void> _loadIndex(int index, {Duration? startAt}) async {
    if (_disposed) return;

    await _persistProgress();

    _index = index;
    _position = Duration.zero;
    _duration = Duration.zero;
    _completionPersisted = false;
    _status = PlayerStatus.loading;
    _errorMessage = null;
    _notify();

    final episode = _episodes[index];
    try {
      await engine.open(
        episode.url,
        startAt: startAt ?? Duration.zero,
        headers: episode.headers.isEmpty ? null : episode.headers,
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> togglePlay() async {
    if (_disposed ||
        _status == PlayerStatus.idle ||
        _status == PlayerStatus.loading) {
      return;
    }
    if (_status == PlayerStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    if (_status == PlayerStatus.completed) {
      await seek(Duration.zero);
      _completionPersisted = false;
    }
    _status = PlayerStatus.playing;
    _errorMessage = null;
    _notify();
    await engine.play();
  }

  /// 暂停是**持久化点**：调用即写内部库 + core 投影。
  Future<void> pause() async {
    if (_disposed) return;
    _status = PlayerStatus.paused;
    _notify();
    await engine.pause();
    await _persistProgress();
  }

  /// 跳转；越界自动钳制到 [0, duration]。
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    var target = position < Duration.zero ? Duration.zero : position;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    _position = target;
    if (_status == PlayerStatus.completed) _status = PlayerStatus.paused;
    _notify();
    await engine.seek(target);
  }

  /// 限制在 [minSpeed, maxSpeed]；非法值抛 [ArgumentError]，状态不变。
  Future<void> setSpeed(double speed) async {
    if (!speed.isFinite || speed < minSpeed || speed > maxSpeed) {
      throw ArgumentError.value(
        speed,
        'speed',
        '倍速必须位于 $minSpeed–$maxSpeed 之间',
      );
    }
    if (_disposed || speed == _speed) return;
    _speed = speed;
    await engine.setSpeed(speed);
    _notify();
  }

  /// 手动持久化点（如切后台时由集成方调用）。
  Future<void> persistNow() => _persistProgress();

  void _onSnapshot(PlaybackSnapshot snapshot) {
    if (_disposed) return;
    final error = snapshot.error;
    if (error != null && error.isNotEmpty) {
      _errorMessage = error;
      _status = PlayerStatus.error;
      _notify();
      return;
    }

    _buffering = snapshot.buffering;
    _position = snapshot.position;
    if (snapshot.duration > Duration.zero) _duration = snapshot.duration;
    onProgress?.call(_position, _duration);

    if (snapshot.completed && !_completionPersisted) {
      _status = PlayerStatus.completed;
      _completionPersisted = true;
      unawaited(_persistProgress(completed: true));
    } else if (snapshot.playing) {
      _status = PlayerStatus.playing;
      _errorMessage = null;
    } else if (_status == PlayerStatus.playing) {
      _status = PlayerStatus.paused;
    }
    _notify();
  }

  Future<void> _persistProgress({bool completed = false}) async {
    final recorder = _recorder;
    if (recorder == null) return;
    final position = completed && _duration > Duration.zero
        ? _duration
        : _position;
    // 还没开始播就切集/退出时不写，避免用 0 覆盖内部库里的真实进度。
    if (!completed && position <= Duration.zero) return;
    try {
      await recorder.persist(
        EpisodeProgress(
          episode: currentEpisode.number,
          episodeTitle: currentEpisode.title,
          position: position,
          total: _duration,
        ),
      );
    } catch (error) {
      _errorMessage = '进度保存失败：$error';
      _notify();
    }
  }

  /// 打开流失败：切到错误态并提示（start / loadEpisode 共用）。
  void _fail(Object error) {
    _status = PlayerStatus.error;
    _errorMessage = '$error';
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // 退出播放页也是一个持久化点。
    unawaited(_persistProgress());
    unawaited(_subscription.cancel());
    unawaited(engine.dispose());
    super.dispose();
  }
}
