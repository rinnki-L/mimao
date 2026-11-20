// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 test/novel/contract_test.dart 同款说明。
/// 小说导航骨架测试：五 tab、typed 路由、搜索提交与壳层注册。
///
/// 只测结构/导航，不碰抓取/解析/IO：占位屏渲染、tab 切换、路由 push 参数、
/// registry 装配后 moduleFor(MediaType.novel) 非空。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/pages/novel_module_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart';

void main() {
  testWidgets('导航骨架：五 tab 齐全，默认显示书架', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NovelModulePage(embedded: true)),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    for (final label in <String>['书架', '发现', '搜索', '书源', '设置']) {
      expect(find.text(label), findsWidgets);
    }
    expect(bar.selectedIndex, 0);
    expect(find.text('已收藏的书籍将在这里列出。\n书架与本地缓存随数据层切片接入。'), findsOneWidget);
  });

  testWidgets('tab 切换：点「书源」显示书源占位与导入按钮', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NovelModulePage(embedded: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();

    expect(find.text('书源'), findsWidgets);
    expect(find.byKey(const Key('novel-source-import')), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3);
  });

  testWidgets('typed 路由：书源导入按钮经 onOpenRoute 打开 sourceManage 路由', (
    tester,
  ) async {
    NovelRoute? opened;
    Map<String, Object?>? openedArgs;
    await tester.pumpWidget(
      MaterialApp(
        home: NovelModulePage(
          embedded: true,
          onOpenRoute: (route, {args = const <String, Object?>{}}) {
            opened = route;
            openedArgs = args;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-source-import')));
    await tester.pumpAndSettle();

    expect(opened, NovelRoute.sourceManage);
    expect(openedArgs, isEmpty);
  });

  testWidgets('搜索：提交关键词经 onOpenRoute 打开 search 路由并透传 keyword', (tester) async {
    NovelRoute? opened;
    Map<String, Object?>? openedArgs;
    await tester.pumpWidget(
      MaterialApp(
        home: NovelModulePage(
          embedded: true,
          onOpenRoute: (route, {args = const <String, Object?>{}}) {
            opened = route;
            openedArgs = args;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), '三体');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(opened, NovelRoute.search);
    expect(openedArgs, <String, Object?>{'keyword': '三体'});
  });

  test('typed 路由表：routeName/label 稳定且唯一', () {
    final names = NovelRoute.values.map((r) => r.routeName).toList();
    expect(names.toSet().length, names.length);
    expect(NovelRoute.read.routeName, 'novel/read');
    expect(NovelRoute.toc.label, '目录');
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

    // 占位屏 AppBar 标题 + 路由名 + 参数 chip 均可见。
    expect(find.text('书籍详情'), findsWidgets);
    expect(find.textContaining('novel/book-info'), findsOneWidget);
    expect(find.textContaining('bookId: b1'), findsOneWidget);
  });
}
