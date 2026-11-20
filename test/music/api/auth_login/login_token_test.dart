/// login_token（token 续期登录）测试：请求装配（p3/t1/t2 常量加密/pk 小写）+
/// 20017 分支 + 解密凭证 + input/decode/authentication。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_token.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(
      jsonBytes(
        envelopeJson(
          data: <String, Object?>{
            'userid': 7,
            't1': 'NEW-T1',
            't_expire_time': 99,
            'nickname': '续期昵称',
            'pic': 'http://pic/token',
            'secu_params': encryptedCredentials(<String, Object?>{
              'token': 'NEW-TK',
            }),
          },
        ),
      ),
    );
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final identity = fixtureIdentity(userId: 7, token: 'OLD-TK', t1: 'OLD-T1');
    session = fakeSession(client, identity);
  });

  test('请求装配：body 键序/LITE 常量加密/pk 小写', () async {
    final result = await fetchLoginToken(
      session,
      timestampMs: testTimestampMs,
      seed: testSeed,
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v5/login_by_token');
    expect(request.headers['x-router'], 'login.user.kugou.com');

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'clienttime_ms',
      'dev',
      'dfid',
      'p3',
      'params',
      'pk',
      'plat',
      't1',
      't2',
      't3',
      'userid',
    ], reason: 'serde_json BTreeMap 键序');
    expect(body['clienttime_ms'], testTimestampMs);
    expect(body['dev'], 'fixture-device');
    expect(body['dfid'], 'fixture-dfid');
    expect(body['plat'], 1);
    expect(body['t3'], kugouTokenProofT3);
    expect(body['userid'], 7);

    // p3 = aes256({"clienttime":s,"token":TK}, LITEKEY/LITEIV)。
    expect(
      body['p3'],
      kugouAes256Hex(
        utf8.encode(
          '{"clienttime":${testTimestampMs ~/ 1000},"token":"OLD-TK"}',
        ),
        utf8.encode(kLiteKey),
        utf8.encode(kLiteIv),
      ),
    );
    expect(
      body['t1'],
      kugouAes256Hex(
        utf8.encode('OLD-T1|$testTimestampMs'),
        utf8.encode(kLiteT1Key),
        utf8.encode(kLiteT1Iv),
      ),
    );
    expect(
      body['t2'],
      kugouAes256Hex(
        utf8.encode(
          'fixture-guid|0f607264fc6318a92b9e13c65db7cd3c'
          '|fixture-mac|fixture-device|$testTimestampMs',
        ),
        utf8.encode(kLiteT2Key),
        utf8.encode(kLiteT2Iv),
      ),
    );
    expect(body['pk'], isNot(contains('A')), reason: '本端点 pk 转小写');
    // pk 全小写 hex。
    expect(RegExp(r'^[0-9a-f]{256}$').hasMatch(body['pk'] as String), isTrue);

    final envelope = kugouLoginParameterEnvelope(
      <String, Object?>{},
      testTimestampMs,
      seed: testSeed,
    );
    expect(body['params'], envelope.params);
    expect(
      utf8.decode(kugouDecryptCredentials(body['params'] as String, testSeed)),
      '{}',
      reason: '空对象明文按 BTreeMap 序列化',
    );
    expect(envelope.portrait.toLowerCase(), body['pk']);
    expect(result.refreshCredential, 'NEW-T1');
  });

  test('成功解码：解密凭证 + 全字段', () async {
    final result = await fetchLoginToken(
      session,
      timestampMs: testTimestampMs,
      seed: testSeed,
    );
    expect(result.userId, 7);
    expect(result.token, 'NEW-TK');
    expect(result.refreshCredential, 'NEW-T1');
    expect(result.expiresAtSeconds, 99);
    expect(result.nickname, '续期昵称');
    expect(result.avatarUrl, 'http://pic/token');
  });

  test('20017 → authentication（code 20017）', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":20017}');
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'authentication')
            .having((error) => error.code, 'code', 20017),
      ),
    );
  });

  test('业务失败 / 20018', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":101}');
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 101),
      ),
    );
    adapter.bytes = jsonBytes('{"status":0,"error_code":20018}');
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('userid 与本地身份不一致 → authentication', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'userid': 8,
          't1': 'NEW-T1',
          'secu_params': encryptedCredentials(<String, Object?>{
            'token': 'NEW-TK',
          }),
        },
      ),
    );
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'authentication')
            .having((error) => error.message, 'message', '服务未返回有效登录凭证'),
      ),
    );
  });

  test('缺 t1 → decode；t1 空 → authentication', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'userid': 7,
          'secu_params': encryptedCredentials(<String, Object?>{
            'token': 'NEW-TK',
          }),
        },
      ),
    );
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having((error) => error.message, 'message', contains('t1')),
      ),
    );

    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'userid': 7,
          't1': '',
          'secu_params': encryptedCredentials(<String, Object?>{
            'token': 'NEW-TK',
          }),
        },
      ),
    );
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('解密凭证里是 20018 信封 → authentication（request::decode 语义）', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'userid': 7,
          't1': 'NEW-T1',
          'secu_params': encryptForSeed('{"error_code":20018}', testSeed),
        },
      ),
    );
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('input：匿名身份拒绝（无请求）；secu_params 非法 hex → decode', () async {
    await expectLater(
      fetchLoginToken(
        fakeSession(client, KugouIdentity.anonymous()),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', '刷新登录需要完整账号与设备身份'),
      ),
    );
    expect(adapter.requests, isEmpty);

    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{'userid': 7, 't1': 'T1', 'secu_params': 'zz'},
      ),
    );
    await expectLater(
      fetchLoginToken(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );
  });
}
