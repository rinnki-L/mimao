// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 榜单详情页测试：rank.id 缺失不发请求、rankAudio 错误重试、空态、点歌。
/// 全部走 fake（无网络、无真实计时器）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/pages/music_rank_detail_page.dart';

import 'fakes.dart';

Widget _app(Widget body) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(body: SafeArea(child: body)),
);

void main() {
  testWidgets('rank.id 缺失 → 不调 API，直接显示错误态', (tester) async {
    final api = FakeRankApi();
    await tester.pumpWidget(
      _app(
        MusicRankDetailPage(api: api, rank: rankNoId, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无名榜'), findsOneWidget);
    expect(find.textContaining('榜单缺少有效 ID'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(api.calls, isEmpty, reason: '无 id 时不发 rankAudio 请求');
  });

  testWidgets('rankAudio 失败 → 错误态；重试成功后渲染歌曲行', (tester) async {
    final api = FakeRankApi(
      failures: <String, List<Object>>{
        'rankAudio': <Object>[StateError('榜单接口挂了')],
      },
    );
    await tester.pumpWidget(
      _app(
        MusicRankDetailPage(api: api, rank: rankWithId, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('榜单接口挂了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(api.rankAudioRankIds, <int>[101]);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('榜单歌一'), findsOneWidget);
    expect(find.text('榜单歌二'), findsOneWidget);
    expect(find.text('榜单歌三'), findsOneWidget);
    // 榜内序号取 ranking.position；无 ranking 的歌三退回列表序号。
    expect(find.text('1'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(api.rankAudioRankIds, <int>[101, 101]);
  });

  testWidgets('rankAudio 空列表 → 空态文案', (tester) async {
    final api = FakeRankApi(rankAudioEmpty: true);
    await tester.pumpWidget(
      _app(
        MusicRankDetailPage(api: api, rank: rankWithId, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无歌曲'), findsOneWidget);
    expect(find.text('榜单歌一'), findsNothing);
  });

  testWidgets('点歌曲行 → playSong(song) + push 播放页', (tester) async {
    final api = FakeRankApi();
    final player = FakePlayerUi();
    await tester.pumpWidget(
      _app(MusicRankDetailPage(api: api, rank: rankWithId, player: player)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('榜单歌一'));
    await tester.pumpAndSettle();

    expect(player.played, hasLength(1));
    expect(player.played.first.id, '9001');
    expect(player.playerPageBuilds, 1);
    expect(find.text('播放页测试桩'), findsOneWidget);
  });
}
