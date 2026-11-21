// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 发现页 widget 测试（取消搜索分类 Tab 后）：不联网、不碰真实计时器。
///
/// 覆盖：
/// 1. 页面骨架：只有 AppBar + SearchBar + 入口网格 + 每日推荐，五 tab / 歌词 /
///    音效入口不再存在；
/// 2. 入口区两排布局（上排两个无封面长条各占一半、下排四个封面卡拉开间距、
///    两排左右边界对齐），入口渲染（排行榜仅接线时显示）、点击导航/回调；
/// 3. 4 个内容入口封面预取：cover Key 出现、接口在页面加载时被调用、FM 失败
///    静默无封面；authEpoch 变化只重取 FM 预览；
/// 4. 每日推荐长条渲染、点歌播放、失败独立重试、空数据隐藏、下拉刷新重取；
/// 5. 搜索提交 / 建议词 / 热搜页点词统一 push 搜索页（搜索页自身行为在
///    music_discovery_search_page_test.dart 覆盖）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
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
  final FakePlayerUi player;

  /// 是否接上「排行榜」回调；默认接线（入口网格显示排行榜入口）。
  final bool wireRank;
  int openRankCalls = 0;

  /// 登录态信号；非空时转发给私人 FM 长条页。
  final ValueNotifier<int>? authEpoch;

  Widget get page => MusicDiscoveryPage(
    searchExt: searchExt,
    discovery: discovery,
    store: store,
    player: player,
    authEpoch: authEpoch,
    onOpenRank: wireRank ? () => openRankCalls++ : null,
  );
}

/// 首帧装载：pumpWidget + 一次 pump（异步预览/每日推荐装载完成）。
Future<_Fixture> _pumpPage(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(_host(fixture.page));
  await tester.pump();
  await tester.pump();
  return fixture;
}

/// 在搜索框输入并点箭头提交。
Future<void> _submitSearch(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(TextField), keyword);
  await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
}

/// 等路由 push/pop 动画结束。
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  // ── 骨架：入口网格 + 每日推荐，搜索分类 Tab 已取消 ─────────────────────

  testWidgets('发现页无分类 Tab / 歌词 / 音效入口，仅保留入口网格与每日推荐', (tester) async {
    await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          dailySongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '20', hash: 'd20', title: '每日之歌A'),
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

    // 五个分类 tab 消失。
    for (final tab in <String>['发现', '歌曲', '专辑', '歌手', '歌单', '歌词']) {
      expect(find.text(tab), findsNothing, reason: '$tab tab 应被删除');
    }
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);

    // 音效商城入口不存在。
    expect(find.byKey(const Key('discover-effects-entry')), findsNothing);
    expect(find.text('音效商城'), findsNothing);

    // 每日推荐仍内联，长条行渲染。
    expect(find.text('每日推荐'), findsOneWidget);
    expect(find.text('每日之歌A'), findsOneWidget);
  });

  // ── 入口区两排布局 ─────────────────────────────────────────────────────

  testWidgets('入口区两排布局：上排两个长条各半，下排四个封面卡拉开间距', (tester) async {
    await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          homeItems: <MusicDiscoverItem>[
            fakeHomeItem(
              id: '10',
              hash: 'd10',
              title: '首页之歌',
              coverUrl: 'https://img.example/home.jpg',
            ),
          ],
        ),
      ),
    );

    Rect rectOf(String key) => tester.getRect(find.byKey(Key(key)));

    final hot = rectOf('discover-entry-hot');
    final rank = rectOf('discover-entry-rank');
    final home = rectOf('discover-entry-home');
    final style = rectOf('discover-entry-style');
    final ai = rectOf('discover-entry-ai');
    final fm = rectOf('discover-entry-fm');

    // 上排：两个长条同一行、等宽（各占一半），中间留横向空隙。
    expect((hot.top - rank.top).abs(), lessThan(0.5), reason: '两个长条同一行');
    expect(
      (hot.width - rank.width).abs(),
      lessThanOrEqualTo(2),
      reason: '两个长条各占一半宽度',
    );
    expect(hot.right, lessThan(rank.left), reason: '长条之间有空隙');
    expect(rank.left - hot.right, greaterThanOrEqualTo(4));
    // 长条形态：横向明显比纵向长。
    expect(hot.width, greaterThan(hot.height * 2));
    expect(rank.width, greaterThan(rank.height * 2));

    // 下排：四个封面卡同一行，彼此间距明显拉开（>= 20）。
    for (final rect in <Rect>[style, ai, fm]) {
      expect((rect.top - home.top).abs(), lessThan(0.5), reason: '四个卡同一行');
      expect((rect.height - home.height).abs(), lessThanOrEqualTo(2));
    }
    expect(style.left - home.right, greaterThanOrEqualTo(20));
    expect(ai.left - style.right, greaterThanOrEqualTo(20));
    expect(fm.left - ai.right, greaterThanOrEqualTo(20));
    // 正方形：高宽相等（封面完整显示），间距拉大后等比例缩小。
    expect(
      (home.height - home.width).abs(),
      lessThanOrEqualTo(2),
      reason: '封面卡为正方形',
    );

    // 两排上下分开。
    expect(home.top, greaterThanOrEqualTo(hot.bottom + 8));

    // 两排左右边界对齐（都继承外层 ListView 的 16px 内边距），且离屏幕边缘有空隙。
    expect(hot.left, greaterThan(0));
    expect((home.left - hot.left).abs(), lessThanOrEqualTo(2));
    expect((fm.right - rank.right).abs(), lessThanOrEqualTo(2));
  });

  // ── 入口封面预取 ───────────────────────────────────────────────────────

  testWidgets('4 个内容入口封面预取：cover Key 出现，接口在页面加载时被调用', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          homeItems: <MusicDiscoverItem>[
            fakeHomeItem(
              id: '10',
              hash: 'd10',
              title: '首页之歌',
              coverUrl: 'https://img.example/home.jpg',
            ),
          ],
          aiSongs: <MusicDiscoverySong>[
            fakeDiscoverySong(
              id: '30',
              hash: 'ai30',
              title: 'AI之歌',
              coverUrl: 'https://img.example/ai.jpg',
            ),
          ],
          fmBatches: <List<MusicPersonalFmSong>>[
            <MusicPersonalFmSong>[
              fakeFmSong(
                id: '40',
                hash: 'fm40',
                title: 'FM之歌',
                coverUrl: 'https://img.example/fm.jpg',
              ),
            ],
          ],
          styleBatches: <MusicStyleRecommendations>[
            fakeStyleRecommendations(
              songs: <MusicDiscoverySong>[
                fakeDiscoverySong(
                  id: '50',
                  hash: 'st50',
                  title: '风格之歌',
                  coverUrl: 'https://img.example/style.jpg',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // 4 个封面 Key 都在（errorBuilder 回退不影响 Key 存在）。
    expect(find.byKey(const Key('discover-entry-cover-home')), findsOneWidget);
    expect(find.byKey(const Key('discover-entry-cover-style')), findsOneWidget);
    expect(find.byKey(const Key('discover-entry-cover-ai')), findsOneWidget);
    expect(find.byKey(const Key('discover-entry-cover-fm')), findsOneWidget);

    // 入口接口在页面加载时就被调用（封面预取）。
    expect(fixture.discovery.homeDiscoverCalls, greaterThan(0));
    expect(fixture.discovery.styleCalls, greaterThan(0));
    expect(fixture.discovery.aiCalls, greaterThan(0));
    expect(fixture.discovery.fmCalls, greaterThan(0));
  });

  testWidgets('FM 未登录（预取失败）静默无封面，入口仍可点', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(discovery: FakeDiscoveryApi(fmFailuresLeft: 99)),
    );

    // FM 卡回退 icon（无 cover Key），入口仍渲染。
    expect(find.byKey(const Key('discover-entry-cover-fm')), findsNothing);
    expect(find.byKey(const Key('discover-entry-fm')), findsOneWidget);
    expect(fixture.discovery.fmCalls, greaterThan(0));

    // 点进去仍能 push 长条页（loader 会失败 → 空态，不崩）。
    await tester.tap(find.byKey(const Key('discover-entry-fm')));
    await _settleRoute(tester);
    expect(find.text('私人 FM'), findsOneWidget);
  });

  testWidgets('authEpoch 变化只重取 FM 预览', (tester) async {
    final epoch = ValueNotifier<int>(0);
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        authEpoch: epoch,
        discovery: FakeDiscoveryApi(
          homeItems: <MusicDiscoverItem>[
            fakeHomeItem(
              id: '10',
              hash: 'd10',
              title: '首页之歌',
              coverUrl: 'https://img.example/home.jpg',
            ),
          ],
        ),
      ),
    );
    final homeBefore = fixture.discovery.homeDiscoverCalls;
    final fmBefore = fixture.discovery.fmCalls;

    epoch.value += 1;
    await tester.pump();
    await tester.pump();

    expect(fixture.discovery.fmCalls, fmBefore + 1, reason: 'FM 预览重取一次');
    expect(
      fixture.discovery.homeDiscoverCalls,
      homeBefore,
      reason: '其它入口预览不重取',
    );
  });

  // ── 每日推荐 ───────────────────────────────────────────────────────────

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
    expect(find.text('3:20'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(2));

    await tester.tap(find.text('每日之歌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 单击回调在双击判定超时后才触发，再等路由动画完成。
    await tester.pumpAndSettle();

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

  // ── 入口导航 ───────────────────────────────────────────────────────────

  testWidgets('排行榜入口：仅接线时显示，点击回调', (tester) async {
    final fixture = await _pumpPage(tester, _Fixture());
    expect(find.byKey(const Key('discover-entry-rank')), findsOneWidget);

    await tester.tap(find.byKey(const Key('discover-entry-rank')));
    await tester.pump();
    expect(fixture.openRankCalls, 1);

    await _pumpPage(tester, _Fixture(wireRank: false));
    expect(find.byKey(const Key('discover-entry-rank')), findsNothing);
    expect(find.text('排行榜'), findsNothing);
  });

  testWidgets('首页发现入口推入长条列表页，预览批次立即显示', (tester) async {
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

    expect(find.text('发现之歌A'), findsOneWidget);
    expect(find.text('推荐歌手'), findsOneWidget);

    await tester.tap(find.text('发现之歌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.player.played, hasLength(1));
    expect(fixture.player.played.single.id, '10');
  });

  testWidgets('AI 与 FM 入口推入长条列表页', (tester) async {
    await _pumpPage(
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

    await tester.pageBack();
    await _settleRoute(tester);

    await tester.tap(find.byKey(const Key('discover-entry-fm')));
    await _settleRoute(tester);
    expect(find.text('FM之歌A'), findsOneWidget);
  });

  // ── 搜索统一 push 搜索页 ───────────────────────────────────────────────

  testWidgets('SearchBar 提交 push 搜索页，预填关键词并自动搜索', (tester) async {
    final fixture = await _pumpPage(tester, _Fixture());

    await _submitSearch(tester, '晴天');
    await _settleRoute(tester);

    // 搜索页预填词 + 自动提交 → store.lastKeyword 写入 + 结果长条出现。
    expect(find.byKey(const Key('discovery-search-bar')), findsOneWidget);
    expect(fixture.store.lastKeyword, '晴天');
    expect(find.text('晴天 之一'), findsOneWidget);
    expect(find.text('晴天 之二'), findsOneWidget);
  });

  testWidgets('建议词点击 push 搜索页并自动提交', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          suggestionGroups: <MusicSuggestionGroup>[fakeSuggestionGroup()],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '周');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.text('周杰伦'), findsOneWidget);

    await tester.tap(find.text('周杰伦'));
    await _settleRoute(tester);

    expect(fixture.store.lastKeyword, '周杰伦');
    expect(find.text('周杰伦 之一'), findsOneWidget);
  });

  testWidgets('热搜页点词 pop 返回并 push 搜索页自动提交', (tester) async {
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

    await tester.tap(find.text('默认词A'));
    await _settleRoute(tester);

    expect(fixture.store.lastKeyword, '默认词A');
    expect(find.byKey(const Key('discovery-search-bar')), findsOneWidget);
    expect(find.text('默认词A 之一'), findsOneWidget);
  });
}
