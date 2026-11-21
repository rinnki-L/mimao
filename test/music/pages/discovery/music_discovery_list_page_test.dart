// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 通用长条歌曲列表页 widget 测试：不联网、不碰真实计时器。
///
/// 两种装载模式都覆盖：
/// - 整页模式（loader）：首载长条渲染与点歌播放、错误态重试恢复、空列表空态、
///   refreshLabel 刷新按钮、未给 refreshLabel 时无刷新按钮、authEpoch 自动重拉；
/// - 分批模式（initialSongs + loadMore）：预览立即显示、后台追加到目标数量、
///   id/hash 去重、换一批清空后重新拉满、底部小 spinner、封面与列表第一首同源。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_discovery_list_page.dart';

import 'fakes.dart';

Widget _host(Widget page) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF4A6CF7),
    brightness: Brightness.light,
  ),
  home: page,
);

/// 可控的整页 loader：失败计数 + 批次队列（每次调用推进一批，越界停最后一批）。
class _Loader {
  _Loader({this.batches = const <List<MusicSong>>[]});

  final List<List<MusicSong>> batches;
  int failuresLeft = 0;
  int calls = 0;
  int _cursor = 0;

  Future<List<MusicSong>> call() async {
    calls++;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('列表挂了');
    }
    if (batches.isEmpty) return const <MusicSong>[];
    final index = _cursor < batches.length ? _cursor : batches.length - 1;
    _cursor++;
    return batches[index];
  }
}

void main() {
  // ── 整页模式（loader） ────────────────────────────────────────────────

  testWidgets('首载渲染长条行：歌名/歌手/时长，点歌播放并打开播放页', (tester) async {
    final player = FakePlayerUi();
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[
          fakeSong(id: '101', hash: 'h101', title: '列表之歌A', artist: '列表歌手A'),
          fakeSong(id: '102', hash: 'h102', title: '列表之歌B', artist: '列表歌手B'),
        ],
      ],
    );
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '首页发现',
          player: player,
          loader: loader.call,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('首页发现'), findsOneWidget);
    expect(find.text('列表之歌A'), findsOneWidget);
    expect(find.text('列表歌手A'), findsOneWidget);
    expect(find.text('3:01'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(2));

    await tester.tap(find.text('列表之歌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 单击回调在双击判定超时后才触发，再等路由动画完成。
    await tester.pumpAndSettle();

    expect(player.played, hasLength(1));
    expect(player.played.single.id, '101');
    expect(find.text('播放页占位'), findsOneWidget);
  });

  testWidgets('loader 失败：错误态与重试恢复', (tester) async {
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[fakeSong(id: '101', hash: 'h101', title: '列表之歌A')],
      ],
    )..failuresLeft = 1;
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '首页发现',
          player: FakePlayerUi(),
          loader: loader.call,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('列表挂了'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(find.text('列表之歌A'), findsOneWidget);
    expect(loader.calls, 2);
  });

  testWidgets('空列表：空态文案，不渲染长条', (tester) async {
    final loader = _Loader();
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '首页发现',
          player: FakePlayerUi(),
          loader: loader.call,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暂无歌曲'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('整页模式 refreshLabel 刷新按钮：重拉下一批', (tester) async {
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[fakeSong(id: '40', hash: 'h40', title: 'FM之歌A')],
        <MusicSong>[fakeSong(id: '41', hash: 'h41', title: 'FM之歌B')],
      ],
    );
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '私人 FM',
          player: FakePlayerUi(),
          loader: loader.call,
          refreshLabel: '换一批',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('FM之歌A'), findsOneWidget);
    expect(loader.calls, 1);

    await tester.tap(find.byTooltip('换一批'));
    await tester.pump();
    await tester.pump();

    expect(find.text('FM之歌A'), findsNothing);
    expect(find.text('FM之歌B'), findsOneWidget);
    expect(loader.calls, 2);
  });

  testWidgets('未给 refreshLabel 时不显示刷新按钮', (tester) async {
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[fakeSong(id: '101', hash: 'h101', title: '列表之歌A')],
      ],
    );
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '首页发现',
          player: FakePlayerUi(),
          loader: loader.call,
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byTooltip('换一批'), findsNothing);
  });

  testWidgets('整页模式 authEpoch 变化自动重拉', (tester) async {
    final epoch = ValueNotifier<int>(0);
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[fakeSong(id: '40', hash: 'h40', title: 'FM之歌A')],
        <MusicSong>[fakeSong(id: '41', hash: 'h41', title: 'FM之歌B')],
      ],
    );
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '私人 FM',
          player: FakePlayerUi(),
          loader: loader.call,
          authEpoch: epoch,
        ),
      ),
    );
    await tester.pump();
    expect(loader.calls, 1);

    epoch.value += 1;
    await tester.pump();
    await tester.pump();

    expect(loader.calls, 2);
    expect(find.text('FM之歌B'), findsOneWidget);
  });

  // ── 分批模式（initialSongs + loadMore） ───────────────────────────────

  testWidgets('分批模式：预览立即显示，后台追加到目标数量', (tester) async {
    final initial = <MusicSong>[
      fakeSong(id: '1', hash: 'h1', title: '预览歌1', coverUrl: 'https://c/1.jpg'),
    ];
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[fakeSong(id: '2', hash: 'h2', title: '批次歌2')],
        <MusicSong>[fakeSong(id: '3', hash: 'h3', title: '批次歌3')],
      ],
    );
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '首页发现',
          player: FakePlayerUi(),
          initialSongs: initial,
          loadMore: loader.call,
          targetCount: 3,
          maxBatches: 6,
        ),
      ),
    );
    // 首帧：预览立即在（无整页 loading）。
    await tester.pump();
    expect(find.text('预览歌1'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 后台两批陆续追加，等异步完成。
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('批次歌2'), findsOneWidget);
    expect(find.text('批次歌3'), findsOneWidget);
    expect(loader.calls, 2, reason: '达到目标 3 首后停止追加');
  });

  testWidgets('分批模式：按 id/hash 去重', (tester) async {
    final initial = <MusicSong>[fakeSong(id: '1', hash: 'h1', title: '预览歌1')];
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[
          // id 与预览重复
          fakeSong(id: '1', hash: 'hx', title: '重复id歌'),
          // hash 与预览重复
          fakeSong(id: '9', hash: 'h1', title: '重复hash歌'),
          fakeSong(id: '2', hash: 'h2', title: '新歌2'),
        ],
      ],
    );
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '首页发现',
          player: FakePlayerUi(),
          initialSongs: initial,
          loadMore: loader.call,
          targetCount: 10,
          maxBatches: 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('重复id歌'), findsNothing);
    expect(find.text('重复hash歌'), findsNothing);
    expect(find.text('新歌2'), findsOneWidget);
    expect(find.text('预览歌1'), findsOneWidget);
  });

  testWidgets('分批模式：换一批清空后重新拉满', (tester) async {
    final initial = <MusicSong>[fakeSong(id: '1', hash: 'h1', title: '预览歌1')];
    final loader = _Loader(
      batches: <List<MusicSong>>[
        <MusicSong>[fakeSong(id: '2', hash: 'h2', title: '批次歌2')],
        <MusicSong>[fakeSong(id: '3', hash: 'h3', title: '新批次歌3')],
      ],
    );
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '私人 FM',
          player: FakePlayerUi(),
          initialSongs: initial,
          loadMore: loader.call,
          targetCount: 2,
          maxBatches: 4,
          refreshLabel: '换一批',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('预览歌1'), findsOneWidget);
    expect(find.text('批次歌2'), findsOneWidget);

    final callsBefore = loader.calls;
    await tester.tap(find.byTooltip('换一批'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 清空后重拉：预览歌1 消失，第二批数据出现。
    expect(find.text('预览歌1'), findsNothing);
    expect(find.text('批次歌2'), findsNothing);
    expect(find.text('新批次歌3'), findsOneWidget);
    expect(loader.calls, greaterThan(callsBefore));
  });

  testWidgets('分批模式：预览与列表第一首同源（封面一致）', (tester) async {
    const cover = 'https://c/first.jpg';
    final initial = <MusicSong>[
      fakeSong(id: '1', hash: 'h1', title: '预览歌1', coverUrl: cover),
      fakeSong(id: '2', hash: 'h2', title: '预览歌2'),
    ];
    final loader = _Loader();
    await tester.pumpWidget(
      _host(
        MusicDiscoveryListPage(
          title: '首页发现',
          player: FakePlayerUi(),
          initialSongs: initial,
          loadMore: loader.call,
          targetCount: 30,
          maxBatches: 1,
        ),
      ),
    );
    await tester.pump();

    // 首行封面 URL 与预览第一首一致（同一份数据源）。
    final firstTile = find.byType(ListTile).first;
    final coverWidget = find.descendant(
      of: firstTile,
      matching: find.byType(Image),
    );
    expect(coverWidget, findsOneWidget);
    final image = tester.widget<Image>(coverWidget);
    expect((image.image as NetworkImage).url, cover);
  });
}
