// ignore_for_file: deprecated_member_use — 与 music_module_test 同款说明。
/// 设置页登录区 widget 测试：扫码按钮、二维码渲染（两种 data URL）、状态文案、
/// 授权后回到设置页显示账号、退出登录恢复匿名。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_module_settings.dart';
import 'package:mimao/music/pages/qr_login_controller.dart';
import 'package:mimao/music/pages/qr_login_view.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _FakeApi implements MusicApi {
  _FakeApi(this.identity);

  KugouIdentity? identity;

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
  _FakeAccountApi({
    required this.imageDataUrl,
    this.states = const <QrLoginState>[QrLoginState.waiting],
  });

  final String imageDataUrl;
  List<QrLoginState> states;
  int polls = 0;

  @override
  Future<QrLoginSession> startQrLogin() async =>
      QrLoginSession(key: 'KEY', imageDataUrl: imageDataUrl);

  @override
  Future<QrLoginStatus> pollQrLogin(String key) async {
    final index = polls++;
    final state = index < states.length ? states[index] : states.last;
    return QrLoginStatus(
      state: state,
      authorization: state == QrLoginState.authorized
          ? const QrAuthorization(
              userId: 42,
              token: 'token-value',
              nickname: '小明',
              avatarUrl: '',
            )
          : null,
    );
  }

  @override
  Future<KugouIdentity> loginWith(QrAuthorization authorization) async {
    final identity = KugouIdentity.anonymous().withAccount(
      userId: authorization.userId,
      token: authorization.token,
      nickname: authorization.nickname,
      avatarUrl: authorization.avatarUrl,
    );
    return identity;
  }

  @override
  Future<KugouIdentity> logout() async =>
      KugouIdentity.anonymous().withDfid('dfid1234567890');
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: <Widget>[child])),
);

void main() {
  testWidgets('未登录显示二维码入口；点击后渲染二维码并随轮询更新状态', (tester) async {
    final api = _FakeApi(KugouIdentity.anonymous().withDfid('dfid1234567890'));
    final account = _FakeAccountApi(
      imageDataUrl: 'data:image/png;base64,$_pngBase64',
      states: const <QrLoginState>[QrLoginState.scanned],
    );
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: api,
          account: account,
          pollInterval: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前：匿名设备 · 未登录'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);

    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('扫码登录'), findsWidgets);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('等待扫码'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已扫码，请在手机上确认'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('授权成功：对话框关闭、设置页显示昵称/ID；退出登录恢复匿名', (tester) async {
    final api = _FakeApi(KugouIdentity.anonymous().withDfid('dfid1234567890'));
    final account = _FakeAccountApi(
      imageDataUrl: 'data:image/png;base64,$_pngBase64',
      states: const <QrLoginState>[QrLoginState.authorized],
    );
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: api,
          account: account,
          pollInterval: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('小明'), findsOneWidget);
    expect(find.textContaining('用户 ID：42'), findsWidgets);
    expect(find.text('退出登录'), findsOneWidget);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(find.text('当前：匿名设备 · 未登录'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('已退出，仍可匿名试听'), findsOneWidget);
  });

  testWidgets('纯 base64（无 data: 前缀）也能渲染二维码', (tester) async {
    final api = _FakeApi(KugouIdentity.anonymous().withDfid('dfid1234567890'));
    final account = _FakeAccountApi(imageDataUrl: _pngBase64);
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: api,
          account: account,
          pollInterval: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Image), findsWidgets);
    expect(find.text('二维码图片解析失败，请刷新'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('QrCodeImage 同一 dataUrl 多次重建复用同一 bytes 引用（不闪烁）', (tester) async {
    // Flutter 的 MemoryImage 用 bytes 引用相等判断缓存命中；轮询 setState
    // 重建时若每次重新 base64 解码生成新 Uint8List，缓存不命中 → 二维码闪烁。
    // 这里把渲染出的 Image provider 提出来，断言同一 dataUrl 下引用稳定。
    const url = 'data:image/png;base64,$_pngBase64';
    await tester.pumpWidget(
      MaterialApp(
        home: QrCodeImage(dataUrl: url, phase: QrLoginPhase.waiting),
      ),
    );

    final first = tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    // 模拟轮询导致的状态重建：不同 phase、同一 dataUrl。
    await tester.pumpWidget(
      MaterialApp(
        home: QrCodeImage(dataUrl: url, phase: QrLoginPhase.scanned),
      ),
    );
    final second =
        tester.widget<Image>(find.byType(Image)).image as MemoryImage;

    expect(identical(first.bytes, second.bytes), isTrue);

    // 真正换新码（刷新）时必须重新解码、换 bytes 引用。
    const otherUrl =
        'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/nK8AAAAASUVORK5CYII=';
    await tester.pumpWidget(
      MaterialApp(
        home: QrCodeImage(dataUrl: otherUrl, phase: QrLoginPhase.waiting),
      ),
    );
    final refreshed =
        tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    expect(identical(first.bytes, refreshed.bytes), isFalse);
  });

  testWidgets('未登录与二维码对话框都不回显 token/t1 文案', (tester) async {
    final api = _FakeApi(KugouIdentity.anonymous().withDfid('dfid1234567890'));
    final account = _FakeAccountApi(
      imageDataUrl: 'data:image/png;base64,$_pngBase64',
    );
    await tester.pumpWidget(
      _wrap(
        MusicModuleSettings(
          api: api,
          account: account,
          pollInterval: const Duration(seconds: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('token'), findsNothing);
    expect(find.textContaining('t1'), findsNothing);

    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('token'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
