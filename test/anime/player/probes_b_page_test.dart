// B 线 · PlayerPage 线路选择 UI widget 测试。
// 多线路显示选择器并显示当前线路名；切线路触发新 URL 加载；单线路无选择器。
// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/anime/player/player_page.dart';

import 'fake_playback_engine.dart';

List<Episode> multiRoad() => const <Episode>[
  Episode(
    number: 1,
    title: '1主',
    url: 'https://a.test/1.m3u8',
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
];

void main() {
  testWidgets('多线路：显示选择器，显示当前线路名，两个选项都在', (tester) async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(engine: engine, episodes: multiRoad());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: PlayerPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('player-road')), findsOneWidget);
    expect(find.text('主线路'), findsWidgets);

    await tester.tap(find.byKey(const Key('player-road')));
    await tester.pumpAndSettle();
    expect(find.text('主线路'), findsWidgets);
    expect(find.text('备用线路'), findsWidgets);
  });

  testWidgets('切线路：选备用线路触发新 URL 加载', (tester) async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: multiRoad(),
      initialIndex: 0,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: PlayerPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('player-road')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用线路').last);
    await tester.pump();
    await tester.pump();

    expect(controller.currentRoadIndex, 2);
    expect(engine.openedUrls, contains('https://b.test/1.m3u8'));
  });

  testWidgets('单线路：不显示选择器，保持原有播放行为', (tester) async {
    final engine = FakePlaybackEngine();
    final controller = PlayerController(
      engine: engine,
      episodes: const <Episode>[
        Episode(number: 1, title: '1', url: 'https://a.test/1.m3u8'),
        Episode(number: 2, title: '2', url: 'https://a.test/2.m3u8'),
      ],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: PlayerPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('player-road')), findsNothing);
    expect(find.byKey(const Key('player-play-pause')), findsOneWidget);
    expect(controller.isPlaying, isTrue);
  });
}
