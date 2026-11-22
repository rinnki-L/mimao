// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 test/novel/contract_test.dart 同款说明。
/// 小说导航壳测试：五入口（首页/书架/发现/订阅/我的）、宽窄窗导航形态、
/// typed 路由与参数、占位屏。
///
/// 只测结构与导航，不碰抓取/解析/IO；本地数据页的渲染由 wiring 测试覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/pages/novel_module_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart';

void main() {
  setUp(resetNovelRoutePagesForTest);

  testWidgets('导航骨架：五入口齐全，默认首页', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NovelModulePage(embedded: true)),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    for (final label in <String>['首页', '书架', '发现', '订阅', '我的']) {
      expect(find.text(label), findsWidgets);
    }
    expect(bar.selectedIndex, 0);
    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('还没有最近阅读'), findsOneWidget);
    expect(find.text('今日阅读目标'), findsWidgets);
  });

  testWidgets('宽窗用左侧 NavigationRail，窄窗用底部 NavigationBar', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: NovelModulePage(embedded: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final label in <String>['首页', '书架', '发现', '订阅', '我的']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('tab 切换：点到「订阅」显示书源仓库未接线空态', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NovelModulePage(embedded: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('订阅').last);
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3);
    expect(find.text('订阅'), findsWidgets);
    expect(find.text('书源仓库未接线'), findsOneWidget);
  });

  testWidgets('typed 路由：首页「导入书源」经 onOpenRoute 打开 sourceManage', (tester) async {
    NovelRoute? opened;
    Map<String, Object?>? openedArgs;
    await tester.pumpWidget(
      MaterialApp(
        home: NovelModulePage(
          embedded: true,
          onOpenRoute: (route, {args = const <String, Object?>{}}) async {
            opened = route;
            openedArgs = args;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('novel-home-import-source')));
    await tester.pumpAndSettle();

    expect(opened, NovelRoute.sourceManage);
    expect(openedArgs, isEmpty);
  });

  testWidgets('首页搜索钮经 onOpenRoute 打开 search 路由', (tester) async {
    NovelRoute? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: NovelModulePage(
          embedded: true,
          onOpenRoute: (route, {args = const <String, Object?>{}}) async {
            opened = route;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索').first);
    await tester.pumpAndSettle();

    expect(opened, NovelRoute.search);
  });

  test('typed 路由表：routeName/label 稳定且唯一', () {
    final names = NovelRoute.values.map((r) => r.routeName).toList();
    expect(names.toSet().length, names.length);
    expect(NovelRoute.read.routeName, 'novel/read');
    expect(NovelRoute.toc.label, '目录');
    expect(NovelRoute.history.routeName, 'novel/history');
  });

  testWidgets('pushNovelRoute：路由名进 RouteSettings，占位屏展示参数', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => pushNovelRoute<void>(
              context,
              NovelRoute.bookInfo,
              args: <String, Object?>{'bookId': 'b1'},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('书籍详情'), findsWidgets);
    expect(find.textContaining('novel/book-info'), findsOneWidget);
    expect(find.textContaining('bookId: b1'), findsOneWidget);
  });
}
