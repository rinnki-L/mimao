/// login_openplat（微信开放平台登录）测试：Authorize 换凭证（provider 主机、
/// 无酷狗签名/身份）+ Finish partner=36 + convert_oauth 宽容分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(
      jsonBytes('{"access_token":"AT-1","openid":"OID-1"}'),
    );
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final identity = fixtureIdentity(userId: 7, token: 'OLD', t1: 'OLDT1');
    session = fakeSession(client, identity);
  });

  group('Authorize（微信授权码换凭证）', () {
    test('请求装配：provider 主机 + 固定参数序 + 无酷狗签名/身份', () async {
      final result = await fetchLoginOpenplat(
        session,
        const MusicOpenplatQuery.authorize('WX-CODE'),
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, 'https://api.weixin.qq.com/sns/oauth2/access_token');
      final queryMap = request.query;
      expect(queryMap.keys.toList(), <String>[
        'secret',
        'appid',
        'code',
        'grant_type',
      ]);
      expect(queryMap['secret'], kWxLiteSecret);
      expect(queryMap['appid'], kWxLiteAppId);
      expect(queryMap['code'], 'WX-CODE');
      expect(queryMap['grant_type'], 'authorization_code');
      // provider 请求不带酷狗签名/身份/头。
      expect(queryMap.containsKey('signature'), isFalse);
      expect(queryMap.containsKey('dfid'), isFalse);
      expect(queryMap.containsKey('mid'), isFalse);
      expect(queryMap.containsKey('token'), isFalse);
      expect(request.headers.containsKey('x-router'), isFalse);
      expect(request.headers.containsKey('dfid'), isFalse);
      expect(request.headers.containsKey('mid'), isFalse);

      expect(result, isA<MusicProviderAuthorization>());
      final authorization = result as MusicProviderAuthorization;
      expect(authorization.openid, 'OID-1');
      expect(authorization.accessToken, 'AT-1');
    });

    test('errcode 非 0 → provider；缺字段 → decode；空凭证 → authentication', () async {
      adapter.bytes = jsonBytes('{"errcode":40013,"errmsg":"invalid appid"}');
      await expectLater(
        fetchLoginOpenplat(session, const MusicOpenplatQuery.authorize('C')),
        throwsA(
          isA<KugouApiException>()
              .having((error) => error.kind, 'kind', 'provider')
              .having((error) => error.message, 'message', '微信授权已失效，请重新扫码'),
        ),
      );

      adapter.bytes = jsonBytes('{"errcode":0,"openid":"OID"}');
      await expectLater(
        fetchLoginOpenplat(session, const MusicOpenplatQuery.authorize('C')),
        throwsA(
          isA<KugouApiException>().having(
            (error) => error.kind,
            'kind',
            'decode',
          ),
        ),
      );

      adapter.bytes = jsonBytes(
        '{"errcode":0,"openid":"","access_token":"AT"}',
      );
      await expectLater(
        fetchLoginOpenplat(session, const MusicOpenplatQuery.authorize('C')),
        throwsA(
          isA<KugouApiException>()
              .having((error) => error.kind, 'kind', 'authentication')
              .having((error) => error.message, 'message', '服务未返回有效登录凭证'),
        ),
      );

      // optional<String> 的数字宽容：openid 数字 → 文本。
      adapter.bytes = jsonBytes('{"openid":123,"access_token":"AT"}');
      final authorization =
          await fetchLoginOpenplat(
                session,
                const MusicOpenplatQuery.authorize('C'),
              )
              as MusicProviderAuthorization;
      expect(authorization.openid, '123');
    });

    test('input：空 code / 超长 code（无请求）', () async {
      await expectLater(
        fetchLoginOpenplat(session, const MusicOpenplatQuery.authorize('')),
        throwsA(
          isA<KugouApiException>()
              .having((error) => error.kind, 'kind', 'input')
              .having((error) => error.message, 'message', '微信授权码无效'),
        ),
      );
      await expectLater(
        fetchLoginOpenplat(session, MusicOpenplatQuery.authorize('c' * 4097)),
        throwsA(
          isA<KugouApiException>().having(
            (error) => error.kind,
            'kind',
            'input',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('Finish（partner=36 微信登录）', () {
    test('请求装配：无 third_appid + 成功解码', () async {
      adapter.bytes = jsonBytes(
        envelopeJson(
          data: accountWireData(
            credentials: <String, Object?>{'token': 'WX-TK'},
          ),
        ),
      );
      final result = await fetchLoginOpenplat(
        session,
        const MusicOpenplatQuery.finish(
          MusicProviderAuthorization(openid: 'OID', accessToken: 'AT'),
        ),
        timestampMs: testTimestampMs,
        seed: testSeed,
      );

      final request = adapter.requests.single;
      expect(request.path, 'https://gateway.kugou.com/v6/login_by_openplat');
      final body = jsonDecode(request.bodyText) as Map<String, Object?>;
      expect(
        body.containsKey('third_appid'),
        isFalse,
        reason: 'partner=36 不带 QQ appid',
      );
      expect(body['partnerid'], 36);
      expect(body['openid'], 'OID');
      expect(body.keys.last, 't3', reason: '无 third_appid 时键序末位是 t3');
      expect(result, isA<MusicLoginAuthorization>());
      expect((result as MusicLoginAuthorization).token, 'WX-TK');
    });

    test('input：凭证无效不发起请求', () async {
      await expectLater(
        fetchLoginOpenplat(
          session,
          const MusicOpenplatQuery.finish(
            MusicProviderAuthorization(openid: '', accessToken: 'AT'),
          ),
          timestampMs: testTimestampMs,
          seed: testSeed,
        ),
        throwsA(
          isA<KugouApiException>().having(
            (error) => error.kind,
            'kind',
            'input',
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('kugouProviderRequest 白名单（provider.rs）', () {
    test('非 https / 非白名单主机 / 显式端口 / 用户信息 → input', () async {
      const cases = <String>[
        'http://api.weixin.qq.com/x',
        'https://evil.example.com/x',
        'https://api.weixin.qq.com:8443/x',
        'https://user@api.weixin.qq.com/x',
      ];
      for (final url in cases) {
        await expectLater(
          kugouProviderRequest(client, method: 'GET', url: url),
          throwsA(
            isA<KugouApiException>()
                .having((error) => error.kind, 'kind', 'input')
                .having((error) => error.message, 'message', '登录服务地址无效'),
          ),
        );
      }
    });

    test('非 2xx/3xx → http；3xx 放行并读取响应头', () async {
      final stub = ProviderStubAdapter()..enqueue(500, 'boom');
      final rawClient = KugouClient(dio: Dio()..httpClientAdapter = stub);
      await expectLater(
        kugouProviderRequest(
          rawClient,
          method: 'GET',
          url: 'https://long.open.weixin.qq.com/connect/l/qrconnect',
        ),
        throwsA(
          isA<KugouApiException>()
              .having((error) => error.kind, 'kind', 'http')
              .having((error) => error.message, 'message', '登录服务暂时不可用'),
        ),
      );

      stub
        ..clear()
        ..enqueue(302, '', <String, String>{
          'location': 'https://xui.ptlogin2.qq.com/n',
        });
      final response = await kugouProviderRequest(
        rawClient,
        method: 'GET',
        url: 'https://long.open.weixin.qq.com/connect/l/qrconnect',
      );
      expect(response.statusCode, 302);
      expect(response.headers['location'], 'https://xui.ptlogin2.qq.com/n');
    });
  });
}
