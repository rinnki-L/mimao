// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 账号中心登录态刷新测试：登录/切号事件（authEpoch 递增）后整页自动重拉，
/// 不需要用户手动点「重试」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/models/user_models.dart';
import 'package:mimao/music/pages/music_account_center_page.dart';

import 'fakes.dart';

void main() {
  testWidgets('authEpoch 递增后资料/会员/等级/歌单自动重拉', (tester) async {
    final profile = FakeUserProfileApi()
      ..detail = fakeProfile()
      ..tags = fakeTags()
      ..vip = fakeVip(
        products: <MusicUserVipMembershipProduct>[fakeVipProduct()],
      )
      ..grade = fakeGrade();
    final library = FakeUserLibraryApi()
      ..playlists = fakePlaylists(
        items: <MusicUserPlaylist>[fakePlaylist(title: '我的歌单')],
      );
    // 历史/已购分区刷新时也会被重拉：各准备两页，避免刷新时 fake 抛未配置。
    for (var i = 0; i < 2; i++) {
      library.historyPages.add(
        fakeHistoryPage(items: <MusicHistoryItem>[fakeHistoryItem()]),
      );
      library.purchasedAlbumPages.add(
        MusicPage<MusicPurchasedAlbum>(
          page: 1,
          pageSize: 20,
          total: 0,
          items: const <MusicPurchasedAlbum>[],
        ),
      );
      library.purchasedSongPages.add(
        MusicPage<MusicPurchasedSong>(
          page: 1,
          pageSize: 20,
          total: 0,
          items: const <MusicPurchasedSong>[],
        ),
      );
    }
    final epoch = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: MusicAccountCenterPage(
          profile: profile,
          library: library,
          player: FakePlayerUi(),
          authEpoch: epoch,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(profile.detailCalls, 1);
    expect(profile.vipCalls, 1);
    expect(library.playlistQueries.length, 1);

    // 模拟登录成功：页面应自动重拉，而不是停在匿名时的错误态。
    epoch.value += 1;
    await tester.pump();
    await tester.pump();

    expect(profile.detailCalls, 2);
    expect(profile.vipCalls, 2);
    expect(profile.gradeCalls, 2);
    expect(library.playlistQueries.length, 2);
  });
}
