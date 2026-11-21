// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 耳机品牌型号音效页 widget 测试（L1）：不联网。
///
/// 覆盖：装载渲染与查询装配（brandId/pageSize）、首屏失败重试、
/// 按 total 的加载更多、无 total 时的整页满推测与收口、空态、
/// unavailableReason 置灰。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/pages/music_effects_brand_page.dart';

import 'fakes.dart';

Widget _host(Widget page) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF4A6CF7),
    brightness: Brightness.light,
  ),
  home: page,
);

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_host(page));
  await tester.pump();
}

void main() {
  testWidgets('装载与查询装配：标题用品牌名，brandId/pageSize 正确', (tester) async {
    final effects = FakeEffectsApi(
      brandDetailPages: <List<MusicEffect>>[
        <MusicEffect>[
          fakeEffect(id: 21, name: '型号音效一'),
          fakeEffect(id: 22, name: '型号音效二'),
        ],
      ],
      brandDetailTotal: 2,
    );
    await _pumpPage(
      tester,
      MusicEffectsBrandPage(
        effects: effects,
        brand: fakeBrand(id: 7, name: '品牌A'),
      ),
    );

    expect(find.text('品牌A'), findsOneWidget);
    expect(find.text('型号音效一'), findsOneWidget);
    expect(find.text('型号音效二'), findsOneWidget);
    // total 已取满：无加载更多页脚。
    expect(find.text('加载更多'), findsNothing);
    final query = effects.brandDetailQueries.single;
    expect(query.brandId, 7);
    expect(query.page, 1);
    expect(query.pageSize, 50);
  });

  testWidgets('首屏失败：错误态 + 重试恢复', (tester) async {
    final effects = FakeEffectsApi(
      brandDetailFailuresLeft: 1,
      brandDetailPages: <List<MusicEffect>>[
        <MusicEffect>[fakeEffect(id: 21, name: '型号音效一')],
      ],
    );
    await _pumpPage(
      tester,
      MusicEffectsBrandPage(
        effects: effects,
        brand: fakeBrand(id: 7, name: '品牌A'),
      ),
    );

    expect(find.textContaining('耳机音效加载失败'), findsOneWidget);
    expect(find.textContaining('耳机音效挂了'), findsOneWidget);
    expect(effects.brandDetailCalls, 1);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('型号音效一'), findsOneWidget);
    expect(effects.brandDetailCalls, 2);
  });

  testWidgets('加载更多：按 total 追加后收口', (tester) async {
    final effects = FakeEffectsApi(
      brandDetailPages: <List<MusicEffect>>[
        <MusicEffect>[fakeEffect(id: 21, name: '型号音效一')],
        <MusicEffect>[fakeEffect(id: 22, name: '型号音效二')],
      ],
      brandDetailTotal: 2,
    );
    await _pumpPage(
      tester,
      MusicEffectsBrandPage(
        effects: effects,
        brand: fakeBrand(id: 7, name: '品牌A'),
      ),
    );

    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.pump();

    expect(find.text('型号音效二'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(effects.brandDetailQueries[1].page, 2);
  });

  testWidgets('加载更多：无 total 时整页满触发、空页收口', (tester) async {
    // 无 total：第一页满 50 条 → 推测还有下一页；第二页空 → 收口。
    final effects = FakeEffectsApi(
      brandDetailPages: <List<MusicEffect>>[
        <MusicEffect>[
          for (var i = 0; i < 50; i++) fakeEffect(id: i, name: '音效$i'),
        ],
        <MusicEffect>[],
      ],
    );
    await _pumpPage(
      tester,
      MusicEffectsBrandPage(
        effects: effects,
        brand: fakeBrand(id: 7, name: '品牌A'),
      ),
    );

    // 50 张卡片远超一屏（页脚未进树）；先滚到页脚再点。
    // scrollUntilVisible 的 delta 约定：正值沿滚动方向前进（竖列表即向下）。
    await tester.scrollUntilVisible(
      find.text('加载更多'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.pump();

    // 列表保留（滚动位置在列表尾部，尾卡可见）、页脚收口、第二页查询发出。
    expect(find.text('音效49'), findsOneWidget);
    expect(effects.brandDetailQueries[1].page, 2);
    expect(effects.brandDetailCalls, 2);
    // 收口后再滚一次确认：页脚不再渲染。
    await tester.scrollUntilVisible(
      find.text('音效49'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('空态：该品牌暂无耳机音效', (tester) async {
    await _pumpPage(
      tester,
      MusicEffectsBrandPage(
        effects: FakeEffectsApi(
          brandDetailPages: <List<MusicEffect>>[<MusicEffect>[]],
        ),
        brand: fakeBrand(id: 7, name: '品牌A'),
      ),
    );

    expect(find.text('该品牌暂无耳机音效'), findsOneWidget);
  });

  testWidgets('unavailable 型号置灰并显示原因', (tester) async {
    await _pumpPage(
      tester,
      MusicEffectsBrandPage(
        effects: FakeEffectsApi(
          brandDetailPages: <List<MusicEffect>>[
            <MusicEffect>[
              fakeEffect(id: 22, name: '型号音效二', unavailableReason: '此耳机音效尚未解锁'),
            ],
          ],
        ),
        brand: fakeBrand(id: 7, name: '品牌A'),
      ),
    );

    expect(find.text('此耳机音效尚未解锁'), findsOneWidget);
    final dimmed = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('型号音效二'), matching: find.byType(Opacity))
          .first,
    );
    expect(dimmed.opacity, 0.45);
  });
}
