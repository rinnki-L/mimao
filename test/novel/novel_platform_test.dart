// 阅读页平台能力抽象：桌面 no-op、系统栏映射、Android 调用路径（fake 通道）。
//
// 这里能证明的：参数映射与真实现的分支都在 Dart 侧跑通了；不能证明的：Android
// 原生侧的窗口亮度 / FLAG_KEEP_SCREEN_ON 是否真的生效（无真机，见 LESSON.md §七）。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/volume_keys.dart';
import 'package:mimao/novel/reader/novel_platform.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';

/// 可控租约：手动决定激活成功、记录释放次数（与漫画侧的 fake 同款）。
class _Lease implements ReaderVolumeConnection {
  _Lease(this.onEvent);

  final void Function(Object?) onEvent;
  final Completer<void> _ready = Completer<void>();
  bool released = false;

  void activate() {
    if (!_ready.isCompleted) _ready.complete();
  }

  @override
  Future<void> get ready => _ready.future;

  @override
  Future<void> closeAndWait() async {
    released = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('resolveNovelPlatform', () {
    test('桌面 / Web / 测试环境一律 no-op', () {
      for (final platform in <NovelPlatform>[
        resolveNovelPlatform(android: false),
        resolveNovelPlatform(web: true),
        resolveNovelPlatform(test: true),
      ]) {
        expect(platform, isA<NoopNovelPlatform>());
        expect(platform.supportsScreenBrightness, isFalse);
        expect(platform.supportsKeepAwake, isFalse);
        expect(platform.supportsSystemBars, isFalse);
        expect(platform.supportsOrientation, isFalse);
        expect(platform.supportsVolumeKeys, isFalse);
        expect(platform.supportsBackgroundTts, isFalse);
        expect(platform.usesRealBrightness, isFalse);
      }
    });

    test('Android 环境拿到真实实现：除后台朗读外能力全开', () {
      final platform = resolveNovelPlatform(android: true, test: false);
      expect(platform, isA<AndroidNovelPlatform>());
      expect(platform.supportsScreenBrightness, isTrue);
      expect(platform.supportsKeepAwake, isTrue);
      expect(platform.supportsSystemBars, isTrue);
      expect(platform.supportsOrientation, isTrue);
      expect(platform.supportsVolumeKeys, isTrue);
      expect(platform.supportsBackgroundTts, isFalse);
      expect(platform.usesRealBrightness, isTrue);
    });
  });

  test('no-op 实现不碰任何原生通道', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(AndroidNovelPlatform.displayChannel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidNovelPlatform.displayChannel,
        null,
      ),
    );

    const platform = NoopNovelPlatform();
    await platform.setBrightness(0.3);
    await platform.setKeepAwake(true);
    await platform.applySystemBars(
      hideStatusBar: false,
      hideNavigationBar: false,
    );
    await platform.setOrientation(NovelScreenOrientation.landscape);
    await platform.setVolumeKeysEnabled(true);
    await platform.dispose();

    expect(calls, isEmpty, reason: '桌面端必须是纯 no-op');
  });

  group('系统栏映射', () {
    test('两根都隐藏 = 改造前的 immersiveSticky', () {
      final plan = planNovelSystemBars(
        hideStatusBar: true,
        hideNavigationBar: true,
      );
      expect(plan.mode, SystemUiMode.immersiveSticky);
      expect(plan.overlays, isNull);
    });

    test('只隐藏状态栏 → 手动模式只留导航栏', () {
      final plan = planNovelSystemBars(
        hideStatusBar: true,
        hideNavigationBar: false,
      );
      expect(plan.mode, SystemUiMode.manual);
      expect(plan.overlays, <SystemUiOverlay>[SystemUiOverlay.bottom]);
    });

    test('只隐藏导航栏 → 手动模式只留状态栏', () {
      final plan = planNovelSystemBars(
        hideStatusBar: false,
        hideNavigationBar: true,
      );
      expect(plan.mode, SystemUiMode.manual);
      expect(plan.overlays, <SystemUiOverlay>[SystemUiOverlay.top]);
    });

    test('都不隐藏 → edgeToEdge', () {
      final plan = planNovelSystemBars(
        hideStatusBar: false,
        hideNavigationBar: false,
      );
      expect(plan.mode, SystemUiMode.edgeToEdge);
      expect(plan.overlays, isNull);
    });
  });

  test('方向设置 → setPreferredOrientations 参数（跟随系统 = 空列表）', () {
    expect(novelOrientationValues(NovelScreenOrientation.system), isEmpty);
    expect(
      novelOrientationValues(NovelScreenOrientation.portrait),
      <DeviceOrientation>[DeviceOrientation.portraitUp],
    );
    expect(
      novelOrientationValues(NovelScreenOrientation.landscape),
      <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  });

  group('Android 调用路径（fake 通道）', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AndroidNovelPlatform.displayChannel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(
        AndroidNovelPlatform.displayChannel,
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('亮度：下发给窗口亮度，null = 交还系统，越界值夹取', () async {
      final platform = AndroidNovelPlatform();
      await platform.setBrightness(0.6);
      await platform.setBrightness(null);
      await platform.setBrightness(2);

      expect(calls.map((call) => call.method), <String>[
        'setBrightness',
        'setBrightness',
        'setBrightness',
      ]);
      expect(calls[0].arguments, <String, Object?>{'value': 0.6});
      expect(calls[1].arguments, <String, Object?>{'value': null});
      expect(calls[2].arguments, <String, Object?>{'value': 1.0});
    });

    test('常亮：开关都落到同一个原生方法', () async {
      final platform = AndroidNovelPlatform();
      await platform.setKeepAwake(true);
      await platform.setKeepAwake(false);

      expect(calls.map((call) => call.method), <String>[
        'keepAwake',
        'keepAwake',
      ]);
      expect(calls[0].arguments, <String, Object?>{'enabled': true});
      expect(calls[1].arguments, <String, Object?>{'enabled': false});
    });

    test('系统栏与方向走 SystemChrome，参数与映射一致', () async {
      final platformCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
      final platform = AndroidNovelPlatform();

      await platform.applySystemBars(
        hideStatusBar: true,
        hideNavigationBar: true,
      );
      expect(
        platformCalls.any(
          (call) =>
              call.method == 'SystemChrome.setEnabledSystemUIMode' &&
              call.arguments == 'SystemUiMode.immersiveSticky',
        ),
        isTrue,
      );

      platformCalls.clear();
      await platform.applySystemBars(
        hideStatusBar: true,
        hideNavigationBar: false,
      );
      expect(
        platformCalls.any(
          (call) =>
              call.method == 'SystemChrome.setEnabledSystemUIOverlays' &&
              (call.arguments! as List<Object?>).contains(
                'SystemUiOverlay.bottom',
              ),
        ),
        isTrue,
      );

      platformCalls.clear();
      await platform.setOrientation(NovelScreenOrientation.portrait);
      expect(
        platformCalls.any(
          (call) =>
              call.method == 'SystemChrome.setPreferredOrientations' &&
              (call.arguments! as List<Object?>).contains(
                'DeviceOrientation.portraitUp',
              ),
        ),
        isTrue,
      );
    });

    test('音量键：事件转成翻页方向，dispose 释放租约', () async {
      final leases = <_Lease>[];
      final turns = <int>[];
      final platform = AndroidNovelPlatform(
        hooks: NovelVolumeHooks(onTurn: turns.add),
        connect: (onEvent) {
          final lease = _Lease(onEvent);
          leases.add(lease);
          return lease;
        },
      );

      final enabling = platform.setVolumeKeysEnabled(true);
      await Future<void>.delayed(Duration.zero);
      leases.single.activate();
      await enabling;

      leases.single.onEvent(2);
      leases.single.onEvent(1);
      expect(turns, <int>[1, -1]);

      await platform.dispose();
      expect(leases.single.released, isTrue);
    });

    test('退出阅读页：还原亮度 / 常亮 / 系统栏 / 方向', () async {
      final display = <MethodCall>[];
      final chrome = <MethodCall>[];
      messenger.setMockMethodCallHandler(AndroidNovelPlatform.displayChannel, (
        call,
      ) async {
        display.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        chrome.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          AndroidNovelPlatform.displayChannel,
          null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final platform = AndroidNovelPlatform();
      await platform.setBrightness(0.4);
      await platform.setKeepAwake(true);
      await platform.dispose();

      expect(
        display.any(
          (call) =>
              call.method == 'setBrightness' &&
              (call.arguments! as Map<Object?, Object?>)['value'] == null,
        ),
        isTrue,
        reason: '亮度要交还系统',
      );
      expect(
        display.any(
          (call) =>
              call.method == 'keepAwake' &&
              (call.arguments! as Map<Object?, Object?>)['enabled'] == false,
        ),
        isTrue,
      );
      expect(
        chrome.any(
          (call) =>
              call.method == 'SystemChrome.setEnabledSystemUIMode' &&
              call.arguments == 'SystemUiMode.edgeToEdge',
        ),
        isTrue,
      );
      expect(
        chrome.any(
          (call) =>
              call.method == 'SystemChrome.setPreferredOrientations' &&
              (call.arguments! as List<Object?>).isEmpty,
        ),
        isTrue,
        reason: '方向还原成跟随系统（空列表）',
      );
    });

    test('音量键关闭时不建立租约', () async {
      var connections = 0;
      final platform = AndroidNovelPlatform(
        connect: (onEvent) {
          connections++;
          final lease = _Lease(onEvent)..activate();
          return lease;
        },
      );

      await platform.setVolumeKeysEnabled(false);
      expect(connections, 0);
    });
  });
}
