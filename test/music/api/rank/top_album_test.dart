/// top_album 端点测试：POST 装配（token 进 body）+ 四地区解码 + 必填边界。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/top_album.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

String albumWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'timestamp': 1763700000,
    'chn': <Object?>[
      <String, Object?>{
        'albumid': '501',
        'albumname': 'Album A',
        'singerid': 11,
        'singername': 'Singer A',
        'intro': 'intro-a',
        'publishtime': '2026-11-01',
        'imgurl': 'http://imge.kugou.com/stdmusic/{size}/a.png',
        'isfirst': 1,
        'songcount': 10,
        'privilege': 8,
        'trans_param': <String, Object?>{'special_tag': 'tag-a'},
        'quality': 3,
        'ad_id': 77,
      },
    ],
    'eur': <Object?>[
      <String, Object?>{
        'albumid': 602,
        'albumname': 'Album E',
        'singername': 'Singer E',
        'imgurl': '',
        'trans_param': <String, Object?>{},
      },
    ],
    'jpn': <Object?>[],
    'kor': <Object?>[],
  },
});

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test(
    '请求装配：POST /musicadservice/v1/mobile_newalbum_sp，token 写进 body',
    () async {
      fixture.adapter.bytes = jsonBytes(albumWire());
      await fetchTopAlbums(fixture.session);

      final request = fixture.adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.path,
        'https://gateway.kugou.com/musicadservice/v1/mobile_newalbum_sp',
      );
      expect(request.headers['x-router'], isNull);
      final body = jsonDecode(request.bodyText) as Map<String, Object?>;
      expect(body['apiver'], 20);
      expect(body['token'], '', reason: '匿名身份 token 为空串');
      expect(body['page'], 1);
      expect(body['pagesize'], 30);
      expect(body['withpriv'], 1);
    },
  );

  test('解码：四地区分组（BTreeMap 字典序）+ 卡片/元数据字段', () async {
    fixture.adapter.bytes = jsonBytes(albumWire());
    final albums = await fetchTopAlbums(fixture.session);

    expect(albums.regions.keys.toList(), <String>['chn', 'eur', 'jpn', 'kor']);
    expect(albums.timestamp, 1763700000);

    final chn = albums.regions['chn']!.single;
    expect(chn.id, '501');
    expect(chn.title, 'Album A');
    expect(chn.creator, 'Singer A');
    expect(chn.coverUrl, 'http://imge.kugou.com/stdmusic/240/a.png');
    expect(chn.songCount, 10);
    expect(chn.publishedAt, '2026-11-01');
    expect(chn.metadata.artistId, 11);
    expect(chn.metadata.advertisementId, 77);
    expect(chn.metadata.description, 'intro-a');
    expect(chn.metadata.firstReleaseCode, 1);
    expect(chn.metadata.privilege, 8);
    expect(chn.metadata.qualityCode, 3);
    expect(chn.metadata.specialTag, 'tag-a');

    final eur = albums.regions['eur']!.single;
    expect(eur.id, '602', reason: '数字型 albumid 同样字符串化');
    expect(eur.metadata.specialTag, '', reason: 'special_tag 走 text 宽容');
    expect(albums.regions['jpn'], isEmpty);
    expect(albums.regions['kor'], isEmpty);
  });

  test('账号身份：body 携带真实 token', () async {
    final accountFixture = RankFixture(
      withIdentity: KugouIdentity.anonymous().withAccount(
        userId: 10086,
        token: 'tok-1',
      ),
    );
    accountFixture.adapter.bytes = jsonBytes(albumWire());
    await fetchTopAlbums(accountFixture.session);
    final body =
        jsonDecode(accountFixture.adapter.requests.single.bodyText)
            as Map<String, Object?>;
    expect(body['token'], 'tok-1');
  });

  test('边界：albumid 缺失 / trans_param 缺失 → decode；地区列表空对象宽容', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"chn":[{"albumname":"x","trans_param":{}}]}}',
    );
    await expectLater(
      fetchTopAlbums(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"chn":[{"albumid":1}]}}',
    );
    await expectLater(
      fetchTopAlbums(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"chn":{},"kor":[]}}',
    );
    final albums = await fetchTopAlbums(fixture.session);
    expect(albums.regions['chn'], isEmpty, reason: '空对象按 list 宽容归空表');
  });

  test('error_code 非 0 → business；data 非 object → decode', () async {
    fixture.adapter.bytes = jsonBytes('{"status":1,"error_code":9,"data":{}}');
    await expectLater(
      fetchTopAlbums(fixture.session),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('/9'),
        ),
      ),
    );

    fixture.adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    await expectLater(
      fetchTopAlbums(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
