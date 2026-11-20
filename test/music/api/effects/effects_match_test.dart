/// 耳机音效匹配端点测试（effects_match.rs）：请求装配（无分页参数）+
/// common 的 optional 宽容（非法结构吞成 null）+ 信封分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/effects_match.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/effects_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// audio_effect.rs `Headphone` wire（match 的 common 字段）。
Map<String, Object?> matchedHeadphone({
  Object? model = 'FreeBuds Pro 3',
  Object? modelIcon = 'http://imge.kugou.com/hp/{size}/fbp3.png',
  Object? isUnlocked = 1,
  Map<String, Object?>? sound,
}) => <String, Object?>{
  'model_id': 7001,
  if (model != null) 'model': model,
  if (modelIcon != null) 'model_icon': modelIcon,
  if (isUnlocked != null) 'is_unlocked': isUnlocked,
  'sound':
      sound ??
      <String, Object?>{
        'id': 5753,
        'sound': 'https://down.kugou.com/hp/5753.wav',
      },
};

/// effects_match.rs `Wire`：ErrcodeEnvelope + Data（common 为可选 Headphone）。
String matchWire({
  int status = 1,
  int errcode = 0,
  Object? data = const <String, Object?>{},
}) => jsonEncode(<String, Object?>{
  'status': status,
  'errcode': errcode,
  'data': data,
});

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(matchWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<MusicEffect?> fetch() =>
      fetchEffectsMatch(fakeEffectsSession(client, identity));

  test('请求装配：effectsCatalog 主机/路径/plat+version/clearDefaults/签名', () async {
    adapter.bytes = jsonBytes(
      matchWire(data: <String, Object?>{'common': matchedHeadphone()}),
    );
    await fetch();

    final captured = adapter.requests.single;
    expect(captured.method, 'GET');
    expect(
      '${adapter.captured.uri}'.startsWith(
        'http://mobilecdngz.kugou.com/api/v5/earphone/match?',
      ),
      isTrue,
    );
    final query = captured.query;
    // 上游 execute 的参数只有 plat/version + signature。
    expect(query, <String, String>{
      'plat': '2',
      'version': '12460',
      'signature': query['signature']!,
    });
    for (final key in const <String>[
      'appid',
      'clientver',
      'clienttime',
      'dfid',
      'mid',
      'token',
      'userid',
      'uuid',
      'page',
      'pagesize',
    ]) {
      expect(query.containsKey(key), isFalse, reason: 'clearDefaults 不注入 $key');
    }
    expect(
      query['signature'],
      kugouSignatureAndroid(<String, String>{
        'plat': '2',
        'version': '12460',
      }, const <int>[]),
    );
    expect(captured.headers['clienttime'], isNull);
    expect(captured.headers['dfid'], identity.dfid);
    expect(captured.headers['mid'], identity.mid);
    expect(captured.headers['x-router'], isNull);
  });

  test('解码：common → MusicEffect（id 取 sound.id；固定 intro；未解锁标记）', () async {
    adapter.bytes = jsonBytes(
      matchWire(
        data: <String, Object?>{'common': matchedHeadphone(isUnlocked: 0)},
      ),
    );
    final effect = await fetch();
    expect(effect, isNotNull);
    expect(effect!.id, 5753, reason: '不是 model_id（7001）');
    expect(effect.name, 'FreeBuds Pro 3');
    expect(effect.intro, '针对对应耳机型号调校，请选择与你的设备一致的型号。');
    expect(effect.iconUrl, 'http://imge.kugou.com/hp/240/fbp3.png');
    expect(effect.source, 'headphone');
    expect(effect.unavailableReason, '此耳机音效尚未解锁');
  });

  test(
    'optional 宽容：common 缺失/null/空 object/非 object/缺 sound → null 不抛',
    () async {
      // data.common 走 response.rs optional：非法结构吞成 None。
      for (final data in <Object?>[
        <String, Object?>{},
        <String, Object?>{'common': null},
        <String, Object?>{'common': <String, Object?>{}},
        <String, Object?>{'common': 5},
        <String, Object?>{'common': 'text'},
        <String, Object?>{
          'common': <String, Object?>{'model': 'X'},
        },
        <String, Object?>{
          'common': <String, Object?>{
            'model': 'X',
            'sound': <String, Object?>{'name': 'x'},
          },
        },
      ]) {
        adapter.bytes = jsonBytes(matchWire(data: data));
        expect(await fetch(), isNull, reason: 'common=$data → None');
      }
    },
  );

  test('data 本身缺失/非 object → decode（from_value::<Data> 严格）', () async {
    for (final wire in <String>[
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 0}),
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 0, 'data': null}),
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 0, 'data': []}),
    ]) {
      adapter.bytes = jsonBytes(wire);
      await expectLater(
        fetch(),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    }
  });

  test(
    '信封：errcode=20018 → business；error_code=20018 / msg 过期 → authentication',
    () async {
      // effects 信封的 errcode 不触发 authentication_expiration（success 判定）。
      adapter.bytes = jsonBytes(matchWire(errcode: 20018));
      await expectLater(
        fetch(),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'business' &&
                e.code == 20018,
          ),
        ),
      );
      // 宽松 error_code 探测（decode 前置）。
      adapter.bytes = jsonBytes(
        jsonEncode(<String, Object?>{
          'status': 1,
          'errcode': 0,
          'error_code': '20018',
          'data': <String, Object?>{},
        }),
      );
      await expectLater(
        fetch(),
        throwsA(
          predicate(
            (Object e) => e is KugouApiException && e.kind == 'authentication',
          ),
        ),
      );
      // msg 含「登录已过期」同样前置（即使 errcode/status 表面上是业务失败）。
      adapter.bytes = jsonBytes(
        jsonEncode(<String, Object?>{
          'status': 0,
          'errcode': 9,
          'msg': '用户登录已过期，请重新登录',
        }),
      );
      await expectLater(
        fetch(),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'authentication' &&
                // msg 路径不带 code（authentication_expiration 只读
                // error_code 字段，上游 error.code = None）。
                e.code == null,
          ),
        ),
      );
    },
  );

  test('业务失败：status=0 → business 带码', () async {
    adapter.bytes = jsonBytes(matchWire(status: 0, errcode: 31002));
    await expectLater(
      fetch(),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 31002,
        ),
      ),
    );
  });
}
