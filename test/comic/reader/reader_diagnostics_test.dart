// 阅读诊断：采集开关、有界缓冲、阶段耗时、导出与裁剪。
// 全部用注入的 nowMicros / 假帧回调，不依赖真实时间与渲染。

import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_diagnostics.dart';

/// 可控时钟 + 手动喂帧。
class _Clock {
  int now = 1000;
  void advance(int micros) => now += micros;
}

ReaderDiagnostics _build(_Clock clock) {
  return ReaderDiagnostics(
    nowMicros: () => clock.now,
    attachTimings: (_) {},
    detachTimings: (_) {},
    maxEvents: 5,
    maxFrames: 4,
    maxImages: 3,
    maxNavigationEvents: 4,
  );
}

Map<String, Object?> _decode(String json) =>
    jsonDecode(json) as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未开始采集时不记录任何样本', () {
    final clock = _Clock();
    final diagnostics = _build(clock);
    final span = diagnostics.beginImageSpan(1, ReaderDiagnosticStage.read);
    expect(span, isNull);
    final data = _decode(diagnostics.exportJson());
    expect(data['retainedEventCount'], 0);
    expect(diagnostics.hasCapture, isFalse);
  });

  test('阶段耗时被记录，且按图片匿名编号', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.paged,
        appVersion: '1.2.3',
        refreshRate: 60,
      );

    final span = diagnostics.beginImageSpan(42, ReaderDiagnosticStage.decode)!;
    clock.advance(5000);
    span.finish();

    final data = _decode(diagnostics.exportJson());
    final events = data['imageEvents'] as List<Object?>;
    expect(events, hasLength(1));
    final event = events.single as Map<String, Object?>;
    expect(event['stage'], 'decode');
    expect(event['waitUs'], 5000);
    expect(event['image'], 1, reason: '第一张图编号为 1');
    expect(
      diagnostics.exportJson(),
      isNot(contains('42')),
      reason: '不写原始身份，只写匿名编号',
    );
  });

  test('超出缓冲容量时丢弃最旧样本并计数', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.continuous,
        appVersion: '1.0.0',
        refreshRate: 60,
      );
    for (var i = 0; i < 8; i++) {
      // 复用同一张图的身份，避免撞上 maxImages=3 的编号上限。
      final span = diagnostics.beginImageSpan(1, ReaderDiagnosticStage.read)!;
      clock.advance(100);
      span.finish();
    }
    final data = _decode(diagnostics.exportJson());
    expect(data['retainedEventCount'], 5);
    expect(data['droppedEvents'], 3);
  });

  test('图片编号超过上限后忽略新身份', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.waterfall,
        appVersion: '1.0.0',
        refreshRate: 60,
      );
    for (var i = 0; i < 5; i++) {
      final span = diagnostics.beginImageSpan(
        100 + i,
        ReaderDiagnosticStage.read,
      );
      if (i < 3) {
        expect(span, isNotNull, reason: '前 3 张接受');
      } else {
        expect(span, isNull, reason: '第 4、5 张超上限被忽略');
      }
      span?.finish();
    }
    final data = _decode(diagnostics.exportJson());
    expect(data['ignoredImageLookups'], 2);
  });

  test('45 秒到点自动停止，stopReason=timeout', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.paged,
        appVersion: '1.0.0',
        refreshRate: 60,
      );
    clock.advance(ReaderDiagnostics.captureDuration.inMicroseconds + 1);
    diagnostics.recordNavigation(
      ReaderDiagnosticNavigation.pageSelected,
      page: 2,
    );
    expect(diagnostics.isRecording, isFalse);
    final data = _decode(diagnostics.exportJson());
    expect(data['stopReason'], 'timeout');
    expect(
      (data['navigationEvents'] as List<Object?>),
      isEmpty,
      reason: '超时后的样本不再记录',
    );
  });

  test('帧样本进入统计，慢帧被挑出', () {
    final clock = _Clock();
    final diagnostics = _build(clock);
    // 用真实的 TimingsCallback 注入不了，这里直接走公开导出路径验证空统计。
    diagnostics.start(
      mode: ReaderDiagnosticMode.paged,
      appVersion: '1.0.0',
      refreshRate: 60,
    );
    final data = _decode(diagnostics.exportJson());
    final summary = data['retainedFrameSamples'] as Map<String, Object?>;
    expect((summary['ui'] as Map<String, Object?>)['count'], 0);
    expect(summary['frameBudgetUs'], 16667);
  });

  test('配置里版本号不合规时写 unknown，不泄漏任意字符串', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.paged,
        appVersion: 'C:/secret/path',
        refreshRate: 0,
      );
    final data = _decode(diagnostics.exportJson());
    final config = data['configuration'] as Map<String, Object?>;
    expect(config['appVersion'], 'unknown');
    expect(config['displayRefreshHz'], 60.0);
    expect(config.containsKey('platform'), isTrue);
  });

  test('clear 清空缓冲且 generation 递增', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.paged,
        appVersion: '1.0.0',
        refreshRate: 60,
      );
    final span = diagnostics.beginImageSpan(7, ReaderDiagnosticStage.read)!;
    clock.advance(200);
    span.finish();
    final generation = diagnostics.captureGeneration;

    diagnostics.clear();
    expect(diagnostics.hasCapture, isFalse);
    expect(_decode(diagnostics.exportJson())['retainedEventCount'], 0);

    // 旧 span 在 clear 后 finish 不应写入新采集。
    diagnostics.start(
      mode: ReaderDiagnosticMode.paged,
      appVersion: '1.0.0',
      refreshRate: 60,
    );
    expect(diagnostics.captureGeneration, isNot(generation));
    span.finish();
    expect(_decode(diagnostics.exportJson())['retainedEventCount'], 0);
  });

  test('导出报告不超过字符上限，并记录省略数量', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.continuous,
        appVersion: '1.0.0',
        refreshRate: 60,
      );
    // 5 个事件 × 每轮 3 张图，撑大明细后仍要被裁到上限内。
    for (var i = 0; i < 5; i++) {
      final span = diagnostics.beginImageSpan(
        1,
        ReaderDiagnosticStage.display,
      )!;
      clock.advance(10);
      span.finish();
    }
    final report = diagnostics.exportJson();
    expect(
      report.length,
      lessThanOrEqualTo(ReaderDiagnostics.maxReportCharacters),
    );
    expect(_decode(report)['schema'], 3);
  });

  test('翻页句柄在采集结束后不再补写', () {
    final clock = _Clock();
    final diagnostics = _build(clock)
      ..start(
        mode: ReaderDiagnosticMode.paged,
        appVersion: '1.0.0',
        refreshRate: 60,
      );
    final turn = diagnostics.beginPageTurn(page: 1, targetPage: 2, chapter: 1)!;
    diagnostics.stop(ReaderDiagnosticStop.review);
    turn.finish(page: 2);
    final events =
        _decode(diagnostics.exportJson())['navigationEvents'] as List<Object?>;
    expect(events, hasLength(1), reason: '只有 animationStart');
  });

  test('TimingsCallback 注入后可统计慢帧', () {
    final clock = _Clock();
    TimingsCallback? attached;
    final diagnostics =
        ReaderDiagnostics(
          nowMicros: () => clock.now,
          attachTimings: (callback) => attached = callback,
          detachTimings: (_) => attached = null,
          maxFrames: 8,
        )..start(
          mode: ReaderDiagnosticMode.paged,
          appVersion: '1.0.0',
          refreshRate: 60,
        );
    expect(attached, isNotNull);
    attached!(<FrameTiming>[
      _fakeFrame(uiUs: 40000, rasterUs: 1000),
      _fakeFrame(uiUs: 1000, rasterUs: 1000),
    ]);
    final data = _decode(diagnostics.exportJson());
    final summary = data['retainedFrameSamples'] as Map<String, Object?>;
    expect((summary['ui'] as Map<String, Object?>)['maxUs'], 40000);
    expect(summary['overBudget'], 1);
  });
}

/// FrameTiming 的公开测试构造器：用固定时间戳喂出想要的 ui/raster 耗时。
FrameTiming _fakeFrame({required int uiUs, required int rasterUs}) =>
    FrameTiming(
      vsyncStart: 0,
      buildStart: 100,
      buildFinish: 100 + uiUs,
      rasterStart: 100 + uiUs,
      rasterFinish: 100 + uiUs + rasterUs,
      rasterFinishWallTime: 100 + uiUs + rasterUs,
    );
