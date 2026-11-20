// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与其它测试同款。
/// 设置抽屉的「网络」分组：代理模式切换与自定义代理输入。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/shell/network_settings.dart';
import 'package:mimao/shell/settings_page.dart';

void main() {
  setUp(() {
    // 每个用例从直连开始（全局单例）。
    networkSettings.setProxyMode(NetworkProxyMode.direct);
  });

  testWidgets('网络分组可展开，三种代理模式可选，自定义显示地址/端口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsPage())),
    );
    await tester.pumpAndSettle();

    // 外观组默认展开，「网络」在它下面。
    await tester.tap(find.text('网络'));
    await tester.pumpAndSettle();

    expect(find.text('直连'), findsOneWidget);
    expect(find.text('环境变量'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);

    // 800x600 测试视口里 SegmentedButton 在折叠区下方，先滚进视口。
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(networkSettings.proxyMode, NetworkProxyMode.custom);
    expect(find.text('代理地址'), findsOneWidget);
    expect(find.text('端口'), findsOneWidget);
  });
}
