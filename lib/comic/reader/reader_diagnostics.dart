// 阅读短时诊断：opt-in、内存内、可导出 JSON。
//
// 移植自 Venera-Next `lib/foundation/reader_diagnostics.dart` 的核心（schema 3
// 的子集）：45 秒采集、逐图阶段耗时、帧时间统计、导航事件、图片缓存前后快照、
// 有界缓冲与超长预览裁剪。
//
// 与上游的差别：上游接 `ImageWork` 的任务生命周期与自定义 JS 处理阶段；本仓
// 阅读器没有那两层，所以阶段枚举只保留本仓真实存在的读取/解码/显示等待。
//
// 隐私边界（与上游同口径）：不记录漫画标题、路径、URL、账号、脚本正文或
// 错误正文，图片只用本轮匿名编号。

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

/// 阅读模式（诊断里只记录名字，便于对照不同模式）。
enum ReaderDiagnosticMode { paged, continuous, waterfall }

/// 单张图的等待阶段。
enum ReaderDiagnosticStage {
  /// 本地文件 / 编码缓存读取。
  read,

  /// 解码器初始化与首帧解码。
  decode,

  /// 从拿到字节到真正上屏。
  display,
}

/// 采集结束原因。
enum ReaderDiagnosticStop { timeout, review, background, interrupted, disposed }

/// 导航事件类型。
enum ReaderDiagnosticNavigation {
  animationStart,
  animationEnd,
  jumpToPage,
  pageSelected,
  viewport,
}

/// 一次 opt-in 的内存内采集。
class ReaderDiagnostics extends ChangeNotifier {
  ReaderDiagnostics({
    int Function()? nowMicros,
    void Function(TimingsCallback)? attachTimings,
    void Function(TimingsCallback)? detachTimings,
    this.maxEvents = 480,
    this.maxFrames = 6000,
    this.maxImages = 256,
    this.maxNavigationEvents = 480,
  }) : assert(
         maxEvents > 0 &&
             maxFrames > 0 &&
             maxImages > 0 &&
             maxNavigationEvents > 0,
       ),
       _nowMicros = nowMicros ?? (() => Timeline.now),
       _attachTimings =
           attachTimings ??
           ((callback) =>
               SchedulerBinding.instance.addTimingsCallback(callback)),
       _detachTimings =
           detachTimings ??
           ((callback) =>
               SchedulerBinding.instance.removeTimingsCallback(callback));

  static const captureDuration = Duration(seconds: 45);
  static const maxReportCharacters = 60000;
  static const frameSampleColumns = <String>[
    'receivedAtUs',
    'uiUs',
    'rasterUs',
    'totalSpanUs',
    'vsyncStartUs',
    'buildStartUs',
  ];

  final int maxEvents;
  final int maxFrames;
  final int maxImages;
  final int maxNavigationEvents;

  final int Function() _nowMicros;
  final void Function(TimingsCallback) _attachTimings;
  final void Function(TimingsCallback) _detachTimings;

  final ListQueue<Map<String, Object>> _events =
      ListQueue<Map<String, Object>>();
  final ListQueue<List<int>> _frames = ListQueue<List<int>>();
  final ListQueue<Map<String, Object>> _navigationEvents =
      ListQueue<Map<String, Object>>();
  final Map<int, int> _imageIds = <int, int>{};

  Timer? _timer;
  int _generation = 0;
  int _startedAt = 0;
  int _duration = 0;
  int _droppedEvents = 0;
  int _droppedFrames = 0;
  int _ignoredImages = 0;
  int _droppedNavigationEvents = 0;
  int _inFlight = 0;
  int _inFlightAtStop = 0;
  bool _recording = false;
  bool _hasCapture = false;
  bool _disposed = false;
  double _frameBudgetUs = 1000000 / 60;
  Map<String, Object> _configuration = <String, Object>{};
  Map<String, int> _cacheBefore = <String, int>{};
  Map<String, int> _cacheAfter = <String, int>{};
  ReaderDiagnosticStop? _stopReason;
  late final TimingsCallback _onFrames = _recordFrames;

  bool get isRecording => _recording;
  bool get hasCapture => _hasCapture;
  int? get captureGeneration => _recording ? _generation : null;
  int get _elapsed => math.max(0, _nowMicros() - _startedAt);

  void _notifyChanged() {
    if (_disposed) return;
    // 采集截止可能在建帧回调里被发现，此时延到微任务再通知。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  bool _acceptSample() {
    if (_recording && _elapsed >= captureDuration.inMicroseconds) {
      stop(ReaderDiagnosticStop.timeout);
    }
    return _recording;
  }

  static Map<String, int> _cacheSnapshot() {
    final cache = PaintingBinding.instance.imageCache;
    return <String, int>{
      'maximumBytes': cache.maximumSizeBytes,
      'maximumImages': cache.maximumSize,
      'decodedBytes': cache.currentSizeBytes,
      'keepAliveImages': cache.currentSize,
      'liveImages': cache.liveImageCount,
      'pendingImages': cache.pendingImageCount,
    };
  }

  void start({
    required ReaderDiagnosticMode mode,
    required String appVersion,
    required double refreshRate,
  }) {
    if (_disposed) return;
    stop(ReaderDiagnosticStop.interrupted);
    clear(notify: false);
    final hz = refreshRate.isFinite && refreshRate >= 1 && refreshRate <= 1000
        ? refreshRate
        : 60.0;
    _frameBudgetUs = 1000000 / hz;
    _configuration = <String, Object>{
      'appVersion':
          RegExp(
            r'^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?(?:\+\d+)?$',
          ).hasMatch(appVersion)
          ? appVersion
          : 'unknown',
      'platform': defaultTargetPlatform.name,
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'readerMode': mode.name,
      'displayRefreshHz': hz,
    };
    _cacheBefore = _cacheSnapshot();
    _startedAt = _nowMicros();
    _recording = true;
    _hasCapture = true;
    _attachTimings(_onFrames);
    _timer = Timer(captureDuration, () => stop(ReaderDiagnosticStop.timeout));
    _notifyChanged();
  }

  void stop(ReaderDiagnosticStop reason) {
    if (!_recording) return;
    _duration = math.min(_elapsed, captureDuration.inMicroseconds);
    _recording = false;
    _timer?.cancel();
    _timer = null;
    _detachTimings(_onFrames);
    _cacheAfter = _cacheSnapshot();
    _inFlightAtStop = _inFlight;
    _imageIds.clear();
    _stopReason = reason;
    _notifyChanged();
  }

  void clear({bool notify = true}) {
    if (_recording) stop(ReaderDiagnosticStop.interrupted);
    _generation++;
    _hasCapture = false;
    _events.clear();
    _frames.clear();
    _navigationEvents.clear();
    _imageIds.clear();
    _droppedEvents = 0;
    _droppedFrames = 0;
    _ignoredImages = 0;
    _droppedNavigationEvents = 0;
    _inFlight = 0;
    _inFlightAtStop = 0;
    _duration = 0;
    _stopReason = null;
    _configuration = <String, Object>{};
    _cacheBefore = <String, int>{};
    _cacheAfter = <String, int>{};
    if (notify) _notifyChanged();
  }

  int? _imageId(int identity) {
    final existing = _imageIds[identity];
    if (existing != null) return existing;
    if (_imageIds.length >= maxImages) {
      _ignoredImages++;
      return null;
    }
    final id = _imageIds.length + 1;
    _imageIds[identity] = id;
    return id;
  }

  /// 开始记录某张图的一个阶段；返回的 span 调 [ReaderDiagnosticSpan.finish] 结束。
  ReaderDiagnosticSpan? beginImageSpan(
    int identity,
    ReaderDiagnosticStage stage,
  ) {
    if (!_acceptSample()) return null;
    final image = _imageId(identity);
    if (image == null) return null;
    _inFlight++;
    return ReaderDiagnosticSpan._(this, _generation, image, stage, _elapsed);
  }

  void recordCache(
    int identity, {
    required bool pending,
    required bool keepAlive,
    required bool live,
  }) {
    if (!_acceptSample()) return;
    final image = _imageId(identity);
    if (image == null) return;
    _append(<String, Object>{
      'atUs': _elapsed,
      'image': image,
      'stage': 'cacheLookup',
      'pending': pending,
      'keepAlive': keepAlive,
      'live': live,
    });
  }

  void _append(Map<String, Object> event) {
    if (_events.length == maxEvents) {
      _events.removeFirst();
      _droppedEvents++;
    }
    _events.add(event);
  }

  void recordNavigation(
    ReaderDiagnosticNavigation event, {
    required int page,
    int? targetPage,
    int? chapter,
    double? viewportPage,
    bool? scrolling,
  }) {
    if (!_acceptSample()) return;
    if (_navigationEvents.length == maxNavigationEvents) {
      _navigationEvents.removeFirst();
      _droppedNavigationEvents++;
    }
    _navigationEvents.add(<String, Object>{
      'atUs': _elapsed,
      'event': event.name,
      'page': page,
      if (targetPage != null) 'targetPage': targetPage,
      if (chapter != null) 'chapter': chapter,
      if (viewportPage != null && viewportPage.isFinite)
        'viewportPage': viewportPage,
      if (scrolling != null) 'scrolling': scrolling,
    });
  }

  /// 记录一次翻页动画开始；返回句柄，结束调 [ReaderDiagnosticPageTurn.finish]。
  ReaderDiagnosticPageTurn? beginPageTurn({
    required int page,
    required int targetPage,
    required int chapter,
    double? viewportPage,
  }) {
    if (!_acceptSample()) return null;
    recordNavigation(
      ReaderDiagnosticNavigation.animationStart,
      page: page,
      targetPage: targetPage,
      chapter: chapter,
      viewportPage: viewportPage,
    );
    return ReaderDiagnosticPageTurn._(this, _generation, targetPage, chapter);
  }

  void _recordFrames(List<FrameTiming> timings) {
    if (!_acceptSample()) return;
    final receivedAt = _elapsed;
    for (final frame in timings) {
      if (_frames.length == maxFrames) {
        _frames.removeFirst();
        _droppedFrames++;
      }
      _frames.add(<int>[
        receivedAt,
        frame.buildDuration.inMicroseconds,
        frame.rasterDuration.inMicroseconds,
        frame.totalSpan.inMicroseconds,
        frame.timestampInMicroseconds(FramePhase.vsyncStart) - _startedAt,
        frame.timestampInMicroseconds(FramePhase.buildStart) - _startedAt,
      ]);
    }
  }

  Map<String, Object> _summary(Iterable<int> source) {
    final values = source.toList()..sort();
    if (values.isEmpty) return <String, Object>{'count': 0};
    return <String, Object>{
      'count': values.length,
      'medianUs': values[values.length ~/ 2],
      'p95Us': values[(values.length * .95).ceil() - 1],
      'maxUs': values.last,
    };
  }

  /// 导出 JSON。[complete] 为 true 时不裁剪（用于保存到文件）。
  String exportJson({bool complete = false}) {
    final slow =
        _frames
            .where(
              (frame) => frame[1] > _frameBudgetUs || frame[2] > _frameBudgetUs,
            )
            .toList()
          ..sort(
            (a, b) => math.max(b[1], b[2]).compareTo(math.max(a[1], a[2])),
          );
    final events = _events.toList();
    final frameSamples = _frames.toList();
    final navigationEvents = _navigationEvents.toList();
    final data = <String, Object?>{
      'schema': 3,
      'privacy':
          'No comic content, titles, paths, URLs, accounts, scripts, or error text.',
      'measurement':
          'Elapsed waits are not CPU time or UI-thread blocking. Frame samples are not measured FPS. receivedAtUs is the batched callback receipt time, not the frame time. vsyncStartUs and buildStartUs are engine timestamps relative to capture start; negative values precede capture.',
      'configuration': _configuration,
      'durationUs': _recording ? _elapsed : _duration,
      'stopReason': _stopReason?.name,
      'limits': <String, int>{
        'seconds': captureDuration.inSeconds,
        'events': maxEvents,
        'frames': maxFrames,
        'images': maxImages,
        'navigationEvents': maxNavigationEvents,
        'reportCharacters': maxReportCharacters,
      },
      'droppedEvents': _droppedEvents,
      'droppedFrames': _droppedFrames,
      'droppedNavigationEvents': _droppedNavigationEvents,
      'ignoredImageLookups': _ignoredImages,
      'retainedEventCount': _events.length,
      'omittedEventsForCopy': 0,
      'retainedFrameCount': _frames.length,
      'omittedFrameSamplesForCopy': 0,
      'retainedNavigationEventCount': _navigationEvents.length,
      'omittedNavigationEventsForCopy': 0,
      'inFlightStagesAtStop': _inFlightAtStop,
      'globalImageCacheBefore': _cacheBefore,
      'globalImageCacheAfter': _cacheAfter,
      'retainedFrameSamples': <String, Object?>{
        'ui': _summary(_frames.map((frame) => frame[1])),
        'raster': _summary(_frames.map((frame) => frame[2])),
        'frameBudgetUs': _frameBudgetUs.round(),
        'overBudget': slow.length,
        'slowest': slow.take(40).toList(),
        'slowestColumns': frameSampleColumns,
      },
      'frameSamples': frameSamples,
      'frameSampleColumns': frameSampleColumns,
      'navigationEvents': navigationEvents,
      'retainedStageSamples': <String, Object>{
        for (final stage in ReaderDiagnosticStage.values)
          stage.name: _summary(
            _events
                .where((event) => event['stage'] == stage.name)
                .map((event) => event['waitUs'] as int),
          ),
      },
      'imageEvents': events,
    };
    var omitted = 0;
    var omittedFrames = 0;
    var omittedNavigation = 0;
    const encoder = JsonEncoder.withIndent('  ');
    while (true) {
      data['omittedEventsForCopy'] = omitted;
      data['omittedFrameSamplesForCopy'] = omittedFrames;
      data['omittedNavigationEventsForCopy'] = omittedNavigation;
      final report = encoder.convert(data);
      if (complete || report.length <= maxReportCharacters) return report;
      // 先裁最大的明细缓冲，保留较新样本与完整统计。
      final sizes = <int>[
        encoder.convert(events).length,
        encoder.convert(frameSamples).length,
        encoder.convert(navigationEvents).length,
      ];
      final largest = sizes.indexOf(sizes.reduce(math.max));
      final List<Object> samples = switch (largest) {
        0 => events,
        1 => frameSamples,
        _ => navigationEvents,
      };
      if (samples.isEmpty) return report;
      final remove = math.min(
        samples.length,
        math.max(
          1,
          ((report.length - maxReportCharacters) *
                  samples.length /
                  sizes[largest])
              .ceil(),
        ),
      );
      samples.removeRange(0, remove);
      switch (largest) {
        case 0:
          omitted += remove;
        case 1:
          omittedFrames += remove;
        case 2:
          omittedNavigation += remove;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop(ReaderDiagnosticStop.disposed);
    clear(notify: false);
    super.dispose();
  }
}

/// 一次翻页动画的句柄：结束时补一条 animationEnd。
class ReaderDiagnosticPageTurn {
  ReaderDiagnosticPageTurn._(
    this._owner,
    this._generation,
    this._targetPage,
    this._chapter,
  );

  final ReaderDiagnostics _owner;
  final int _generation;
  final int _targetPage;
  final int _chapter;
  bool _finished = false;

  void finish({required int page, double? viewportPage, bool? scrolling}) {
    if (_finished) return;
    _finished = true;
    // 旧采集的动画结束不能写进新采集。
    if (_generation != _owner._generation) return;
    _owner.recordNavigation(
      ReaderDiagnosticNavigation.animationEnd,
      page: page,
      targetPage: _targetPage,
      chapter: _chapter,
      viewportPage: viewportPage,
      scrolling: scrolling,
    );
  }
}

/// 一个阶段耗时的句柄。
class ReaderDiagnosticSpan {
  ReaderDiagnosticSpan._(
    this._owner,
    this._generation,
    this._image,
    this._stage,
    this._startedAt,
  );

  final ReaderDiagnostics _owner;
  final int _generation;
  final int _image;
  final ReaderDiagnosticStage _stage;
  final int _startedAt;
  bool _finished = false;

  void finish({bool failed = false}) {
    if (_finished) return;
    _finished = true;
    _owner._inFlight = math.max(0, _owner._inFlight - 1);
    if (_generation != _owner._generation) return;
    final waitUs = math.max(0, _owner._elapsed - _startedAt);
    _owner._append(<String, Object>{
      'atUs': _startedAt,
      'image': _image,
      'stage': _stage.name,
      'waitUs': waitUs,
      if (failed) 'failed': true,
    });
  }
}
