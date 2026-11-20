/// login_cellphone（手机验证码登录）测试：请求装配（掩码/重试 UA/证明）+
/// 34175 候选分支 + 解密 + input/proofs 设备校验。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_cellphone.dart';
import 'package:mimao/music/api/login_openplat.dart';
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

  MusicCellphoneQuery query({int? userId}) => MusicCellphoneQuery(
    mobile: '13800000000',
    code: '123456',
    userId: userId,
  );

  Future<MusicCellphoneLoginResult> run({int? userId}) => fetchLoginCellphone(
    session,
    query(userId: userId),
    timestampMs: testTimestampMs,
    seed: testSeed,
  );

  setUp(() {
    adapter = CaptureAdapter(
      jsonBytes(
        envelopeJson(
          data: accountWireData(
            credentials: <String, Object?>{'token': 'CELL-TK'},
          ),
        ),
      ),
    );
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = fixtureIdentity(userId: 7, token: 'OLD', t1: 'OLDT1');
    session = fakeSession(client, identity);
  });

  test('请求装配：掩码/keyed_time/proofs/重试 UA/匿名化/body 键序', () async {
    final result = await run();

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path,
      'https://loginserviceretry.kugou.com/v7/login_by_verifycode',
    );
    expect(
      request.headers['x-router'],
      isNull,
      reason: 'LoginRetry 不走 x-router',
    );
    expect(request.headers['support-calm'], '1');
    expect(
      request.headers['User-Agent'],
      'Android16-1070-11440-130-0-LOGIN-wifi',
    );

    final queryMap = request.query;
    expect(queryMap['token'], isNull, reason: '登录请求匿名化');
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
      'dfid',
      'gitversion',
      'key',
      'mobile',
      'params',
      'pk',
      'plat',
      'support_multi',
      't1',
      't2',
    ], reason: 'serde_json BTreeMap 键序');
    expect(body['clienttime_ms'], testTimestampMs);
    expect(body['dev'], 'fixture-device');
    expect(body['dfid'], identity.dfid);
    expect(body['gitversion'], '5f0b7c4');
    expect(body['key'], kugouCloudListKeyedTime(testTimestampMs));
    // Rust 字节切片掩码：前 2 位 + ***** + 最后 1 位。
    expect(body['mobile'], '13*****0');
    expect(body['plat'], 1);
    expect(body['support_multi'], 1);

    final envelope = kugouLoginParameterEnvelope(
      <String, Object?>{'mobile': '13800000000', 'code': '123456'},
      testTimestampMs,
      seed: testSeed,
    );
    expect(body['params'], envelope.params);
    expect(body['pk'], envelope.portrait);
    final (t1, t2) = kugouLoginProofs(
      identity.withoutAccount(),
      testTimestampMs,
    );
    expect(body['t1'], t1);
    expect(body['t2'], t2);
    expect(result.selectAccount, isFalse);
    expect(result.authorization!.token, 'CELL-TK');
  });

  test('请求装配：显式 userid 进 body（多账号选择重试）', () async {
    await run(userId: 5);
    final body =
        jsonDecode(adapter.requests.single.bodyText) as Map<String, Object?>;
    expect(body.keys.last, 'userid', reason: 'userid 恒在键序末位');
    expect(body['userid'], 5);
  });

  test('成功解码：密文凭证 + account 兜底', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(
          credentials: <String, Object?>{
            'token': 'CELL-TK',
            'userid': '43',
            'nickname': '手机昵称',
          },
          userId: 42,
          pic: 'http://pic/cell',
        ),
      ),
    );
    final result = await run();
    expect(result.authorization!.userId, 43);
    expect(result.authorization!.nickname, '手机昵称');
    expect(result.authorization!.avatarUrl, 'http://pic/cell');
    expect(result.selectAccount, isFalse);
  });

  test('34175 → select_account 候选列表（展示名回退链）', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        errorCode: 34175,
        data: <String, Object?>{
          'info_list': <Object?>[
            <String, Object?>{
              'userid': 1,
              'nickname': '',
              'username': 'u-one',
              'pic': 'http://p/1',
              'appid': 3116,
            },
            <String, Object?>{'userid': '2'},
            <String, Object?>{
              'userid': 3,
              'nickname': '直接昵称',
              'username': 'ignored',
            },
          ],
        },
      ),
    );
    final result = await run();
    expect(result.selectAccount, isTrue);
    expect(result.authorization, isNull);
    final candidates = result.candidates;
    expect(candidates, hasLength(3));
    // nickname 空 → username；再空 → userid 文本。
    expect(candidates[0].nickname, 'u-one');
    expect(candidates[0].userId, 1);
    expect(candidates[0].avatarUrl, 'http://p/1');
    expect(candidates[0].username, 'u-one');
    expect(candidates[0].appId, 3116);
    expect(candidates[1].nickname, '2', reason: '全空时回退 userid 文本');
    expect(candidates[1].appId, isNull);
    expect(candidates[2].nickname, '直接昵称');
    expect(candidates[2].username, 'ignored');
  });

  test('34175：info_list 空对象/缺省宽容；行缺 userid → decode', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        errorCode: 34175,
        data: <String, Object?>{'info_list': <String, Object?>{}},
      ),
    );
    expect((await run()).candidates, isEmpty);

    adapter.bytes = jsonBytes(
      envelopeJson(errorCode: 34175, data: <String, Object?>{}),
    );
    expect((await run()).candidates, isEmpty);

    adapter.bytes = jsonBytes(
      envelopeJson(
        errorCode: 34175,
        data: <String, Object?>{
          'info_list': <Object?>[
            <String, Object?>{'nickname': 'x'},
          ],
        },
      ),
    );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having((error) => error.message, 'message', contains('userid')),
      ),
    );
  });

  test('input：非法手机号/空验证码/userid=0', () async {
    await expectLater(
      fetchLoginCellphone(
        session,
        MusicCellphoneQuery(mobile: '23800000000', code: '123456'),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', '请输入手机号码和验证码'),
      ),
    );
    await expectLater(
      fetchLoginCellphone(
        session,
        const MusicCellphoneQuery(mobile: '13800000000', code: '  '),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    await expectLater(
      fetchLoginCellphone(
        session,
        const MusicCellphoneQuery(
          mobile: '13800000000',
          code: '123456',
          userId: 0,
        ),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('proofs 要求完整设备上下文：deviceName 空 → input（无请求）', () async {
    await expectLater(
      fetchLoginCellphone(
        fakeSession(client, KugouIdentity.anonymous()),
        query(),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', '登录设备上下文不完整'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('20018 → authentication；业务失败 → business', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":20018}');
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
    adapter.bytes = jsonBytes('{"status":0,"error_code":30102}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 30102),
      ),
    );
  });
}
