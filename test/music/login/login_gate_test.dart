// ignore_for_file: deprecated_member_use — 与 settings_login_test 同款说明。
/// 进入音乐时的全屏登录闸门测试（用户拍板：可跳过 / 未登录每次进入都弹）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_login_gate.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _FakeApi implements MusicApi {
  _FakeApi(this.identity);

  final KugouIdentity? identity;

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async => const MusicPage<MusicSong>(items: <MusicSong>[]);

  @override
  Future<KugouIdentity> ensureDevice() async =>
      identity ?? KugouIdentity.anonymous();

  @override
  Future<KugouIdentity?> currentIdentity() async => identity;
}

class _FakeAccountApi implements MusicAccountApi {
  @override
  Future<QrLoginSession> startQrLogin() async => QrLoginSession(
    key: 'KEY',
    imageDataUrl: 'data:image/png;base64,$_pngBase64',
  );

  @override
  Future<QrLoginStatus> pollQrLogin(String key) async =>
      const QrLoginStatus(state: QrLoginState.waiting);

  @override
  Future<KugouIdentity> loginWith(QrAuthorization authorization) async =>
      KugouIdentity.anonymous().withAccount(
        userId: authorization.userId,
        token: authorization.token,
      );

  @override
  Future<KugouIdentity> logout() async => KugouIdentity.anonymous();
}

Widget _gate({required MusicApi api, required MusicAccountApi? account}) {
  return MaterialApp(
    home: MusicLoginGate(
      api: api,
      account: account,
      pollInterval: const Duration(milliseconds: 300),
      child: const Scaffold(body: Center(child: Text('音乐主页'))),
    ),
  );
}

void main() {
  testWidgets('匿名进入音乐：全屏扫码页弹出，可跳过回到主页', (tester) async {
    await tester.pumpWidget(
      _gate(
        api: _FakeApi(KugouIdentity.anonymous().withDfid('dfid1234567890')),
        account: _FakeAccountApi(),
      ),
    );
    await tester.pumpAndSettle();

    // 全屏登录页已 push（fullscreenDialog + 具名路由）。
    expect(find.text('登录酷狗账号'), findsOneWidget);
    expect(find.byKey(const Key('qr-login-skip')), findsOneWidget);
    expect(find.text('等待扫码'), findsOneWidget);
    expect(find.text('音乐主页'), findsNothing);

    await tester.tap(find.byKey(const Key('qr-login-skip')));
    await tester.pumpAndSettle();

    expect(find.text('登录酷狗账号'), findsNothing);
    expect(find.text('音乐主页'), findsOneWidget);
  });

  testWidgets('已登录进入音乐：直进主页，不弹登录页', (tester) async {
    final loggedIn = KugouIdentity.anonymous()
        .withDfid('dfid1234567890')
        .withAccount(userId: 42, token: 'tok');
    await tester.pumpWidget(
      _gate(api: _FakeApi(loggedIn), account: _FakeAccountApi()),
    );
    await tester.pumpAndSettle();

    expect(find.text('音乐主页'), findsOneWidget);
    expect(find.text('登录酷狗账号'), findsNothing);
  });

  testWidgets('account 未接线：纯透传，不弹登录页', (tester) async {
    await tester.pumpWidget(
      _gate(api: _FakeApi(KugouIdentity.anonymous()), account: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('音乐主页'), findsOneWidget);
    expect(find.text('登录酷狗账号'), findsNothing);
  });
}
