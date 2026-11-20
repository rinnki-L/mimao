/// login_wx_check（微信扫码轮询）测试：状态码映射（408/404/402/403/405）+
/// provider_code 的授权码有界性 + text 宽容 + input。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_wx_check.dart';
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
    adapter = CaptureAdapter(jsonBytes('{"wx_errcode":408,"wx_code":""}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    session = fakeSession(client, fixtureIdentity());
  });

  Future<MusicWxCheckResult> run() => fetchLoginWxCheck(session, 'UUID-1');

  test('请求装配：long.open.weixin 主机 + f=json/uuid，无酷狗签名', () async {
    final result = await run();

    final request = adapter.requests.single;
    expect(request.path, 'https://long.open.weixin.qq.com/connect/l/qrconnect');
    expect(request.query.keys.toList(), <String>['f', 'uuid']);
    expect(request.query['f'], 'json');
    expect(request.query['uuid'], 'UUID-1');
    expect(request.query.containsKey('signature'), isFalse);
    expect(request.headers.containsKey('dfid'), isFalse);
    expect(request.headers.containsKey('mid'), isFalse);
    expect(result.state, MusicWxCheckResult.stateWaiting);
    expect(result.code, isNull);
  });

  test('状态映射：404 扫描 / 402+403 过期 / 405 带码 → provider_code', () async {
    adapter.bytes = jsonBytes('{"wx_errcode":404,"wx_code":""}');
    expect((await run()).state, MusicWxCheckResult.stateScanned);

    adapter.bytes = jsonBytes('{"wx_errcode":402,"wx_code":""}');
    expect((await run()).state, MusicWxCheckResult.stateExpired);

    adapter.bytes = jsonBytes('{"wx_errcode":403,"wx_code":""}');
    expect((await run()).state, MusicWxCheckResult.stateExpired);

    adapter.bytes = jsonBytes('{"wx_errcode":405,"wx_code":"WX-CODE"}');
    final result = await run();
    expect(result.state, MusicWxCheckResult.stateProviderCode);
    expect(result.code, 'WX-CODE');

    adapter.bytes = jsonBytes('{"wx_errcode":"408"}');
    expect(
      (await run()).state,
      MusicWxCheckResult.stateWaiting,
      reason: 'scalar 数字字符串宽容',
    );
  });

  test('405 无码/超长码/未知码 → provider 失败', () async {
    adapter.bytes = jsonBytes('{"wx_errcode":405,"wx_code":""}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'provider')
            .having((error) => error.message, 'message', '微信扫码状态异常，请重新获取二维码'),
      ),
    );

    adapter.bytes = jsonBytes('{"wx_errcode":405,"wx_code":"${'c' * 4097}"}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'provider',
        ),
      ),
    );

    adapter.bytes = jsonBytes('{"wx_errcode":500,"wx_code":"X"}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'provider',
        ),
      ),
    );
  });

  test('decode：wx_errcode 缺失 / 非 object', () async {
    adapter.bytes = jsonBytes('{"wx_code":"X"}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having(
              (error) => error.message,
              'message',
              contains('wx_errcode'),
            ),
      ),
    );
    adapter.bytes = jsonBytes('[1]');
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

  test('text 宽容：wx_code 为 bool → 空串（405 退化为 provider 失败）', () async {
    adapter.bytes = jsonBytes('{"wx_errcode":405,"wx_code":true}');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'provider',
        ),
      ),
    );
  });

  test('input：空 key / 超长 key（无请求）', () async {
    await expectLater(
      fetchLoginWxCheck(session, ''),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', '微信二维码会话无效'),
      ),
    );
    await expectLater(
      fetchLoginWxCheck(session, 'k' * 257),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });
}
