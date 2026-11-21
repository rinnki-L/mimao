// ignore_for_file: deprecated_member_use — 与 fakes.dart 同款说明。
/// 登录闸门 L5 扩展 widget 测试：auth/verify/searchExt 齐备时全屏扫码页
/// 提供「使用其他方式登录」（进方法页，登录成功关闭闸门；取消则恢复扫码轮询）；
/// 缺失时保持现状（原始 QrLoginScreen，无扩展按钮）。
///
/// 扫码轮询用长间隔（不触发）或显式 pump 步进；结束前卸载页面树，
/// 无 pending timer。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/pages/music_login_gate.dart';

import 'fakes.dart';

const Duration _longInterval = Duration(hours: 1);

Widget _gate({
  required FakeMusicApi api,
  required FakeAccountApi account,
  Duration pollInterval = _longInterval,
  FakeAuthApi? auth,
  FakeVerifyApi? verify,
  FakeSearchExtApi? searchExt,
}) => MaterialApp(
  home: MusicLoginGate(
    api: api,
    account: account,
    auth: auth,
    verify: verify,
    searchExt: searchExt,
    pollInterval: pollInterval,
    child: const Scaffold(body: Center(child: Text('音乐主页'))),
  ),
);

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('扩展齐备：闸门登录页有「使用其他方式登录」；方法页登录成功关闭闸门', (tester) async {
    final auth = FakeAuthApi()..cellphoneResults.add(cellphoneAuthorized());
    await tester.pumpWidget(
      _gate(
        api: FakeMusicApi(KugouIdentity.anonymous()),
        account: FakeAccountApi(),
        auth: auth,
        verify: FakeVerifyApi(),
        searchExt: FakeSearchExtApi(),
      ),
    );
    await tester.pumpAndSettle();

    // 闸门登录页已弹出：扫码态 + 扩展按钮。
    expect(find.text('登录酷狗账号'), findsOneWidget);
    expect(find.byKey(const Key('gate-open-methods')), findsOneWidget);
    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.text('音乐主页'), findsNothing);

    await tester.tap(find.byKey(const Key('gate-open-methods')));
    await tester.pump();
    await tester.pumpAndSettle();

    // 方法页已打开（默认手机号 tab）。
    expect(find.text('发送验证码'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '手机号'),
      '13800001234',
    );
    await tester.enterText(find.widgetWithText(TextField, '验证码'), '123456');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    // 方法页 pop(true) → 闸门页 pop(true) → 回到音乐主页。
    expect(find.text('音乐主页'), findsOneWidget);
    expect(find.text('登录酷狗账号'), findsNothing);
    expect(find.text('发送验证码'), findsNothing);
    expect(auth.cellphoneQueries.single.userId, isNull);
  });

  testWidgets('方法页取消返回：闸门页恢复扫码轮询', (tester) async {
    await tester.pumpWidget(
      _gate(
        api: FakeMusicApi(KugouIdentity.anonymous()),
        account: FakeAccountApi(),
        auth: FakeAuthApi(),
        verify: FakeVerifyApi(),
        searchExt: FakeSearchExtApi(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('gate-open-methods')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('发送验证码'), findsOneWidget);

    // 返回（未登录成功）→ 恢复扫码轮询并重新取码。
    await tester.pageBack();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('登录酷狗账号'), findsOneWidget);
    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.text('音乐主页'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('扩展齐备时扫码授权线仍然工作：轮询到授权关闭闸门', (tester) async {
    await tester.pumpWidget(
      _gate(
        api: FakeMusicApi(KugouIdentity.anonymous()),
        account: FakeAccountApi(
          states: <QrLoginState>[QrLoginState.waiting, QrLoginState.authorized],
        ),
        auth: FakeAuthApi(),
        verify: FakeVerifyApi(),
        searchExt: FakeSearchExtApi(),
        pollInterval: const Duration(milliseconds: 300),
      ),
    );
    await tester.pump();
    await tester.pump();
    // 取码完成（进入等待），第一次轮询在 300ms 后。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400)); // 第 2 次轮询：授权
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('音乐主页'), findsOneWidget);
    expect(find.text('登录酷狗账号'), findsNothing);
  });

  testWidgets('扩展缺失：保持现状（原始扫码页，无「使用其他方式登录」）', (tester) async {
    await tester.pumpWidget(
      _gate(
        api: FakeMusicApi(KugouIdentity.anonymous()),
        account: FakeAccountApi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录酷狗账号'), findsOneWidget);
    expect(find.byKey(const Key('gate-open-methods')), findsNothing);
    // 既有跳过入口仍在。
    expect(find.byKey(const Key('qr-login-skip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('qr-login-skip')));
    await tester.pumpAndSettle();
    expect(find.text('音乐主页'), findsOneWidget);
  });
}
