// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 通用长条歌曲列表页 widget 测试：不联网、不碰真实计时器。
///
/// 覆盖：首载长条渲染与点歌播放、错误态重试恢复、空列表空态、
/// refreshLabel 刷新按钮（私人 FM「换一批」重拉下一批）、
/// 未给 refreshLabel 时无刷新按钮、authEpoch 登录态变化自动重拉。
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

/// 可控的 loader：失败计数 + 批次队列（每次调用推进一批，越界停在最后一批）。
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
    // fakeSong durationMs 181000 → 3:01；行尾播放图标。
    expect(find.text('3:01'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(2));

    await tester.tap(find.text('列表之歌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

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

  testWidgets('refreshLabel 刷新按钮：重拉下一批（FM 换一批）', (tester) async {
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

  testWidgets('authEpoch 变化自动重拉（登录/切号）', (tester) async {
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

    // 模拟登录成功：无需手动重试即自动重取第二批。
    epoch.value += 1;
    await tester.pump();
    await tester.pump();

    expect(loader.calls, 2);
    expect(find.text('FM之歌B'), findsOneWidget);
  });
}
