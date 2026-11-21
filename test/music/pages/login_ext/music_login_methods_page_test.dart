// ignore_for_file: deprecated_member_use — 与 fakes.dart 同款说明。
/// 更多登录方式页 widget 测试：手机号验证码（发码/倒计时/候选重试/错误重试）、
/// QQ 与微信扫码轮询状态流转（含过期刷新、两步登录）、设备列表与踢出。
///
/// 全部用 fake API + 注入短间隔/短倒计时；结束前先卸载页面树，
/// 保证无 pending timer（dispose 取消轮询与倒计时）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';
import 'package:mimao/music/pages/music_login_methods_page.dart';

import 'fakes.dart';

/// push 页面的宿主：点「打开」进入，记录 pop 返回值。
class _PushResult {
  bool? value;
}

Future<_PushResult> _pumpHost(WidgetTester tester, Widget page) async {
  final result = _PushResult();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final popped = await Navigator.of(
                  context,
                ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page));
                result.value = popped;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pump();
  // 等路由转场完成再交互（初始 tab 是手机号，无轮询定时器，可安全 settle）。
  await tester.pumpAndSettle();
  return result;
}

/// 卸载页面树：State.dispose 同步执行，轮询/倒计时全部取消。
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

const MusicQqQrCheckResult _qqWaiting = MusicQqQrCheckResult(
  state: MusicQqQrCheckResult.stateWaiting,
);
const MusicQqQrCheckResult _qqScanned = MusicQqQrCheckResult(
  state: MusicQqQrCheckResult.stateScanned,
);
const MusicQqQrCheckResult _qqExpired = MusicQqQrCheckResult(
  state: MusicQqQrCheckResult.stateExpired,
);

const MusicWxCheckResult _wxWaiting = MusicWxCheckResult(
  state: MusicWxCheckResult.stateWaiting,
  code: null,
);
const MusicWxCheckResult _wxScanned = MusicWxCheckResult(
  state: MusicWxCheckResult.stateScanned,
  code: null,
);
const MusicWxCheckResult _wxExpired = MusicWxCheckResult(
  state: MusicWxCheckResult.stateExpired,
  code: null,
);

void main() {
  group('手机号 tab', () {
    testWidgets('发送验证码：调用 captchaSent 并进入倒计时，到 0 可重发', (tester) async {
      final auth = FakeAuthApi();
      final verify = FakeVerifyApi();
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: verify,
          codeCountdown: const Duration(seconds: 2),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13800001234',
      );
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      await tester.pump();

      expect(verify.captchaCalls, 1);
      expect(verify.captchaQueries.single.mobile, '13800001234');
      // 冷却中按钮禁用并显示剩余秒数。
      expect(find.text('重新发送（2 s）'), findsOneWidget);
      final TextButton coolingButton = tester.widget(
        find.widgetWithText(TextButton, '重新发送（2 s）'),
      );
      expect(coolingButton.onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('重新发送（1 s）'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      // 倒计时到 0：恢复「发送验证码」且可重发。
      expect(find.text('发送验证码'), findsOneWidget);
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      await tester.pump();
      expect(verify.captchaCalls, 2);

      await _teardown(tester);
    });

    testWidgets('手机号非法不发起请求；发码失败提示且不进入倒计时', (tester) async {
      final auth = FakeAuthApi();
      final verify = FakeVerifyApi()..captchaError = authenticationError();
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: verify,
          codeCountdown: const Duration(seconds: 60),
        ),
      );

      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      await tester.pump();
      expect(verify.captchaCalls, 0);
      expect(find.text('请输入正确的 11 位手机号码'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13800001234',
      );
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      await tester.pump();
      expect(verify.captchaCalls, 1);
      // 发码失败：提示服务端文案，按钮仍是「发送验证码」（未进入倒计时）。
      expect(find.text('请先登录'), findsOneWidget);
      expect(find.text('发送验证码'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('验证码登录成功 pop(true)，查询参数完整', (tester) async {
      final auth = FakeAuthApi()..cellphoneResults.add(cellphoneAuthorized());
      final verify = FakeVerifyApi();
      final result = await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: verify,
          codeCountdown: const Duration(seconds: 60),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13900001234',
      );
      await tester.enterText(find.widgetWithText(TextField, '验证码'), '123456');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
      expect(auth.cellphoneQueries.single.mobile, '13900001234');
      expect(auth.cellphoneQueries.single.code, '123456');
      expect(auth.cellphoneQueries.single.userId, isNull);
    });

    testWidgets('34175 多账号：展示候选列表，选中带 userId 重试', (tester) async {
      final auth = FakeAuthApi()
        ..cellphoneResults.add(
          MusicCellphoneLoginResult.selectAccount(cellphoneCandidates),
        )
        ..cellphoneResults.add(cellphoneAuthorized());
      final verify = FakeVerifyApi();
      final result = await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: verify,
          codeCountdown: const Duration(seconds: 60),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13800001234',
      );
      await tester.enterText(find.widgetWithText(TextField, '验证码'), '654321');
      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump();

      expect(find.text('该手机号下存在多个账号，请选择要登录的账号'), findsOneWidget);
      expect(find.text('账号一'), findsOneWidget);
      expect(find.text('账号二'), findsOneWidget);

      await tester.tap(find.text('账号二'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
      expect(auth.cellphoneQueries, hasLength(2));
      expect(auth.cellphoneQueries[1].userId, 1002);
      expect(auth.cellphoneQueries[1].mobile, '13800001234');
    });

    testWidgets('登录失败页内提示；清除错误后重试成功', (tester) async {
      final auth = FakeAuthApi()
        ..cellphoneError = const KugouApiException('business', '验证码错误')
        ..cellphoneResults.add(cellphoneAuthorized());
      final verify = FakeVerifyApi();
      final result = await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: verify,
          codeCountdown: const Duration(seconds: 60),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13800001234',
      );
      await tester.enterText(find.widgetWithText(TextField, '验证码'), '123456');
      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump();
      expect(find.text('登录失败：验证码错误'), findsOneWidget);
      expect(result.value, isNull);

      auth.cellphoneError = null;
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(result.value, isTrue);
      expect(find.text('登录失败：验证码错误'), findsNothing);
    });
  });

  group('QQ 扫码 tab', () {
    testWidgets('轮询状态流转：等待 → 已扫码 → 授权后 loginQq 并 pop(true)', (tester) async {
      final auth = FakeAuthApi()
        ..qqSession = fakeQqSession()
        ..qqCheckStates.addAll(<MusicQqQrCheckResult>[
          _qqWaiting,
          _qqScanned,
          MusicQqQrCheckResult(
            state: MusicQqQrCheckResult.stateProviderAuthorized,
            authorization: const MusicProviderAuthorization(
              openid: 'openid-qq',
              accessToken: 'access-token-qq',
            ),
          ),
        ]);
      final result = await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: FakeVerifyApi(),
          pollInterval: const Duration(seconds: 1),
        ),
      );

      await tester.tap(find.text('QQ扫码'));
      await tester.pumpAndSettle();

      expect(find.text('等待扫码'), findsOneWidget);
      // 二维码图片已渲染（fake 给的是合法 PNG data URL）。
      expect(find.byType(Image), findsOneWidget);
      expect(auth.qqCreateCalls, 1);

      await tester.pump(const Duration(seconds: 1)); // 第 1 次轮询：waiting
      await tester.pump(const Duration(seconds: 1)); // 第 2 次轮询：scanned
      expect(find.text('已扫码，请在手机上确认'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1)); // 第 3 次轮询：已授权
      await tester.pump();
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
      expect(auth.qqCheckCalls, 3);
      expect(auth.qqLoginCalls, 1);
      expect(auth.qqLogins.single.openid, 'openid-qq');
      expect(auth.qqLogins.single.accessToken, 'access-token-qq');
    });

    testWidgets('二维码过期：停止轮询展示刷新入口，刷新后重新取码轮询', (tester) async {
      final auth = FakeAuthApi()
        ..qqSession = fakeQqSession()
        ..qqCheckStates.add(_qqExpired);
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: FakeVerifyApi(),
          pollInterval: const Duration(seconds: 1),
        ),
      );

      await tester.tap(find.text('QQ扫码'));
      await tester.pumpAndSettle();
      expect(find.text('等待扫码'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1)); // 第 1 次轮询：expired
      expect(find.text('二维码已过期，点击刷新'), findsOneWidget);
      expect(find.text('刷新二维码'), findsOneWidget);
      final int pollsAfterExpired = auth.qqCheckCalls;

      await tester.pump(const Duration(seconds: 1));
      // 过期后轮询已停止，不再发起请求。
      expect(auth.qqCheckCalls, pollsAfterExpired);

      await tester.tap(find.text('刷新二维码'));
      await tester.pump();
      await tester.pump();
      expect(auth.qqCreateCalls, 2);
      expect(find.text('等待扫码'), findsOneWidget);

      // 状态队列已取空 → 轮询回 waiting，不再报过期。
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('等待扫码'), findsOneWidget);
      expect(find.text('二维码已过期，点击刷新'), findsNothing);

      await _teardown(tester);
    });

    testWidgets('取码失败展示错误与刷新；恢复后重新取码', (tester) async {
      final auth = FakeAuthApi()
        ..qqCreateError = const KugouApiException('http', '登录服务暂时不可用');
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: FakeVerifyApi(),
          pollInterval: const Duration(seconds: 1),
        ),
      );

      await tester.tap(find.text('QQ扫码'));
      await tester.pumpAndSettle();

      expect(find.text('登录服务暂时不可用'), findsOneWidget);
      expect(find.text('刷新二维码'), findsOneWidget);

      auth
        ..qqCreateError = null
        ..qqSession = fakeQqSession();
      await tester.tap(find.text('刷新二维码'));
      await tester.pump();
      await tester.pump();

      expect(find.text('等待扫码'), findsOneWidget);
      expect(find.text('登录服务暂时不可用'), findsNothing);

      await _teardown(tester);
    });
  });

  group('微信扫码 tab', () {
    testWidgets('轮询 provider_code 后两步登录：authorize 换凭证 → finish 登录', (
      tester,
    ) async {
      final auth = FakeAuthApi()
        ..wxSession = fakeWxSession()
        ..wxCheckStates.addAll(<MusicWxCheckResult>[
          _wxWaiting,
          _wxScanned,
          const MusicWxCheckResult(
            state: MusicWxCheckResult.stateProviderCode,
            code: 'wx-code-1',
          ),
        ])
        ..openplatResults.addAll(<Object>[
          const MusicProviderAuthorization(
            openid: 'openid-wx',
            accessToken: 'access-token-wx',
          ),
          authorizedLogin(),
        ]);
      final result = await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: FakeVerifyApi(),
          pollInterval: const Duration(seconds: 1),
        ),
      );

      await tester.tap(find.text('微信扫码'));
      await tester.pumpAndSettle();

      expect(find.text('等待扫码'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(auth.wxCreateCalls, 1);

      await tester.pump(const Duration(seconds: 1)); // waiting
      await tester.pump(const Duration(seconds: 1)); // scanned
      expect(find.text('已扫码，请在手机上确认'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1)); // provider_code → 两步登录
      await tester.pump();
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
      expect(auth.wxCheckCalls, 3);
      expect(auth.openplatCalls, 2);
      // 第一步 authorize 用扫码授权码；第二步 finish 用换到的 openid/access_token。
      expect(auth.openplatQueries[0].code, 'wx-code-1');
      expect(auth.openplatQueries[0].authorization, isNull);
      expect(auth.openplatQueries[1].code, isNull);
      expect(auth.openplatQueries[1].authorization?.openid, 'openid-wx');
      expect(
        auth.openplatQueries[1].authorization?.accessToken,
        'access-token-wx',
      );
    });

    testWidgets('二维码过期：停止轮询、可刷新重新取码', (tester) async {
      final auth = FakeAuthApi()
        ..wxSession = fakeWxSession()
        ..wxCheckStates.add(_wxExpired);
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: FakeVerifyApi(),
          pollInterval: const Duration(seconds: 1),
        ),
      );

      await tester.tap(find.text('微信扫码'));
      await tester.pumpAndSettle();
      expect(find.text('等待扫码'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('二维码已过期，点击刷新'), findsOneWidget);
      final int pollsAfterExpired = auth.wxCheckCalls;

      await tester.pump(const Duration(seconds: 1));
      expect(auth.wxCheckCalls, pollsAfterExpired);

      await tester.tap(find.text('刷新二维码'));
      await tester.pump();
      await tester.pump();
      expect(auth.wxCreateCalls, 2);
      expect(find.text('等待扫码'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('两步登录失败：收口成页内错误并允许刷新重试', (tester) async {
      final auth = FakeAuthApi()
        ..wxSession = fakeWxSession()
        ..wxCheckStates.add(
          const MusicWxCheckResult(
            state: MusicWxCheckResult.stateProviderCode,
            code: 'wx-code-1',
          ),
        )
        ..openplatError = const KugouApiException('provider', '微信授权已失效，请重新扫码');
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(
          auth: auth,
          verify: FakeVerifyApi(),
          pollInterval: const Duration(seconds: 1),
        ),
      );

      await tester.tap(find.text('微信扫码'));
      await tester.pumpAndSettle();
      await tester.pump(
        const Duration(seconds: 1),
      ); // provider_code → authorize 失败
      await tester.pump();
      await tester.pump();

      expect(find.text('微信授权已失效，请重新扫码'), findsOneWidget);
      expect(find.text('刷新二维码'), findsOneWidget);
      expect(auth.openplatCalls, 1);

      await _teardown(tester);
    });
  });

  group('登录设备 tab', () {
    testWidgets('列表：当前设备只读，其它设备可移除；缺信息的设备不可移除', (tester) async {
      final auth = FakeAuthApi()
        ..devices = <MusicLoginDevice>[
          fakeDevice(id: 'MID-CURRENT', current: true, model: '本机设备'),
          fakeDevice(id: 'MID-OTHER', current: false, model: '其它设备'),
          fakeDevice(
            id: 'MID-NOINFO',
            current: false,
            model: '缺信息设备',
            activeAtSeconds: 0,
            appId: 0,
            clientVersion: 0,
          ),
        ];
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(auth: auth, verify: FakeVerifyApi()),
      );

      await tester.tap(find.text('登录设备'));
      await tester.pumpAndSettle();

      expect(find.text('本机设备'), findsOneWidget);
      expect(find.text('其它设备'), findsOneWidget);
      expect(find.text('缺信息设备'), findsOneWidget);
      expect(find.text('当前设备'), findsOneWidget);
      // 只有两台其它设备有「移除」按钮；缺 activeAt/appid/clientver 的禁用。
      final removeButtons = tester
          .widgetList<TextButton>(find.widgetWithText(TextButton, '移除'))
          .toList();
      expect(removeButtons, hasLength(2));
      expect(removeButtons[0].onPressed, isNotNull);
      expect(removeButtons[1].onPressed, isNull);
    });

    testWidgets('踢出：确认对话框 → loginDeviceKick 参数来自设备行 → 成功后刷新', (tester) async {
      final auth = FakeAuthApi()
        ..devices = <MusicLoginDevice>[
          fakeDevice(id: 'MID-CURRENT', current: true, model: '本机设备'),
          fakeDevice(id: 'MID-OTHER', current: false, model: '其它设备'),
        ];
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(auth: auth, verify: FakeVerifyApi()),
      );

      await tester.tap(find.text('登录设备'));
      await tester.pumpAndSettle();
      expect(auth.deviceCalls, 1);

      await tester.tap(find.text('移除'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('确定移除「其它设备」吗？移除后该设备需要重新登录。'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('移除'),
        ),
      );
      await tester.pumpAndSettle();

      expect(auth.kickCalls, 1);
      expect(auth.kickQueries.single.targetMid, 'MID-OTHER');
      expect(auth.kickQueries.single.activeAtSeconds, 1760000000);
      expect(auth.kickQueries.single.appId, 100);
      expect(auth.kickQueries.single.clientVersion, 11440);
      expect(auth.kickQueries.single.transportFingerprint, 'mt-fingerprint');
      expect(find.text('设备已移除'), findsOneWidget);
      // 成功后刷新列表。
      expect(auth.deviceCalls, 2);
    });

    testWidgets('踢出失败：SnackBar 提示服务端文案，不刷新列表', (tester) async {
      final auth = FakeAuthApi()
        ..devices = <MusicLoginDevice>[
          fakeDevice(id: 'MID-OTHER', current: false, model: '其它设备'),
        ]
        ..kickError = const KugouApiException('business', '设备会话已失效');
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(auth: auth, verify: FakeVerifyApi()),
      );

      await tester.tap(find.text('登录设备'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('移除'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设备会话已失效'), findsOneWidget);
      expect(auth.kickCalls, 1);
      expect(auth.deviceCalls, 1);
    });

    testWidgets('未登录：设备列表报认证错误并给登录引导，重试后恢复', (tester) async {
      final auth = FakeAuthApi()..deviceError = authenticationError();
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(auth: auth, verify: FakeVerifyApi()),
      );

      await tester.tap(find.text('登录设备'));
      await tester.pumpAndSettle();

      expect(find.text('请先登录酷狗账号，登录后即可管理登录设备'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      auth
        ..deviceError = null
        ..devices = <MusicLoginDevice>[
          fakeDevice(id: 'MID-OTHER', current: false, model: '其它设备'),
        ];
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('其它设备'), findsOneWidget);
    });

    testWidgets('空设备列表展示空态', (tester) async {
      final auth = FakeAuthApi();
      await _pumpHost(
        tester,
        MusicLoginMethodsPage(auth: auth, verify: FakeVerifyApi()),
      );

      await tester.tap(find.text('登录设备'));
      await tester.pumpAndSettle();

      expect(find.text('暂无登录设备'), findsOneWidget);
    });
  });
}
