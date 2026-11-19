/// 轮询控制器测试：状态机时序、停表、错误保留与重试、无自动启动。
/// 用 testWidgets 的假时钟推进定时器（不引额外依赖，Dispose 后无 pending timer）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/pages/qr_login_controller.dart';

class _FakeAccountApi implements MusicAccountApi {
  _FakeAccountApi({
    this.states = const <QrLoginState>[QrLoginState.waiting],
    this.session = const QrLoginSession(
      key: 'KEY',
      imageDataUrl: 'data:image/png;base64,AAAA',
    ),
  });

  List<QrLoginState> states;
  QrLoginSession session;
  Object? startError;
  Object? pollError;

  int starts = 0;
  int polls = 0;
  int logins = 0;
  int logouts = 0;

  @override
  Future<QrLoginSession> startQrLogin() async {
    starts++;
    final error = startError;
    if (error != null) throw error;
    return session;
  }

  @override
  Future<QrLoginStatus> pollQrLogin(String key) async {
    polls++;
    final error = pollError;
    if (error != null) {
      pollError = null;
      throw error;
    }
    final index = polls - 1;
    final state = index < states.length ? states[index] : states.last;
    return QrLoginStatus(
      state: state,
      authorization: state == QrLoginState.authorized
          ? const QrAuthorization(
              userId: 42,
              token: 'token-value',
              nickname: '小明',
            )
          : null,
    );
  }

  @override
  Future<KugouIdentity> loginWith(QrAuthorization authorization) async {
    logins++;
    return KugouIdentity.anonymous().withAccount(
      userId: authorization.userId,
      token: authorization.token,
      nickname: authorization.nickname,
      avatarUrl: authorization.avatarUrl,
    );
  }

  @override
  Future<KugouIdentity> logout() async {
    logouts++;
    return KugouIdentity.anonymous();
  }
}

void main() {
  const interval = Duration(seconds: 2);

  testWidgets('waiting → scanned → authorized：3 次轮询后停表且只登录一次', (tester) async {
    final api = _FakeAccountApi(
      states: const <QrLoginState>[
        QrLoginState.waiting,
        QrLoginState.scanned,
        QrLoginState.authorized,
      ],
    );
    final controller = QrLoginController(account: api, pollInterval: interval);
    addTearDown(controller.dispose);

    controller.start();
    await tester.pump();
    expect(controller.phase, QrLoginPhase.waiting);
    expect(api.starts, 1);
    expect(api.polls, 0);

    await tester.pump(interval);
    expect(api.polls, 1);
    expect(controller.phase, QrLoginPhase.waiting);

    await tester.pump(interval);
    expect(api.polls, 2);
    expect(controller.phase, QrLoginPhase.scanned);

    await tester.pump(interval);
    expect(api.polls, 3);
    expect(api.logins, 1);
    expect(controller.phase, QrLoginPhase.authorized);
    expect(controller.identity!.userId, 42);
    expect(controller.identity!.nickname, '小明');

    // 已停表：再推进 10 秒也不会有第 4 次轮询。
    await tester.pump(const Duration(seconds: 10));
    expect(api.polls, 3);
    expect(api.logins, 1);
  });

  testWidgets('expired 停表；refresh() 重新取码并从 waiting 开始', (tester) async {
    final api = _FakeAccountApi(
      states: const <QrLoginState>[QrLoginState.expired],
    );
    final controller = QrLoginController(account: api, pollInterval: interval);
    addTearDown(controller.dispose);

    controller.start();
    await tester.pump();
    await tester.pump(interval);
    expect(controller.phase, QrLoginPhase.expired);
    expect(api.polls, 1);

    await tester.pump(const Duration(seconds: 10));
    expect(api.polls, 1, reason: '过期后不再轮询');

    controller.refresh();
    await tester.pump();
    expect(api.starts, 2);
    expect(controller.phase, QrLoginPhase.waiting);
    await tester.pump(interval);
    expect(api.polls, 2);
    expect(controller.phase, QrLoginPhase.expired);
  });

  testWidgets('cancel() 后无 pending timer，也不再发请求', (tester) async {
    final api = _FakeAccountApi(
      states: const <QrLoginState>[QrLoginState.waiting],
    );
    final controller = QrLoginController(account: api, pollInterval: interval);

    controller.start();
    await tester.pump();
    await tester.pump(interval);
    expect(api.polls, 1);

    controller.cancel();
    expect(controller.isActive, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(api.polls, 1);
    // 测试结束时若仍有定时器，flutter_test 会直接报 pending timer。
    controller.dispose();
  });

  testWidgets('dispose() 停表；构造后不自动 start', (tester) async {
    final api = _FakeAccountApi();
    final controller = QrLoginController(account: api, pollInterval: interval);

    // 构造后静置 5 秒：既没有取码也没有轮询。
    await tester.pump(const Duration(seconds: 5));
    expect(api.starts, 0);
    expect(api.polls, 0);
    expect(controller.phase, QrLoginPhase.idle);

    controller.start();
    await tester.pump();
    await tester.pump(interval);
    expect(api.polls, 1);

    controller.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(api.polls, 1);
  });

  testWidgets('网络异常一次 → failed 保留文案；refresh 可恢复', (tester) async {
    final api = _FakeAccountApi(
      states: const <QrLoginState>[QrLoginState.scanned],
    )..pollError = StateError('网络超时');
    final controller = QrLoginController(account: api, pollInterval: interval);
    addTearDown(controller.dispose);

    controller.start();
    await tester.pump();
    await tester.pump(interval);
    expect(controller.phase, QrLoginPhase.failed);
    expect(controller.error, contains('网络超时'));

    // 失败已停表。
    await tester.pump(const Duration(seconds: 10));
    expect(api.polls, 1);

    controller.refresh();
    await tester.pump();
    expect(controller.phase, QrLoginPhase.waiting);
    await tester.pump(interval);
    expect(controller.phase, QrLoginPhase.scanned);
  });

  testWidgets('取码返回空 key/空图 → failed「二维码获取失败，请刷新」', (tester) async {
    final api = _FakeAccountApi(
      session: const QrLoginSession(key: '  ', imageDataUrl: 'x'),
    );
    final controller = QrLoginController(account: api, pollInterval: interval);
    addTearDown(controller.dispose);

    controller.start();
    await tester.pump();
    expect(controller.phase, QrLoginPhase.failed);
    expect(controller.error, '二维码获取失败，请刷新');
    await tester.pump(const Duration(seconds: 10));
    expect(api.polls, 0);
  });

  testWidgets('取码网络异常 → failed 且可重试；onChanged 被通知', (tester) async {
    final api = _FakeAccountApi()..startError = StateError('超时');
    var changes = 0;
    final controller = QrLoginController(
      account: api,
      pollInterval: interval,
      onChanged: () => changes++,
    );
    addTearDown(controller.dispose);

    controller.start();
    await tester.pump();
    expect(controller.phase, QrLoginPhase.failed);
    expect(controller.error, contains('超时'));
    expect(changes, greaterThanOrEqualTo(2));

    api.startError = null;
    controller.refresh();
    await tester.pump();
    expect(controller.phase, QrLoginPhase.waiting);
  });

  test('decodeQrImageData：data URL 前缀与纯 base64 都接受，坏输入返回 null', () {
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
        'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    expect(decodeQrImageData('data:image/png;base64,$pngBase64'), isNotNull);
    expect(decodeQrImageData(pngBase64), isNotNull);
    expect(decodeQrImageData(''), isNull);
    expect(decodeQrImageData('data:image/png;base64'), isNull);
    expect(decodeQrImageData('!!not base64!!'), isNull);
  });
}
