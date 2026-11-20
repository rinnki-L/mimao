/// login_device_kick（踢出登录设备）测试：p 画像参数/Query 校验/web 签名 +
/// removed 应答与错误分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_device_kick.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(envelopeJson()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final identity = fixtureIdentity(userId: 7, token: 'KICK-TK', t1: 'T1');
    session = fakeSession(client, identity);
  });

  MusicDeviceKickQuery query({
    String targetMid = 'target-mid',
    String fingerprint = 'MT-9',
  }) => MusicDeviceKickQuery(
    targetMid: targetMid,
    activeAtSeconds: 1234567890,
    appId: 3116,
    clientVersion: 11440,
    transportFingerprint: fingerprint,
  );

  test('请求装配：GET dev_logout/web 签名/p=h5+画像/参数齐', () async {
    final result = await fetchLoginDeviceKick(
      session,
      query(),
      timestampMs: testTimestampMs,
    );

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      'https://gateway.kugou.com/loginservice/v1/dev_logout',
    );
    expect(request.headers['x-router'], isNull);

    final queryMap = request.query;
    expect(
      queryMap['token'],
      'h5${kugouUserPortrait(utf8.encode('moc.uoguk.59::KICK-TK'))}',
    );
    expect(RegExp(r'^h5[0-9A-F]{256}$').hasMatch(queryMap['token']!), isTrue);
    expect(queryMap['clienttime'], '$testTimestampMs');
    expect(queryMap['srcappid'], '2919');
    expect(queryMap['plat'], '1');
    expect(queryMap['t_mid'], 'target-mid');
    expect(queryMap['t'], '1234567890');
    expect(queryMap['t_appid'], '3116');
    expect(queryMap['t_clientver'], '11440');
    expect(queryMap['dfid'], 'MT-9');
    expect(queryMap['uuid'], '-');
    final signature = queryMap.remove('signature')!;
    expect(
      signature,
      kugouSignatureWeb(queryMap, const <int>[]),
      reason: 'DeviceLogout 走 web 签名',
    );

    expect(result.removed, isTrue);
  });

  test('dfid 空指纹 → "-"', () async {
    await fetchLoginDeviceKick(
      session,
      query(fingerprint: ''),
      timestampMs: testTimestampMs,
    );
    expect(adapter.requests.single.query['dfid'], '-');
  });

  test('input：目标为当前设备/空 mid/零字段（无请求）', () async {
    await expectLater(
      fetchLoginDeviceKick(
        session,
        query(targetMid: 'fixture-mid'),
        timestampMs: testTimestampMs,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', '请选择可移除的其它登录设备'),
      ),
    );
    await expectLater(
      fetchLoginDeviceKick(
        session,
        query(targetMid: ''),
        timestampMs: testTimestampMs,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    await expectLater(
      fetchLoginDeviceKick(
        session,
        MusicDeviceKickQuery(
          targetMid: 'target-mid',
          activeAtSeconds: 0,
          appId: 3116,
          clientVersion: 11440,
        ),
        timestampMs: testTimestampMs,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    await expectLater(
      fetchLoginDeviceKick(
        session,
        MusicDeviceKickQuery(
          targetMid: 'target-mid',
          activeAtSeconds: 100,
          appId: 0,
          clientVersion: 11440,
        ),
        timestampMs: testTimestampMs,
      ),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('匿名身份 → authentication「请先登录」（无请求）', () async {
    await expectLater(
      fetchLoginDeviceKick(
        fakeSession(client, KugouIdentity.anonymous()),
        query(),
        timestampMs: testTimestampMs,
      ),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'authentication')
            .having((error) => error.message, 'message', '请先登录'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('业务失败 / 20018 → authentication', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":9002}');
    await expectLater(
      fetchLoginDeviceKick(session, query(), timestampMs: testTimestampMs),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 9002),
      ),
    );
    adapter.bytes = jsonBytes('{"status":0,"error_code":20018}');
    await expectLater(
      fetchLoginDeviceKick(session, query(), timestampMs: testTimestampMs),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('decode：信封非 JSON', () async {
    adapter.bytes = jsonBytes('not-json');
    await expectLater(
      fetchLoginDeviceKick(session, query(), timestampMs: testTimestampMs),
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
