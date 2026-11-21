// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 发现页 widget 测试（U1 改版）：不联网、不碰真实计时器。
///
/// 「发现」tab 改为「入口网格 + 每日推荐长条」后覆盖：
/// 1. 入口网格渲染（排行榜仅接线时显示），点击导航/回调；
/// 2. 每日推荐长条渲染、点歌播放、失败独立重试、空数据隐藏、下拉刷新重取；
/// 3. 旧的内联默认词/热搜/首页发现/风格/AI/FM section 不再出现在发现 tab，
///    内容收进各自入口页（入口页自身在各自测试文件覆盖）；
/// 4. 搜索六 tab：点歌播放、专辑/歌手/歌单行回调、歌词候选流程、
///    建议/历史（原有断言不变）；
/// 5. 音效商城入口（接线显示+回调 / 未接线隐藏）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_discovery_page.dart';

import 'fakes.dart';

Widget _host(Widget page) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF4A6CF7),
    brightness: Brightness.light,
  ),
  home: page,
);

/// 一套注入桩 + 打开详情页的记录。
class _Fixture {
  _Fixture({
    FakeSearchExtApi? searchExt,
    FakeDiscoveryApi? discovery,
    this.lyric,
    this.collect,
    this.history,
    this.wireEffects = false,
    this.wireRank = true,
    this.authEpoch,
  }) : searchExt = searchExt ?? FakeSearchExtApi(),
       discovery = discovery ?? FakeDiscoveryApi(),
       player = FakePlayerUi() {
    store = MusicStore(FakeMusicApi());
  }

  late final MusicStore store;
  final FakeSearchExtApi searchExt;
  final FakeDiscoveryApi discovery;
  final FakeLyricApi? lyric;
  final FakeCollectApi? collect;
  final FakeSearchHistoryApi? history;
  final FakePlayerUi player;

  /// 是否给页面接上「音效商城」入口；默认不接（入口隐藏）。
  final bool wireEffects;
  int openEffectsCalls = 0;

  /// 是否接上「排行榜」回调；默认接线（入口网格显示排行榜入口）。
  final bool wireRank;
  int openRankCalls = 0;

  /// 登录态信号；非空时转发给私人 FM 长条页。
  final ValueNotifier<int>? authEpoch;

  final List<int> openedAlbums = <int>[];
  final List<int> openedArtists = <int>[];
  final List<String> openedPlaylists = <String>[];

  Widget get page => MusicDiscoveryPage(
    searchExt: searchExt,
    discovery: discovery,
    store: store,
    player: player,
    lyric: lyric,
    collect: collect,
    searchHistory: history,
    authEpoch: authEpoch,
    onOpenAlbum: openedAlbums.add,
    onOpenArtist: openedArtists.add,
    onOpenPlaylist: openedPlaylists.add,
    onOpenRank: wireRank ? () => openRankCalls++ : null,
    onOpenEffects: wireEffects ? () => openEffectsCalls++ : null,
  );
}

/// 首帧装载：pumpWidget + 一次 pump（异步 sections 装载完成）。
///
/// 视口加高而不是加宽：发现 tab 现在有入口网格，默认 800×600 会把每日推荐
/// 挤出 ListView 的构建窗口（懒构建 → find 找不到、tap 落空）；保持 800 宽
/// 不影响两列/单列断点断言。
Future<_Fixture> _pumpPage(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(_host(fixture.page));
  await tester.pump();
  return fixture;
}

/// 在搜索框输入并点放大镜提交。
Future<void> _submitSearch(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(TextField), keyword);
  await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
}

/// 等搜索/切 tab 的动画与异步装载都结束。
///
/// 注意先 pump 一次空帧：tap 后 ticker 的首帧 elapsed=0（动画从当前时刻起
/// 步），直接 pump(600ms) 会被当成「第一帧」吃掉，动画停在 0 处不推进。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// 等页面 push/pop 路由动画结束。
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  // ── 发现 tab：入口网格 + 每日推荐长条 ──────────────────────────────────

  testWidgets('发现 tab 改版：入口网格渲染，旧内联 section 移除', (tester) async {
    await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          promotions: <MusicSearchPromotion>[fakePromotion(title: '默认词A')],
          hotGroups: <MusicHotSearchGroup>[fakeHotGroup()],
        ),
        discovery: FakeDiscoveryApi(
          homeItems: <MusicDiscoverItem>[
            fakeHomeItem(id: '10', hash: 'd10', title: '发现之歌A'),
          ],
          dailySongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '20', hash: 'd20', title: '每日之歌A'),
          ],
          aiSongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '30', hash: 'ai30', title: 'AI之歌A'),
          ],
          fmBatches: <List<MusicPersonalFmSong>>[
            <MusicPersonalFmSong>[
              fakeFmSong(id: '40', hash: 'fm40', title: 'FM之歌A'),
            ],
          ],
          styleBatches: <MusicStyleRecommendations>[
            fakeStyleRecommendations(
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(id: '50', hash: 'st50', title: '风格之歌A'),
              ],
            ),
          ],
        ),
      ),
    );

    // 入口网格：六个入口（默认接线排行榜）。
    expect(find.byKey(const Key('discover-entry-grid')), findsOneWidget);
    expect(find.text('首页发现'), findsOneWidget);
    expect(find.text('风格推荐'), findsOneWidget);
    expect(find.text('AI 免费畅听'), findsOneWidget);
    expect(find.text('私人 FM'), findsOneWidget);
    expect(find.text('热门搜索'), findsOneWidget);
    expect(find.text('排行榜'), findsOneWidget);

    // 旧内联 section 移除：默认词/热搜/首页发现/AI/FM/风格内容不在发现 tab。
    expect(find.text('默认词A'), findsNothing);
    expect(find.text('飙升榜'), findsNothing);
    expect(find.text('热词B'), findsNothing);
    expect(find.text('发现之歌A'), findsNothing);
    expect(find.text('AI之歌A'), findsNothing);
    expect(find.text('FM之歌A'), findsNothing);
    expect(find.text('风格之歌A'), findsNothing);

    // 每日推荐仍内联，长条行渲染。
    expect(find.text('每日推荐'), findsOneWidget);
    expect(find.text('每日之歌A'), findsOneWidget);
  });

  testWidgets('每日推荐长条：歌名/歌手/时长渲染，点歌播放并打开播放页', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          dailySongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '20', hash: 'd20', title: '每日之歌A'),
            fakeDiscoverySong(id: '21', hash: 'd21', title: '每日之歌B'),
          ],
        ),
      ),
    );

    expect(find.text('每日之歌A'), findsOneWidget);
    expect(find.text('每日之歌B'), findsOneWidget);
    expect(find.text('推荐歌手'), findsNWidgets(2));
    // fakeDiscoverySong durationMs 200000 → 3:20；行尾有播放图标。
    expect(find.text('3:20'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(2));

    await tester.tap(find.text('每日之歌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fixture.player.played, hasLength(1));
    expect(fixture.player.played.single.id, '20');
    expect(find.text('播放页占位'), findsOneWidget);
  });

  testWidgets('每日推荐失败：独立错误与重试，入口网格不受影响', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          dailySongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '20', hash: 'd20', title: '每日之歌A'),
          ],
          dailyFailuresLeft: 1,
        ),
      ),
    );

    expect(find.textContaining('每日推荐挂了'), findsOneWidget);
    final dailyRetry = find.descendant(
      of: find.byKey(const Key('discover-daily')),
      matching: find.text('重试'),
    );
    expect(dailyRetry, findsOneWidget);
    expect(find.byKey(const Key('discover-entry-grid')), findsOneWidget);

    await tester.tap(dailyRetry);
    await tester.pump();
    await tester.pump();

    expect(find.text('每日之歌A'), findsOneWidget);
    expect(fixture.discovery.dailyCalls, 2);
  });

  testWidgets('每日推荐空数据：整段隐藏', (tester) async {
    await _pumpPage(tester, _Fixture());
    expect(find.text('每日推荐'), findsNothing);
    expect(find.byKey(const Key('discover-daily')), findsNothing);
  });

  testWidgets('下拉刷新重取每日推荐', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          dailySongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '20', hash: 'd20', title: '每日之歌A'),
          ],
        ),
      ),
    );
    expect(fixture.discovery.dailyCalls, 1);

    // 触发 RefreshIndicator 的 onRefresh（下拉手势在测试视口里容易落空；
    // show() 走的是同一条 onRefresh 链路，断言目标仍是「刷新重取」）。
    // show() 的 Future 要等指示器动画回弹才完成，必须先 pump 再 await，
    // 否则动画没有帧驱动会一直挂住。
    final indicator = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    final refresh = indicator.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await refresh;

    expect(fixture.discovery.dailyCalls, 2);
    expect(find.text('每日之歌A'), findsOneWidget);
  });

  testWidgets('排行榜入口：仅接线时显示，点击回调', (tester) async {
    final fixture = await _pumpPage(tester, _Fixture());
    expect(find.byKey(const Key('discover-entry-rank')), findsOneWidget);

    await tester.tap(find.byKey(const Key('discover-entry-rank')));
    await tester.pump();
    expect(fixture.openRankCalls, 1);

    // 未接线（onOpenRank == null）时入口不显示。
    await _pumpPage(tester, _Fixture(wireRank: false));
    expect(find.byKey(const Key('discover-entry-rank')), findsNothing);
    expect(find.text('排行榜'), findsNothing);
  });

  testWidgets('首页发现入口推入长条列表页，点歌播放', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          homeItems: <MusicDiscoverItem>[
            fakeHomeItem(id: '10', hash: 'd10', title: '发现之歌A'),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('discover-entry-home')));
    await _settleRoute(tester);

    // 入口页：AppBar 标题 + 长条行（歌名/歌手/时长）。
    expect(find.text('发现之歌A'), findsOneWidget);
    expect(find.text('推荐歌手'), findsOneWidget);
    expect(find.text('3:20'), findsOneWidget);

    await tester.tap(find.text('发现之歌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.player.played, hasLength(1));
    expect(fixture.player.played.single.id, '10');
    expect(find.text('播放页占位'), findsOneWidget);
  });

  testWidgets('AI 免费畅听与私人 FM 入口推入长条列表页', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          aiSongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '30', hash: 'ai30', title: 'AI之歌A'),
          ],
          fmBatches: <List<MusicPersonalFmSong>>[
            <MusicPersonalFmSong>[
              fakeFmSong(id: '40', hash: 'fm40', title: 'FM之歌A'),
            ],
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('discover-entry-ai')));
    await _settleRoute(tester);
    expect(find.text('AI之歌A'), findsOneWidget);

    // 返回发现 tab，再进私人 FM。
    await tester.pageBack();
    await _settleRoute(tester);

    await tester.tap(find.byKey(const Key('discover-entry-fm')));
    await _settleRoute(tester);
    expect(find.text('FM之歌A'), findsOneWidget);
    expect(fixture.discovery.fmCalls, 1);
  });

  testWidgets('登录态变化后私人 FM 长条页自动重拉（authEpoch 转发）', (tester) async {
    final epoch = ValueNotifier<int>(0);
    final fixture = _Fixture(
      discovery: FakeDiscoveryApi(
        fmBatches: <List<MusicPersonalFmSong>>[
          <MusicPersonalFmSong>[
            fakeFmSong(id: '40', hash: 'fm40', title: 'FM之歌A'),
          ],
          <MusicPersonalFmSong>[
            fakeFmSong(id: '41', hash: 'fm41', title: 'FM之歌B'),
          ],
        ],
      ),
      authEpoch: epoch,
    );
    await _pumpPage(tester, fixture);
    // 发现 tab 不再预载私人 FM（内容在入口页），点进去才请求。
    expect(fixture.discovery.fmCalls, 0);

    await tester.tap(find.byKey(const Key('discover-entry-fm')));
    await _settleRoute(tester);
    expect(find.text('FM之歌A'), findsOneWidget);
    expect(fixture.discovery.fmCalls, 1);

    // 模拟登录成功：FM 长条页自动重取第二批，用户不必点换一批。
    epoch.value += 1;
    await tester.pump();
    await tester.pump();

    expect(fixture.discovery.fmCalls, 2);
    expect(find.text('FM之歌B'), findsOneWidget);
  });

  testWidgets('热门搜索入口：点词触发搜索并返回发现页', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          promotions: <MusicSearchPromotion>[fakePromotion(title: '默认词A')],
          hotGroups: <MusicHotSearchGroup>[fakeHotGroup()],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('discover-entry-hot')));
    await _settleRoute(tester);

    expect(find.text('默认词A'), findsOneWidget);
    expect(find.text('飙升榜'), findsOneWidget);
    expect(find.text('热词B'), findsOneWidget);

    // 点词：onSearch → 发现页提交 → 页面 pop 返回。
    await tester.tap(find.text('默认词A'));
    await _settleRoute(tester);

    expect(fixture.store.lastKeyword, '默认词A');
    expect(find.text('默认词A 之一'), findsOneWidget);
    expect(find.text('默认词A 之二'), findsOneWidget);
    expect(find.text('默认搜索词'), findsNothing);
  });

  // ── 音效商城入口 ───────────────────────────────────────────────────────

  testWidgets('音效商城入口：接线后展示入口卡，点击触发回调', (tester) async {
    final fixture = await _pumpPage(tester, _Fixture(wireEffects: true));

    expect(find.byKey(const Key('discover-effects-entry')), findsOneWidget);
    expect(find.text('音效商城'), findsOneWidget);
    expect(find.text('耳机品牌 / 设备匹配'), findsOneWidget);

    await tester.tap(find.text('音效商城'));
    await tester.pump();
    expect(fixture.openEffectsCalls, 1);
  });

  testWidgets('音效商城入口：未接线（onOpenEffects 为 null）时隐藏', (tester) async {
    await _pumpPage(tester, _Fixture());
    expect(find.byKey(const Key('discover-effects-entry')), findsNothing);
    expect(find.text('音效商城'), findsNothing);
  });

  // ── 搜索六 tab（原有断言不变） ──────────────────────────────────────────

  testWidgets('搜索结果点歌：playSong 被调用并 push 播放页占位', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(collect: FakeCollectApi(initialIds: <String>{'101'})),
    );

    await _submitSearch(tester, '晴天');
    await _settle(tester);

    expect(fixture.store.lastKeyword, '晴天');
    // collect 已接线：已收藏的 101 显示实底心，未收藏的 102 显示描边心。
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(fixture.player.played, isEmpty);

    await tester.tap(find.text('晴天 之一'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fixture.player.played, hasLength(1));
    expect(fixture.player.played.first.id, '101');
    expect(find.text('播放页占位'), findsOneWidget);
  });

  testWidgets('专辑/歌手/歌单行点击回调拿到正确 id', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          albums: <MusicAlbumSummary>[fakeAlbum(id: 42)],
          artists: <MusicArtistSummary>[fakeArtist(id: 7)],
          playlists: <MusicPlaylistSummary>[fakePlaylist(globalId: 'global-1')],
        ),
      ),
    );

    await _submitSearch(tester, '关键词');
    await _settle(tester);

    await tester.tap(find.text('专辑'));
    await _settle(tester);
    await tester.tap(find.text('测试专辑'));
    await tester.pump();
    expect(fixture.openedAlbums, <int>[42]);

    await tester.tap(find.text('歌手'));
    await _settle(tester);
    await tester.tap(find.text('测试歌手'));
    await tester.pump();
    expect(fixture.openedArtists, <int>[7]);

    await tester.tap(find.text('歌单'));
    await _settle(tester);
    await tester.tap(find.text('测试歌单'));
    await tester.pump();
    expect(fixture.openedPlaylists, <String>['global-1']);
  });

  testWidgets('歌词命中 → 候选 sheet → downloadLyric → 弹出解码文本', (tester) async {
    final lyricApi = FakeLyricApi(base64Lyric('[00:01.00] 歌词正文第一行'));
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          lyricHits: <MusicLyricHit>[fakeLyricHit()],
          lyricCandidates: <MusicLyricCandidate>[fakeCandidate()],
        ),
        lyric: lyricApi,
      ),
    );

    await _submitSearch(tester, '歌词歌');
    await _settle(tester);
    await tester.tap(find.text('歌词'));
    await _settle(tester);

    // 命中行点击：按歌曲 hash 拉候选（标题 =「歌名 - 歌手」精确匹配）。
    await tester.tap(find.text('歌词歌 - 歌词歌手'));
    await tester.pumpAndSettle();

    expect(find.textContaining('歌词候选'), findsOneWidget);
    final query = fixture.searchExt.lastLyricQuery;
    expect(query, isNotNull);
    expect(query!.hash, 'hash77');
    expect(query.songId, 77);
    expect(query.allCandidates, isTrue);

    // 候选点击：downloadLyric(id/accesskey) → base64 → UTF-8 文本弹窗。
    await tester.tap(find.textContaining('候选歌'));
    await tester.pumpAndSettle();

    expect(lyricApi.queries, hasLength(1));
    expect(lyricApi.queries.single.id, 'cid');
    expect(lyricApi.queries.single.accesskey, 'ak');
    expect(find.textContaining('歌词正文'), findsOneWidget);
  });

  testWidgets('歌词解码失败显示「歌词格式不支持」', (tester) async {
    final lyricApi = FakeLyricApi('###不是base64###', format: 'krc');
    await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          lyricHits: <MusicLyricHit>[fakeLyricHit()],
          lyricCandidates: <MusicLyricCandidate>[fakeCandidate()],
        ),
        lyric: lyricApi,
      ),
    );

    await _submitSearch(tester, '歌词歌');
    await _settle(tester);
    await tester.tap(find.text('歌词'));
    await _settle(tester);
    await tester.tap(find.text('歌词歌 - 歌词歌手'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('候选歌'));
    await tester.pumpAndSettle();

    expect(find.text('歌词格式不支持'), findsOneWidget);
  });

  testWidgets('搜索历史：未搜索时展示历史词，点击/提交都写入历史', (tester) async {
    final history = FakeSearchHistoryApi(initial: <String>['老关键词']);
    final fixture = await _pumpPage(tester, _Fixture(history: history));

    // 切到「歌曲」tab：未搜索落位展示历史词 chips。
    await tester.tap(find.text('歌曲'));
    await _settle(tester);
    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('老关键词'), findsOneWidget);

    await tester.tap(find.text('老关键词'));
    await _settle(tester);

    expect(fixture.store.lastKeyword, '老关键词');
    expect(history.words.last, '老关键词');
    expect(history.words.length, 2, reason: '点击历史词后再次 record');
  });

  testWidgets('搜索建议：输入防抖拉取，点击建议触发搜索', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          suggestionGroups: <MusicSuggestionGroup>[fakeSuggestionGroup()],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '周');
    // 防抖 400ms：时钟推进后建议 chip 才出现。
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.text('周杰伦'), findsOneWidget);

    await tester.tap(find.text('周杰伦'));
    await _settle(tester);

    expect(fixture.store.lastKeyword, '周杰伦');
    expect(find.text('周杰伦 之一'), findsOneWidget);
    // 提交后建议条收回：剩下的「周杰伦」只有搜索框里的输入文本。
    expect(find.text('周杰伦'), findsOneWidget);
  });
}
