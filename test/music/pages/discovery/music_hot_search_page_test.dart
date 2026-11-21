// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 热门搜索页 widget 测试：不联网、不碰真实计时器。
///
/// 覆盖：默认词与热搜分组两个 section 的渲染、各自独立失败重试（互不牵连）、
/// 点词 onSearch 回调 + pop 返回宿主页、两个 section 全空时的空态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:mimao/music/pages/music_hot_search_page.dart';

import 'fakes.dart';

/// 宿主页：给一个「打开」按钮 push 热门搜索页（用于测 pop 返回行为）。
class _Host extends StatelessWidget {
  const _Host({required this.searchExt, required this.onSearch});

  final FakeSearchExtApi searchExt;
  final void Function(String keyword) onSearch;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildMimaoTheme(
        seedColor: const Color(0xFF4A6CF7),
        brightness: Brightness.light,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MusicHotSearchPage(
                    searchExt: searchExt,
                    onSearch: onSearch,
                  ),
                ),
              ),
              child: const Text('打开热门搜索'),
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开热门搜索页（等 push 动画结束）。
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('打开热门搜索'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 等待 pop 动画结束回到宿主页。
Future<void> _back(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认词与热搜分组两个 section 渲染，点词回调并返回', (tester) async {
    final searched = <String>[];
    await tester.pumpWidget(
      _Host(
        searchExt: FakeSearchExtApi(
          promotions: <MusicSearchPromotion>[fakePromotion(title: '默认词A')],
          hotGroups: <MusicHotSearchGroup>[fakeHotGroup()],
        ),
        onSearch: searched.add,
      ),
    );
    await _open(tester);

    // 两个 section 独立渲染。
    expect(find.text('默认搜索词'), findsOneWidget);
    expect(find.text('默认词A'), findsOneWidget);
    expect(find.text('热搜榜'), findsOneWidget);
    expect(find.text('飙升榜'), findsOneWidget);
    expect(find.text('热词B'), findsOneWidget);

    // 点默认词：onSearch 收到关键词，页面 pop 回宿主页。
    await tester.tap(find.text('默认词A'));
    await _back(tester);
    expect(searched, <String>['默认词A']);
    expect(find.text('打开热门搜索'), findsOneWidget);
    expect(find.text('默认搜索词'), findsNothing);

    // 再进一次点热词。
    await _open(tester);
    await tester.tap(find.text('热词B'));
    await _back(tester);
    expect(searched, <String>['默认词A', '热词B']);
  });

  testWidgets('默认词失败：独立错误与重试，热搜不受影响', (tester) async {
    await tester.pumpWidget(
      _Host(
        searchExt: FakeSearchExtApi(
          promotions: <MusicSearchPromotion>[fakePromotion(title: '默认词A')],
          hotGroups: <MusicHotSearchGroup>[fakeHotGroup()],
          defaultFailuresLeft: 1,
        ),
        onSearch: (_) {},
      ),
    );
    await _open(tester);

    expect(find.textContaining('默认词挂了'), findsOneWidget);
    expect(find.text('热词B'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(find.text('默认词A'), findsOneWidget);
    expect(find.textContaining('默认词挂了'), findsNothing);
    expect(find.text('热词B'), findsOneWidget);
  });

  testWidgets('热搜失败：独立错误与重试，默认词不受影响', (tester) async {
    await tester.pumpWidget(
      _Host(
        searchExt: FakeSearchExtApi(
          promotions: <MusicSearchPromotion>[fakePromotion(title: '默认词A')],
          hotGroups: <MusicHotSearchGroup>[fakeHotGroup()],
          hotFailuresLeft: 1,
        ),
        onSearch: (_) {},
      ),
    );
    await _open(tester);

    expect(find.textContaining('热搜挂了'), findsOneWidget);
    expect(find.text('默认词A'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(find.text('热词B'), findsOneWidget);
    expect(find.textContaining('热搜挂了'), findsNothing);
    expect(find.text('默认词A'), findsOneWidget);
  });

  testWidgets('空数据：两个 section 全空时显示空态', (tester) async {
    await tester.pumpWidget(
      _Host(searchExt: FakeSearchExtApi(), onSearch: (_) {}),
    );
    await _open(tester);

    expect(find.text('暂无热门搜索'), findsOneWidget);
    expect(find.text('默认搜索词'), findsNothing);
    expect(find.text('热搜榜'), findsNothing);
  });
}
