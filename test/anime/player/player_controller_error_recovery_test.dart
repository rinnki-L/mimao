// 播放器错误遮罩自恢复——回归契约测试（B 线留档 bug 的复现结论落点）。
//
// Windows 桌面六场景复现（tool/diag_mpv_error.dart；事件序列与结论全文见
// docs/anime-mpv-error-mask-diagnosis.md）**未复现**「遮罩不自恢复」：
// mpv 对被替换的加载是静默取消（S4/S6），错误爆发是单行或 1ms 级紧邻两行
// （S1/S5），均不跨过下一次 open() 漏进新代。因此本仓只补回归契约、不改
// 引擎：
//   - 契约 1（对应 S2）：错误遮罩出现后切好集，遮罩消失、恢复播放；
//   - 契约 2（对应 S3）：重试坏集，遮罩再现、文案更新；
//   - 契约 3（对应 S6）：坏→坏中途切集，遮罩显示替换方自己的错误；
//   - 契约 4（对应 S1 时序）：open 后错误迟到窗口（实测 1.2–5s）内不得
//     误报遮罩；
//   - 契约 5（验收分句）：播放中途的新错误不被吞；
//   - 契约 6（潜在风险钉，见诊断文档 §潜在风险）：引擎若把旧代错误带进
//     新代的持续快照，controller 现行语义是遮罩持续——engine 端分代清理
//     是唯一防线，此条把该责任钉在测试里。
//
// 全部走 FakePlaybackEngine（无 libmpv / 无网络、CI 无 native 也真实执行，
// 无「无 native 就 return」的空转路径）。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/player/player_controller.dart';

import 'fake_playback_engine.dart';

const String badUrl = 'https://example.test/bad.m3u8';
const String badUrl2 = 'https://example.test/bad-2.m3u8';
const String goodUrl = 'https://example.test/good.mp4';
const String badError = 'Failed to open https://example.test/bad.m3u8.';
const String badError2 = 'Failed to open https://example.test/bad-2.m3u8.';

const List<Episode> episodes = <Episode>[
  Episode(number: 1, title: '坏集', url: badUrl),
  Episode(number: 2, title: '好集', url: goodUrl),
  Episode(number: 3, title: '坏集 2', url: badUrl2),
];

void main() {
  test('契约 1（S2）：错误遮罩出现后切好集，遮罩消失并恢复播放', () async {
    final engine = FakePlaybackEngine()..openFailures[badUrl] = badError;
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    await controller.start();
    await pumpEventQueue();
    engine.flushPendingErrors();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error);
    expect(controller.errorMessage, badError);

    // 切到好集：引擎 open 清掉旧代错误 → controller 回到播放态。
    await controller.loadEpisode(1);
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing, reason: '遮罩应消失');
    expect(controller.errorMessage, isNull);

    // 恢复播放后的普通快照不得再进错误态。
    engine.position = const Duration(seconds: 5);
    engine.emitSnapshot();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing);
    expect(controller.errorMessage, isNull);
  });

  test('契约 2（S3）：重试坏集遮罩再现，文案为新一次错误', () async {
    final engine = FakePlaybackEngine()..openFailures[badUrl] = badError;
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    await controller.start();
    await pumpEventQueue();
    engine.flushPendingErrors();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error);

    // 重试同一集：open 重新分代清理 → 短暂乐观起播 → 错误再次到达。
    // 乐观窗口内必须已脱离错误态——这一步区分「新代的新错误」与
    // 「旧代文案粘滞」（后者不会经历这个干净窗口）。
    await controller.loadEpisode(0);
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing, reason: '重试先清理旧代错误');
    expect(controller.errorMessage, isNull);

    engine.flushPendingErrors();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error, reason: '遮罩应再现');
    expect(controller.errorMessage, badError);
    expect(engine.openedUrls, hasLength(2), reason: '重试应重新 open 一次');
  });

  test('契约 3（S6）：坏→坏中途切集，遮罩显示替换方自己的错误', () async {
    final engine = FakePlaybackEngine()
      ..openFailures[badUrl] = badError
      ..openFailures[badUrl2] = badError2;
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    // 坏集 1 的错误尚未到达（真实场景：连接挂起 5s）就切到坏集 2。
    // mpv loadfile replace 静默取消被替换的加载（S4/S6 实测）：fake 的
    // open 会丢弃坏集 1 的 pending 错误，与真实引擎一致——它永远不会到达。
    await controller.loadEpisode(0);
    await pumpEventQueue();
    await controller.loadEpisode(2);
    await pumpEventQueue();

    // 到达的是替换方（坏集 2）自己的错误；若实现错误地让旧代文案上遮罩
    // （或先旧后新），此断言即红。
    engine.flushPendingErrors();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error);
    expect(controller.errorMessage, badError2);
  });

  test('契约 4（S1 时序）：错误迟到窗口内不得误报遮罩', () async {
    final engine = FakePlaybackEngine()..openFailures[badUrl] = badError;
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    await controller.start();
    await pumpEventQueue();
    // 真实 mpv 对坏地址乐观起播，错误 1.4–5s 后才到（S1/S5 实测）；
    // 这个窗口内 UI 不得提前进错误态。
    expect(controller.status, PlayerStatus.playing, reason: '错误尚未到达');
    expect(controller.errorMessage, isNull);

    // 窗口内的普通进度快照也不得触发错误态。
    engine.position = const Duration(seconds: 1);
    engine.emitSnapshot();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing);

    // 迟到错误到达后遮罩才出现。
    engine.flushPendingErrors();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error);
    expect(controller.errorMessage, badError);
  });

  test('契约 5：播放中途的新错误不被吞', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    await controller.start();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing);

    // 与切集无关的播放中错误（解码失败等）必须原样进入错误态。
    const midPlayError = 'vd: Could not open codec.';
    engine.error = midPlayError;
    engine.emitSnapshot();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error);
    expect(controller.errorMessage, midPlayError);
  });

  test('契约 6（潜在风险钉）：引擎持续上报旧代错误时遮罩持续', () async {
    final engine = FakePlaybackEngine()..openFailures[badUrl] = badError;
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    await controller.start();
    await pumpEventQueue();
    engine.flushPendingErrors();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error);

    // 切到好集后引擎本应分代清理；这里模拟「清理失效、旧代错误泄漏并
    // 粘在每个后续快照上」的最坏情形——controller 现行语义是遮罩持续，
    // 不会自恢复。此条与契约 1 合起来钉住：恢复的唯一防线在 engine 端。
    await controller.loadEpisode(1);
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.playing);

    engine.error = badError;
    engine.position = const Duration(seconds: 2);
    engine.emitSnapshot();
    await pumpEventQueue();
    expect(controller.status, PlayerStatus.error, reason: '泄漏即粘滞');

    engine.position = const Duration(seconds: 3);
    engine.emitSnapshot();
    await pumpEventQueue();
    expect(
      controller.status,
      PlayerStatus.error,
      reason: 'engine 端不分代清理就无自恢复——见诊断文档 §潜在风险',
    );
  });
}
