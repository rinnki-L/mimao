/// KugouMusicApi 门面测试：设备引导（生成→注册→落盘）、缓存复用、
/// currentIdentity 只读语义；注册函数注入假实现，全程无真网络。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/register_dev.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';

/// 假注册函数：按调用序返回预置结果，记录调用。
class _FakeRegistrar {
  _FakeRegistrar({this.error});

  final Object? error;
  int calls = 0;

  Future<RegisteredDevice> call(
    KugouClient client,
    KugouIdentity identity,
  ) async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return const RegisteredDevice(dfid: 'registeredDfid');
  }
}

/// 假搜索实现：直接实现 MusicApi（不经客户端）。
class _FakeSearchApi implements MusicApi {
  int calls = 0;

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    calls++;
    return MusicPage<MusicSong>(
      page: page,
      pageSize: pageSize,
      total: 1,
      items: <MusicSong>[
        MusicSong(
          id: '1',
          hash: 'h',
          title: keyword,
          artists: const <MusicArtistRef>[],
          albumId: '',
          albumTitle: '',
          coverUrl: '',
        ),
      ],
    );
  }

  @override
  Future<KugouIdentity> ensureDevice() async => const KugouIdentity.empty();

  @override
  Future<KugouIdentity?> currentIdentity() async => null;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mimao_music_api_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  KugouMusicApi buildApi({_FakeRegistrar? registrar}) => KugouMusicApi(
    client: KugouClient(),
    identityStoreFactory: () async => KugouIdentityStore(tempDir),
    register: registrar?.call,
  );

  test('ensureDevice：首次生成匿名身份并注册 dfid，逐步落盘', () async {
    final registrar = _FakeRegistrar();
    final api = buildApi(registrar: registrar);

    final identity = await api.ensureDevice();
    expect(identity.guid, isNotEmpty);
    expect(identity.mid, kugouCalculateMid(identity.guid));
    expect(identity.dfid, 'registeredDfid');
    expect(registrar.calls, 1);

    final stored = await KugouIdentityStore(tempDir).load();
    expect(stored!.dfid, 'registeredDfid');
    expect(stored.guid, identity.guid);
  });

  test('ensureDevice：已有身份不再注册（幂等）', () async {
    final registrar = _FakeRegistrar();
    final api = buildApi(registrar: registrar);
    await api.ensureDevice();
    await api.ensureDevice();
    await api.ensureDevice();
    expect(registrar.calls, 1, reason: 'dfid 已注册，不再发起注册');
  });

  test('ensureDevice：注册失败原样抛出，下次调用重试', () async {
    final registrar = _FakeRegistrar(error: StateError('网络不可达'));
    final api = buildApi(registrar: registrar);

    await expectLater(api.ensureDevice(), throwsA(isA<StateError>()));
    expect(registrar.calls, 1);

    // 换成可用注册函数后成功（身份已落盘，注册重试）。
    final recovered = buildApi(registrar: _FakeRegistrar());
    final identity = await recovered.ensureDevice();
    expect(identity.dfid, 'registeredDfid');
  });

  test('注册失败的错误不吞身份：身份文件仍在，可重试', () async {
    final failing = buildApi(registrar: _FakeRegistrar(error: StateError('x')));
    await expectLater(failing.ensureDevice(), throwsA(isA<StateError>()));
    final stored = await KugouIdentityStore(tempDir).load();
    // 匿名身份已落盘（注册前保存），dfid 还是占位 '-'。
    expect(stored!.guid, isNotEmpty);
    expect(stored.dfid, '-');
  });

  test('currentIdentity：只读不注册；未引导返回 null', () async {
    final registrar = _FakeRegistrar();
    final api = buildApi(registrar: registrar);

    expect(await api.currentIdentity(), isNull);
    expect(registrar.calls, 0, reason: '只读身份不发网络');

    await api.ensureDevice();
    final identity = await api.currentIdentity();
    expect(identity!.dfid, 'registeredDfid');
  });

  test('身份仓库损坏 → 重启后（新实例）重新引导（不崩）', () async {
    final registrar = _FakeRegistrar();
    final api = buildApi(registrar: registrar);
    await api.ensureDevice();

    // 模拟身份文件损坏（内存缓存在实例内，重启后的新实例才重读盘）。
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}music_identity.json',
    );
    await file.writeAsString('{ broken');

    final restartedRegistrar = _FakeRegistrar();
    final restarted = buildApi(registrar: restartedRegistrar);
    final identity = await restarted.ensureDevice();
    expect(restartedRegistrar.calls, 1, reason: '重新引导 → 重新注册');
    expect(identity.needsDeviceRegistration, isFalse);
  });

  test('MusicApi 接口缝：页面/Store 可整体换假实现', () async {
    final fake = _FakeSearchApi();
    final page = await fake.searchSongs(keyword: 'abc');
    expect(page.items.single.title, 'abc');
    expect(fake.calls, 1);
  });
}
