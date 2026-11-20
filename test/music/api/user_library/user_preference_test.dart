/// 偏好读取端点测试：preference 协议装配（显式参数+端点自算签名+cloud 语义）、
/// p/params 密文形状、WeightPreference 三态、解码/业务分支。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_preference.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_library_models.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

const String kTestSeed = '0123456789abcdef';
final DateTime kFixedNow = DateTime.fromMillisecondsSinceEpoch(
  1764000000000,
  isUtc: true,
);

/// 偏好响应（六字段全为字符串/对象形态）。
String preferencesWire(Map<String, Object?> fields) =>
    jsonEncode(<String, Object?>{'status': 1, 'error_code': 0, 'data': fields});

void main() {
  late CaptureAdapter adapter;
  late HostCaptureAdapter hostAdapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    hostAdapter = HostCaptureAdapter(adapter);
    client = KugouClient(dio: Dio()..httpClientAdapter = hostAdapter);
    identity = accountIdentity();
  });

  Future<MusicPreferences> fetch() => fetchUserPreference(
    sessionFor(client, identity),
    seed: kTestSeed,
    now: () => kFixedNow,
  );

  test('请求装配：显式参数+端点签名，cloud+clearDefaults 下 URL 无 token/userid', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(preferencesWire(<String, Object?>{})),
    );
    await fetch();

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/userpreferservice/v1/get_user_conf'));
    expect(hostAdapter.uris.single.host, 'gateway.kugou.com');
    expect(request.headers['x-router'], isNull);
    // request_grade：clearDefaults 后只剩端点显式列出的参数 + 自算签名；
    // token/userid 只在 body/加密画像里，URL 上必须缺席。
    expect(request.query.keys.toSet(), <String>{
      'appid',
      'clienttime',
      'clientver',
      'dfid',
      'mid',
      'signature',
      'uuid',
    });
    expect(request.query['appid'], '3116');
    expect(request.query['clientver'], '11440');
    // clienttime 与加密画像里的秒级时间戳同源（同一 time）。
    expect(
      request.query['clienttime'],
      '${kFixedNow.millisecondsSinceEpoch ~/ 1000}',
    );
    expect(request.query['uuid'], identity.uuid);
    expectValidAndroidSignature(request);
    expect(request.headers['KG-Rec'], '1');
    expect(request.headers['KG-RC'], '1');
    expect(
      request.headers['User-Agent'],
      'Android15-1070-11440-201-0-get_user_conf-wifi',
    );
    expect(request.headers['Content-Type'], 'application/json');
  });

  test('body 键序（BTreeMap 字典序）+ p 为小写 256 hex + params 可解密', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(preferencesWire(<String, Object?>{})),
    );
    await fetch();

    final request = adapter.requests.single;
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>['p', 'params', 'plat', 'userid']);
    expect(body['plat'], 1);
    expect(body['userid'], identity.userId);
    final p = body['p']! as String;
    expect(p, hasLength(256));
    expect(RegExp(r'^[0-9a-f]{256}$').hasMatch(p), isTrue);
    // portrait 公开 JSON 是 {"clienttime":"<秒>","key":"<seed>"}（字典序），
    // p 应与裸 RSA 画像一致（小写）。
    final expectedPortrait = kugouUserPortrait(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'clienttime': '${kFixedNow.millisecondsSinceEpoch ~/ 1000}',
          'key': kTestSeed,
        }),
      ),
    ).toLowerCase();
    expect(p, expectedPortrait);
    // params 用信封 seed 可解密回 {"token": ...}（BTreeMap 键序）。
    final decrypted = utf8.decode(
      kugouDecryptCredentials(body['params']! as String, kTestSeed),
    );
    expect(decrypted, '{"token":"${identity.token}"}');
  });

  test('解码：字符串字段 + 权重偏好三态（字符串/对象/数字/空串）', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        preferencesWire(<String, Object?>{
          'mode': 'classic',
          'gender': '1',
          'age': '18-25',
          // 字符串编码的权重表 → encoded 原样 + weights 解析。
          'lang': '{"8080":3,"8583":0.5}',
          // 对象形态 → encoded 是紧凑 JSON（BTreeMap 键序）。
          'style': <String, Object?>{'8583': 2, '8080': 1.5},
          // 空串 → weights 空表（不 null）。
          'song_lang': '',
        }),
      ),
    );
    final preferences = await fetch();
    expect(preferences.recommendationMode, 'classic');
    expect(preferences.gender, '1');
    expect(preferences.age, '18-25');

    expect(preferences.languages.encoded, '{"8080":3,"8583":0.5}');
    expect(preferences.languages.weights, <String, double>{
      '8080': 3.0,
      '8583': 0.5,
    });
    expect(preferences.languages.raw, '{"8080":3,"8583":0.5}');

    expect(preferences.styles.encoded, '{"8080":1.5,"8583":2}');
    expect(preferences.styles.weights, <String, double>{
      '8080': 1.5,
      '8583': 2.0,
    });
    expect(preferences.styles.raw, <String, Object?>{'8583': 2, '8080': 1.5});

    expect(preferences.recommendation.encoded, '');
    expect(preferences.recommendation.weights, <String, double>{});
  });

  test('宽容面：数字字段取字面量；bool/非法编码不拒绝整页', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        preferencesWire(<String, Object?>{
          'mode': 7,
          'gender': true,
          'lang': 5,
          'style': 'not-json',
          'song_lang': '{"8080":"bad"}',
        }),
      ),
    );
    final preferences = await fetch();
    expect(preferences.recommendationMode, '7');
    expect(preferences.gender, isNull);
    // 数字形态：WeightPreference 只认字符串/对象 → encoded/weights 双 null
    // （原值保留在 raw）。
    expect(preferences.languages.encoded, isNull);
    expect(preferences.languages.weights, isNull);
    expect(preferences.languages.raw, 5);
    expect(preferences.styles.encoded, 'not-json');
    expect(preferences.styles.weights, isNull);
    expect(preferences.recommendation.encoded, '{"8080":"bad"}');
    expect(preferences.recommendation.weights, isNull);
  });

  test('匿名身份 → authentication，不发出请求', () async {
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    adapter.bytes = Uint8List.fromList(
      utf8.encode(preferencesWire(<String, Object?>{})),
    );
    await expectLater(
      fetchUserPreference(
        sessionFor(client, anonymous),
        seed: kTestSeed,
        now: () => kFixedNow,
      ),
      throwsKugou('authentication'),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    '业务失败 → business 带码；20018 → authentication；data null → decode',
    () async {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 0,
            'error_code': 30231,
            'data': <String, Object?>{'mode': 'invalid'},
          }),
        ),
      );
      await expectLater(fetch(), throwsKugou('business', code: 30231));

      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 0,
            'error_code': 20018,
            'data': <String, Object?>{'mode': 'invalid'},
          }),
        ),
      );
      await expectLater(fetch(), throwsKugou('authentication'));

      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 1,
            'error_code': 0,
            'data': null,
          }),
        ),
      );
      await expectLater(fetch(), throwsKugou('decode'));
    },
  );
}
