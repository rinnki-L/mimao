/// login_device（登录设备列表）测试：加密信封装配 + 行解码宽容 + 排序 +
/// authentication/business 分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_device.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

Map<String, Object?> deviceRow({
  String mid = 'other-mid',
  String mt = 'MT-1',
  String dev = 'Model X',
  String app = 'KugouMusic',
  String loc = '广东深圳',
  Object? loginType = -1,
  Object? t = 100,
  Object? newAt = 50,
  Object? appid = 3116,
  Object? ver = 11440,
}) => <String, Object?>{
  'mid': mid,
  'mt': mt,
  'dev': dev,
  'app': app,
  'loc': loc,
  if (loginType != null) 'login_type': loginType,
  if (t != null) 't': t,
  if (newAt != null) 'new': newAt,
  if (appid != null) 'appid': appid,
  if (ver != null) 'ver': ver,
};

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(
      jsonBytes(
        envelopeJson(
          data: <String, Object?>{
            'li': <Object?>[deviceRow()],
          },
        ),
      ),
    );
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final identity = fixtureIdentity(userId: 7, token: 'DEV-TK', t1: 'T1');
    session = fakeSession(client, identity);
  });

  test('请求装配：加密信封/路由/匿名与否（要求账号）', () async {
    final devices = await fetchLoginDevice(
      session,
      timestampMs: testTimestampMs,
      seed: testSeed,
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v2/get_dev');
    expect(request.headers['x-router'], 'userinfoservice.kugou.com');

    final queryMap = request.query;
    final signature = queryMap.remove('signature')!;
    expect(
      signature,
      kugouSignatureAndroid(queryMap, utf8.encode(request.bodyText)),
    );

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'clienttime_ms',
      'params',
      'pk',
      'plat',
      'userid',
    ], reason: 'serde_json BTreeMap 键序');
    expect(body['clienttime_ms'], testTimestampMs);
    expect(body['plat'], 1);
    expect(body['userid'], 7);

    final envelope = kugouLoginEnvelope(
      <String, Object?>{'token': 'DEV-TK'},
      testTimestampMs,
      seed: testSeed,
    );
    expect(body['pk'], envelope.portrait);
    expect(RegExp(r'^[0-9A-F]{256}$').hasMatch(body['pk'] as String), isTrue);
    expect(body['params'], envelope.params);
    expect(
      utf8.decode(kugouDecryptCredentials(body['params'] as String, testSeed)),
      '{"token":"DEV-TK"}',
    );

    expect(devices, hasLength(1));
    expect(devices.single.id, 'other-mid');
    expect(devices.single.current, isFalse);
  });

  test('解码：行字段全量 + current 判定 + 数字字符串宽容', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'li': <Object?>[
            deviceRow(
              mid: 'fixture-mid',
              t: '123',
              ver: '11440',
              loginType: -1,
            ),
          ],
        },
      ),
    );
    final devices = await fetchLoginDevice(
      session,
      timestampMs: testTimestampMs,
      seed: testSeed,
    );
    final row = devices.single;
    expect(row.id, 'fixture-mid');
    expect(row.current, isTrue, reason: 'mid == 本机 mid');
    expect(row.transportFingerprint, 'MT-1');
    expect(row.model, 'Model X');
    expect(row.platform, 'KugouMusic');
    expect(row.location, '广东深圳');
    expect(row.loginType, -1, reason: '本地刷新会话 -1 原样保留');
    expect(row.activeAtSeconds, 123);
    expect(row.newAtSeconds, 50);
    expect(row.appId, 3116);
    expect(row.clientVersion, 11440);
  });

  test('排序：当前设备优先，其余按活跃时间倒序', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'li': <Object?>[
            deviceRow(mid: 'a', t: 100),
            deviceRow(mid: 'b', t: 200),
            deviceRow(mid: 'fixture-mid', t: 5),
            deviceRow(mid: 'c'),
          ],
        },
      ),
    );
    final devices = await fetchLoginDevice(
      session,
      timestampMs: testTimestampMs,
      seed: testSeed,
    );
    expect(devices.map((d) => d.id).toList(), <String>[
      'fixture-mid',
      'b',
      'a',
      'c',
    ], reason: 'current → t 倒序 → 无 t 的垫底（行序稳定）');
  });

  test('list 宽容：li 空对象/缺省 → 空列表；非 object 行 → decode', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(data: <String, Object?>{'li': <String, Object?>{}}),
    );
    expect(
      await fetchLoginDevice(
        session,
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      isEmpty,
    );

    adapter.bytes = jsonBytes(envelopeJson(data: <String, Object?>{}));
    expect(
      await fetchLoginDevice(
        session,
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      isEmpty,
    );

    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'li': <Object?>[3],
        },
      ),
    );
    await expectLater(
      fetchLoginDevice(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );
  });

  test('text/optional 宽容：bool 文本 → 空串；bool optional → null', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'li': <Object?>[
            <String, Object?>{
              'mid': 'm',
              'mt': 'mt',
              'dev': true,
              'app': null,
              'loc': 'L',
              'login_type': true,
              't': 9,
              'new': 'bad',
              'appid': 3116,
              'ver': 1,
            },
          ],
        },
      ),
    );
    final row = (await fetchLoginDevice(
      session,
      timestampMs: testTimestampMs,
      seed: testSeed,
    )).single;
    expect(row.model, '', reason: 'text 的 bool → 空串');
    expect(row.platform, '', reason: 'text 的 null → 空串');
    expect(row.loginType, isNull, reason: 'optional 的 bool → null');
    expect(row.newAtSeconds, isNull, reason: 'optional 的坏字符串 → null');
    expect(row.activeAtSeconds, 9);
  });

  test('20018 → authentication；业务失败 → business', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":20018}');
    await expectLater(
      fetchLoginDevice(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
    adapter.bytes = jsonBytes(
      '{"status":0,"error_code":20018,"msg":"用户登录已过期，请重新登录"}',
    );
    await expectLater(
      fetchLoginDevice(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
    adapter.bytes = jsonBytes('{"status":0,"error_code":9001}');
    await expectLater(
      fetchLoginDevice(session, timestampMs: testTimestampMs, seed: testSeed),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 9001),
      ),
    );
  });

  test('匿名身份 → authentication「请先登录」（无请求）', () async {
    await expectLater(
      fetchLoginDevice(
        fakeSession(client, KugouIdentity.anonymous()),
        timestampMs: testTimestampMs,
        seed: testSeed,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'authentication')
            .having((error) => error.message, 'message', '请先登录'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });
}
