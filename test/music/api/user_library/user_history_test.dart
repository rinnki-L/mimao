/// 听歌历史端点测试：请求装配（body 键序/签名/默认参数）、64 位 id 字符串
/// 语义、分页事实（has_more/finished/bp）、20017/业务/解码分支。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_history.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

/// 上游 user_history.rs 采样响应（隐私文本已替换；64 位 id 保持显式）。
const String sampledPage =
    '{"status":1,"error_code":0,"data":{"userid":"9007199254741005",'
    '"bp":"fixture-bp-1|0:fixture","bp_finished":"fixture-bp-1","has_more":1,'
    '"id":"","songs":[{"mxid":9007199254740993,"ot":1760000000,"op":1,"pc":7,'
    '"sr":0,"info":{"name":"示例歌曲","singername":"示例歌手",'
    '"hash":"0123456789abcdef0123456789abcdef","size":4359930,"timelen":272457,'
    '"bitrate":128,"cover":"https://example.com/cover.png",'
    '"mixsongid":9007199254740993,"album_id":9007199254740995,'
    '"audio_id":9007199254740997,"privilege":10,"level":1,"medistype":"flac",'
    '"albuminfo":{"name":"示例专辑","id":9007199254740999}}}]}}';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = accountIdentity();
  });

  test('请求装配：POST /playhistory/v1/get_songs，body 键序按 BTreeMap', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(sampledPage));
    final page = await fetchUserHistory(
      sessionFor(client, identity),
      const MusicUserHistoryQuery(),
    );
    expect(page.items, hasLength(1));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/playhistory/v1/get_songs'));
    expect(request.headers['x-router'], isNull);
    // json! 宏经 serde_json BTreeMap：键按字典序。
    expect(
      (jsonDecode(request.bodyText) as Map<String, Object?>).keys.toList(),
      <String>['source_classify', 'to_subdivide_sr', 'token', 'userid'],
    );
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body['source_classify'], 'app');
    expect(body['to_subdivide_sr'], 1);
    expect(body['token'], identity.token);
    expect(body['userid'], identity.userId);
    // 首页不带 bp。
    expect(body.containsKey('bp'), isFalse);
    // 标准请求：默认参数 + 账号字段注入 + Android 签名自洽。
    expect(request.query['appid'], '3116');
    expect(request.query['clientver'], '11440');
    expect(request.query['token'], identity.token);
    expect(request.query['userid'], '${identity.userId}');
    expect(request.query['uuid'], '-');
    expect(request.query['signature'], isNotNull);
    expectValidAndroidSignature(request);
  });

  test('带游标装配：bp 进 body 且排最前；游标 ≤4096 字节放行', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(sampledPage));
    final query = MusicUserHistoryQuery(bp: 'fixture-bp-0|0:seed');
    await fetchUserHistory(sessionFor(client, identity), query);
    final body =
        jsonDecode(adapter.requests.single.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'bp',
      'source_classify',
      'to_subdivide_sr',
      'token',
      'userid',
    ]);
    expect(body['bp'], 'fixture-bp-0|0:seed');
  });

  test('游标超 4096 字节 → input，且不发出请求', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(sampledPage));
    final query = MusicUserHistoryQuery(bp: 'x' * 4097);
    await expectLater(
      fetchUserHistory(sessionFor(client, identity), query),
      throwsKugou('input'),
    );
    expect(adapter.requests, isEmpty);
  });

  test('匿名身份 → authentication，不发出请求', () async {
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    adapter.bytes = Uint8List.fromList(utf8.encode(sampledPage));
    await expectLater(
      fetchUserHistory(
        sessionFor(client, anonymous),
        const MusicUserHistoryQuery(),
      ),
      throwsKugou('authentication'),
    );
    expect(adapter.requests, isEmpty);
  });

  test('采样页解码：64 位 id 保持字符串、时长/播放事实逐项对齐', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(sampledPage));
    final page = await fetchUserHistory(
      sessionFor(client, identity),
      const MusicUserHistoryQuery(),
    );
    expect(page.userId, '9007199254741005');
    expect(page.cursor, 'fixture-bp-1|0:fixture');
    expect(page.hasMore, isTrue);
    expect(page.finished, isFalse);
    final item = page.items.single;
    expect(item.songId, '9007199254740993');
    expect(item.albumId, '9007199254740995');
    expect(item.audioId, '9007199254740997');
    expect(item.name, '示例歌曲');
    expect(item.artist, '示例歌手');
    expect(item.album, '示例专辑');
    expect(item.hash, '0123456789abcdef0123456789abcdef');
    expect(item.cover, 'https://example.com/cover.png');
    expect(item.durationMs, 272457);
    expect(item.bitrate, 128);
    expect(item.playCount, 7);
    expect(item.lastPlayedAt, 1760000000);
  });

  test('完结页保留空游标：has_more=0 → finished=true，bp="" 原样', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        '{"status":1,"error_code":0,"data":{"userid":"9007199254741005",'
        '"bp":"","bp_finished":"","has_more":0,"songs":[]}}',
      ),
    );
    final page = await fetchUserHistory(
      sessionFor(client, identity),
      const MusicUserHistoryQuery(),
    );
    expect(page.finished, isTrue);
    expect(page.hasMore, isFalse);
    expect(page.items, isEmpty);
    expect(page.cursor, '');
  });

  test('songs 缺省/空对象/null 都给空表，翻页事实独立保留', () async {
    for (final songs in <Object?>[null, <String, Object?>{}]) {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 1,
            'error_code': 0,
            'data': <String, Object?>{
              'has_more': 1,
              'bp': 'next',
              'songs': songs,
            },
          }),
        ),
      );
      final page = await fetchUserHistory(
        sessionFor(client, identity),
        const MusicUserHistoryQuery(),
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
      expect(page.cursor, 'next');
    }
  });

  test('未知事实保持 null：has_more=99、pc 文本不可解析', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        '{"status":1,"error_code":0,"data":{"bp":"next","has_more":99,'
        '"songs":[{"mxid":123,"pc":"unknown"}]}}',
      ),
    );
    final page = await fetchUserHistory(
      sessionFor(client, identity),
      const MusicUserHistoryQuery(),
    );
    expect(page.cursor, 'next');
    expect(page.hasMore, isNull);
    expect(page.finished, isNull);
    final item = page.items.single;
    expect(item.songId, '123');
    expect(item.playCount, isNull);
  });

  test('显式 0 播放次数与完结事实原样保留', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        '{"status":1,"error_code":0,"data":{"has_more":0,'
        '"songs":[{"mxid":123,"pc":0}]}}',
      ),
    );
    final page = await fetchUserHistory(
      sessionFor(client, identity),
      const MusicUserHistoryQuery(),
    );
    expect(page.hasMore, isFalse);
    expect(page.finished, isTrue);
    expect(page.items.single.playCount, 0);
  });

  test('业务失败优先于不可用数据：20017 → authentication，30001 → business', () async {
    for (final (code, kind) in <(int, String)>[
      (20017, 'authentication'),
      (30001, 'business'),
    ]) {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 0,
            'error_code': code,
            'data': <String, Object?>{'songs': 'invalid'},
          }),
        ),
      );
      await expectLater(
        fetchUserHistory(
          sessionFor(client, identity),
          const MusicUserHistoryQuery(),
        ),
        throwsKugou(kind, code: code),
      );
    }
  });

  test('成功响应的畸形 data 不得当空页：data null / songs 非法 / 行为 null', () async {
    for (final data in <Object?>[
      null,
      <String, Object?>{'songs': 'invalid'},
      <String, Object?>{
        'has_more': 1,
        'bp': 'next',
        'songs': <Object?>[
          <String, Object?>{'mxid': 123},
          null,
        ],
      },
    ]) {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 1,
            'error_code': 0,
            'data': data,
          }),
        ),
      );
      await expectLater(
        fetchUserHistory(
          sessionFor(client, identity),
          const MusicUserHistoryQuery(),
        ),
        throwsKugou('decode'),
      );
    }
  });

  test('mxid 缺省回退 info.mixsongid；info 缺省给空事实', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        '{"status":1,"error_code":0,"data":{"has_more":0,"songs":['
        '{"pc":3,"info":{"mixsongid":"4567","name":"回退歌"}},'
        '{"mxid":"89","pc":4}]}}',
      ),
    );
    final page = await fetchUserHistory(
      sessionFor(client, identity),
      const MusicUserHistoryQuery(),
    );
    expect(page.items, hasLength(2));
    expect(page.items[0].songId, '4567');
    expect(page.items[0].name, '回退歌');
    expect(page.items[1].songId, '89');
    expect(page.items[1].name, '');
    expect(page.items[1].playCount, 4);
  });

  test('封面模板 {size} 替换为 240；cover 缺失回退 trans_param.union_cover', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        '{"status":1,"error_code":0,"data":{"has_more":0,"songs":['
        '{"info":{"name":"有封面","cover":'
        '"http://imge.kugou.com/stdmusic/{size}/a.jpg"}},'
        '{"info":{"name":"回退封面","trans_param":{"union_cover":'
        '"http://imge.kugou.com/stdmusic/{size}/b.jpg"}}},'
        '{"info":{"name":"无封面"}}]}}',
      ),
    );
    final page = await fetchUserHistory(
      sessionFor(client, identity),
      const MusicUserHistoryQuery(),
    );
    expect(page.items[0].cover, 'http://imge.kugou.com/stdmusic/240/a.jpg');
    expect(page.items[1].cover, 'http://imge.kugou.com/stdmusic/240/b.jpg');
    expect(page.items[2].cover, isNull);
  });
}
