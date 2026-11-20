/// 专辑详情端点测试：POST 装配（body 字段序/kg-tid/router/签名）+ 解码成功
/// + 空数组/空对象 → null + 残缺专辑 + 业务/过期/decode 分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/album_detail.dart';
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

  Future<MusicAlbumDetail?> fetch() =>
      fetchAlbumDetail(fakeMusicSession(client), 8890);

  test(
    '请求装配：POST /kmr/v2/albums + router + kg-tid + body 字段序 + 签名自验',
    () async {
      adapter.bytes = jsonBytes(albumWire());
      await fetch();

      final captured = adapter.requests.single;
      expect(captured.method, 'POST');
      expect(captured.path, 'https://gateway.kugou.com/kmr/v2/albums');
      expect(captured.headers['x-router'], 'openapi.kugou.com');
      expect(captured.headers['kg-tid'], '255');
      expect(captured.headers['Content-Type'], 'application/json');

      final body = jsonDecode(captured.bodyText) as Map<String, Object?>;
      // serde 序列化顺序 = 字段声明顺序：data → is_buy → fields。
      expect(body.keys.toList(), <String>['data', 'is_buy', 'fields']);
      expect((body['data'] as List<Object?>).single, <String, Object?>{
        'album_id': '8890',
      });
      expect(body['is_buy'], 0);
      expect(body['fields'], kugouAlbumDetailFields);

      // 网关默认参数（匿名身份不带 token/userid）+ 签名可复算。
      final query = Map<String, String>.from(captured.query);
      expect(query['appid'], '3116');
      expect(query['clientver'], '11440');
      expect(query['dfid'], '-');
      expect(query['mid'], fixedIdentity().mid);
      expect(query['uuid'], '-');
      expect(query.containsKey('token'), isFalse);
      expect(query.containsKey('userid'), isFalse);
      final signature = query.remove('signature');
      expect(
        signature,
        kugouSignatureAndroid(query, utf8.encode(captured.bodyText)),
      );
    },
  );

  test('解码成功：字符串 id/flag 解析、封面 {size}→240、作者 id 回退 null', () async {
    adapter.bytes = jsonBytes(albumWire());
    final album = await fetch();

    expect(album, isNotNull);
    expect(album!.id, 8890);
    expect(album.title, '专辑名');
    expect(album.artists, hasLength(2));
    expect(album.artists[0].id, 11);
    expect(album.artists[0].name, '歌手A');
    expect(album.artists[1].id, isNull);
    expect(album.coverUrl, 'http://imge.kugou.com/album/240/cover.jpg');
    expect(album.publishedAt, '2021-08-01');
    expect(album.publisher, '厂牌');
    expect(album.description, '简介');
    expect(album.language, '国语');
    expect(album.category, '录音室专辑');
    expect(album.heat, 80);
    expect(album.quality, 10);
    expect(album.exclusive, isTrue);
    expect(album.published, isFalse);
  });

  test('空 data 数组与空对象 → null（无此专辑，不是错误）', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    expect(await fetch(), isNull);

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[{}]}');
    expect(await fetch(), isNull);
  });

  test('残缺专辑保留可用事实；可选字段缺失归空/未知', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":['
      '{"album_id":"42","album_name":"部分专辑","exclusive":"2","is_publish":"true"}'
      ']}',
    );
    final album = await fetch();

    expect(album!.id, 42);
    expect(album.title, '部分专辑');
    expect(album.artists, isEmpty);
    expect(album.coverUrl, '');
    expect(album.publisher, '');
    // 非 0/1 的 flag 与不可解析文本 → 未知（null），不臆造 false。
    expect(album.exclusive, isNull);
    expect(album.published, isNull);
    expect(album.heat, isNull);
    expect(album.quality, isNull);
  });

  test(
    '业务失败 status=0 → business 携带 error_code；20018 → authentication',
    () async {
      adapter.bytes = jsonBytes('{"status":0,"error_code":32002,"data":[]}');
      await expectLater(
        fetch(),
        throwsA(
          isA<KugouApiException>()
              .having((e) => e.kind, 'kind', 'business')
              .having((e) => e.code, 'code', 32002),
        ),
      );

      adapter.bytes = jsonBytes('{"error_code":20018,"data":[]}');
      await expectLater(
        fetch(),
        throwsA(
          isA<KugouApiException>().having(
            (e) => e.kind,
            'kind',
            'authentication',
          ),
        ),
      );
    },
  );

  test('decode：data 条目非 object / authors 元素非 object → decode', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":["str"]}');
    await expectLater(
      fetch(),
      throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', 'decode')),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":[{"authors":["x"]}]}',
    );
    await expectLater(
      fetch(),
      throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', 'decode')),
    );
  });
}

/// 最小可信专辑 wire（album_detail.rs 的采样形状：id/flag 都是字符串）。
String albumWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <Object?>[
    <String, Object?>{
      'album_id': '8890',
      'album_name': '专辑名',
      'authors': <Object?>[
        <String, Object?>{'author_id': '11', 'author_name': '歌手A'},
        <String, Object?>{'author_name': '歌手B'},
      ],
      'sizable_cover': 'http://imge.kugou.com/album/{size}/cover.jpg',
      'publish_date': '2021-08-01',
      'publish_company': '厂牌',
      'intro': '简介',
      'language': '国语',
      'type': '录音室专辑',
      'heat': '80',
      'quality': '10',
      'exclusive': '1',
      'is_publish': '0',
    },
  ],
});
