/// login（密码登录）测试：请求装配（匿名化/信封/证明常量）+ 凭证解密 +
/// 失败文本提取 + input/业务/decode 分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/auth_models.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;

  MusicLoginQuery query([String password = 'pw']) =>
      MusicLoginQuery(username: 'user', password: password);

  Future<MusicLoginAuthorization> run() => fetchLogin(
    session,
    query(),
    timestampMs: testTimestampMs,
    seed: testSeed,
  );

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(envelopeJson(data: accountWireData())));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = fixtureIdentity(userId: 7, token: 'OLD-TOKEN', t1: 'OLD-T1');
    session = fakeSession(client, identity);
  });

  test('请求装配：匿名身份/路由/body 键序/证明常量/params 解密', () async {
    final result = await run();

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v9/login_by_pwd');
    expect(request.headers['x-router'], 'login.user.kugou.com');

    final queryMap = request.query;
    expect(queryMap['token'], isNull, reason: '登录绝不继承旧账号');
    expect(queryMap['userid'], isNull);
    expect(queryMap['mid'], identity.mid);
    expect(queryMap['dfid'], identity.dfid);
    final signature = queryMap.remove('signature')!;
    expect(
      signature,
      kugouSignatureAndroid(queryMap, utf8.encode(request.bodyText)),
    );

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'clienttime_ms',
      'dev',
      'params',
      'pk',
      'plat',
      'support_multi',
      't1',
      't2',
      't3',
      'username',
    ], reason: 'serde_json BTreeMap 键序');
    expect(body['clienttime_ms'], testTimestampMs);
    expect(body['dev'], 'fixture-device');
    expect(body['plat'], 1);
    expect(body['support_multi'], 1);
    expect(body['t1'], kugouLoginProofT1);
    expect(body['t2'], kugouLoginProofT2);
    expect(body['t3'], kugouLoginProofT3);
    expect(body['username'], 'user');

    final envelope = kugouLoginParameterEnvelope(
      <String, Object?>{
        'pwd': 'pw',
        'code': '',
        'clienttime_ms': testTimestampMs,
      },
      testTimestampMs,
      seed: testSeed,
    );
    expect(body['pk'], envelope.portrait);
    expect(RegExp(r'^[0-9A-F]{256}$').hasMatch(body['pk'] as String), isTrue);
    expect(body['params'], envelope.params);
    // 加密明文按 BTreeMap 键序。
    expect(
      utf8.decode(kugouDecryptCredentials(body['params'] as String, testSeed)),
      '{"clienttime_ms":$testTimestampMs,"code":"","pwd":"pw"}',
    );
    expect(result.userId, 42);
  });

  test('成功解码：密文凭证字段优先，account 字段兜底', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(
          credentials: <String, Object?>{
            'token': 'TK-ENC',
            'userid': 99,
            't1': 'T1-ENC',
            't_expire_time': 1893456000,
            'nickname': '加密昵称',
            'pic': 'http://enc/pic',
          },
        ),
      ),
    );
    final result = await run();
    expect(result.userId, 99);
    expect(result.token, 'TK-ENC');
    expect(result.refreshCredential, 'T1-ENC');
    expect(result.expiresAtSeconds, 1893456000);
    expect(result.nickname, '加密昵称');
    expect(result.avatarUrl, 'http://enc/pic');
  });

  test('成功解码：数字字符串宽容 + account t1/过期兜底 + 0 过滤', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(
          credentials: <String, Object?>{'token': 'TK-ENC', 'userid': '99'},
          t1: 'ACCOUNT-T1',
          tExpire: '0',
        ),
      ),
    );
    var result = await run();
    expect(result.userId, 99);
    expect(result.refreshCredential, 'ACCOUNT-T1');
    expect(result.expiresAtSeconds, isNull, reason: '0 按上游过滤为缺失');

    adapter.bytes = jsonBytes(envelopeJson(data: accountWireData()));
    result = await run();
    expect(result.refreshCredential, isNull);
    expect(result.expiresAtSeconds, isNull);
    expect(result.nickname, '昵称');
    expect(result.avatarUrl, 'http://pic/1');
  });

  test('明文 token 兜底：secu_params 为空时保留 token 字段', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(secuParams: '', token: 'PLAIN-TK'),
      ),
    );
    final result = await run();
    expect(result.token, 'PLAIN-TK');
    expect(result.userId, 42);
  });

  test('业务失败：从 data/error/message/msg 提取有界文本', () async {
    adapter.bytes = jsonBytes(
      '{"status":0,"error_code":5012,"data":"  密码错误  ","error":"","msg":"忽略"}',
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 5012)
            .having((error) => error.message, 'message', '密码错误'),
      ),
    );

    // data 超长（>1024 字节）→ 跳过，取 error 文本。
    final long = '长' * 600;
    adapter.bytes = jsonBytes(
      '{"status":0,"error_code":5012,"data":"$long","error":"second"}',
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.code, 'code', 5012)
            .having((error) => error.message, 'message', 'second'),
      ),
    );

    // 无文本 → 上游默认文案。
    adapter.bytes = jsonBytes('{"status":0,"error_code":5012,"data":3}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 5012)
            .having((error) => error.message, 'message', '请求失败'),
      ),
    );
  });

  test('20018 → authentication（decode 层统一判）', () async {
    adapter.bytes = jsonBytes(
      '{"status":0,"error_code":20018,"data":"expired"}',
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('凭证无效 → authentication（userid 0 / 空 token）', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(
          userId: 0,
          credentials: <String, Object?>{'token': 'TK'},
        ),
      ),
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'authentication')
            .having((error) => error.message, 'message', '服务未返回有效登录凭证'),
      ),
    );

    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(credentials: <String, Object?>{'token': ''}),
      ),
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('input 校验：空用户名/超长密码/超长 code/空设备名（无请求发出）', () async {
    await expectLater(
      fetchLogin(
        session,
        const MusicLoginQuery(username: '  ', password: 'pw'),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', '账号、密码或设备参数无效'),
      ),
    );
    await expectLater(
      fetchLogin(
        session,
        MusicLoginQuery(username: 'user', password: 'p' * 257),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    await expectLater(
      fetchLogin(
        session,
        MusicLoginQuery(username: 'user', password: 'pw', code: 'c' * 129),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    // deviceName 为空的身份 → input（上游 execute 的 identity.device_name 校验）。
    await expectLater(
      fetchLogin(
        fakeSession(client, KugouIdentity.anonymous()),
        query(),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('decode：secu_params 为 null / data 非 object', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(data: accountWireData(secuParams: null, token: 'TK')),
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );

    adapter.bytes = jsonBytes(envelopeJson(data: 3));
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );
  });

  test('凭证解密失败 / 非 object 凭证 → decode', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(data: accountWireData(secuParams: 'zz-not-hex')),
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );

    // 密文解出来是数组 → 凭证结构无效。
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(secuParams: encryptForSeed('[1]', testSeed)),
      ),
    );
    await expectLater(
      run(),
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
