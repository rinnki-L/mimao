// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 用户中心页测试：分区渲染、登录引导、播放映射、游标/分页加载、回调与
/// 故障隔离。全部走 fake（见 fakes.dart），不联网、无真实计时器。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/models/user_models.dart';
import 'package:mimao/music/pages/music_account_center_page.dart';

import 'fakes.dart';

/// 测试夹具：fake 三接口 + 回调记录。
class _Harness {
  final FakeUserProfileApi profile = FakeUserProfileApi();
  final FakeUserLibraryApi library = FakeUserLibraryApi();
  final FakePlayerUi player = FakePlayerUi();
  final List<int> openedAlbums = <int>[];
  final List<MusicUserPlaylist> openedPlaylists = <MusicUserPlaylist>[];

  /// 配置一套「全部成功」的最小数据（单个测试再按需覆盖个别分区）。
  _Harness() {
    profile
      ..detail = fakeProfile()
      ..tags = fakeTags()
      ..vip = fakeVip(
        products: <MusicUserVipMembershipProduct>[fakeVipProduct()],
      )
      ..grade = fakeGrade();
    library
      ..playlists = fakePlaylists(
        items: <MusicUserPlaylist>[
          fakePlaylist(title: '歌单一', songCount: 12),
          fakePlaylist(title: '歌单二', songCount: 3),
        ],
      )
      ..historyPages.add(
        fakeHistoryPage(
          items: <MusicHistoryItem>[
            fakeHistoryItem(),
            fakeHistoryItem(songId: '7002', name: '历史歌二', artist: '歌手乙'),
          ],
        ),
      )
      ..purchasedAlbumPages.add(
        MusicPage<MusicPurchasedAlbum>(
          page: 1,
          pageSize: 20,
          total: 3,
          items: <MusicPurchasedAlbum>[
            fakePurchasedAlbum(id: 321, title: '专辑甲'),
            fakePurchasedAlbum(id: null, title: '专辑乙'),
          ],
        ),
      )
      ..purchasedSongPages.add(
        MusicPage<MusicPurchasedSong>(
          page: 1,
          pageSize: 20,
          total: 1,
          items: <MusicPurchasedSong>[fakePurchasedSong()],
        ),
      );
  }

  Widget build() {
    return MaterialApp(
      home: MusicAccountCenterPage(
        profile: profile,
        library: library,
        player: player,
        onOpenAlbum: openedAlbums.add,
        onOpenPlaylist: openedPlaylists.add,
      ),
    );
  }
}

/// 装载页面：fake 接口在微任务里完成，一次 pump 即可拿到终态。
/// [surface] 非空时覆盖测试视口（窄屏/加高用）。
Future<_Harness> _pumpPage(
  WidgetTester tester,
  _Harness harness, {
  Size? surface,
}) async {
  if (surface != null) {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(harness.build());
  await tester.pump();
  return harness;
}

Finder _section(String key) => find.byKey(ValueKey<String>(key));

void main() {
  testWidgets('资料头渲染昵称/等级/简介/标签/统计，各分区按默认查询装载', (tester) async {
    final h = await _pumpPage(tester, _Harness());

    expect(find.text('示例昵称'), findsOneWidget);
    expect(find.text('ID：9001 · Lv.7'), findsOneWidget);
    expect(find.text('一句话简介'), findsOneWidget);
    expect(find.text('夜猫子'), findsOneWidget);
    expect(find.text('关注 3 · 粉丝 9 · 听歌 1234 分钟 · 属地 广东深圳'), findsOneWidget);

    // 听歌等级：userGradeInfo(null) 查当前账号。
    expect(h.profile.gradeCalls, 1);
    expect(h.profile.gradeUserIds, <int?>[null]);
    // 听歌历史首页：不带 bp 游标。
    expect(h.library.historyQueries.single.bp, isNull);
    // 我的歌单：page=1、pageSize=20。
    expect(h.library.playlistQueries.single.page, 1);
    expect(h.library.playlistQueries.single.pageSize, 20);
    // 已购分区首页：page=1、pageSize=20。
    expect(h.library.purchasedAlbumQueries.single.page, 1);
    expect(h.library.purchasedAlbumQueries.single.pageSize, 20);
    expect(h.library.purchasedSongQueries.single.page, 1);
  });

  testWidgets('匿名（authentication）时资料头与分区显示登录提示且可重试', (tester) async {
    final h = _Harness()
      ..profile.detailError = authenticationError()
      ..library.historyError = authenticationError();
    await _pumpPage(tester, h);

    // 资料头 + 听歌历史分区两处引导。
    expect(find.text('请先登录酷狗账号'), findsNWidgets(2));
    expect(find.text('示例昵称'), findsNothing);

    await tester.tap(
      find.descendant(
        of: _section('account-profile'),
        matching: find.text('重试'),
      ),
    );
    await tester.pump();
    expect(h.profile.detailCalls, 2);
    // 仍是匿名：提示保持。
    expect(find.text('请先登录酷狗账号'), findsNWidgets(2));
  });

  testWidgets('会员与听歌等级分区渲染产品/到期与等级进度', (tester) async {
    await _pumpPage(tester, _Harness(), surface: const Size(800, 1800));

    expect(find.text('豪华会员 · 至 2027-01-01 00:00:00'), findsOneWidget);
    expect(find.text('酷狗豪华VIP'), findsOneWidget);
    expect(find.text('到期：2026-12-31 23:59:59'), findsOneWidget);
    expect(find.text('生效中'), findsOneWidget);

    expect(find.text('Lv.7'), findsOneWidget);
    expect(find.text('当前积分 300'), findsOneWidget);
    expect(find.text('累计听歌 2 小时 3 分钟'), findsOneWidget);
    expect(find.text('距 Lv.8 还需 300 积分'), findsOneWidget);
    final LinearProgressIndicator bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5); // (300 - 0) / (600 - 0)
  });

  testWidgets('历史列表点击播放：MusicHistoryItem 映射为 MusicSong', (tester) async {
    final h = await _pumpPage(
      tester,
      _Harness(),
      surface: const Size(800, 1800),
    );

    await tester.ensureVisible(find.text('历史歌一'));
    await tester.tap(find.text('历史歌一'));
    await tester.pump();

    expect(h.player.played, hasLength(1));
    final MusicSong song = h.player.played.single;
    expect(song.id, '7001');
    expect(song.title, '历史歌一');
    expect(song.hash, '0123456789abcdef0123456789abcdef');
    expect(song.artistText, '歌手甲');
    expect(song.albumTitle, '专辑甲');
    expect(song.durationMs, 213000);
  });

  testWidgets('历史按 bp 游标加载更多：追加且游标透传，耗尽后收尾', (tester) async {
    final h = _Harness();
    h.library.historyPages
      ..clear()
      ..addAll(<MusicHistoryPage>[
        fakeHistoryPage(
          items: <MusicHistoryItem>[fakeHistoryItem()],
          cursor: 'bp-1',
          hasMore: true,
        ),
        fakeHistoryPage(
          items: <MusicHistoryItem>[
            fakeHistoryItem(songId: '7003', name: '历史歌三'),
          ],
          hasMore: false,
        ),
      ]);
    await _pumpPage(tester, h, surface: const Size(800, 1800));

    expect(find.text('历史歌一'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('account-history-more')),
    );
    await tester.tap(find.byKey(const ValueKey('account-history-more')));
    await tester.pump();

    // 第二次请求带上游给的 bp 游标。
    expect(h.library.historyQueries, hasLength(2));
    expect(h.library.historyQueries[1].bp, 'bp-1');
    expect(find.text('历史歌三'), findsOneWidget);
    expect(
      find.descendant(
        of: _section('account-history'),
        matching: find.text('没有更多了'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('已购专辑点击回调携带 id（id 为空不回调），分页加载更多追加', (tester) async {
    final h = _Harness()
      ..library.purchasedAlbumPages.add(
        MusicPage<MusicPurchasedAlbum>(
          page: 2,
          pageSize: 20,
          total: 3,
          items: <MusicPurchasedAlbum>[
            fakePurchasedAlbum(id: 999, title: '专辑丙'),
          ],
        ),
      );
    await _pumpPage(tester, h, surface: const Size(800, 1800));

    await tester.ensureVisible(find.text('专辑甲'));
    await tester.tap(find.text('专辑甲'));
    await tester.pump();
    expect(h.openedAlbums, <int>[321]);

    // id 为 null 的专辑不回调。
    await tester.tap(find.text('专辑乙'));
    await tester.pump();
    expect(h.openedAlbums, <int>[321]);

    // 分页加载更多：第二页、追加后总数齐平、hasMore 收口。
    await tester.ensureVisible(
      find.byKey(const ValueKey('account-albums-more')),
    );
    await tester.tap(find.byKey(const ValueKey('account-albums-more')));
    await tester.pump();
    expect(h.library.purchasedAlbumQueries, hasLength(2));
    expect(h.library.purchasedAlbumQueries[1].page, 2);
    expect(find.text('专辑丙'), findsOneWidget);
    expect(
      find.descendant(
        of: _section('account-albums'),
        matching: find.text('没有更多了'),
      ),
      findsOneWidget,
    );
    expect(h.library.purchasedAlbumPages, isEmpty);
  });

  testWidgets('已购单曲点击播放', (tester) async {
    final h = await _pumpPage(
      tester,
      _Harness(),
      surface: const Size(800, 1800),
    );

    await tester.ensureVisible(find.text('已购单曲一'));
    await tester.tap(find.text('已购单曲一'));
    await tester.pump();

    expect(h.player.played, hasLength(1));
    expect(h.player.played.single.id, '8001');
    expect(h.player.played.single.title, '已购单曲一');
  });

  testWidgets('我的歌单点击回调携带条目', (tester) async {
    final h = await _pumpPage(
      tester,
      _Harness(),
      surface: const Size(800, 1800),
    );

    expect(find.text('共 2 个'), findsOneWidget);
    await tester.ensureVisible(find.text('歌单一'));
    await tester.tap(find.text('歌单一'));
    await tester.pump();

    expect(h.openedPlaylists, hasLength(1));
    expect(h.openedPlaylists.single.title, '歌单一');
    expect(h.openedPlaylists.single.songCount, 12);
  });

  testWidgets('某分区失败时其它分区仍渲染，重试后恢复', (tester) async {
    final h = _Harness()
      ..profile.vipError = const KugouApiException(
        'business',
        '服务繁忙',
        code: 500,
      );
    await _pumpPage(tester, h, surface: const Size(800, 1800));

    // 会员分区行内报错，其余分区照常。
    expect(find.textContaining('服务繁忙'), findsOneWidget);
    expect(find.text('示例昵称'), findsOneWidget);
    expect(find.text('历史歌一'), findsOneWidget);
    expect(find.text('歌单一'), findsOneWidget);

    h.profile.vipError = null;
    await tester.tap(
      find.descendant(of: _section('account-vip'), matching: find.text('重试')),
    );
    await tester.pump();
    expect(find.text('豪华会员 · 至 2027-01-01 00:00:00'), findsOneWidget);
    expect(find.textContaining('服务繁忙'), findsNothing);
  });

  testWidgets('整页下拉刷新重拉所有分区', (tester) async {
    final h = await _pumpPage(
      tester,
      _Harness(),
      surface: const Size(800, 1800),
    );
    expect(h.profile.detailCalls, 1);

    // 队列已被首页消费：补一页，让刷新后分区仍有数据。
    h.library.historyPages.add(
      fakeHistoryPage(
        items: <MusicHistoryItem>[
          fakeHistoryItem(songId: '7002', name: '历史歌二', artist: '歌手乙'),
        ],
      ),
    );

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, 300),
      1000,
    );
    await tester.pump(); // onRefresh 启动
    await tester.pump(const Duration(seconds: 1)); // fake 响应返回
    await tester.pumpAndSettle(); // 刷新指示器退场

    expect(h.profile.detailCalls, 2);
    expect(h.library.historyQueries, hasLength(2));
    expect(find.text('历史歌二'), findsOneWidget);
  });

  testWidgets('宽屏布局：资料卡与会员同一行、等级与专辑并排、历史通栏在下', (tester) async {
    await _pumpPage(tester, _Harness(), surface: const Size(800, 1800));

    Rect rectOf(String key) =>
        tester.getRect(find.byKey(ValueKey<String>(key)));

    final profile = rectOf('account-profile');
    final vip = rectOf('account-vip');
    final grade = rectOf('account-grade');
    final albums = rectOf('account-albums');
    final history = rectOf('account-history');

    // 第一行：资料卡（左，较宽）+ 会员（右），顶部对齐、左右分开。
    expect((profile.top - vip.top).abs(), lessThan(0.5), reason: '资料卡与会员同一行');
    expect(profile.right, lessThan(vip.left), reason: '会员在资料卡右侧');
    expect(vip.left, greaterThan(0), reason: '会员未贴屏幕左边缘');
    expect(profile.width, greaterThan(vip.width), reason: '资料卡占较大份');

    // 第二行：听歌等级 + 已购专辑并排、顶部对齐，且在资料卡行下方。
    expect((grade.top - albums.top).abs(), lessThan(0.5), reason: '等级与专辑并排');
    expect(grade.right, lessThan(albums.left), reason: '专辑在等级右侧');
    expect(grade.top, greaterThanOrEqualTo(profile.bottom - 12));

    // 第三行：听歌历史通栏大卡片，位于等级卡片下方，左边界与资料卡对齐。
    expect(history.top, greaterThan(grade.top), reason: '历史在等级下方');
    expect(
      history.width,
      greaterThan(grade.width * 1.5),
      reason: '历史为通栏宽卡，明显宽于等级卡',
    );
    expect(
      (history.left - profile.left).abs(),
      lessThanOrEqualTo(2),
      reason: '历史左边界与资料卡对齐',
    );
  });

  testWidgets('窄屏走单列布局（无两栏 SingleChildScrollView）', (tester) async {
    await _pumpPage(tester, _Harness(), surface: const Size(400, 1200));

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byKey(const ValueKey('account-profile')), findsOneWidget);
    expect(find.text('示例昵称'), findsOneWidget);
  });
}
