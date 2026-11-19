/// user_verify 端点测试：请求装配/签名自验 + 登录态失败 + auth 校验。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_verify.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import 'capture_adapter.dart';

const String _identity =
    '{"status":1,"error_code":0,'
    '"data":{"valid":1,"auth":"AUTH-1"}}';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  test('请求装配：网关路径 / x-router / module_id=51 / 签名可自验', () async {
    adapter.bytes = jsonBytes(_identity);
    final result = await userVerify(client, identity);

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/v1/user_verify?',
      ),
      isTrue,
    );
    expect(adapter.captured.headers['x-router'], 'trackercdngz.kugou.com');
    final query = capturedQuery(adapter.captured);
    expect(query['module_id'], '51');
    expect(query['appid'], '3116');
    expect(query['clientver'], '11440');
    expect(query['mid'], identity.mid);
    expect(query['dfid'], identity.dfid);
    expect(query.containsKey('token'), isFalse, reason: '匿名态不注入 token');

    final signature = query.remove('signature');
    expect(signature, kugouSignatureAndroid(query, const <int>[]));
    expect(result.valid, isTrue);
    expect(result.authorization, 'AUTH-1');
  });

  test('status=0 / error_code=35005 → authentication（登录态失败）', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":35005,"data":"请先登录"}');
    await expectLater(
      userVerify(client, identity),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'authentication')
            .having((error) => error.code, 'code', 35005),
      ),
    );
  });

  test('data.auth 空串 / 非字符串 → authentication', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"valid":1,"auth":"  "}}',
    );
    await expectLater(
      userVerify(client, identity),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"valid":1,"auth":123}}',
    );
    await expectLater(
      userVerify(client, identity),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('valid 只上报不作准入；其余失败按 business 透出 error_code', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"valid":0,"auth":"AUTH-2"}}',
    );
    final result = await userVerify(client, identity);
    expect(result.valid, isFalse);
    expect(result.authorization, 'AUTH-2');

    adapter.bytes = jsonBytes(
      '{"status":0,"error_code":12345,"data":{"auth":"x"}}',
    );
    await expectLater(
      userVerify(client, identity),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 12345),
      ),
    );
  });
}
