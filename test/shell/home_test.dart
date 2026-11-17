// 壳的冒烟测试：验证入口拼贴页四个入口齐全、钻进/返回导航可用。
// 顺带把 shell/ 与其生成的 shell_store.g.dart 拉进覆盖率分母并真实执行。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/home.dart';
import 'package:mimao/shell/shell_store.dart';

void main() {
  late AppDb db;

  setUp(() async {
    db = AppDb.forTesting(NativeDatabase.memory());
    shellStore.goHome();
    shellStore.closeSettings();
  });

  tearDown(() async {
    await db.close();
  });

  Widget pumpApp(WidgetTester tester) {
    return LibraryScope(
      repository: LibraryRepository(db),
      child: const MimaoApp(),
    );
  }

  testWidgets('入口页展示标题与四个媒体入口', (tester) async {
    await tester.pumpWidget(pumpApp(tester));
    await tester.pumpAndSettle();

    expect(find.text('mimao'), findsOneWidget);
    for (final type in MediaType.values) {
      expect(find.text(type.label), findsWidgets);
    }
  });

  testWidgets('点入口卡片钻进模块层，返回后回到入口页', (tester) async {
    await tester.pumpWidget(pumpApp(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text(MediaType.anime.label).first);
    await tester.pumpAndSettle();
    expect(find.text('${MediaType.anime.label}模块尚未接入'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('mimao'), findsOneWidget);
  });

  testWidgets('统一书架入口显示空态', (tester) async {
    await tester.pumpWidget(pumpApp(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('统一书架'));
    await tester.pumpAndSettle();
    expect(find.text('番剧模块接入后这里开始有内容'), findsOneWidget);
  });

  testWidgets('设置抽屉可打开，四个模块分组齐全', (tester) async {
    await tester.pumpWidget(pumpApp(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    // 全局抽屉按「外观 / 存储 / 四模块」分组（用户拍板的 C + 全局一个设置）
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('存储'), findsOneWidget);
    for (final type in MediaType.values) {
      expect(find.text(type.label), findsWidgets);
    }
  });
}
