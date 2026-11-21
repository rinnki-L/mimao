// ignore_for_file: deprecated_member_use — 与 fakes.dart 同款说明。
/// 安全验证页 widget 测试：事件号查挑战、展示 provider/提示/验证方式、
/// sideDt 提交（32/23 类型选择、成功/失败）、searchExt 缺失时只读展示。
///
/// 全部用 fake API；结束前卸载页面树保证无 pending timer。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/pages/music_security_verify_page.dart';

import 'fakes.dart';

Widget _page({required FakeVerifyApi verify, FakeSearchExtApi? searchExt}) =>
    MusicSecurityVerifyPage(verify: verify, searchExt: searchExt);

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('查询挑战：展示 provider 类别/供应商/提示文案/可用验证方式', (tester) async {
    final verify = FakeVerifyApi()..verifyInfo = fakeVerifyConfig();
    final searchExt = FakeSearchExtApi();
    await tester.pumpWidget(
      MaterialApp(
        home: _page(verify: verify, searchExt: searchExt),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '验证事件号'), 'event-1');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();

    expect(verify.verifyInfoCalls, 1);
    expect(verify.verifyInfoQueries.single.eventId, 'event-1');
    expect(find.text('短信验证'), findsOneWidget);
    expect(find.textContaining('供应商：TX'), findsOneWidget);
    expect(find.text('请输入短信验证码完成验证'), findsOneWidget);
    expect(find.text('验证方式 23'), findsOneWidget);
    expect(find.text('验证方式 32'), findsOneWidget);
    // searchExt 已注入：提交区可见。
    expect(find.text('提交验证码'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('提交验证码：verificationType=32 走短信类型，成功提示', (tester) async {
    final verify = FakeVerifyApi()..verifyInfo = fakeVerifyConfig();
    final searchExt = FakeSearchExtApi()..acknowledged = true;
    await tester.pumpWidget(
      MaterialApp(
        home: _page(verify: verify, searchExt: searchExt),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '验证事件号'), 'event-1');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '验证码'), '886644');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(searchExt.sideDtCalls, 1);
    expect(searchExt.sideDtQueries.single.eventId, 'event-1');
    expect(searchExt.sideDtQueries.single.verifyType, 32);
    expect(searchExt.sideDtQueries.single.proof, '886644');
    expect(find.text('验证已通过'), findsWidgets);

    await _teardown(tester);
  });

  testWidgets('非短信挑战（v_type != 32）按普通验证（23）提交', (tester) async {
    final verify = FakeVerifyApi()
      ..verifyInfo = fakeVerifyConfig(
        provider: 'account_risk',
        vendor: 'KG',
        displayMessage: '账号存在风险，请完成验证',
        verificationType: 51,
        availableTypes: const <int>[23],
      );
    final searchExt = FakeSearchExtApi();
    await tester.pumpWidget(
      MaterialApp(
        home: _page(verify: verify, searchExt: searchExt),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '验证事件号'), 'event-2');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();
    expect(find.text('账号风控'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '验证码'), '1234');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(searchExt.sideDtQueries.single.verifyType, 23);

    await _teardown(tester);
  });

  testWidgets('提交未通过（acknowledged=false）与异常都给页内失败提示', (tester) async {
    final verify = FakeVerifyApi()..verifyInfo = fakeVerifyConfig();
    final searchExt = FakeSearchExtApi()..acknowledged = false;
    await tester.pumpWidget(
      MaterialApp(
        home: _page(verify: verify, searchExt: searchExt),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '验证事件号'), 'event-1');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '验证码'), '000000');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.text('验证未通过，请核对验证码后重试'), findsOneWidget);

    searchExt
      ..acknowledged = true
      ..sideDtError = const KugouApiException('business', '验证事件已失效');
    await tester.enterText(find.widgetWithText(TextField, '验证码'), '000000');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.text('验证事件已失效'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('查询失败给页内错误；空事件号不发请求', (tester) async {
    final verify = FakeVerifyApi()..verifyInfoError = authenticationError();
    await tester.pumpWidget(MaterialApp(home: _page(verify: verify)));

    // 空事件号：本地拦截，不发请求。
    await tester.tap(find.text('查询'));
    await tester.pump();
    await tester.pump();
    expect(verify.verifyInfoCalls, 0);
    expect(find.text('查询失败：请输入验证事件号'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '验证事件号'), 'event-1');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();

    expect(verify.verifyInfoCalls, 1);
    expect(find.text('查询失败：请先登录'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('searchExt 未接线：只展示挑战信息，不显示提交入口', (tester) async {
    final verify = FakeVerifyApi()..verifyInfo = fakeVerifyConfig();
    await tester.pumpWidget(MaterialApp(home: _page(verify: verify)));

    await tester.enterText(find.widgetWithText(TextField, '验证事件号'), 'event-1');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();

    expect(find.text('验证提交通道未接线，仅展示挑战信息。'), findsOneWidget);
    expect(find.text('提交验证码'), findsNothing);
    expect(find.text('提交'), findsNothing);

    await _teardown(tester);
  });
}
