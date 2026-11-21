/// 播放器内核测试（fake engine + fake playbackApi + 注入时钟）。
///
/// 不初始化 media_kit、不做真实等待；节流用注入时钟推进。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/player/play_mode.dart';
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

void main() {
  late FakeMusicEngine engine;
  late FakePlaybackApi api;
  late RecordingProgressSink sink;
  late _Clock clock;
  late List<String> log;

  MusicPlayerStore buildStore({
    bool withEngine = true,
    MusicSettings? settings,
    Random? random,
  }) => MusicPlayerStore(
    playbackApi: api,
    engineFactory: withEngine ? () => engine : null,
    progressSink: sink.call,
    clock: clock.call,
    settings: settings,
    random: random,
  );

  setUp(() {
    log = <String>[];
    engine = FakeMusicEngine(log: log);
    api = FakePlaybackApi(log: log);
    sink = RecordingProgressSink();
    clock = _Clock();
  });

  test('playSong：resolve → open(url,startAt) → play 顺序正确', () async {
    final store = buildStore();
    await store.playSong(fakeSong());

    expect(log, <String>[
      'resolve',
      'open:https://cdn.example/7301.mp3',
      'play',
    ]);
    expect(engine.openedStartAt, Duration.zero);
    expect(store.queue.length, 1);
    expect(store.index, 0);
    expect(store.currentSong!.id, '7301');
    expect(store.isResolving, isFalse);
    expect(store.error, isNull);
  });

  test('playSong：startAt 透传给 engine.open（历史续播）', () async {
    final store = buildStore();
    await store.playSong(fakeSong(), startAt: const Duration(seconds: 42));
    expect(engine.openedStartAt, const Duration(seconds: 42));
  });

  test('引擎工厂惰性求值：构造 store 不调用，首次 playSong 才调用', () async {
    var factoryCalls = 0;
    final store = MusicPlayerStore(
      playbackApi: api,
      engineFactory: () {
        factoryCalls++;
        return engine;
      },
      clock: clock.call,
    );
    expect(factoryCalls, 0);
    expect(store.canPlay, isTrue);

    await store.playSong(fakeSong());
    expect(factoryCalls, 1);
    await store.playSong(fakeSong(id: '7302'));
    expect(factoryCalls, 1, reason: '引擎只构造一次');
  });

  test('engineFactory 为 null：点歌只报「播放未配置」，不调 API', () async {
    final store = buildStore(withEngine: false);
    await store.playSong(fakeSong());
    expect(store.error, '播放未配置');
    expect(api.resolvedSongs, isEmpty);
    expect(store.queue, isEmpty);
  });

  test('默认列表循环：next/previous 顺序切歌、首尾回绕', () async {
    final store = buildStore();
    expect(store.playMode, PlayMode.listLoop, reason: '默认列表循环');
    await store.playSong(fakeSong(id: '1'));
    await store.playSong(fakeSong(id: '2'));
    await store.playSong(fakeSong(id: '3'));
    expect(store.queue.map((song) => song.id), <String>['1', '2', '3']);
    expect(store.index, 2);

    await store.previous();
    expect(store.index, 1);
    expect(store.currentSong!.id, '2');
    await store.previous();
    expect(store.index, 0);

    // 第一首再 previous：列表循环回绕到最后一首。
    await store.previous();
    expect(store.index, 2);
    expect(store.currentSong!.id, '3');

    // 最后一首 next：回绕到第一首，而不是停在原地标记播完。
    await store.next();
    expect(store.index, 0);
    expect(store.currentSong!.id, '1');
    expect(store.snapshot.completed, isFalse);
  });

  test('单曲队列：next/previous 都重播当前曲、不越界', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: 'only'));
    expect(engine.playCalls, 1);
    await store.next();
    expect(store.index, 0);
    expect(store.queue.length, 1);
    expect(store.snapshot.completed, isFalse);
    expect(engine.playCalls, 2, reason: '单曲循环重播当前');
    await store.previous();
    expect(store.index, 0);
    expect(store.queue.length, 1);
    expect(engine.playCalls, 3);
  });

  test('repeatOne：next/previous 重播当前曲而不换歌', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    await store.playSong(fakeSong(id: '2'));
    store.setPlayMode(PlayMode.repeatOne);

    await store.next();
    expect(store.index, 1);
    expect(store.currentSong!.id, '2');
    expect(api.resolvedSongs.map((song) => song.id), <String>['1', '2', '2']);

    await store.previous();
    expect(store.index, 1);
    expect(store.currentSong!.id, '2');
    expect(api.resolvedSongs.map((song) => song.id), <String>[
      '1',
      '2',
      '2',
      '2',
    ]);
  });

  test('shuffle：next/previous 随机切到非当前曲', () async {
    final store = buildStore(random: Random(7));
    await store.playSong(fakeSong(id: '1'));
    await store.playSong(fakeSong(id: '2'));
    await store.playSong(fakeSong(id: '3'));
    await store.playSong(fakeSong(id: '4'));
    await store.playAt(1);
    store.setPlayMode(PlayMode.shuffle);

    await store.next();
    expect(store.index, isNot(1));
    expect(store.index, inInclusiveRange(0, 3));

    final afterNext = store.index;
    await store.previous();
    expect(store.index, isNot(afterNext));
    expect(store.index, inInclusiveRange(0, 3));
  });

  test('setPlayMode：立即更新状态并写入 settings', () async {
    final settings = FakeMusicSettings();
    final store = buildStore(settings: settings);
    expect(store.playMode, PlayMode.listLoop);

    store.setPlayMode(PlayMode.shuffle);
    expect(store.playMode, PlayMode.shuffle);
    await pumpEventQueue();
    expect(settings.playMode, PlayMode.shuffle);
  });

  test('构造时从 settings 读取初始播放模式', () async {
    final store = buildStore(
      settings: FakeMusicSettings(playMode: PlayMode.repeatOne),
    );
    expect(store.playMode, PlayMode.repeatOne);
  });

  test('播完自动切歌：listLoop 播完进入下一首（重复快照不重复推进）', () async {
    final store = buildStore();
    await store.playSong(fakeSong(id: '1'));
    await store.playSong(fakeSong(id: '2'));
    await store.playAt(0);
    api.resolvedSongs.clear();

    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    await pumpEventQueue();

    expect(store.index, 1);
    expect(store.currentSong!.id, '2');
    expect(api.resolvedSongs.map((song) => song.id), <String>['2']);
  });

  test('播完自动切歌：repeatOne 重播当前曲', () async {
    final store = buildStore(
      settings: FakeMusicSettings(playMode: PlayMode.repeatOne),
    );
    await store.playSong(fakeSong(id: '1'));
    api.resolvedSongs.clear();

    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    await pumpEventQueue();

    expect(store.index, 0);
    expect(store.currentSong!.id, '1');
    expect(store.snapshot.completed, isFalse);
    expect(api.resolvedSongs.map((song) => song.id), <String>['1']);
  });

  test('播完自动切歌：shuffle 随机换一首', () async {
    final store = buildStore(random: Random(3));
    await store.playSong(fakeSong(id: '1'));
    await store.playSong(fakeSong(id: '2'));
    await store.playAt(0);
    store.setPlayMode(PlayMode.shuffle);
    api.resolvedSongs.clear();

    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    await pumpEventQueue();

    expect(store.index, 1, reason: '两首队列随机只能是另一首');
    expect(api.resolvedSongs.map((song) => song.id), <String>['2']);
  });

  test('toggle：playing/paused 切换并调用 engine 对应方法', () async {
    final store = buildStore();
    await store.playSong(fakeSong());

    // 初始未播放 → play。
    await store.toggle();
    expect(engine.playCalls, 2, reason: 'playSong 一次 + toggle 一次');
    expect(store.snapshot.playing, isTrue);

    // 再 toggle → pause，并写一次进度。
    final before = sink.writes.length;
    await store.toggle();
    expect(engine.pauseCalls, 1);
    expect(store.snapshot.playing, isFalse);
    expect(sink.writes.length, before + 1);
  });

  test('进度写入：暂停/拖动/切歌/播完各一次', () async {
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
    sink.writes.clear();

    // 暂停一次。
    await store.toggle();
    expect(sink.writes.length, 1);
    expect(sink.writes.single.$1, '1');
    sink.writes.clear();

    // 拖动一次。
    await store.seekTo(const Duration(seconds: 30));
    expect(sink.writes.length, 1);
    expect(sink.writes.single.$2, const Duration(seconds: 30));
    sink.writes.clear();

    // 切歌：为上一首写一次。
    await store.playSong(fakeSong(id: '2'));
    expect(sink.writes.length, 1);
    expect(sink.writes.single.$1, '1');
    sink.writes.clear();

    // 播完一次（重复 completed 快照不重复写；自动切歌只落一次进度）。
    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    engine.emit(const MusicPlaybackSnapshot(completed: true, playing: false));
    await pumpEventQueue();
    expect(sink.writes.length, 1);
  });

  test('播放中按 10 秒节流写进度（注入时钟，不真实等待）', () async {
    final store = buildStore();
    await store.playSong(fakeSong());
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 1),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    expect(sink.writes.length, 1, reason: '起播即写一次');

    clock.advance(const Duration(seconds: 5));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 6),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    expect(sink.writes.length, 1, reason: '未满 10 秒不写');

    clock.advance(const Duration(seconds: 5));
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 11),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    expect(sink.writes.length, 2, reason: '满 10 秒写一次');
  });

  test('dispose：引擎释放、不再写进度、快照不再更新', () async {
    final store = buildStore();
    await store.playSong(fakeSong());
    final before = sink.writes.length;

    store.dispose();
    expect(engine.disposed, isTrue);

    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 99),
        duration: Duration(seconds: 180),
        playing: true,
      ),
    );
    await pumpEventQueue();
    expect(sink.writes.length, before);
    expect(store.snapshot.position, Duration.zero);
  });

  test('错误映射：authentication → 请先登录', () async {
    api.failure = const KugouApiException('authentication', '登录已过期');
    final store = buildStore();
    await store.playSong(fakeSong());
    expect(store.error, contains('请先登录'));
    expect(store.isResolving, isFalse);
  });

  test('错误映射：business → 带错误码', () async {
    api.failure = const KugouApiException('business', '没地址', code: 20010);
    final store = buildStore();
    await store.playSong(fakeSong());
    expect(store.error, contains('20010'));
    expect(store.error, contains('暂不可播'));
  });

  test('错误映射：input → 信息不完整', () async {
    api.failure = const KugouApiException('input', 'bad');
    final store = buildStore();
    await store.playSong(fakeSong());
    expect(store.error, contains('信息不完整'));
  });

  test('retry 重走解析链路且不重复入队', () async {
    api.failure = const KugouApiException('business', 'no url', code: 20010);
    final store = buildStore();
    await store.playSong(fakeSong());
    expect(store.error, contains('20010'));

    api.failure = null;
    await store.retry();
    expect(store.error, isNull);
    expect(store.queue.length, 1);
    expect(api.resolvedSongs.length, 1);
  });
}
