/// 偏好写入端点测试：差量字段表（键序/只带显式字段/空表拒绝）、update 专用
/// 路径与 UA、AckEnvelope 成功判定、业务/认证优先级。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_preference_update.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_library_models.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

const String kTestSeed = '0123456789abcdef';
final DateTime kFixedNow = DateTime.fromMillisecondsSinceEpoch(
  1764000000000,
  isUtc: true,
);

String ackWire(Map<String, Object?> envelope) => jsonEncode(envelope);

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = accountIdentity();
  });

  Future<MusicPreferenceAcknowledgement> fetch(
    MusicPreferenceUpdateQuery query,
  ) => fetchUserPreferenceUpdate(
    sessionFor(client, identity),
    query,
    seed: kTestSeed,
    now: () => kFixedNow,
  );

  test('全部字段缺省 → input「偏好没有变化」，不发出请求', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(ackWire(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    await expectLater(
      fetch(const MusicPreferenceUpdateQuery()),
      throwsKugou('input'),
    );
    expect(adapter.requests, isEmpty);
  });

  test('请求装配：update_user_conf 路径/UA，data 只带显式字段且键序有序', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(ackWire(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    const query = MusicPreferenceUpdateQuery(
      recommendationMode: 'classic',
      styles: '{"8080":2}',
      recommendation: '',
    );
    final ack = await fetch(query);
    expect(ack.updated, isTrue);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/userpreferservice/v1/update_user_conf'));
    expect(
      request.headers['User-Agent'],
      'Android15-1070-11440-201-0-update_user_conf-wifi',
    );
    // body：data < p < params < plat < userid（BTreeMap 字典序）。
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'data',
      'p',
      'params',
      'plat',
      'userid',
    ]);
    // 差量字段表：只带显式给出的三个字段，键按字典序（lang < mode < song_lang
    // < style）；空串也是有效值。
    final data = body['data']! as Map<String, Object?>;
    expect(data.keys.toList(), <String>['mode', 'song_lang', 'style']);
    expect(data['mode'], 'classic');
    expect(data['song_lang'], '');
    expect(data['style'], '{"8080":2}');
    expectValidAndroidSignature(request);
    // cloud + clearDefaults：URL 上无 token/userid。
    expect(request.query.containsKey('token'), isFalse);
    expect(request.query.containsKey('userid'), isFalse);
    expect(request.query['signature'], isNotNull);
  });

  test(
    '六字段全给 → data 键序 age < gender < lang < mode < song_lang < style',
    () async {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(ackWire(<String, Object?>{'status': 1, 'error_code': 0})),
      );
      const query = MusicPreferenceUpdateQuery(
        recommendationMode: 'm',
        gender: 'g',
        age: 'a',
        languages: 'l',
        styles: 's',
        recommendation: 'r',
      );
      await fetch(query);
      final body =
          jsonDecode(adapter.requests.single.bodyText) as Map<String, Object?>;
      expect((body['data']! as Map<String, Object?>).keys.toList(), <String>[
        'age',
        'gender',
        'lang',
        'mode',
        'song_lang',
        'style',
      ]);
    },
  );

  test('成功判定：status=1 且 error_code=0 → updated（data 形态不参与）', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        ackWire(<String, Object?>{'status': 1, 'error_code': 0, 'data': ''}),
      ),
    );
    final ack = await fetch(const MusicPreferenceUpdateQuery(gender: '2'));
    expect(ack.updated, isTrue);
  });

  test('业务失败：status=0/error_code=30201 → business；20017 也是 business'
      '（preference 转换没有 20017 认证分支）', () async {
    for (final code in const [30201, 20017]) {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          ackWire(<String, Object?>{
            'status': 0,
            'error_code': code,
            'data': null,
          }),
        ),
      );
      await expectLater(
        fetch(const MusicPreferenceUpdateQuery(gender: '2')),
        throwsKugou('business', code: code),
      );
    }
  });

  test('字段校验先于账号检查（Rust 求值顺序）：匿名 + 空字段 → input', () async {
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    adapter.bytes = Uint8List.fromList(
      utf8.encode(ackWire(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    await expectLater(
      fetchUserPreferenceUpdate(
        sessionFor(client, anonymous),
        const MusicPreferenceUpdateQuery(),
      ),
      throwsKugou('input'),
    );
    expect(adapter.requests, isEmpty);
  });

  test('匿名 + 非空字段 → authentication', () async {
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    adapter.bytes = Uint8List.fromList(
      utf8.encode(ackWire(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    await expectLater(
      fetchUserPreferenceUpdate(
        sessionFor(client, anonymous),
        const MusicPreferenceUpdateQuery(gender: '2'),
        seed: kTestSeed,
        now: () => kFixedNow,
      ),
      throwsKugou('authentication'),
    );
    expect(adapter.requests, isEmpty);
  });

  test('响应缺 status/error_code → decode', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode('{"status":1}'));
    await expectLater(
      fetch(const MusicPreferenceUpdateQuery(gender: '2')),
      throwsKugou('decode'),
    );
  });
}
