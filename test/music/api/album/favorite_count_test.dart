/// 收藏计数端点测试：GET 装配（mixsongids 逗号连接/空表原样）+ errcode 缺省
/// 0 + data/list/元素坏形静默归空 + flatten 旁路 + 20018 双键语义区分。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/favorite_count.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/album_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
  });

  Future<List<MusicAlbumFavoriteCount>> fetch(List<int> ids) =>
      fetchFavoriteCount(fakeMusicSession(client), ids);

  test(
    '请求装配：GET /count/v1/audio/mget_collect + mixsongids 逗号连接 + 签名自验',
    () async {
      adapter.bytes = jsonBytes(countsWire());
      await fetch(<int>[7301, 7302, 7303]);

      final captured = adapter.requests.single;
      expect(captured.method, 'GET');
      expect(
        captured.path,
        'https://gateway.kugou.com/count/v1/audio/mget_collect',
      );
      expect(captured.query['mixsongids'], '7301,7302,7303');
      expect(
        captured.headers.containsKey('x-router'),
        isFalse,
        reason: '上游 request 无 router',
      );

      final query = Map<String, String>.from(captured.query);
      expect(query['dfid'], '-');
      expect(query['mid'], fixedIdentity().mid);
      final signature = query.remove('signature');
      expect(signature, kugouSignatureAndroid(query, const <int>[]));
    },
  );

  test('input：空 ids 无校验，原样发送 mixsongids=（与上游一致）', () async {
    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{"list":[]}}');
    await fetch(<int>[]);
    expect(adapter.requests.single.query['mixsongids'], '');
  });

  test('解码成功：数字/字符串宽容 + count_text + flatten 捕获其余键', () async {
    adapter.bytes = jsonBytes(countsWire());
    final counts = await fetch(<int>[7301, 7302]);

    expect(counts, hasLength(2));
    expect(counts[0].mixsongId, 7301);
    expect(counts[0].count, 12000);
    expect(counts[0].countText, '1.2万');
    expect(counts[0].extension, <String, Object?>{'cid': 'c1'});
    expect(counts[1].mixsongId, 7302);
    expect(counts[1].count, 3);
    expect(counts[1].countText, '3');
    expect(counts[1].extension, isEmpty);
  });

  test('errcode 缺省 0：status=1 无 errcode 仍成功（serde default）', () async {
    adapter.bytes = jsonBytes('{"status":1,"data":{"list":[]}}');
    expect(await fetch(<int>[1]), isEmpty);
  });

  test('data 坏形静默归空：data 缺失/非 object/list 错配/元素非 object', () async {
    for (final body in <String>[
      '{"status":1,"errcode":0}',
      '{"status":1,"errcode":0,"data":"str"}',
      '{"status":1,"errcode":0,"data":[]}',
      '{"status":1,"errcode":0,"data":{"list":"str"}}',
      '{"status":1,"errcode":0,"data":{"list":["str"]}}',
    ]) {
      adapter.bytes = jsonBytes(body);
      expect(await fetch(<int>[1]), isEmpty, reason: body);
    }
  });

  test('业务失败 status=0 → business 携带 errcode', () async {
    adapter.bytes = jsonBytes('{"status":0,"errcode":32002,"data":{}}');
    await expectLater(
      fetch(<int>[1]),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 32002),
      ),
    );
  });

  test('errcode=20018 仍是 business（登录过期判定只看 error_code 键/msg）', () async {
    adapter.bytes = jsonBytes('{"status":0,"errcode":20018,"data":{}}');
    await expectLater(
      fetch(<int>[1]),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 20018),
      ),
    );
  });

  test('error_code=20018（字面键）或 msg 含「登录已过期」→ authentication', () async {
    adapter.bytes = jsonBytes('{"error_code":20018,"data":{}}');
    await expectLater(
      fetch(<int>[1]),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'authentication')
            .having((e) => e.code, 'code', 20018),
      ),
    );

    adapter.bytes = jsonBytes('{"status":0,"errcode":0,"msg":"用户登录已过期，请重新登录"}');
    await expectLater(
      fetch(<int>[1]),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });
}

/// 最小可信收藏计数 wire（favorite_count.rs 的采样形状）。
String countsWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'errcode': 0,
  'data': <String, Object?>{
    'list': <Object?>[
      <String, Object?>{
        'mixsongid': '7301',
        'count': '12000',
        'count_text': '1.2万',
        'cid': 'c1',
      },
      <String, Object?>{'mixsongid': 7302, 'count': 3, 'count_text': '3'},
    ],
  },
});
