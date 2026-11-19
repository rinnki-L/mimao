/// 账号门面测试：合并/落盘、非法凭证不写盘、登出幂等、生产门面接线。
/// 身份仓库走临时目录（无插件），端点走捕获型 adapter（无真实网络）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/music_identity_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

class _NoopAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final body = options.path.contains('get_userinfo_qrcode')
        ? '{"status":1,"error_code":0,"data":{"status":1}}'
        : '{"status":1,"error_code":0,'
              '"data":{"qrcode":"K","qrcode_img":"I"}}';
    return ResponseBody.fromBytes(utf8.encode(body), 200);
  }

  @override
  void close({bool force = false}) {}
}

class _RecordingIdentityApi implements MusicIdentityApi {
  _RecordingIdentityApi(this.identity);

  final KugouIdentity identity;
  int ensureCalls = 0;
  KugouIdentity? saved;

  @override
  Future<KugouIdentity> ensureDevice() async {
    ensureCalls++;
    return identity;
  }

  @override
  Future<KugouIdentity?> currentIdentity() async => saved ?? identity;

  @override
  Future<void> saveIdentity(KugouIdentity identity) async {
    saved = identity;
  }
}

/// currentIdentity 恒 null 的身份门面（未引导设备）。
class _NullIdentityApi implements MusicIdentityApi {
  @override
  Future<KugouIdentity> ensureDevice() async => const KugouIdentity.empty();

  @override
  Future<KugouIdentity?> currentIdentity() async => null;

  @override
  Future<void> saveIdentity(KugouIdentity identity) async {}
}

QrAuthorization authWith({
  int userId = 42,
  String token = 'token-value',
  String nickname = '',
}) => QrAuthorization(userId: userId, token: token, nickname: nickname);

void main() {
  late Directory dir;
  late KugouIdentityStore store;
  late KugouIdentity device;
  late KugouClient client;
  late KugouMusicApi api;
  late KugouAccountApi account;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mimao_music_account_');
    store = KugouIdentityStore(dir);
    device = KugouIdentity.anonymous().withDfid('dfid-device-1');
    await store.save(device);
    client = KugouClient(dio: Dio()..httpClientAdapter = _NoopAdapter());
    api = KugouMusicApi(
      client: client,
      identityStoreFactory: () async => store,
    );
    account = KugouAccountApi(client: client, identityApi: api);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('loginWith：设备字段逐项保留，账号字段合并并落盘可读回', () async {
    final auth = authWith(token: 'token-42', nickname: '小明');
    final identity = await account.loginWith(
      QrAuthorization(
        userId: auth.userId,
        token: auth.token,
        nickname: auth.nickname,
        avatarUrl: 'https://img/avatar.png',
      ),
    );

    expect(identity.userId, auth.userId);
    expect(identity.token, auth.token);
    expect(identity.t1, isEmpty);
    expect(identity.nickname, auth.nickname);
    expect(identity.avatarUrl, 'https://img/avatar.png');
    expect(identity.guid, device.guid);
    expect(identity.mid, device.mid);
    expect(identity.dfid, device.dfid);
    expect(identity.uuid, device.uuid);
    expect(identity.mac, device.mac);
    expect(identity.deviceName, device.deviceName);
    expect(identity.renderFingerprint, device.renderFingerprint);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.userId, auth.userId);
    expect(loaded.token, auth.token);
    expect(loaded.nickname, auth.nickname);
    expect(loaded.avatarUrl, 'https://img/avatar.png');
    expect(loaded.mid, device.mid);
    expect(loaded.dfid, device.dfid);

    // 门面缓存同步更新：下一次搜索会带登录态（不必重读盘）。
    final current = await api.currentIdentity();
    expect(current!.hasAccount, isTrue);
    expect(current.userId, auth.userId);
  });

  test('loginWith：userId=0 或空 token → input，且不写盘', () async {
    for (final auth in <QrAuthorization>[
      authWith(userId: 0, token: 'tok'),
      authWith(userId: 42, token: ''),
    ]) {
      try {
        await account.loginWith(auth);
        fail('应当抛 input');
      } on KugouApiException catch (error) {
        expect(error.kind, 'input');
      }
    }
    final loaded = await store.load();
    expect(loaded!.userId, 0);
    expect(loaded.token, isEmpty);
  });

  test('logout：清账号保留设备，重复调用幂等且匿名身份可用', () async {
    await account.loginWith(authWith(nickname: '小明'));

    final anonymous = await account.logout();
    expect(anonymous.hasAccount, isFalse);
    expect(anonymous.userId, 0);
    expect(anonymous.token, isEmpty);
    expect(anonymous.t1, isEmpty);
    expect(anonymous.nickname, isEmpty);
    expect(anonymous.avatarUrl, isEmpty);
    expect(anonymous.guid, device.guid);
    expect(anonymous.mid, device.mid);
    expect(anonymous.dfid, device.dfid);
    expect(anonymous.isUsable, isTrue);

    final loaded = await store.load();
    expect(loaded!.hasAccount, isFalse);
    expect(loaded.nickname, isEmpty);

    // 再登出一次：幂等，不抛也不改变身份。
    final again = await account.logout();
    expect(again.mid, device.mid);
    expect((await api.currentIdentity())!.hasAccount, isFalse);
  });

  test('start/poll 先 ensureDevice 再匿名请求', () async {
    final recording = _RecordingIdentityApi(
      device.withAccount(userId: 9, token: 'old-token'),
    );
    final adapter = _NoopAdapter();
    final recorded = KugouAccountApi(
      client: KugouClient(dio: Dio()..httpClientAdapter = adapter),
      identityApi: recording,
    );

    await recorded.startQrLogin();
    await recorded.pollQrLogin('KEY');
    expect(recording.ensureCalls, 2);
    expect(adapter.calls, 2);
  });

  test('loginWith：设备未引导（currentIdentity null）→ input', () async {
    final uninitialized = KugouAccountApi(
      client: KugouClient(dio: Dio()..httpClientAdapter = _NoopAdapter()),
      identityApi: _NullIdentityApi(),
    );
    try {
      await uninitialized.loginWith(authWith());
      fail('应当抛 input');
    } on KugouApiException catch (error) {
      expect(error.kind, 'input');
      expect(error.message, '设备身份未引导');
    }
  });
}
