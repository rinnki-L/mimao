// ignore_for_file: deprecated_member_use — 与 fakes.dart 同款说明。
/// 设置页 L5 扩展 widget 测试：扩展入口的出现条件（auth/verify/settings 齐
/// 备才显示）、入口 push 对应页面、「听歌上报」开关的读盘初值/写入/失败回滚。
///
/// 既有登录测试（test/music/login/settings_login_test.dart）继续覆盖扫码线。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/pages/music_module_settings.dart';

import 'fakes.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: <Widget>[child])),
);

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('auth/verify/settings 都未接线：不显示任何 L5 入口', (tester) async {
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), account: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多登录方式'), findsNothing);
    expect(find.text('安全验证'), findsNothing);
    expect(find.text('听歌上报'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('扩展入口出现条件：verify 才有安全验证；auth+verify 才有更多登录方式', (tester) async {
    // 只有 verify（auth 缺失）：只显示「安全验证」。
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(api: FakeMusicApi(null), verify: FakeVerifyApi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多登录方式'), findsNothing);
    expect(find.text('安全验证'), findsOneWidget);
    expect(find.text('听歌上报'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('「更多登录方式」push 方法页（手机号/QQ/微信/设备 tab）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: FakeMusicApi(null),
          auth: FakeAuthApi(),
          verify: FakeVerifyApi(),
          searchExt: FakeSearchExtApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多登录方式'), findsOneWidget);
    await tester.tap(find.text('更多登录方式'));
    await tester.pump();
    await tester.pumpAndSettle();

    // 方法页已打开：默认手机号 tab + 四个 tab 标签。
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.text('QQ扫码'), findsOneWidget);
    expect(find.text('微信扫码'), findsOneWidget);
    expect(find.text('登录设备'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('「安全验证」push 安全验证页', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: FakeMusicApi(null),
          auth: FakeAuthApi(),
          verify: FakeVerifyApi(),
          searchExt: FakeSearchExtApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('安全验证'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('验证事件号'), findsOneWidget);
    expect(find.text('查询'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('「听歌上报」开关：ensureLoaded 后刷新初值；切换写入并回显', (tester) async {
    final settings = FakeMusicSettings(initial: true);
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    expect(settings.ensureLoadedCalls, 1);
    expect(find.text('听歌上报'), findsOneWidget);
    // 默认开启。
    final Switch initialSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(initialSwitch.value, isTrue);

    // 关闭 → 写入 false 并回显。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(settings.savedValues, <bool>[false]);
    final Switch toggledSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(toggledSwitch.value, isFalse);

    await _teardown(tester);
  });

  testWidgets('「听歌上报」写入失败：回滚开关并提示', (tester) async {
    final settings = FakeMusicSettings(initial: true)
      ..saveError = StateError('disk');
    await tester.pumpWidget(
      _wrap(MusicModuleSettings(api: FakeMusicApi(null), settings: settings)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // 失败：开关回滚为 true，页内给出保存失败提示。
    expect(settings.savedValues, isEmpty);
    final Switch rolledBack = tester.widget<Switch>(find.byType(Switch));
    expect(rolledBack.value, isTrue);
    expect(find.text('听歌上报设置保存失败'), findsOneWidget);

    await _teardown(tester);
  });
}
