// ignore_for_file: avoid_print
// ════════════════════════════════════════════════════════════════════════
// mpv 错误遮罩不自恢复——桌面复现诊断入口（B 线留档 bug，不属于产品导航）。
//
//   flutter run -d windows -t tool/diag_mpv_error.dart
//
// 无 UI、无数据库：直接装配与 player_demo 相同的两层
// （MediaKitPlaybackEngine + PlayerController），把全过程 raw
// stream.error、引擎快照、controller 状态迁移打上时间戳打到 stdout，
// 跑完自动退出。结论与事件序列归档见 docs/anime-mpv-error-mask-diagnosis.md。
//
// 场景矩阵（每个场景的预期都写进 EXPECT 行，输出可自证）：
//   S1  打开坏地址（本机拒绝端口）→ 遮罩应当出现；
//   S2  切好地址 → 遮罩应消失、恢复播放；
//   S3  重试坏地址 → 遮罩应再次出现；
//   S4  打开「挂起地址」（错误要到 +5s 才到达）中途切好地址 → 旧代的迟到
//       错误不得污染新代（遮罩不得出现，且应恢复播放）；
//   S5  打开 demo 同形态坏地址（m3u8 404），在错误第一行到达的瞬间立刻
//       切好地址（程序化最坏时序）→ 观察旧代错误尾行是否跨过 open()
//       漏进新代（粘滞假设的定向验证）；
//   S6  坏地址中途切到另一个坏地址 → 被替换方的错误不得出现，替换方自己
//       的错误应照常出现（验收点「重试坏 URL 遮罩仍出现」的最坏时序版）。
// ════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mimao/anime/player/media_kit_playback_engine.dart';
import 'package:mimao/anime/player/playback_engine.dart';
import 'package:mimao/anime/player/player_controller.dart';

/// 本机必然拒绝的端口：不依赖外网，错误确定性（Windows 下约 5s 后报错）。
const String badUrl = 'http://127.0.0.1:9/mimao-refused.m3u8';

/// 第二个坏地址：与 [badUrl] 同端口不同路径——mpv 的错误文本内嵌完整 URL，
/// 便于在事件序列里区分「被替换方的错误」与「替换方自己的错误」。
const String badUrl2 = 'http://127.0.0.1:9/mimao-refused-2.m3u8';

/// 非 DHCP 段的保留地址：TCP SYN 无人应答，连接一直挂起（不拒绝不超时，
/// 由 network-timeout 兜底）——用来制造「错误迟到的旧代」。
const String hangUrl = 'http://10.255.255.1:81/mimao-hang.m3u8';

/// demo 同形态坏地址：真实 CDN 上的 m3u8 404（验收清单「把 URL 改坏」的
/// 原始形态，错误爆发形状与连接拒绝不同）。
const String mux404Url =
    'https://test-streams.mux.dev/x36xhzz/nonexistent.m3u8';

/// 好地址沿用 demo 第 3 话的直链（验收清单中已验证可播）。
const String goodUrl = 'https://media.w3.org/2010/05/sintel/trailer.mp4';

final Stopwatch _clock = Stopwatch()..start();

void _log(String message) {
  final double t = _clock.elapsedMicroseconds / 1000;
  print('[diag t+${t.toStringAsFixed(0).padLeft(7)}ms] $message');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _log('诊断开始 bad=$badUrl');
  _log('         bad2=$badUrl2');
  _log('         hang=$hangUrl');
  _log('         mux404=$mux404Url');
  _log('         good=$goodUrl');

  final MediaKitPlaybackEngine engine = MediaKitPlaybackEngine();
  // network-timeout 只在诊断里给 mpv 兜底，让挂起地址在 5s 后确定性报错；
  // 不改 engine / controller 任何行为。
  final Object? mpvPlatform = engine.player.platform;
  if (mpvPlatform is NativePlayer) {
    await mpvPlatform.setProperty('network-timeout', '5');
    _log('已设置 mpv network-timeout=5s');
  }

  engine.snapshots.listen((PlaybackSnapshot s) {
    _log(
      'ENGINE    pos=${s.position.inMilliseconds}ms '
      'dur=${s.duration.inMilliseconds}ms playing=${s.playing} '
      'buffering=${s.buffering} completed=${s.completed} '
      'error=${s.error == null ? 'null' : '"${s.error}"'}',
    );
  });

  // S5 用：错误第一行到达即完成，触发「瞬间切集」的最坏时序。
  Completer<void>? firstError;
  var errorCount = 0;
  engine.player.stream.error.listen((String message) {
    errorCount++;
    _log('MPV-ERROR #$errorCount "$message"');
    firstError?.complete();
    firstError = null;
  });
  engine.player.stream.log.listen((PlayerLog entry) {
    if (entry.level == 'warn' || entry.level == 'error') {
      _log('MPV-log(${entry.level}) ${entry.prefix}: ${entry.text}');
    }
  });

  final PlayerController controller = PlayerController(
    engine: engine,
    episodes: const <Episode>[
      Episode(number: 1, title: '坏地址（连接拒绝 1）', url: badUrl),
      Episode(number: 2, title: '好地址（直链 MP4）', url: goodUrl),
      Episode(number: 3, title: '挂起地址（5s 后才报错）', url: hangUrl),
      Episode(number: 4, title: '坏地址（m3u8 404）', url: mux404Url),
      Episode(number: 5, title: '坏地址（连接拒绝 2）', url: badUrl2),
    ],
  );
  controller.addListener(() {
    _log(
      'CONTROLLER status=${controller.status} '
      'errorMessage=${controller.errorMessage == null ? 'null' : '"${controller.errorMessage}"'}',
    );
  });

  // 整体看门狗：任何一步意外挂死都能带诊断退出。
  Timer(const Duration(seconds: 180), () {
    _log('!! 看门狗超时（180s），强制退出 exit(3)');
    exit(3);
  });

  Future<void> settle(Duration duration, String what) async {
    await Future<void>.delayed(duration);
    _log(
      '$what 等待结束：status=${controller.status} '
      'errorMessage=${controller.errorMessage == null ? 'null' : '"${controller.errorMessage}"'}',
    );
  }

  // ── S1：坏地址 → 遮罩出现 ────────────────────────────────────────────
  _log('── S1 start() 打开坏地址');
  await controller.start();
  _log('S1 open() 已返回');
  await settle(const Duration(seconds: 8), 'S1');
  _log('S1 EXPECT 遮罩出现（status=error）');

  // ── S2：切好地址 → 遮罩消失并恢复播放 ────────────────────────────────
  _log('── S2 loadEpisode(1) 切到好地址');
  await controller.loadEpisode(1);
  _log('S2 open() 已返回');
  await settle(const Duration(seconds: 12), 'S2');
  _log('S2 EXPECT 遮罩消失且 playing（status=playing）');

  // ── S3：重试坏地址 → 遮罩再现 ────────────────────────────────────────
  _log('── S3 loadEpisode(0) 重试坏地址');
  await controller.loadEpisode(0);
  _log('S3 open() 已返回');
  await settle(const Duration(seconds: 8), 'S3');
  _log('S3 EXPECT 遮罩再现（status=error）');

  // ── S4：挂起地址中途切集 → 旧代迟到错误不得污染新代 ──────────────────
  _log('── S4 loadEpisode(2) 打开挂起地址（错误要到 +5s 才到达）');
  await controller.loadEpisode(2);
  _log('S4 open() 已返回，等 2s（错误尚未到达）');
  await Future<void>.delayed(const Duration(seconds: 2));
  _log('── S4 中途 loadEpisode(1) 切到好地址');
  await controller.loadEpisode(1);
  _log('S4 open() 已返回，旧代超时错误本应在 +3s 后到达');
  await settle(const Duration(seconds: 12), 'S4');
  _log('S4 EXPECT 旧代错误不出现、遮罩不出现且 playing');

  // ── S5：m3u8 404 + 错误第一行到达瞬间切集（最坏时序）─────────────────
  _log('── S5 loadEpisode(3) 打开 m3u8 404 坏地址');
  firstError = Completer<void>();
  await controller.loadEpisode(3);
  _log('S5 open() 已返回，等待错误第一行…');
  final bool gotError = await firstError!.future
      .then((_) => true)
      .timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          _log('S5 20s 内未收到错误第一行（异常）');
          return false;
        },
      );
  if (gotError) {
    _log('── S5 错误第一行到达，立即 loadEpisode(1) 切好地址（最坏时序）');
    await controller.loadEpisode(1);
    _log('S5 open() 已返回——此后到达的任何错误行都属于旧代尾行');
  }
  await settle(const Duration(seconds: 15), 'S5');
  _log('S5 EXPECT 旧代尾行不出现、遮罩消失且 playing');

  // ── S6：坏地址中途切到另一个坏地址 ───────────────────────────────────
  _log('── S6 loadEpisode(0) 打开坏地址 1（错误要到 +5s 才到达）');
  await controller.loadEpisode(0);
  _log('S6 open() 已返回，等 2s（错误尚未到达）');
  await Future<void>.delayed(const Duration(seconds: 2));
  _log('── S6 中途 loadEpisode(4) 切到坏地址 2');
  await controller.loadEpisode(4);
  _log('S6 open() 已返回，坏地址 1 的错误本应在 +3s 后到达');
  await settle(const Duration(seconds: 12), 'S6');
  _log('S6 EXPECT 只看到 refused-2 的错误（遮罩再现），refused(1) 不出现');

  _log('诊断结束，共收到 $errorCount 个 MPV-ERROR，500ms 后退出');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  exit(0);
}
