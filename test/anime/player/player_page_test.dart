// 最小播放页的 widget 测试：mock 后端 + 占位视频槽，不依赖真实解码。
// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/anime/player/player_page.dart';

import 'fake_playback_engine.dart';

const List<Episode> episodes = <Episode>[
  Episode(number: 1, title: '第 1 话', url: 'https://example.test/1.m3u8'),
  Episode(number: 2, title: '第 2 话', url: 'https://example.test/2.m3u8'),
];

void main() {
  testWidgets('最小播放页：视频槽渲染、播放/暂停、点剧集切集', (tester) async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          controller: controller,
          video: const SizedBox(key: Key('video-slot')),
        ),
      ),
    );
    await tester.pump();
    // postFrame 里 start() 的异步链 + 快照流都是微任务，再泵一帧让其落地。
    await tester.pump();

    expect(controller.isPlaying, isTrue);
    expect(find.byKey(const Key('video-slot')), findsOneWidget);
    expect(find.byKey(const Key('player-slider')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-play-pause')));
    await tester.pump();
    expect(controller.status, PlayerStatus.paused);
    expect(engine.pauseCount, 1);

    await tester.tap(find.byKey(const Key('episode-1')));
    await tester.pump();
    await tester.pump();
    expect(controller.index, 1);
    expect(engine.openedUrls.last, episodes[1].url);

    // 拖动进度条（until 松手才 seek，onChangeEnd）。
    await tester.drag(
      find.byKey(const Key('player-slider')),
      const Offset(80, 0),
    );
    await tester.pump();
    expect(engine.seeks, isNotEmpty);
    expect(engine.seeks.last, greaterThan(Duration.zero));
  });

  testWidgets('加载/错误态：后端报错时显示提示并可重试', (tester) async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: episodes);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: PlayerPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();
    expect(controller.isPlaying, isTrue);

    engine.error = 'unable to open stream';
    engine.emitSnapshot();
    await tester.pump();

    expect(controller.status, PlayerStatus.error);
    expect(find.text('播放失败'), findsOneWidget);
    expect(find.text('unable to open stream'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-retry')));
    await tester.pump();
    await tester.pump();
    expect(engine.openedUrls, hasLength(2));
    expect(controller.status, PlayerStatus.playing);
  });
}
