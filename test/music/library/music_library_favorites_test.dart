// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
/// 「我的」页账号收藏测试：登录后内联云歌单「我喜欢」（is_def=2）曲目，
/// 本地收藏仍在下方；登录态变化自动重拉。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/pages/music_library_page.dart';

import '../pages/account/fakes.dart'
    show FakeUserLibraryApi, fakePlaylist, fakePlaylists;
import '../pages/playlist/fakes.dart' show FakePlaylistReadApi, testTrack;
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

  FakeUserLibraryApi libraryWithFavorites() => FakeUserLibraryApi()
    ..playlists = fakePlaylists(
      items: <MusicUserPlaylist>[
        fakePlaylist(
          cloudListId: 2,
          title: '我喜欢',
          defaultKind: 2,
          songCount: 2,
        ),
      ],
    );

  testWidgets('登录后收藏段内联账号「我喜欢」曲目，并可加载更多', (tester) async {
    final library = libraryWithFavorites();
    final read = FakePlaylistReadApi()
      ..trackAllNewPages = <List<MusicPlaylistTrack>>[
        <MusicPlaylistTrack>[testTrack(id: 'f1', title: '账号收藏一')],
        <MusicPlaylistTrack>[testTrack(id: 'f2', title: '账号收藏二')],
      ];

    await tester.pumpWidget(
      _app(
        MusicLibraryPage(
          collect: env.collect,
          history: env.history,
          userLibrary: library,
          playlistRead: read,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 账号「我喜欢」优先展示，且 listid 来自 is_def=2 而不是默认收藏(1)。
    expect(find.text('账号收藏 · 我喜欢'), findsOneWidget);
    expect(find.text('账号收藏一'), findsOneWidget);
    expect(read.trackAllNewQueries.single.cloudListId, 2);
    expect(read.trackAllNewQueries.single.page, 1);

    // 第二页：加载更多带 page 2。
    await tester.tap(find.byKey(const Key('library-favorites-more')));
    await tester.pumpAndSettle();
    expect(find.text('账号收藏二'), findsOneWidget);
    expect(read.trackAllNewQueries.last.page, 2);
  });

  testWidgets('本地收藏仍在账号收藏下方显示', (tester) async {
    await env.collect.collectRef(
      const MusicRef(id: 'local1'),
      title: '本地收藏一',
      song: testSong(id: 'local1', title: '本地收藏一'),
      collectedAt: DateTime(2026, 11, 1),
    );
    final library = libraryWithFavorites();
    final read = FakePlaylistReadApi()
      ..trackAllNewPages = <List<MusicPlaylistTrack>>[
        <MusicPlaylistTrack>[testTrack(id: 'f1', title: '账号收藏一')],
      ];

    await tester.pumpWidget(
      _app(
        MusicLibraryPage(
          collect: env.collect,
          history: env.history,
          userLibrary: library,
          playlistRead: read,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账号收藏一'), findsOneWidget);
    expect(find.text('本地收藏'), findsOneWidget);
    expect(find.text('本地收藏一'), findsOneWidget);
  });

  testWidgets('未登录（authentication）时给登录提示，登录事件后自动重拉', (tester) async {
    final epoch = ValueNotifier<int>(0);
    final library = libraryWithFavorites();
    final read = FakePlaylistReadApi()
      ..trackAllNewError = const KugouApiException('authentication', '未登录');
    final page = MusicLibraryPage(
      collect: env.collect,
      history: env.history,
      userLibrary: library,
      playlistRead: read,
      authEpoch: epoch,
    );

    await tester.pumpWidget(_app(page));
    await tester.pumpAndSettle();

    expect(find.text('登录酷狗账号后同步「我喜欢」'), findsOneWidget);
    final callsBefore = read.trackAllNewQueries.length;

    // 登录成功：错误态被自动重拉覆盖，不需要手动重试。
    read.trackAllNewError = null;
    read.trackAllNewPages = <List<MusicPlaylistTrack>>[
      <MusicPlaylistTrack>[testTrack(id: 'f1', title: '账号收藏一')],
    ];
    epoch.value += 1;
    await tester.pumpAndSettle();

    expect(read.trackAllNewQueries.length, greaterThan(callsBefore));
    expect(find.text('账号收藏一'), findsOneWidget);
    expect(find.text('登录酷狗账号后同步「我喜欢」'), findsNothing);
  });
}
