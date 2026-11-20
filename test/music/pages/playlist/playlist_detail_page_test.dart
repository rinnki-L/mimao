// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 歌单详情页（U4）测试：全 fake，无网络、无真实计时器。
///
/// 云歌单 → playlistTrackAllNew；公开歌单 → playlistDetail + playlistTrackAll；
/// 头部缺失降级为构造占位；曲目点击先 playSong 再 push 播放页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/pages/music_playlist_detail_page.dart';

import 'fakes.dart';

Widget _app(Widget home) =>
    MaterialApp(debugShowCheckedModeBanner: false, home: home);

Future<void> _pumpDetail(
  WidgetTester tester,
  FakePlaylistReadApi read,
  FakePlayerUi player, {
  FakePlaylistWriteApi? write,
  bool? editable,
  int? cloudListId,
  String globalId = '',
  String? title,
  String? coverUrl,
}) async {
  await tester.pumpWidget(
    _app(
      MusicPlaylistDetailPage(
        read: read,
        player: player,
        globalId: globalId,
        cloudListId: cloudListId,
        title: title,
        coverUrl: coverUrl,
        write: write,
        editable: editable,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakePlaylistReadApi read;
  late FakePlaylistWriteApi write;
  late FakePlayerUi player;

  setUp(() {
    read = FakePlaylistReadApi();
    write = FakePlaylistWriteApi();
    player = FakePlayerUi();
  });

  testWidgets('云歌单：走 playlistTrackAllNew，头部用传入标题占位', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单歌曲', artist: '歌手A')],
    ];

    await _pumpDetail(
      tester,
      read,
      player,
      cloudListId: 77,
      title: '我的云单',
      coverUrl: '',
    );

    expect(find.text('我的云单'), findsWidgets); // AppBar + 头部
    expect(find.text('云单歌曲'), findsOneWidget);
    expect(find.text('歌手A'), findsOneWidget);
    expect(find.text('3:20'), findsOneWidget);
    expect(read.trackAllNewQueries.single.cloudListId, 77);
    expect(read.trackAllNewQueries.single.page, 1);
    expect(read.detailQueries, isEmpty);
    expect(read.trackAllQueries, isEmpty);
  });

  testWidgets('公开歌单：playlistDetail + playlistTrackAll；头部用线上信息', (tester) async {
    read.details = <MusicPlaylistDetail>[
      testDetail(
        globalId: 'g-9',
        title: '线上标题',
        creatorName: '收藏作者',
        songCount: 30,
        description: '写给深夜的歌单',
      ),
    ];
    read.trackAllPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '2', title: '公开曲目')],
    ];

    await _pumpDetail(tester, read, player, globalId: 'g-9', title: '占位标题');

    expect(find.text('线上标题'), findsWidgets);
    expect(find.text('创建者：收藏作者'), findsOneWidget);
    expect(find.text('共 30 首'), findsOneWidget);
    expect(find.text('写给深夜的歌单'), findsOneWidget);
    expect(find.text('公开曲目'), findsOneWidget);
    expect(read.detailQueries.single.globalIds, <String>['g-9']);
    expect(read.trackAllQueries.single.globalId, 'g-9');
    expect(read.trackAllQueries.single.page, 1);
    expect(read.trackAllNewQueries, isEmpty);
  });

  testWidgets('公开歌单头部缺失/失败时用传入 title 占位，不挡曲目', (tester) async {
    read.detailError = const KugouApiException('business', '详情加载失败');
    read.trackAllPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '3', title: '曲目三')],
    ];

    await _pumpDetail(
      tester,
      read,
      player,
      globalId: 'g-9',
      title: '占位标题',
      coverUrl: '',
    );

    expect(find.text('占位标题'), findsWidgets);
    expect(find.text('曲目三'), findsOneWidget);
  });

  testWidgets('点击曲目：先 playSong 再打开播放页', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '可播曲目')],
    ];

    await _pumpDetail(tester, read, player, cloudListId: 77, title: '云单');
    await tester.tap(find.text('可播曲目'));
    await tester.pumpAndSettle();

    expect(player.played.single.id, '1');
    expect(find.text('播放页测试锚点'), findsOneWidget);
  });

  testWidgets('云歌单分页「加载更多」追加', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[
        testTrack(id: '1', title: '曲目一'),
        testTrack(id: '2', title: '曲目二'),
      ],
      <MusicPlaylistTrack>[testTrack(id: '3', title: '曲目三')],
    ];

    await _pumpDetail(tester, read, player, cloudListId: 77);
    expect(find.text('曲目一'), findsOneWidget);
    expect(find.text('曲目三'), findsNothing);

    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(find.text('曲目三'), findsOneWidget);
    expect(read.trackAllNewQueries.map((query) => query.page), <int>[1, 2]);
  });

  testWidgets('公开歌单分页「加载更多」追加', (tester) async {
    read.trackAllPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '曲目一')],
      <MusicPlaylistTrack>[testTrack(id: '2', title: '曲目二')],
    ];

    await _pumpDetail(tester, read, player, globalId: 'g-9');
    expect(find.text('曲目二'), findsNothing);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(find.text('曲目二'), findsOneWidget);
    expect(read.trackAllQueries.map((query) => query.page), <int>[1, 2]);
  });

  testWidgets('云歌单 authentication 错误显示登录提示且无重试', (tester) async {
    read.trackAllNewError = const KugouApiException('authentication', '账号认证无效');

    await _pumpDetail(tester, read, player, cloudListId: 77, title: '云单');

    expect(find.text('请先登录酷狗账号'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('公开歌单曲目错误带重试；重试成功后渲染', (tester) async {
    read.trackAllError = const KugouApiException('business', '曲目加载失败');

    await _pumpDetail(tester, read, player, globalId: 'g-9');
    expect(find.text('曲目加载失败'), findsOneWidget);

    read.trackAllError = null;
    read.trackAllPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '4', title: '恢复曲目')],
    ];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('恢复曲目'), findsOneWidget);
  });

  testWidgets('空歌单显示空态提示', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[<MusicPlaylistTrack>[]];

    await _pumpDetail(tester, read, player, cloudListId: 77, title: '空歌单');

    expect(find.text('歌单里还没有歌曲'), findsOneWidget);
  });

  testWidgets('删除歌单：可编辑云歌单出 AppBar 入口，确认后 playlistDel 并返回', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    // 从宿主页 push：验证删除成功后 pop(true) 回到宿主。
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MusicPlaylistDetailPage(
                        read: read,
                        player: player,
                        globalId: '',
                        cloudListId: 77,
                        title: '可删歌单',
                        write: write,
                        editable: true,
                      ),
                    ),
                  );
                },
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('云单曲目'), findsOneWidget);

    await tester.tap(find.byTooltip('删除歌单'));
    await tester.pumpAndSettle();
    // 二次确认；未确认不调用写端点。
    expect(find.text('确定删除歌单「可删歌单」吗？删除后不可恢复。'), findsOneWidget);
    expect(write.delQueries, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(write.delQueries.single.cloudListId, 77);
    expect(find.text('打开详情'), findsOneWidget); // 已 pop 回宿主页
  });

  testWidgets('非可编辑 / write 未接线时不出删除入口', (tester) async {
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单曲目')],
    ];

    await _pumpDetail(
      tester,
      read,
      player,
      cloudListId: 77,
      title: '云单',
      write: write,
      editable: false,
    );
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await _pumpDetail(tester, read, player, cloudListId: 77, title: '云单');
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
