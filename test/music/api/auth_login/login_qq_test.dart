/// login_qq（QQ 开放平台登录）测试：请求装配（partner=1/third_appid/匿名化）+
/// 密文凭证（无明文兜底）+ input/业务分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_qq.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/auth_models.dart';

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
          data: accountWireData(
            credentials: <String, Object?>{
              'token': 'QQ-TK',
              'nickname': 'QQ昵称',
            },
          ),
        ),
      ),
    );
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final identity = fixtureIdentity(userId: 7, token: 'OLD', t1: 'OLDT1');
    session = fakeSession(client, identity);
  });

  const authorization = MusicProviderAuthorization(
    openid: 'OID-1',
    accessToken: 'AT-1',
  );

  test('请求装配：partner=1/third_appid/匿名化/body 键序', () async {
    final result = await fetchLoginQq(
      session,
      authorization,
      timestampMs: testTimestampMs,
      seed: testSeed,
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v6/login_by_openplat');
    expect(request.headers['x-router'], 'login.user.kugou.com');

    final queryMap = request.query;
    expect(queryMap['token'], isNull, reason: 'openplat 登录匿名化');
    expect(queryMap['userid'], isNull);
    final signature = queryMap.remove('signature')!;
    expect(
      signature,
      kugouSignatureAndroid(queryMap, utf8.encode(request.bodyText)),
    );

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'clienttime_ms',
      'dev',
      'force_login',
      'openid',
      'params',
      'partnerid',
      'pk',
      't1',
      't2',
      't3',
      'third_appid',
    ], reason: 'serde_json BTreeMap 键序（third_appid 恒在 t3 后）');
    expect(body['clienttime_ms'], testTimestampMs);
    expect(body['dev'], 'fixture-device');
    expect(body['force_login'], 1);
    expect(body['openid'], 'OID-1');
    expect(body['partnerid'], 1);
    expect(body['t3'], 'MCwwLDAsMCwwLDAsMCwwLDA=');
    expect(body['third_appid'], '101706348');

    final envelope = kugouLoginParameterEnvelope(
      <String, Object?>{'access_token': 'AT-1'},
      testTimestampMs,
      seed: testSeed,
    );
    expect(body['params'], envelope.params);
    expect(body['pk'], envelope.portrait);
    expect(
      utf8.decode(kugouDecryptCredentials(body['params'] as String, testSeed)),
      '{"access_token":"AT-1"}',
    );
    final (t1, t2) = kugouLoginProofs(fixtureIdentity(), testTimestampMs);
    expect(body['t1'], t1);
    expect(body['t2'], t2);

    expect(result.userId, 42);
    expect(result.token, 'QQ-TK');
    expect(result.nickname, 'QQ昵称');
  });

  test('成功解码：凭证 nickname/pic 覆盖 account 字段', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(
          credentials: <String, Object?>{
            'token': 'QQ-TK',
            'nickname': '凭证昵称',
            'pic': 'http://pic/qq',
          },
          nickname: '账号昵称',
        ),
      ),
    );
    final result = await fetchLoginQq(
      session,
      authorization,
      timestampMs: testTimestampMs,
      seed: testSeed,
    );
    expect(result.nickname, '凭证昵称');
    expect(result.avatarUrl, 'http://pic/qq');
  });

  test('空 secu_params → decode（QQ 无明文 token 兜底）', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(secuParams: '', token: 'PLAIN'),
      ),
    );
    await expectLater(
      fetchLoginQq(
        session,
        authorization,
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );
  });

  test('input：空 openid / 空 access_token / 超长 openid', () async {
    await expectLater(
      fetchLoginQq(
        session,
        const MusicProviderAuthorization(openid: '', accessToken: 'AT'),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', '第三方登录凭证无效'),
      ),
    );
    await expectLater(
      fetchLoginQq(
        session,
        const MusicProviderAuthorization(openid: 'OID', accessToken: ''),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    await expectLater(
      fetchLoginQq(
        session,
        MusicProviderAuthorization(openid: 'O' * 4097, accessToken: 'AT'),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('业务失败 / 20018 → authentication', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":30002}');
    await expectLater(
      fetchLoginQq(
        session,
        authorization,
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 30002),
      ),
    );
    adapter.bytes = jsonBytes('{"status":0,"error_code":20018}');
    await expectLater(
      fetchLoginQq(
        session,
        authorization,
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });
}
