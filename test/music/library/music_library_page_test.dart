// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
// 验收 C13/C14：我的页两段列表、倒序、进度文案与续播回调。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_library_page.dart';

import 'music_test_env.dart';

Widget _app(Widget body) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(body: SafeArea(child: body)),
);

void main() {
  late MusicTestEnv env;

  setUp(() {
    env = MusicTestEnv.create();
  });

  tearDown(() => env.close());

  Future<void> seed() async {
    await env.collect.collectRef(
      const MusicRef(id: 'a'),
      title: '收藏一',
      song: testSong(id: 'a', title: '收藏一'),
      collectedAt: DateTime(2026, 11, 1),
    );
    await env.collect.collectRef(
      const MusicRef(id: 'b'),
      title: '收藏二',
      song: testSong(id: 'b', title: '收藏二'),
      collectedAt: DateTime(2026, 11, 2),
    );
    await env.history.saveProgressRef(
      const MusicRef(id: 'h1'),
      positionMs: 60000,
      durationMs: 300000,
      title: '历史一',
      song: testSong(id: 'h1', title: '历史一'),
      at: DateTime(2026, 11, 18),
    );
    await env.history.saveProgressRef(
      const MusicRef(id: 'h2'),
      positionMs: 150000,
      durationMs: 300000,
      title: '历史二',
      song: testSong(id: 'h2', title: '历史二'),
      at: DateTime(2026, 11, 19),
    );
  }

  testWidgets('C13 收藏段倒序显示；历史段显示最近播放 + 进度文案', (tester) async {
    await seed();
    await tester.pumpWidget(
      _app(MusicLibraryPage(collect: env.collect, history: env.history)),
    );
    await tester.pumpAndSettle();

    expect(find.text('我喜欢'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('收藏二'), findsOneWidget);
    expect(find.text('收藏一'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('收藏二')).dy,
      lessThan(tester.getTopLeft(find.text('收藏一')).dy),
      reason: '收藏按时间倒序',
    );

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();

    expect(find.text('历史二'), findsOneWidget);
    expect(find.text('历史一'), findsOneWidget);
    expect(find.textContaining('已听 50%'), findsOneWidget);
    expect(find.textContaining('已听 20%'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('历史二')).dy,
      lessThan(tester.getTopLeft(find.text('历史一')).dy),
      reason: '历史按打开时间倒序',
    );
  });

  testWidgets('C13 两段空态文案', (tester) async {
    await tester.pumpWidget(
      _app(MusicLibraryPage(collect: env.collect, history: env.history)),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有收藏的歌曲'), findsOneWidget);
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('还没有播放记录'), findsOneWidget);
  });

  testWidgets('C14 历史点击：注入 onPlaySong 时收到曲目与起始位置', (tester) async {
    await seed();
    MusicSong? played;
    Duration? startAt;

    await tester.pumpWidget(
      _app(
        MusicLibraryPage(
          collect: env.collect,
          history: env.history,
          onPlaySong: (song, at) {
            played = song;
            startAt = at;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('library-history-h1')));
    await tester.pump();

    expect(played!.id, 'h1');
    expect(played!.title, '历史一');
    expect(startAt, const Duration(milliseconds: 60000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('集成收口：播完的歌从历史续播时从 0 重播（不 seek 到结尾）', (tester) async {
    await env.history.saveProgressRef(
      const MusicRef(id: 'end'),
      positionMs: 300000,
      durationMs: 300000,
      title: '播完的歌',
      song: testSong(id: 'end', title: '播完的歌', durationMs: 300000),
    );
    Duration? startAt;
    await tester.pumpWidget(
      _app(
        MusicLibraryPage(
          collect: env.collect,
          history: env.history,
          onPlaySong: (song, at) => startAt = at,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('library-history-end')));
    await tester.pump();

    expect(startAt, Duration.zero, reason: '历史位置≈总时长时从头重播');
  });

  testWidgets('C14 未接播放时点历史条目：提示未接线且不崩溃', (tester) async {
    await seed();
    await tester.pumpWidget(
      _app(MusicLibraryPage(collect: env.collect, history: env.history)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('library-history-h2')));
    await tester.pump();

    expect(find.text('播放功能未接线'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏段条目在无曲目快照时不崩溃（旧/坏 payload）', (tester) async {
    await env.collect.collectRef(
      const MusicRef(id: 'old'),
      title: '旧收藏',
      // 不传 song：payload 落 '{}'，list() 重建不出曲目。
    );
    await tester.pumpWidget(
      _app(MusicLibraryPage(collect: env.collect, history: env.history)),
    );
    await tester.pumpAndSettle();

    expect(find.text('旧收藏'), findsOneWidget);
    expect(find.text('已收藏'), findsOneWidget);
    await tester.tap(find.text('旧收藏'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
