/// 听歌上报测试（L4）：fake listenReport + fake settings + 注入时钟。
///
/// 覆盖 start/end 触发时机、duration/completed、开关关闭、id 非法、上报
/// 抛错不影响播放；不真实 sleep、不联网。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/models/user_listen_report_models.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_store.dart';

import 'player_fakes.dart';

class _Clock {
  DateTime now = DateTime(2026, 1, 1, 12);

  DateTime call() => now;

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

/// ensureLoaded 必抛的设置替身：验证读盘异常被吞掉、不上报也不崩。
class _ThrowingSettings implements MusicSettings {
  @override
  bool get listenReportEnabled => true;

  @override
  bool get lyricEnabled => true;

  @override
  LyricMode get lyricMode => LyricMode.original;

  @override
  Future<void> ensureLoaded() async => throw Exception('disk broken');

  @override
  Future<void> setListenReportEnabled(bool value) async {}

  @override
  Future<void> setLyricEnabled(bool value) async {}

  @override
  Future<void> setLyricMode(LyricMode mode) async {}
}

void main() {
  late FakeMusicEngine engine;
  late FakePlaybackApi api;
  late FakeListenReportApi report;
  late _Clock clock;

  MusicPlayerStore buildStore({MusicSettings? settings}) => MusicPlayerStore(
    playbackApi: api,
    engineFactory: () => engine,
    clock: clock.call,
    listenReport: report,
    settings: settings,
  );

  setUp(() {
    engine = FakeMusicEngine();
    api = FakePlaybackApi();
    report = FakeListenReportApi();
    clock = _Clock();
  });

  MusicListenReportQuery? eventAt(int index) =>
      index < report.events.length ? report.events[index] : null;

  test('成功起播 → start 上报（mixsongid 解析、先 ensureLoaded）', () async {
    final settings = FakeMusicSettings();
    final store = buildStore(settings: settings);
    await store.playSong(fakeSong(id: '7301'));
    await pumpEventQueue();

    expect(report.events, hasLength(1));
    final start = eventAt(0)!;
    expect(start.event, MusicListenReportEvent.start);
    expect(start.mixsongid, 7301);
    expect(start.durationMs, isNull);
    expect(settings.ensureLoadedCalls, 1, reason: '上报前先读开关');
  });

  test('切歌 → end 上一首（durationMs 累计、completed=快照）+ start 新一首', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 10),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 30));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 40),
        duration: Duration(seconds: 180),
        playing: false,
      ),
    );
    await pumpEventQueue();

    await store.playSong(fakeSong(id: '2'));
    await pumpEventQueue();

    expect(report.events, hasLength(3));
    expect(eventAt(0)!.event, MusicListenReportEvent.start);
    expect(eventAt(0)!.mixsongid, 1);
    final end = eventAt(1)!;
    expect(end.event, MusicListenReportEvent.end);
    expect(end.mixsongid, 1);
    expect(end.durationMs, 30000, reason: '只累计播放中的墙钟时长');
    expect(end.completed, isFalse);
    expect(eventAt(2)!.event, MusicListenReportEvent.start);
    expect(eventAt(2)!.mixsongid, 2);
  });

  test('暂停/恢复：暂停不发 end、只停表；恢复后续算', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 5),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 20));

    await store.toggle(); // 暂停 → 停表
    await pumpEventQueue();
    clock.advance(const Duration(minutes: 5));
    await store.toggle(); // 恢复 → 续表
    clock.advance(const Duration(seconds: 10));

    await store.playSong(fakeSong(id: '2'));
    await pumpEventQueue();

    expect(report.events, hasLength(3));
    final end = eventAt(1)!;
    expect(end.event, MusicListenReportEvent.end);
    expect(end.durationMs, 30000, reason: '暂停期间不计入已播时长');
  });

  test('引擎播完（completed 快照）→ end completed=true；重复快照不重复上报', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 60),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 60));

    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    await pumpEventQueue();
    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    await pumpEventQueue();

    expect(report.events, hasLength(2));
    final end = eventAt(1)!;
    expect(end.event, MusicListenReportEvent.end);
    expect(end.mixsongid, 1);
    expect(end.completed, isTrue, reason: 'completed 取快照标记');
    expect(end.durationMs, 60000);
  });

  test('队列到尾停止（_stopAtEnd）→ end completed=true', () async {
    final store = buildStore();
    // 注意用数字 id：非数字 id（如 'only'）按协议不参与上报。
    await store.playSong(fakeSong(id: '42'));
    await store.next();
    await pumpEventQueue();

    expect(report.events, hasLength(2));
    final end = eventAt(1)!;
    expect(end.event, MusicListenReportEvent.end);
    expect(end.completed, isTrue);
    expect(store.snapshot.completed, isTrue);
  });

  test('dispose → end（completed=当前快照、durationMs=已播时长）', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 15),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 15));

    store.dispose();
    await pumpEventQueue();

    expect(report.events, hasLength(2));
    final end = eventAt(1)!;
    expect(end.event, MusicListenReportEvent.end);
    expect(end.durationMs, 15000);
    expect(end.completed, isFalse);
  });

  test('换歌链：每首歌各一对 start/end，end 只属于上一首', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    await store.playSong(fakeSong(id: '2'));
    await store.playSong(fakeSong(id: '3'));
    await pumpEventQueue();

    expect(report.events, hasLength(5));
    expect(report.events.map((event) => event.event), <MusicListenReportEvent>[
      MusicListenReportEvent.start,
      MusicListenReportEvent.end,
      MusicListenReportEvent.start,
      MusicListenReportEvent.end,
      MusicListenReportEvent.start,
    ]);
    expect(report.events.map((event) => event.mixsongid), <int>[1, 1, 2, 2, 3]);
  });

  test('同一首不重复 start：重试成功不重报；重播同一首=新会话（end+start）', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    await pumpEventQueue();

    await store.retry(); // 同一首重走解析链路（播放中出错后的重试场景）
    await pumpEventQueue();
    expect(report.events, hasLength(1), reason: '同一首会话内不重复 start');

    await store.playSong(fakeSong(id: '1')); // 重播同一首 = 结束旧会话、开新会话
    await pumpEventQueue();
    expect(report.events, hasLength(3));
    expect(eventAt(1)!.event, MusicListenReportEvent.end);
    expect(eventAt(1)!.mixsongid, 1);
    expect(eventAt(2)!.event, MusicListenReportEvent.start);
    expect(eventAt(2)!.mixsongid, 1);
  });

  test('id 非数字/≤0/空：start 与 end 都跳过', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: 'abc'));
    await store.playSong(fakeSong(id: '0'));
    await store.playSong(fakeSong(id: '-5'));
    await store.playSong(fakeSong(hash: 'short', id: ''));
    await pumpEventQueue();
    expect(report.events, isEmpty);
  });

  test('开关关闭：ensureLoaded 后不上报任何事件', () async {
    final settings = FakeMusicSettings(listenReportEnabled: false);
    final store = buildStore(settings: settings);
    await store.playSong(fakeSong(id: '1'));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 10),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    await store.playSong(fakeSong(id: '2'));
    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    store.dispose();
    await pumpEventQueue();

    expect(report.events, isEmpty);
    expect(settings.ensureLoadedCalls, greaterThanOrEqualTo(1));
  });

  test('无 settings 视为允许上报', () async {
    final store = buildStore();
    await store.playSong(fakeSong());
    await pumpEventQueue();
    expect(report.events, hasLength(1));
  });

  test('ensureLoaded 抛错：吞掉、不上报、不影响播放', () async {
    final store = buildStore(settings: _ThrowingSettings());
    await store.playSong(fakeSong());
    await pumpEventQueue();
    expect(report.events, isEmpty);
    expect(store.error, isNull);
    expect(store.isResolving, isFalse);
    expect(engine.playCalls, 1);
  });

  test('上报抛错：不影响播放状态；恢复后 end/start 照常入账', () async {
    report.failure = Exception('network down');
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    await pumpEventQueue();
    expect(store.error, isNull, reason: 'start 上报失败不挡播放');
    expect(store.isResolving, isFalse);
    expect(engine.playCalls, 1);
    expect(api.resolvedSongs.single.id, '1');

    report.failure = null;
    await store.playSong(fakeSong(id: '2'));
    await pumpEventQueue();
    expect(store.error, isNull);
    expect(report.events, hasLength(2), reason: '旧会话的 end + 新会话的 start');
    expect(eventAt(0)!.event, MusicListenReportEvent.end);
    expect(eventAt(0)!.mixsongid, 1);
    expect(eventAt(1)!.event, MusicListenReportEvent.start);
    expect(eventAt(1)!.mixsongid, 2);
  });

  test('未接线 listenReport（null）：不上报，播放照常', () async {
    final store = MusicPlayerStore(
      playbackApi: api,
      engineFactory: () => engine,
      clock: clock.call,
    );
    await store.playSong(fakeSong());
    await pumpEventQueue();
    expect(store.error, isNull);
    expect(engine.playCalls, 1);
  });
}
