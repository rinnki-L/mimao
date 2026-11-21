// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 发现页搜索结果页 widget 测试：不联网、不碰真实计时器。
///
/// 覆盖：未搜索落位（历史 chips + 清空 + 引导）、输入防抖建议与 stale 丢弃、
/// 提交后歌曲长条结果、点歌播放、收藏、空结果、带词进入自动提交。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_discovery_search_page.dart';

import 'fakes.dart';

Widget _host(Widget page) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF4A6CF7),
    brightness: Brightness.light,
  ),
  home: page,
);

/// 一套注入桩。
class _Fixture {
  _Fixture({
    FakeSearchExtApi? searchExt,
    this.collect,
    this.history,
    this.initialKeyword = '',
    FakeMusicApi? musicApi,
  }) : searchExt = searchExt ?? FakeSearchExtApi(),
       player = FakePlayerUi() {
    store = MusicStore(musicApi ?? FakeMusicApi());
  }

  late final MusicStore store;
  final FakeSearchExtApi searchExt;
  final FakeCollectApi? collect;
  final FakeSearchHistoryApi? history;
  final FakePlayerUi player;
  final String initialKeyword;

  Widget get page => MusicDiscoverySearchPage(
    searchExt: searchExt,
    store: store,
    player: player,
    collect: collect,
    searchHistory: history,
    initialKeyword: initialKeyword,
  );
}

Future<_Fixture> _pumpPage(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(_host(fixture.page));
  await tester.pump();
  await tester.pump();
  return fixture;
}

void main() {
  testWidgets('未搜索落位：历史 chips + 清空 + 引导文案', (tester) async {
    final history = FakeSearchHistoryApi(initial: <String>['老关键词']);
    await _pumpPage(tester, _Fixture(history: history));

    expect(find.byKey(const Key('discovery-search-landing')), findsOneWidget);
    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('老关键词'), findsOneWidget);
    expect(find.text('输入关键词开始搜索'), findsOneWidget);

    // 清空历史。
    await tester.tap(find.byKey(const Key('discovery-search-history-clear')));
    await tester.pump();
    await tester.pump();
    expect(history.words, isEmpty);
    expect(find.text('老关键词'), findsNothing);
    expect(find.text('输入关键词开始搜索'), findsOneWidget);
  });

  testWidgets('无历史时只有引导文案，无搜索历史区', (tester) async {
    await _pumpPage(tester, _Fixture());
    expect(find.byKey(const Key('discovery-search-landing')), findsOneWidget);
    expect(find.text('搜索历史'), findsNothing);
    expect(find.text('输入关键词开始搜索'), findsOneWidget);
  });

  testWidgets('历史词点击自动填入并提交', (tester) async {
    final history = FakeSearchHistoryApi(initial: <String>['老关键词']);
    final fixture = await _pumpPage(tester, _Fixture(history: history));

    await tester.tap(find.text('老关键词'));
    await tester.pump();
    await tester.pump();

    expect(fixture.store.lastKeyword, '老关键词');
    expect(history.words.last, '老关键词');
    expect(find.text('老关键词 之一'), findsOneWidget);
  });

  testWidgets('搜索建议：输入防抖拉取，点击建议自动提交', (tester) async {
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
    expect(fixture.searchExt.lastSuggestKeyword, '周');

    await tester.tap(find.text('周杰伦'));
    await tester.pump();
    await tester.pump();

    expect(fixture.store.lastKeyword, '周杰伦');
    expect(find.text('周杰伦 之一'), findsOneWidget);
    // 提交后建议条收回，剩下的「周杰伦」只有搜索框里的输入文本。
    expect(find.text('周杰伦'), findsOneWidget);
  });

  testWidgets('建议 stale 响应丢弃：输入变化后旧建议不落地', (tester) async {
    // 建议源带可控延迟：先发「周」的请求（响应慢），响应回前把输入改成
    // 「晴天」；旧响应回来时 _controller.text 已变化，应被 stale 检查丢弃。
    final ext = _SlowSuggestApi();
    await _pumpPage(tester, _Fixture(searchExt: ext));

    await tester.enterText(find.byType(TextField), '周');
    // 防抖 400ms 到点、请求已发出（100ms 后才回）；此刻 pump 到 450ms，
    // 旧响应尚未返回。
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(ext.searchSuggestCalls, 1);

    // 输入改为「晴天」→ 旧请求 100ms 后返回，但关键词已变 → 被丢弃。
    await tester.enterText(find.byType(TextField), '晴天');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    expect(find.text('旧建议周'), findsNothing, reason: '「周」的迟到响应必须被 stale 丢弃');

    // 新关键词走完自己的防抖 + 慢响应，正常展示「新建议晴天」。
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.text('新建议晴天'), findsOneWidget);
  });

  testWidgets('搜索结果点歌：playSong 被调用并 push 播放页', (tester) async {
    final fixture = await _pumpPage(tester, _Fixture(initialKeyword: '晴天'));

    expect(find.byKey(const Key('discovery-search-results')), findsOneWidget);
    expect(find.text('晴天 之一'), findsOneWidget);
    expect(find.text('晴天 之二'), findsOneWidget);

    await tester.tap(find.text('晴天 之一'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 单击回调在双击判定超时后才触发，再等路由动画完成。
    await tester.pumpAndSettle();

    expect(fixture.player.played, hasLength(1));
    expect(fixture.player.played.first.id, '101');
    expect(find.text('播放页占位'), findsOneWidget);
  });

  testWidgets('收藏按钮：点击写入收藏，已收藏显示实底心', (tester) async {
    final collect = FakeCollectApi(initialIds: <String>{'101'});
    await _pumpPage(tester, _Fixture(collect: collect, initialKeyword: '晴天'));

    // 101 已收藏（实心），102 未收藏（描边）。
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    // 行内收藏按钮与整行双击共用祖先手势，单击会在双击判定超时后触发。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(collect.collected, hasLength(1));
    expect(collect.collected.single.id, '102');
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('空结果：无相关歌曲文案', (tester) async {
    await _pumpPage(
      tester,
      _Fixture(initialKeyword: '无结果', musicApi: FakeMusicApiEmpty()),
    );

    expect(find.text('没有找到相关歌曲'), findsOneWidget);
    expect(find.byKey(const Key('discovery-search-results')), findsNothing);
  });

  testWidgets('搜索失败：错误文案 + 重试', (tester) async {
    await _pumpPage(
      tester,
      _Fixture(
        musicApi: FakeMusicApi(throwOnSearch: StateError('搜索挂了')),
        initialKeyword: '晴天',
      ),
    );

    expect(find.textContaining('搜索挂了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

/// 带延迟的建议替身：按关键词返回不同建议文本，用于验证 stale 响应丢弃。
class _SlowSuggestApi extends FakeSearchExtApi {
  _SlowSuggestApi()
    : super(
        suggestionGroups: <MusicSuggestionGroup>[
          MusicSuggestionGroup(
            title: '测试建议',
            items: <MusicSearchSuggestion>[
              MusicSearchSuggestion(text: '占位', source: '', subtitle: ''),
            ],
          ),
        ],
      );

  @override
  Future<MusicSearchSuggestions> searchSuggest(
    MusicSearchSuggestQuery query,
  ) async {
    searchSuggestCalls++;
    lastSuggestKeyword = query.keyword;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final text = query.keyword == '周' ? '旧建议周' : '新建议晴天';
    return MusicSearchSuggestions(
      groups: <MusicSuggestionGroup>[
        MusicSuggestionGroup(
          title: '测试建议',
          items: <MusicSearchSuggestion>[
            MusicSearchSuggestion(text: text, source: '', subtitle: ''),
          ],
        ),
      ],
    );
  }
}

/// 返回空结果的 MusicApi 替身（复用 FakeMusicApi 结构，仅覆盖 searchSongs）。
class FakeMusicApiEmpty extends FakeMusicApi {
  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async => MusicPage<MusicSong>(items: const <MusicSong>[]);
}
