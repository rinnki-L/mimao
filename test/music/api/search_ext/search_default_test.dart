/// search_default 测试：精确请求体字节（format! 原文）、装配、ErrcodeEnvelope
/// 语义（errcode 键的 20018 走 business）、解码宽容与 decode 分支。
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/search_default.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
    session = fakeMusicSession(client, identity);
  });

  test('请求装配：POST/网关/无 x-router/clientver=12329/精确请求体字节 + 签名自验', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"ads":[],"fallback":null}}',
    );
    await fetchSearchDefault(session);

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/searchnofocus/v1/search_no_focus_word?',
      ),
      isTrue,
    );
    expect(adapter.captured.method, 'POST');
    expect(adapter.captured.headers.containsKey('x-router'), isFalse);
    expect(adapter.captured.headers['Content-Type'], 'application/json');

    final query = capturedQuery(adapter.captured);
    expect(query['clientver'], '12329');
    expect(query['appid'], '3116');
    expect(query['uuid'], '-');
    expect(query.containsKey('token'), isFalse, reason: '匿名身份不注入 token');
    expect(query.containsKey('userid'), isFalse, reason: 'userid=0 不进 query');
    expect(
      query.length,
      7,
      reason: 'clientver + appid/clienttime/dfid/mid/uuid + signature',
    );

    // 上游 format! 原文逐字符对拍（键序/间距/字面量都不能变）。
    expect(
      adapter.requests.last.bodyText,
      '{"plat":0,"userid":0,"tags":"{}","vip_type":65530,"m_type":0,'
      '"own_ads":{},"ability":"3","sources":[],"bitmap":2,"mode":"normal"}',
    );
    final signature = query.remove('signature');
    expect(
      signature,
      kugouSignatureAndroid(query, utf8.encode(adapter.requests.last.bodyText)),
    );
  });

  test('解码：推广位字段映射 + fallback 原样保留', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"ads":['
      '{"id":"1","title":"t","main_title":"m","sub_title":"s",'
      '"jumpType":"url","unifiedUrl":"https://e.example/a?b=1","extra":9}'
      '],"fallback":{"unknown":"shape"}}}',
    );
    final result = await fetchSearchDefault(session);
    final promotion = result.promotions.single;
    expect(promotion.id, 1, reason: 'id 是数字字符串，scalar 宽容解码');
    expect(promotion.title, 't');
    expect(promotion.mainTitle, 'm');
    expect(promotion.subtitle, 's');
    expect(promotion.jumpType, 'url');
    expect(promotion.encodedDestination, 'https://e.example/a?b=1');
    expect(result.fallbackExtension, <String, Object?>{
      'unknown': 'shape',
    }, reason: '未建模扩展原样保留，绝不解读成搜索词');
  });

  test('解码：ads 缺省/空对象回空表；fallback null → null', () async {
    for (final data in <String>['{}', '{"ads":null}', '{"ads":{}}']) {
      adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":$data}');
      final result = await fetchSearchDefault(session);
      expect(result.promotions, isEmpty, reason: 'data=$data');
      expect(result.fallbackExtension, isNull);
    }
  });

  test(
    '业务失败：errcode=152 → business(152)；errcode=20018 也是 business（非 authentication）',
    () async {
      adapter.bytes = jsonBytes('{"status":0,"errcode":152,"data":{}}');
      await expectLater(
        fetchSearchDefault(session),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 152,
          ),
        ),
      );

      adapter.bytes = jsonBytes('{"status":1,"errcode":20018,"data":{}}');
      await expectLater(
        fetchSearchDefault(session),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'business' &&
                e.code == 20018,
          ),
        ),
        reason:
            'ErrcodeEnvelope 用 errcode 键；authentication_expiration 只认根上的 error_code',
      );
    },
  );

  test(
    'decode：status/errcode 缺失、data 非 object、ads 项非 object → decode',
    () async {
      adapter.bytes = jsonBytes('{"errcode":0,"data":{}}');
      await expectLater(
        fetchSearchDefault(session),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      adapter.bytes = jsonBytes('{"status":1,"errcode":0}');
      await expectLater(
        fetchSearchDefault(session),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
        reason: 'Data 从缺失的 data（Null）解码失败',
      );

      adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":[]}');
      await expectLater(
        fetchSearchDefault(session),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      adapter.bytes = jsonBytes(
        '{"status":1,"errcode":0,"data":{"ads":[null]}}',
      );
      await expectLater(
        fetchSearchDefault(session),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    },
  );
}
