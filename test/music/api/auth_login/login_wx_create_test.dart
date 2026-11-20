/// login_wx_create（微信扫码创建）测试：三段 provider 装配（token → getticket
/// → 签名 qrconnect）+ 票据/信封业务分支 + decode 宽容。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/login_wx_create.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

import 'test_support.dart';

void main() {
  late ProviderStubAdapter adapter;
  late KugouClient client;
  late MusicSession session;

  setUp(() {
    adapter = ProviderStubAdapter()
      ..enqueue(200, '{"access_token":"AT-1"}')
      ..enqueue(200, '{"errcode":0,"ticket":"SDK-TICKET"}')
      ..enqueue(
        200,
        '{"errcode":0,"uuid":"UUID-1","qrcode":{"qrcodebase64":"QRCODE=="}}',
      );
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    session = fakeSession(client, fixtureIdentity());
  });

  Future<MusicWxSession> run() => fetchLoginWxCreate(
    session,
    timestampMs: 1760000000123,
    random: FixedRandom(),
  );

  test('请求装配：token/getticket/qrconnect 参数序 + SHA1 签名', () async {
    final result = await run();

    expect(adapter.requests, hasLength(3));

    final tokenRequest = adapter.requests[0];
    expect(tokenRequest.path, 'https://api.weixin.qq.com/cgi-bin/token');
    expect(tokenRequest.query.keys.toList(), <String>[
      'appid',
      'secret',
      'grant_type',
    ]);
    expect(tokenRequest.query['appid'], kWxLiteAppId);
    expect(tokenRequest.query['secret'], kWxLiteSecret);
    expect(tokenRequest.query['grant_type'], 'client_credential');
    expect(tokenRequest.headers.containsKey('dfid'), isFalse);
    expect(tokenRequest.query.containsKey('signature'), isFalse);

    final ticketRequest = adapter.requests[1];
    expect(
      ticketRequest.path,
      'https://api.weixin.qq.com/cgi-bin/ticket/getticket',
    );
    expect(ticketRequest.query.keys.toList(), <String>['access_token', 'type']);
    expect(ticketRequest.query['access_token'], 'AT-1');
    expect(ticketRequest.query['type'], '2');

    final connectRequest = adapter.requests[2];
    expect(
      connectRequest.path,
      'https://open.weixin.qq.com/connect/sdk/qrconnect',
    );
    expect(connectRequest.query.keys.toList(), <String>[
      'appid',
      'noncestr',
      'timestamp',
      'scope',
      'signature',
    ]);
    expect(connectRequest.query['appid'], kWxLiteAppId);
    expect(connectRequest.query['timestamp'], '1760000000123');
    expect(connectRequest.query['scope'], 'snsapi_userinfo');
    final nonce = connectRequest.query['noncestr']!;
    expect(
      RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce),
      isTrue,
      reason: 'md5(u64 大端 8 字节)',
    );
    expect(
      connectRequest.query['signature'],
      sha1
          .convert(
            utf8.encode(
              'appid=$kWxLiteAppId&noncestr=$nonce&sdk_ticket=SDK-TICKET&timestamp=1760000000123',
            ),
          )
          .toString(),
    );

    expect(result.key, 'UUID-1');
    expect(result.imageDataUrl, 'data:image/jpeg;base64,QRCODE==');
  });

  test('票据业务分支：errcode 非 0 → business；缺 ticket → decode', () async {
    adapter
      ..clear()
      ..enqueue(200, '{"access_token":"AT-1"}')
      ..enqueue(200, '{"errcode":40013}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 40013),
      ),
    );

    adapter
      ..clear()
      ..enqueue(200, '{"access_token":"AT-1"}')
      ..enqueue(200, '{"errcode":0}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having((error) => error.message, 'message', '微信 SDK 票据缺失'),
      ),
    );
  });

  test('信封分支：uuid 缺失 / qrcode 缺失 / errcode 非 0 → decode/business', () async {
    adapter
      ..clear()
      ..enqueue(200, '{"access_token":"AT-1"}')
      ..enqueue(200, '{"errcode":0,"ticket":"TK"}')
      ..enqueue(200, '{"errcode":1}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 1),
      ),
    );

    adapter
      ..clear()
      ..enqueue(200, '{"access_token":"AT-1"}')
      ..enqueue(200, '{"errcode":0,"ticket":"TK"}')
      ..enqueue(200, '{"errcode":0,"qrcode":{"qrcodebase64":"X"}}');
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

    adapter
      ..clear()
      ..enqueue(200, '{"access_token":"AT-1"}')
      ..enqueue(200, '{"errcode":0,"ticket":"TK"}')
      ..enqueue(200, '{"errcode":0,"uuid":"U"}');
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

  test('令牌缺 access_token → decode', () async {
    adapter
      ..clear()
      ..enqueue(200, '{"errcode":0}');
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

/// 固定随机源。
class FixedRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0.25;

  @override
  int nextInt(int max) => 7;
}
