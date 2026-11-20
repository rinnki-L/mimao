// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 歌单列表页（U4）测试：全 fake，无网络、无真实计时器。
///
/// SnackBar 会挂一个自动关闭的一次性 Timer——凡触发过 SnackBar 的用例
/// 末尾都要越过其时长，避免「Timer is still pending」导致测试失败。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/pages/music_playlist_list_page.dart';

import 'fakes.dart';

Widget _app(Widget home) =>
    MaterialApp(debugShowCheckedModeBanner: false, home: home);

MusicPlaylistListPage _page(
  FakeUserLibraryApi library,
  FakePlaylistReadApi read,
  FakePlayerUi player, {
  FakePlaylistWriteApi? write,
}) => MusicPlaylistListPage(
  library: library,
  read: read,
  player: player,
  write: write,
);

/// 越过 SnackBar 自动关闭计时器 + 收尾动画。
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  late FakeUserLibraryApi library;
  late FakePlaylistReadApi read;
  late FakePlaylistWriteApi write;
  late FakePlayerUi player;

  setUp(() {
    library = FakeUserLibraryApi();
    read = FakePlaylistReadApi();
    write = FakePlaylistWriteApi();
    player = FakePlayerUi();
  });

  testWidgets('列表渲染云歌单：标题/歌曲数/创建者/公开私有标签', (tester) async {
    library.items.addAll(<MusicUserPlaylist>[
      testPlaylist(
        cloudListId: 101,
        globalId: 'g-101',
        title: '自建歌单',
        songCount: 12,
        editable: true,
        isPrivate: false,
      ),
      testPlaylist(
        cloudListId: 102,
        globalId: 'g-102',
        title: '私有收藏',
        songCount: 3,
        editable: false,
        isPrivate: true,
      ),
    ]);

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();

    expect(find.text('自建歌单'), findsOneWidget);
    expect(find.text('12首 · 我'), findsOneWidget);
    expect(find.text('3首 · 我'), findsOneWidget);
    expect(find.text('公开'), findsOneWidget);
    expect(find.text('私有'), findsOneWidget);
    // 可编辑条目出菜单；不可编辑的不出。
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(library.queries.single.page, 1);
    expect(library.queries.single.pageSize, 50);
  });

  testWidgets('点击云歌单进入详情并携带 cloudListId', (tester) async {
    library.items.add(
      testPlaylist(cloudListId: 101, globalId: 'g-101', title: '自建歌单'),
    );
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '1', title: '云单歌曲')],
    ];

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自建歌单'));
    await tester.pumpAndSettle();

    // 详情页渲染了曲目 → push 成功；且用传入的 cloudListId 发起云歌单请求。
    expect(find.text('云单歌曲'), findsOneWidget);
    expect(read.trackAllNewQueries.single.cloudListId, 101);
    expect(read.trackAllNewQueries.single.page, 1);
    expect(read.detailQueries, isEmpty);
    expect(read.trackAllQueries, isEmpty);
  });

  testWidgets('点击公开歌单进入详情并携带 globalId', (tester) async {
    library.items.add(
      testPlaylist(cloudListId: null, globalId: 'g-201', title: '公开歌单'),
    );
    read.details = <MusicPlaylistDetail>[
      testDetail(globalId: 'g-201', title: '线上标题', creatorName: '收藏作者'),
    ];
    read.trackAllPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: '2', title: '公开曲目')],
    ];

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公开歌单'));
    await tester.pumpAndSettle();

    expect(find.text('线上标题'), findsWidgets);
    expect(find.text('公开曲目'), findsOneWidget);
    expect(read.detailQueries.single.globalIds, <String>['g-201']);
    expect(read.trackAllQueries.single.globalId, 'g-201');
    expect(read.trackAllNewQueries, isEmpty);
  });

  testWidgets('新建歌单：playlistAdd 收到标题/私有标记，列表刷新出现新条目', (tester) async {
    library.items.add(testPlaylist(cloudListId: 101, title: '旧歌单'));
    write.onAdd = (query) => library.items.add(
      testPlaylist(cloudListId: 999, globalId: 'g-999', title: query.title),
    );

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建歌单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的新歌单');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(write.addQueries.single.title, '我的新歌单');
    expect(write.addQueries.single.isPrivate, true);
    expect(find.text('我的新歌单'), findsOneWidget);
    await _drainSnackBar(tester);
  });

  testWidgets('删除歌单：条目菜单 + 二次确认后调用 playlistDel，列表刷新移除', (tester) async {
    library.items.add(
      testPlaylist(cloudListId: 101, title: '待删歌单', editable: true),
    );
    write.onDel = (_) => library.items.clear();

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 二次确认框出现，未确认前不调用写端点。
    expect(find.text('确定删除歌单「待删歌单」吗？删除后不可恢复。'), findsOneWidget);
    expect(write.delQueries, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(write.delQueries.single.cloudListId, 101);
    expect(find.text('待删歌单'), findsNothing);
    await _drainSnackBar(tester);
  });

  testWidgets('非可编辑条目不出删除菜单；write 未接线不出新建入口', (tester) async {
    library.items.add(
      testPlaylist(cloudListId: 101, title: '收藏歌单', editable: false),
    );

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.more_vert), findsNothing);

    // write 为 null：无 FAB。
    await tester.pumpWidget(_app(_page(library, read, player)));
    await tester.pumpAndSettle();
    expect(find.text('新建歌单'), findsNothing);
    expect(find.text('收藏歌单'), findsOneWidget);
  });

  testWidgets('authentication 错误显示登录提示且无重试', (tester) async {
    library.error = const KugouApiException('authentication', '账号认证无效，请重新登录');

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();

    expect(find.text('请先登录酷狗账号'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('其它错误显示重试；重试成功后渲染列表', (tester) async {
    library.error = const KugouApiException('business', '服务繁忙');

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    expect(find.text('服务繁忙'), findsOneWidget);

    library.error = null;
    library.items.add(testPlaylist(cloudListId: 101, title: '恢复歌单'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('恢复歌单'), findsOneWidget);
    expect(library.queries.map((query) => query.page), <int>[1, 1]);
  });

  testWidgets('分页加载更多追加（page/total 回显驱动）', (tester) async {
    for (var i = 1; i <= 5; i++) {
      library.items.add(
        testPlaylist(cloudListId: 100 + i, globalId: 'g-$i', title: '歌单$i'),
      );
    }

    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    expect(find.text('歌单3'), findsOneWidget);
    expect(find.text('歌单4'), findsNothing);

    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(find.text('歌单4'), findsOneWidget);
    expect(find.text('歌单5'), findsOneWidget);
    expect(library.queries.map((query) => query.page), <int>[1, 2]);
  });

  testWidgets('空歌单列表显示空态提示', (tester) async {
    await tester.pumpWidget(_app(_page(library, read, player, write: write)));
    await tester.pumpAndSettle();
    expect(find.text('还没有歌单，点右下角新建一个吧'), findsOneWidget);
  });
}
