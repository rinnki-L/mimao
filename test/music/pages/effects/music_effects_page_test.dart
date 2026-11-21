// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 音效页 widget 测试（L1）：不联网、不碰插件与真实计时器。
///
/// 覆盖：
/// 1. 音效商城 tab：卡片渲染（名称/作者/标签/人数）与按 total 的加载更多；
/// 2. unavailableReason 置灰（Opacity 0.45）与原因文案；
/// 3. 三个 section 独立失败/重试（商城失败不影响品牌与设备匹配）；
/// 4. 品牌分页与点击跳转品牌详情页（brandId/pageSize 断言）；
/// 5. 设备匹配未命中空态 + 重新匹配、失败重试、命中卡片；
/// 6. playbackExt 为空时音效商城 tab 与识曲入口整体隐藏。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/pages/music_effects_page.dart';

import 'fakes.dart';

Widget _host(Widget page) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF4A6CF7),
    brightness: Brightness.light,
  ),
  home: page,
);

/// 首帧装载：pumpWidget + 一次 pump（三个 section 的异步装载完成）。
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_host(page));
  await tester.pump();
}

/// 切 tab：等 300ms 的页面切换动画走完。
Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets('音效商城：卡片渲染与按 total 收口的加载更多', (tester) async {
    final playbackExt = FakePlaybackExtApi(
      marketPages: <List<MusicEffect>>[
        <MusicEffect>[
          fakeEffect(id: 1, name: '音效A'),
          fakeEffect(id: 2, name: '音效B'),
        ],
        <MusicEffect>[fakeEffect(id: 3, name: '音效C')],
      ],
      marketTotal: 3,
    );
    await _pumpPage(
      tester,
      MusicEffectsPage(effects: FakeEffectsApi(), playbackExt: playbackExt),
    );

    // 首页两张卡：名称/作者/标签/人数齐备。
    expect(find.text('音效A'), findsOneWidget);
    expect(find.text('作者甲'), findsNWidgets(2));
    expect(find.text('古风'), findsNWidgets(2));
    expect(find.text('1200人在用'), findsNWidgets(2));
    expect(find.text('加载更多'), findsOneWidget);

    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.pump();

    // 第二页追加后 loaded==total，页脚收口；查询参数按 30/页递增。
    expect(find.text('音效C'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(playbackExt.marketQueries, hasLength(2));
    expect(playbackExt.marketQueries[0].page, 1);
    expect(playbackExt.marketQueries[0].pageSize, 30);
    expect(playbackExt.marketQueries[0].sort, 2);
    expect(playbackExt.marketQueries[1].page, 2);
  });

  testWidgets('unavailable 音效置灰并显示原因；可用音效不置灰', (tester) async {
    await _pumpPage(
      tester,
      MusicEffectsPage(
        effects: FakeEffectsApi(),
        playbackExt: FakePlaybackExtApi(
          marketPages: <List<MusicEffect>>[
            <MusicEffect>[
              fakeEffect(id: 1, name: '正常音效'),
              fakeEffect(
                id: 2,
                name: '受限音效',
                unavailableReason: '此音效需要上游授权，暂不支持下载',
              ),
            ],
          ],
          marketTotal: 2,
        ),
      ),
    );

    // 原因文案单独展示（在灰块外保持可读）。
    expect(find.text('此音效需要上游授权，暂不支持下载'), findsOneWidget);
    final dimmed = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('受限音效'), matching: find.byType(Opacity))
          .first,
    );
    expect(dimmed.opacity, 0.45);
    final normal = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('正常音效'), matching: find.byType(Opacity))
          .first,
    );
    expect(normal.opacity, 1);
  });

  testWidgets('三个 section 独立失败重试：商城挂了不影响品牌与设备匹配', (tester) async {
    final playbackExt = FakePlaybackExtApi(
      marketFailuresLeft: 1,
      marketPages: <List<MusicEffect>>[
        <MusicEffect>[fakeEffect(id: 1, name: '音效A')],
      ],
    );
    final effects = FakeEffectsApi(
      brandPages: <List<MusicEarphoneBrand>>[
        <MusicEarphoneBrand>[fakeBrand(id: 7, name: '品牌A')],
      ],
      matchResults: <MusicEffect?>[
        fakeEffect(id: 9, name: '匹配音效', source: 'headphone'),
      ],
    );
    await _pumpPage(
      tester,
      MusicEffectsPage(effects: effects, playbackExt: playbackExt),
    );

    // 商城失败：错误态 + 重试按钮。
    expect(find.textContaining('音效商城加载失败'), findsOneWidget);
    expect(find.textContaining('音效商城挂了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 品牌与设备匹配不受牵连。
    await _selectTab(tester, '耳机品牌');
    expect(find.text('品牌A'), findsOneWidget);
    await _selectTab(tester, '设备匹配');
    expect(find.text('匹配音效'), findsOneWidget);

    // 回商城重试：恢复列表。
    await _selectTab(tester, '音效商城');
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('音效A'), findsOneWidget);
    expect(playbackExt.marketCalls, 2);
  });

  testWidgets('品牌分页与跳转详情：brandId/pageSize 装配、型号渲染与置灰', (tester) async {
    final effects = FakeEffectsApi(
      brandPages: <List<MusicEarphoneBrand>>[
        <MusicEarphoneBrand>[
          fakeBrand(id: 7, name: '品牌A'),
          fakeBrand(id: 8, name: '品牌B'),
        ],
        <MusicEarphoneBrand>[fakeBrand(id: 9, name: '品牌C')],
      ],
      brandTotal: 3,
      brandDetailPages: <List<MusicEffect>>[
        <MusicEffect>[
          fakeEffect(id: 21, name: '型号音效一', source: 'headphone'),
          fakeEffect(
            id: 22,
            name: '型号音效二',
            source: 'headphone',
            unavailableReason: '此耳机音效尚未解锁',
          ),
        ],
      ],
      brandDetailTotal: 2,
    );
    await _pumpPage(tester, MusicEffectsPage(effects: effects));

    await _selectTab(tester, '耳机品牌');
    expect(find.text('品牌A'), findsOneWidget);
    // 首页两行（品牌A/B），各 3 个型号。
    expect(find.text('3 个型号'), findsNWidgets(2));

    // 品牌分页：按 total 收口。
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.pump();
    expect(find.text('品牌C'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(effects.brandQueries[1].page, 2);

    // 点品牌 A → 详情页：标题用品牌名，brandId/pageSize 装配正确。
    await tester.tap(find.text('品牌A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('型号音效一'), findsOneWidget);
    expect(find.text('此耳机音效尚未解锁'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    final query = effects.brandDetailQueries.single;
    expect(query.brandId, 7);
    expect(query.page, 1);
    expect(query.pageSize, 50);
    final dimmed = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('型号音效二'), matching: find.byType(Opacity))
          .first,
    );
    expect(dimmed.opacity, 0.45);
  });

  testWidgets('设备匹配：未命中空态 + 重新匹配；命中显示一张音效卡', (tester) async {
    final effects = FakeEffectsApi(
      matchResults: <MusicEffect?>[
        null,
        fakeEffect(id: 9, name: '匹配音效', source: 'headphone'),
      ],
    );
    await _pumpPage(tester, MusicEffectsPage(effects: effects));

    await _selectTab(tester, '设备匹配');
    expect(find.text('当前设备未匹配到耳机音效'), findsOneWidget);
    expect(effects.matchCalls, 1);

    await tester.tap(find.byKey(const Key('effects-match-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('匹配音效'), findsOneWidget);
    expect(effects.matchCalls, 2);
  });

  testWidgets('设备匹配失败：错误态与重试', (tester) async {
    final effects = FakeEffectsApi(
      matchFailuresLeft: 1,
      matchResults: <MusicEffect?>[
        fakeEffect(id: 9, name: '匹配音效', source: 'headphone'),
      ],
    );
    await _pumpPage(tester, MusicEffectsPage(effects: effects));

    await _selectTab(tester, '设备匹配');
    expect(find.textContaining('设备匹配挂了'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('匹配音效'), findsOneWidget);
    expect(effects.matchCalls, 2);
  });

  testWidgets('playbackExt 为空：无音效商城 tab、无识曲入口，品牌/匹配照常', (tester) async {
    final effects = FakeEffectsApi(
      brandPages: <List<MusicEarphoneBrand>>[
        <MusicEarphoneBrand>[fakeBrand(id: 7, name: '品牌A')],
      ],
      matchResults: <MusicEffect?>[null],
    );
    await _pumpPage(tester, MusicEffectsPage(effects: effects));

    // AppBar 标题仍在，但「音效商城」tab 与识曲入口消失。
    expect(find.text('音效商城'), findsOneWidget);
    expect(find.widgetWithText(Tab, '音效商城'), findsNothing);
    expect(find.byKey(const Key('effects-match-entry')), findsNothing);

    await _selectTab(tester, '耳机品牌');
    expect(find.text('品牌A'), findsOneWidget);
    await _selectTab(tester, '设备匹配');
    expect(find.text('当前设备未匹配到耳机音效'), findsOneWidget);
  });

  testWidgets('识曲入口：playbackExt 非空时 push 听歌识曲页', (tester) async {
    await _pumpPage(
      tester,
      MusicEffectsPage(
        effects: FakeEffectsApi(),
        playbackExt: FakePlaybackExtApi(),
      ),
    );

    await tester.tap(find.byKey(const Key('effects-match-entry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 识曲页出现：主按钮与引导文案。
    expect(find.text('开始识别'), findsOneWidget);
    expect(find.textContaining('播放一段歌曲'), findsOneWidget);
  });
}
