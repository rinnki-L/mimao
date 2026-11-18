/// 设备注册端点测试：黄金向量（上游 fixture）+ 响应解析/错误分支 +
/// 传输装配（捕获 adapter 全链路）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/register_dev.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.bytes);

  final int status;
  final Uint8List bytes;

  /// 最后一次请求的装配快照（断言主机/参数序/头）。
  final RequestOptions captured = RequestOptions(path: '/');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured
      ..method = options.method
      ..path = options.path
      ..queryParameters = options.queryParameters
      ..headers = options.headers;
    return ResponseBody.fromBytes(bytes, status);
  }

  @override
  void close({bool force = false}) {}
}

/// 用固定 seed 把响应 JSON 封成信封密文（服务端行为的测试替身）。
Uint8List sealResponse(String json, String seed) =>
    kugouAesCbcPkcs7(utf8.encode(json), seed, encrypt: true);

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/music/fixtures/register_dev_request_20261017.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  test('黄金向量：DeviceProfile JSON 与 AES 密文逐字节对拍上游', () async {
    // 直接测 envelope 层（黄金向量不含 HTTP 响应）。
    final profile = kugouDeviceProfile('0123456789abcdef0123456789abcdef');
    expect(
      utf8.encode(jsonEncode(profile)),
      utf8.encode(fixture['plain_text']! as String),
    );
    final envelope = KugouRegistrationEnvelope.withSeed(
      profile,
      seed: fixture['seed']! as String,
      userId: 0,
      token: '',
    );
    expect(base64Encode(envelope.body), fixture['ciphertext_base64']);
  });

  test('全链路：注册成功返回 dfid；请求用匿名身份 + 固定头', () async {
    const seed = 'zz9xxy';
    final adapter = _FakeAdapter(
      200,
      sealResponse(
        '{"status":1,"error_code":0,"data":{"dfid":"newDfid001"}}',
        seed,
      ),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final anonymous = KugouIdentity.anonymous();
    final withAccount = KugouIdentity(
      userId: 42,
      token: 'tok',
      t1: '',
      mid: anonymous.mid,
      dfid: anonymous.dfid,
      uuid: anonymous.uuid,
      guid: anonymous.guid,
      mac: anonymous.mac,
      deviceName: '',
      renderFingerprint: '',
    );

    final device = await registerDevice(client, withAccount, seed: seed);
    expect(device.dfid, 'newDfid001');
  });

  test('注册请求走 registration origin（userservice 主机、固定参数序）', () async {
    const seed = 'zz9xxy';
    final adapter = _FakeAdapter(
      200,
      sealResponse('{"status":1,"error_code":0,"data":{"dfid":"d1"}}', seed),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    await registerDevice(client, KugouIdentity.anonymous(), seed: seed);

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://userservice.kugou.com/risk/v3/r_register_dev?',
      ),
      isTrue,
    );
    final keys = adapter.captured.queryParameters.keys.toList();
    expect(
      keys,
      containsAllInOrder(<String>['dfid', 'mid', 'uuid', 'signature']),
    );
    expect(keys.last, 'signature');
    expect(adapter.captured.queryParameters['part'], '1');
    expect(adapter.captured.queryParameters['platid'], '1');
    expect(adapter.captured.headers['kg-rc'], '1');
    expect(adapter.captured.headers['kg-thash'], '5d816a0');
  });

  test(
    'status=1 但 data 是空数组 → device_registration_unassigned（不杜撰身份）',
    () async {
      const seed = 'zz9xxy';
      final client = KugouClient(
        dio: Dio()
          ..httpClientAdapter = _FakeAdapter(
            200,
            sealResponse('{"status":1,"error_code":0,"data":[]}', seed),
          ),
      );
      await expectLater(
        registerDevice(client, KugouIdentity.anonymous(), seed: seed),
        throwsA(
          predicate(
            (Object e) => '$e'.contains('device_registration_unassigned'),
          ),
        ),
      );
    },
  );

  test('status=1 但 data 缺 dfid → device_registration_unassigned', () async {
    const seed = 'zz9xxy';
    final client = KugouClient(
      dio: Dio()
        ..httpClientAdapter = _FakeAdapter(
          200,
          sealResponse('{"status":1,"error_code":0,"data":{}}', seed),
        ),
    );
    await expectLater(
      registerDevice(client, KugouIdentity.anonymous(), seed: seed),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('device_registration_unassigned'),
        ),
      ),
    );
  });

  test('dfid 为 - 或超长 → authentication 异常', () async {
    const seed = 'zz9xxy';
    final client = KugouClient(
      dio: Dio()
        ..httpClientAdapter = _FakeAdapter(
          200,
          sealResponse('{"status":1,"error_code":0,"data":{"dfid":"-"}}', seed),
        ),
    );
    await expectLater(
      registerDevice(client, KugouIdentity.anonymous(), seed: seed),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });

  test('业务失败（status=0）→ business 异常带 error_code', () async {
    const seed = 'zz9xxy';
    final client = KugouClient(
      dio: Dio()
        ..httpClientAdapter = _FakeAdapter(
          200,
          sealResponse('{"status":0,"error_code":123,"data":{}}', seed),
        ),
    );
    await expectLater(
      registerDevice(client, KugouIdentity.anonymous(), seed: seed),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('123'),
        ),
      ),
    );
  });

  test('响应解不开 → device_registration_decrypt', () async {
    final client = KugouClient(
      dio: Dio()
        ..httpClientAdapter = _FakeAdapter(
          200,
          Uint8List.fromList(List.filled(64, 0x11)),
        ),
    );
    await expectLater(
      registerDevice(client, KugouIdentity.anonymous(), seed: 'zz9xxy'),
      throwsA(
        predicate((Object e) => '$e'.contains('device_registration_decrypt')),
      ),
    );
  });

  test('guid 为空 → input 异常', () async {
    final client = KugouClient(
      dio: Dio()..httpClientAdapter = _FakeAdapter(200, Uint8List(0)),
    );
    final broken = KugouIdentity(
      userId: 0,
      token: '',
      t1: '',
      mid: 'm',
      dfid: '-',
      uuid: '-',
      guid: '',
      mac: '',
      deviceName: '',
      renderFingerprint: '',
    );
    await expectLater(
      registerDevice(client, broken, seed: 'zz9xxy'),
      throwsA(predicate((Object e) => '$e'.contains('input'))),
    );
  });
}
