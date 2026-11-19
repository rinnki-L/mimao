// B 线 · PlayerController 单测：headers 透传 + 线路切换。
// 全程用 FakePlaybackEngine，不碰 media_kit/libmpv/网络。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/player/player_controller.dart';

import 'fake_playback_engine.dart';

void main() {
  const ua = <String, String>{
    'User-Agent': 'Mozilla/5.0 test',
    'Referer': 'https://a.test/',
  };

  List<Episode> multiRoad() => const <Episode>[
    Episode(
      number: 1,
      title: '1主',
      url: 'https://a.test/1.m3u8',
      roadIndex: 1,
      roadName: '主线路',
    ),
    Episode(
      number: 2,
      title: '2主',
      url: 'https://a.test/2.m3u8',
      roadIndex: 1,
      roadName: '主线路',
    ),
    Episode(
      number: 1,
      title: '1备',
      url: 'https://b.test/1.m3u8',
      roadIndex: 2,
      roadName: '备用线路',
    ),
    Episode(
      number: 2,
      title: '2备',
      url: 'https://b.test/2.m3u8',
      roadIndex: 2,
      roadName: '备用线路',
    ),
  ];

  test('Episode 默认无头/单线路，兼容旧构造', () {
    const e = Episode(number: 1, title: 'x', url: 'u');
    expect(e.headers, isEmpty);
    expect(e.roadIndex, 1);
    expect(e.roadName, '');
  });

  test('start() 把头部透传给 engine.open', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: <Episode>[
        Episode(number: 1, title: 'x', url: 'https://a.test/1', headers: ua),
      ],
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(engine.openedHeaders, hasLength(1));
    expect(engine.openedHeaders.single, ua);
  });

  test('headersFor 缝注入：覆盖 Episode.headers', () async {
    final engine = FakePlaybackEngine();
    final injected = <String, String>{'User-Agent': 'injected'};
    final controller = PlayerController(
      engine: engine,
      episodes: <Episode>[
        Episode(number: 1, title: 'x', url: 'https://a.test/1', headers: ua),
      ],
      headersFor: (_) => injected,
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(engine.openedHeaders.single, injected);
  });

  test('无头时 engine.open 收到空 map（既有行为不变）', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: multiRoad());
    addTearDown(controller.dispose);

    await controller.start();
    expect(engine.openedHeaders.single, isEmpty);
  });

  test('roadNames/roadIndices 去重保序，currentRoadIndex 正确', () {
    final controller = PlayerController(
      engine: FakePlaybackEngine(),
      episodes: multiRoad(),
    );
    addTearDown(controller.dispose);

    expect(controller.roadNames, ['主线路', '备用线路']);
    expect(controller.roadIndices, [1, 2]);
    expect(controller.currentRoadIndex, 1);
  });

  test('switchRoad：按当前集数切到新线路同名集并重建 URL', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: multiRoad(),
      initialIndex: 1, // 当前是主线路第 2 集
    );
    addTearDown(controller.dispose);

    await controller.switchRoad(2);
    // 新线路同集数（第 2 集）→ index 3 → b.test/2
    expect(controller.index, 3);
    expect(engine.openedUrls.single, 'https://b.test/2.m3u8');
  });

  test('switchRoad：新线路没有该集数时回退第 1 集', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: <Episode>[
        const Episode(
          number: 1,
          title: '1主',
          url: 'https://a.test/1',
          roadIndex: 1,
          roadName: '主线路',
        ),
        const Episode(
          number: 2,
          title: '2主',
          url: 'https://a.test/2',
          roadIndex: 1,
          roadName: '主线路',
        ),
        // 备用线路只有第 1 集
        const Episode(
          number: 1,
          title: '1备',
          url: 'https://b.test/1',
          roadIndex: 2,
          roadName: '备用线路',
        ),
      ],
      initialIndex: 1,
    );
    addTearDown(controller.dispose);

    await controller.switchRoad(2);
    expect(controller.index, 2);
    expect(engine.openedUrls.single, 'https://b.test/1');
  });

  test('switchRoad：不存在的线路保持状态不变', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: multiRoad());
    addTearDown(controller.dispose);

    await controller.switchRoad(99);
    expect(controller.index, 0);
    expect(engine.openedUrls, isEmpty);
  });

  test('切集 loadEpisode 也透传 headers', () async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: <Episode>[
        Episode(number: 1, title: '1', url: 'https://a.test/1', headers: ua),
        Episode(number: 2, title: '2', url: 'https://a.test/2', headers: ua),
      ],
    );
    addTearDown(controller.dispose);

    await controller.loadEpisode(1);
    expect(engine.openedHeaders.single, ua);
  });
}
