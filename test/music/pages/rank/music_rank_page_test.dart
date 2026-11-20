// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 榜单总页测试：tab 渲染、rankTop/rankList 去重、导航详情、点歌、
/// 错误隔离与重试、歌单分类输入。全部走 fake（无网络、无真实计时器）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/pages/music_rank_detail_page.dart';
import 'package:mimao/music/pages/music_rank_page.dart';

import 'fakes.dart';

Widget _app(Widget body) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(body: SafeArea(child: body)),
);

Future<void> _pumpPage(
  WidgetTester tester,
  FakeRankApi api,
  FakePlayerUi player,
) async {
  await tester.pumpWidget(_app(MusicRankPage(api: api, player: player)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('榜单 tab：rankTop/rankList 并行加载、去重合并渲染卡片', (tester) async {
    final api = FakeRankApi();
    await _pumpPage(tester, api, FakePlayerUi());

    expect(api.calls, containsAll(<String>['rankTop', 'rankList']));
    // soar 同时出现在 rankTop 与 rankList（同 id 101）：卡片只渲染一次。
    expect(find.text('飙升榜'), findsOneWidget);
    expect(find.text('新歌推荐榜'), findsOneWidget);
    expect(find.text('热歌榜'), findsOneWidget);
    // 卡片信息：更新频率 chip 与简介。
    expect(find.text('每天更新'), findsWidgets);
    expect(find.textContaining('飙升榜简介'), findsOneWidget);
    expect(find.textContaining('每周更新'), findsWidgets);
  });

  testWidgets('点榜单卡片 → push 详情页并调用 rankAudio(rankId)', (tester) async {
    final api = FakeRankApi();
    await _pumpPage(tester, api, FakePlayerUi());

    await tester.tap(find.text('飙升榜'));
    await tester.pumpAndSettle();

    expect(find.byType(MusicRankDetailPage), findsOneWidget);
    expect(api.rankAudioRankIds, <int>[101]);
    // 歌曲行渲染；榜内序号取 ranking.position。
    expect(find.text('榜单歌一'), findsOneWidget);
    expect(find.text('榜单歌二'), findsOneWidget);
    expect(find.text('榜单歌三'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // 头部：更新频率 + 发布期 + 简介。
    expect(find.text('每天更新 · 2026-11-20'), findsOneWidget);
    expect(find.textContaining('飙升榜简介'), findsOneWidget);
  });

  testWidgets('新歌/专辑/歌单/IP tab 各自独立加载渲染', (tester) async {
    final api = FakeRankApi();
    await _pumpPage(tester, api, FakePlayerUi());

    // 新歌：topSongs；序号取 chart.position（5）而非列表序号（1）。
    await tester.tap(find.text('新歌'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('topSongs'));
    expect(find.text('新歌一'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('歌手丁 · 专辑丁'), findsOneWidget);
    expect(find.text('3:20'), findsOneWidget);

    // 专辑：topAlbums；空分组（日本/韩国）不渲染标题。
    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('topAlbums'));
    expect(find.text('华语'), findsOneWidget);
    expect(find.text('华语新碟一'), findsOneWidget);
    expect(find.text('欧洲'), findsOneWidget);
    expect(find.text('欧洲新碟一'), findsOneWidget);
    expect(find.text('日本'), findsNothing);
    expect(find.text('韩国'), findsNothing);

    // 歌单：topPlaylists 默认分类 0；播放数缩写。
    await tester.tap(find.text('歌单'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('topPlaylists'));
    expect(api.topPlaylistCategoryIds, <String>['0']);
    expect(find.text('推荐歌单一'), findsOneWidget);
    expect(find.text('创建者801 · 播放 1.2 万'), findsOneWidget);

    // IP：topIps。
    await tester.tap(find.text('IP'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('topIps'));
    expect(find.text('IP 榜单一'), findsOneWidget);
  });

  testWidgets('接口失败 → 该 tab 显示重试，其它 tab 不受影响；重试后恢复', (tester) async {
    final api = FakeRankApi(
      failures: <String, List<Object>>{
        'topAlbums': <Object>[StateError('专辑接口挂了')],
      },
    );
    await _pumpPage(tester, api, FakePlayerUi());

    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();
    expect(find.textContaining('专辑接口挂了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 其它 tab 不受影响。
    await tester.tap(find.text('新歌'));
    await tester.pumpAndSettle();
    expect(find.text('新歌一'), findsOneWidget);
    expect(find.textContaining('专辑接口挂了'), findsNothing);

    // 回到专辑 tab：错误态保留；重试（fake 失败队列已耗尽）后渲染数据。
    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('华语新碟一'), findsOneWidget);
    expect(find.textContaining('专辑接口挂了'), findsNothing);
  });

  testWidgets('新歌 tab 点歌 → playSong + push 播放页', (tester) async {
    final api = FakeRankApi();
    final player = FakePlayerUi();
    await _pumpPage(tester, api, player);

    await tester.tap(find.text('新歌'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新歌一'));
    await tester.pumpAndSettle();

    expect(player.played, hasLength(1));
    expect(player.played.first.title, '新歌一');
    expect(player.playerPageBuilds, 1);
    expect(find.text('播放页测试桩'), findsOneWidget);
  });

  testWidgets('歌单 tab：改分类刷新走 topPlaylists(新分类)；非法分类只出行内提示', (tester) async {
    final api = FakeRankApi();
    await _pumpPage(tester, api, FakePlayerUi());

    await tester.tap(find.text('歌单'));
    await tester.pumpAndSettle();
    expect(find.text('推荐歌单一'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '8');
    await tester.tap(find.byTooltip('按分类刷新'));
    await tester.pumpAndSettle();
    expect(api.topPlaylistCategoryIds, <String>['0', '8']);
    expect(find.text('推荐歌单一'), findsOneWidget);

    // 非法分类：API 查询类 validate 的 input 错误只作行内提示，
    // 不整页替换（输入框与已有卡片保持可见），也不发请求。
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.byTooltip('按分类刷新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('推荐歌单分类无效'), findsOneWidget);
    expect(find.text('推荐歌单一'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(api.topPlaylistCategoryIds, <String>['0', '8']);
  });
}
