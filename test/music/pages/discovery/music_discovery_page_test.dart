// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 发现页 widget 测试（U1）：不联网、不碰真实计时器。
///
/// 覆盖：
/// 1. 默认词/热词渲染，点击 chip 触发搜索；
/// 2. 发现 section 标题与歌曲渲染；
/// 3. 点歌曲 → fake player.playSong 被调用并 push 播放页占位；
/// 4. 专辑/歌手/歌单行点击回调拿到正确 id；
/// 5. 歌词候选 → downloadLyric → 弹出文本（含解码失败「歌词格式不支持」）；
/// 6. 某个 section 失败时页面仍显示其它 section 与重试按钮（重试后恢复）。
/// 附：FM 换一批、搜索建议防抖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/personal_fm.dart';
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

  final List<int> openedAlbums = <int>[];
  final List<int> openedArtists = <int>[];
  final List<String> openedPlaylists = <String>[];
  int openRankCalls = 0;

  Widget get page => MusicDiscoveryPage(
    searchExt: searchExt,
    discovery: discovery,
    store: store,
    player: player,
    lyric: lyric,
    collect: collect,
    searchHistory: history,
    onOpenAlbum: openedAlbums.add,
    onOpenArtist: openedArtists.add,
    onOpenPlaylist: openedPlaylists.add,
    onOpenRank: () => openRankCalls++,
  );
}

/// 首帧装载：pumpWidget + 一次 pump（异步 sections 装载完成）。
Future<_Fixture> _pumpPage(WidgetTester tester, _Fixture fixture) async {
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

void main() {
  testWidgets('默认词渲染，点击 chip 填入并触发搜索', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          promotions: <MusicSearchPromotion>[fakePromotion(title: '默认词A')],
        ),
      ),
    );

    expect(find.text('默认词A'), findsOneWidget);

    await tester.tap(find.text('默认词A'));
    await _settle(tester);

    expect(fixture.store.lastKeyword, '默认词A');
    // 提交后自动切到「歌曲」tab，结果行渲染出来。
    expect(find.text('默认词A 之一'), findsOneWidget);
    expect(find.text('默认词A 之二'), findsOneWidget);
  });

  testWidgets('热搜分组渲染，点击热词触发搜索', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        searchExt: FakeSearchExtApi(
          hotGroups: <MusicHotSearchGroup>[fakeHotGroup()],
        ),
      ),
    );

    expect(find.text('飙升榜'), findsOneWidget);
    expect(find.text('热词B'), findsOneWidget);

    await tester.tap(find.text('热词B'));
    await _settle(tester);

    expect(fixture.store.lastKeyword, '热词B');
    expect(find.text('热词B 之一'), findsOneWidget);
  });

  testWidgets('发现 section 标题与歌曲卡片渲染；排行榜入口回调', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
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
        ),
      ),
    );

    expect(find.text('首页发现'), findsOneWidget);
    expect(find.text('发现之歌A'), findsOneWidget);
    expect(find.text('每日推荐'), findsOneWidget);
    expect(find.text('每日之歌A'), findsOneWidget);

    // 纵向 ListView 惰性构建：滚动后「AI 免费畅听」「私人 FM」才进树。
    await tester.dragUntilVisible(
      find.text('AI之歌A'),
      find.byKey(const Key('discover-scroll')),
      const Offset(0, -200),
    );
    expect(find.text('AI 免费畅听'), findsOneWidget);
    expect(find.text('AI之歌A'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('FM之歌A'),
      find.byKey(const Key('discover-scroll')),
      const Offset(0, -200),
    );
    expect(find.text('私人 FM'), findsOneWidget);
    expect(find.text('FM之歌A'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.leaderboard_outlined));
    await tester.pump();
    expect(fixture.openRankCalls, 1);
  });

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

  testWidgets('私人 FM 换一批：重新拉取并替换为下一批', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
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
      ),
    );

    expect(find.text('FM之歌A'), findsOneWidget);
    expect(fixture.discovery.fmCalls, 1);

    await tester.tap(find.text('换一批'));
    await tester.pump();
    await tester.pump();

    expect(find.text('FM之歌A'), findsNothing);
    expect(find.text('FM之歌B'), findsOneWidget);
    expect(fixture.discovery.fmCalls, 2);
    // 「换一批」按模型默认参数重拉（action=play）。
    expect(fixture.discovery.lastFmQuery?.action, MusicPersonalFmAction.play);
  });

  testWidgets('单个发现 section 失败：其它 section 保留，重试后恢复', (tester) async {
    final fixture = await _pumpPage(
      tester,
      _Fixture(
        discovery: FakeDiscoveryApi(
          homeItems: <MusicDiscoverItem>[
            fakeHomeItem(id: '10', hash: 'd10', title: '发现之歌A'),
          ],
          dailySongs: <MusicDiscoverySong>[
            fakeDiscoverySong(id: '20', hash: 'd20', title: '每日之歌A'),
          ],
          dailyFailuresLeft: 1,
        ),
      ),
    );

    // 每日推荐失败，但首页发现照常渲染；失败 section 有重试按钮。
    expect(find.text('发现之歌A'), findsOneWidget);
    expect(find.textContaining('每日推荐挂了'), findsOneWidget);
    final dailyRetry = find.descendant(
      of: find.byKey(const Key('discover-daily')),
      matching: find.text('重试'),
    );
    expect(dailyRetry, findsOneWidget);

    await tester.tap(dailyRetry);
    await tester.pump();
    await tester.pump();

    expect(find.text('每日之歌A'), findsOneWidget);
    expect(fixture.discovery.dailyCalls, 2);
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
