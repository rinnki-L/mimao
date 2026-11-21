// ignore_for_file: deprecated_member_use — 与音乐模块页测试同款说明。
// 验收 C12/C15：搜索页收藏图标（接口驱动）与搜索历史落库。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_module_page.dart';

import 'music_test_env.dart';

class _FakeApi implements MusicApi {
  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async => MusicPage<MusicSong>(
    page: 1,
    total: 1,
    items: <MusicSong>[testSong(title: '$keyword 之一')],
  );

  @override
  Future<KugouIdentity> ensureDevice() async => KugouIdentity.anonymous();

  @override
  Future<KugouIdentity?> currentIdentity() async => null;
}

Widget _page(MusicTestEnv env) => MaterialApp(
  home: MusicModulePage(
    store: MusicStore(_FakeApi()),
    embedded: true,
    collect: env.collect,
    searchHistory: env.searchHistory,
  ),
);

void main() {
  late MusicTestEnv env;

  setUp(() {
    env = MusicTestEnv.create();
  });

  tearDown(() => env.close());

  testWidgets('C12 搜索列表出现收藏图标：点击后切换且内部库有行', (tester) async {
    await tester.pumpWidget(_page(env));
    await tester.enterText(find.byType(TextField), '稻香');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('收藏'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏'));
    // 行内收藏按钮与整行双击共用祖先手势，单击在双击判定超时后触发。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(await env.collect.isCollected('7301'), isTrue);
    expect(await env.musicDb.collectRow(musicRefOf(testSong())), isNotNull);
    expect((await env.library.timeline()).single.starred, isTrue);

    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(await env.collect.isCollected('7301'), isFalse);
  });

  testWidgets('C15 搜索提交后 search_history 落库', (tester) async {
    await tester.pumpWidget(_page(env));
    await tester.enterText(find.byType(TextField), '  周杰伦  ');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(await env.searchHistory.recent(), <String>['周杰伦']);
  });
}
