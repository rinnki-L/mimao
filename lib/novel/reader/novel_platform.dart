// 阅读页的平台能力抽象：屏幕亮度 / 常亮 / 系统栏 / 屏幕方向 / 音量键。
//
// 两条硬约束（AGENTS.md「UI」「验证分工」）：
// 1. 桌面端必须是 no-op——Windows/macOS/Linux 的能力全是 false、方法空实现，
//    页面拿到的就是 [NoopNovelPlatform]，Windows 构建面一行不动；
// 2. 所有平台调用只在这里出现，页面不直接 import 插件或 SystemChrome。
//
// 为什么亮度/常亮走自建 `mimao/display` 通道而不是 screen_brightness +
// wakelock_plus：两条能力在 Android 上都只要几行原生代码（窗口亮度
// `window.attributes.screenBrightness`、`FLAG_KEEP_SCREEN_ON`），自建通道让
// Windows 构建面完全不变（screen_brightness_windows 会编一个 C++ 插件、
// wakelock_plus 会牵进 package_info_plus 一串依赖），也免了按镜像重生成
// pubspec.lock。与已有 `mimao/volume` 同一套做法（2026-11-25 拍板）。
//
// 测试：`flutter test` 里 [resolveNovelPlatform] 恒返回 no-op；页面测试注入
// FakeNovelPlatform 断言调用序列，Android 侧的原生调用本身无法在无真机时验证。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/volume_keys.dart' as volume;
import 'novel_reader_settings.dart' show NovelScreenOrientation;

/// 系统栏组合：两个开关映射成 `SystemUiMode` + overlays。
///
/// 做成纯函数是因为它是本模块唯一需要「算对」的逻辑，单测不应碰通道。
class NovelSystemBarsPlan {
  const NovelSystemBarsPlan(this.mode, [this.overlays]);

  final SystemUiMode mode;
  final List<SystemUiOverlay>? overlays;

  @override
  bool operator ==(Object other) =>
      other is NovelSystemBarsPlan &&
      other.mode == mode &&
      listEquals(other.overlays, overlays);

  @override
  int get hashCode =>
      Object.hash(mode, overlays == null ? null : Object.hashAll(overlays!));

  @override
  String toString() => 'NovelSystemBarsPlan($mode, $overlays)';
}

/// 两个独立开关 → 系统栏模式。
///
/// 都隐藏时仍用 [SystemUiMode.immersiveSticky]（与进阅读页前的行为逐字一致：
/// 滑动可临时唤出，松手自动收回）；只隐藏一根时必须用 [SystemUiMode.manual]
/// 配 overlays 指定「留下哪根」，其余组合没有现成的 SystemUiMode。
NovelSystemBarsPlan planNovelSystemBars({
  required bool hideStatusBar,
  required bool hideNavigationBar,
}) {
  if (hideStatusBar && hideNavigationBar) {
    return const NovelSystemBarsPlan(SystemUiMode.immersiveSticky);
  }
  if (hideStatusBar) {
    // 只留导航栏。
    return const NovelSystemBarsPlan(SystemUiMode.manual, <SystemUiOverlay>[
      SystemUiOverlay.bottom,
    ]);
  }
  if (hideNavigationBar) {
    // 只留状态栏。
    return const NovelSystemBarsPlan(SystemUiMode.manual, <SystemUiOverlay>[
      SystemUiOverlay.top,
    ]);
  }
  return const NovelSystemBarsPlan(SystemUiMode.edgeToEdge);
}

/// 退出阅读页时的系统栏还原（与改造前 exit() 的行为一致）。
const NovelSystemBarsPlan novelRestoreSystemBarsPlan = NovelSystemBarsPlan(
  SystemUiMode.edgeToEdge,
);

/// 方向设置 → `SystemChrome.setPreferredOrientations` 的参数。
///
/// 「跟随系统」必须是空列表：空列表对应 Android 的 SCREEN_ORIENTATION_UNSPECIFIED，
/// 传四个方向反而会变成强制全传感器（忽略用户的旋转锁）。
List<DeviceOrientation> novelOrientationValues(
  NovelScreenOrientation orientation,
) => switch (orientation) {
  NovelScreenOrientation.system => const <DeviceOrientation>[],
  NovelScreenOrientation.portrait => const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ],
  NovelScreenOrientation.landscape => const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ],
};

/// 音量键事件的接线点（方向键语义与点击区一致：1 = 下一页，-1 = 上一页）。
class NovelVolumeHooks {
  const NovelVolumeHooks({this.onTurn, this.onInput, this.onError});

  final void Function(int direction)? onTurn;

  /// 收到按键时先通知（页面用它重置自动翻页计时，避免刚按完又自动翻）。
  final void Function(bool forward)? onInput;

  final void Function(Object error, StackTrace stack)? onError;
}

/// 阅读页需要的平台能力窄接口。
///
/// 「不支持」是显式的 false，不是靠 null/异常暗示；调用 no-op 实现永远成功、
/// 永远不碰通道。
abstract interface class NovelPlatform {
  /// Android：能改窗口亮度（不需要 WRITE_SETTINGS，退出页面即恢复）。
  bool get supportsScreenBrightness;

  /// Android：能挂 `FLAG_KEEP_SCREEN_ON`。
  bool get supportsKeepAwake;

  /// Android：能独立控制状态栏 / 导航栏。
  bool get supportsSystemBars;

  /// Android：能锁屏幕方向。
  bool get supportsOrientation;

  /// Android：有 `mimao/volume` 原生通道。
  bool get supportsVolumeKeys;

  /// 后台朗读 + 通知栏控制；当前实现没有落地（见 LESSON.md §七）。
  bool get supportsBackgroundTts;

  /// 为 true 时页面不再画黑色遮罩（真亮度已经生效，再叠遮罩等于双重压暗）。
  bool get usesRealBrightness;

  /// [value] 为 null = 交给系统（跟随系统亮度）；否则是 0..1 的窗口亮度。
  Future<void> setBrightness(double? value);

  Future<void> setKeepAwake(bool enabled);

  Future<void> applySystemBars({
    required bool hideStatusBar,
    required bool hideNavigationBar,
  });

  Future<void> setOrientation(NovelScreenOrientation orientation);

  Future<void> setVolumeKeysEnabled(bool enabled);

  /// 退出阅读页：还原亮度 / 常亮 / 系统栏 / 方向，并释放音量键租约。
  Future<void> dispose();
}

/// 桌面 / Web / 测试环境的能力实现：全部不支持、全部空操作。
class NoopNovelPlatform implements NovelPlatform {
  const NoopNovelPlatform();

  @override
  bool get supportsScreenBrightness => false;
  @override
  bool get supportsKeepAwake => false;
  @override
  bool get supportsSystemBars => false;
  @override
  bool get supportsOrientation => false;
  @override
  bool get supportsVolumeKeys => false;
  @override
  bool get supportsBackgroundTts => false;
  @override
  bool get usesRealBrightness => false;

  @override
  Future<void> setBrightness(double? value) async {}

  @override
  Future<void> setKeepAwake(bool enabled) async {}

  @override
  Future<void> applySystemBars({
    required bool hideStatusBar,
    required bool hideNavigationBar,
  }) async {}

  @override
  Future<void> setOrientation(NovelScreenOrientation orientation) async {}

  @override
  Future<void> setVolumeKeysEnabled(bool enabled) async {}

  @override
  Future<void> dispose() async {}
}

/// Android 实现：亮度 / 常亮走 `mimao/display`（MainActivity），
/// 系统栏与方向走 SystemChrome，音量键复用 `mimao/volume` 租约。
class AndroidNovelPlatform implements NovelPlatform {
  AndroidNovelPlatform({
    NovelVolumeHooks hooks = const NovelVolumeHooks(),
    volume.ReaderVolumeConnection Function(void Function(Object?) onEvent)?
    connect,
  }) : _hooks = hooks,
       _volume = volume.ReaderVolumeController(
         // 章节切换由阅读页的 _turnPage 自己处理（翻页模式到页尾会切章，
         // 滚动模式到边界也会切章），所以这里只转发「翻页」两个回调，
         // 切章回调保留空实现，不重复一套边界判断。
         nextPage: () {
           hooks.onTurn?.call(1);
           return true;
         },
         previousPage: () {
           hooks.onTurn?.call(-1);
           return true;
         },
         nextChapter: () {},
         previousChapter: () {},
         onError: (error, stack) => hooks.onError?.call(error, stack),
         onInput: (forward) => hooks.onInput?.call(forward),
         connect: connect,
       );

  /// 亮度 / 常亮的原生通道（与 `mimao/volume` 并列，都是本 app 自己的通道）。
  static const MethodChannel displayChannel = MethodChannel('mimao/display');

  final NovelVolumeHooks _hooks;
  final volume.ReaderVolumeController _volume;

  @override
  bool get supportsScreenBrightness => true;
  @override
  bool get supportsKeepAwake => true;
  @override
  bool get supportsSystemBars => true;
  @override
  bool get supportsOrientation => true;
  @override
  bool get supportsVolumeKeys => true;
  @override
  bool get supportsBackgroundTts => false;
  @override
  bool get usesRealBrightness => true;

  @override
  Future<void> setBrightness(double? value) async {
    await _invokeDisplay('setBrightness', <String, Object?>{
      'value': value?.clamp(0.0, 1.0),
    });
  }

  @override
  Future<void> setKeepAwake(bool enabled) async {
    await _invokeDisplay('keepAwake', <String, Object?>{'enabled': enabled});
  }

  @override
  Future<void> applySystemBars({
    required bool hideStatusBar,
    required bool hideNavigationBar,
  }) async {
    final plan = planNovelSystemBars(
      hideStatusBar: hideStatusBar,
      hideNavigationBar: hideNavigationBar,
    );
    try {
      await SystemChrome.setEnabledSystemUIMode(
        plan.mode,
        overlays: plan.overlays,
      );
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          systemNavigationBarColor: Color(0x00000000),
        ),
      );
    } on Object {
      // 系统栏设置失败不影响阅读。
    }
  }

  @override
  Future<void> setOrientation(NovelScreenOrientation orientation) async {
    try {
      await SystemChrome.setPreferredOrientations(
        novelOrientationValues(orientation),
      );
    } on Object {
      // 方向锁定失败不影响阅读。
    }
  }

  @override
  Future<void> setVolumeKeysEnabled(bool enabled) async {
    try {
      await _volume.setEnabled(enabled && supportsVolumeKeys);
    } on Object catch (error, stack) {
      _hooks.onError?.call(error, stack);
    }
  }

  @override
  Future<void> dispose() async {
    await setBrightness(null);
    await setKeepAwake(false);
    await applySystemBars(hideStatusBar: false, hideNavigationBar: false);
    await setOrientation(NovelScreenOrientation.system);
    try {
      await _volume.dispose();
    } on Object catch (error, stack) {
      _hooks.onError?.call(error, stack);
    }
  }

  Future<void> _invokeDisplay(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      await displayChannel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // 非 Android 平台没有这条通道：按 no-op 处理（这里只会在 Android 上被调到，
      // 但测试/误判平台时不应打崩阅读页）。
    } on PlatformException {
      // 原生拒绝（如窗口已 detach）同样按失败处理，不阻塞阅读。
    }
  }
}

/// 按运行环境选实现。参数只给测试用：生产调用不传。
NovelPlatform resolveNovelPlatform({
  bool? android,
  bool? test,
  bool? web,
  NovelVolumeHooks volumeHooks = const NovelVolumeHooks(),
  volume.ReaderVolumeConnection Function(void Function(Object?) onEvent)?
  connectVolume,
}) {
  final isWeb = web ?? kIsWeb;
  final isTest =
      test ?? (!isWeb && Platform.environment.containsKey('FLUTTER_TEST'));
  final isAndroid = android ?? (!isWeb && Platform.isAndroid);
  if (isWeb || isTest || !isAndroid) return const NoopNovelPlatform();
  return AndroidNovelPlatform(hooks: volumeHooks, connect: connectVolume);
}
