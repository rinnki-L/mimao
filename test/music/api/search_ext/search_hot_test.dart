/// search_hot 测试：msearch 路由、navid/plat 参数、分组/关键词解码宽容、
/// ErrcodeEnvelope 业务失败与 decode 分支。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/search_hot.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

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

  test(
    '请求装配：GET /api/v3/search/hot_tab + x-router=msearch + navid/plat',
    () async {
      adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{"list":[]}}');
      await fetchSearchHot(session);

      expect(
        '${adapter.captured.uri}'.startsWith(
          'https://gateway.kugou.com/api/v3/search/hot_tab?',
        ),
        isTrue,
      );
      expect(adapter.captured.method, 'GET');
      expect(adapter.captured.headers['x-router'], 'msearch.kugou.com');
      final query = capturedQuery(adapter.captured);
      expect(query['navid'], '1');
      expect(query['plat'], '2');
      expect(query['appid'], '3116');
      expect(query['dfid'], identity.dfid);
      expect(query.containsKey('token'), isFalse);
    },
  );

  test('解码：分组/关键词字段映射 + 数字字符串宽容', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":['
      '{"name":"热歌榜","keywords":['
      '{"keyword":"晴天","reason":"热度攀升","type":"1","icon":2,'
      '"jumpurl":"https://j.example","json_url":"https://j.example/x.json"},'
      '{"keyword":"雨天","reason":"","type":3,"icon":0,"jumpurl":"","json_url":""}'
      ']},'
      '{"name":"空分组","keywords":[]}'
      ']}}',
    );
    final groups = await fetchSearchHot(session);
    expect(groups, hasLength(2));
    expect(groups[0].title, '热歌榜');
    final first = groups[0].keywords[0];
    expect(first.keyword, '晴天');
    expect(first.reason, '热度攀升');
    expect(first.kind, 1, reason: 'type 是数字字符串，scalar 宽容解码');
    expect(first.icon, 2);
    expect(first.jumpUrl, 'https://j.example');
    expect(first.jsonUrl, 'https://j.example/x.json');
    final second = groups[0].keywords[1];
    expect(second.kind, 3);
    expect(second.icon, 0, reason: '0 是合法 icon，不是缺省');
    expect(groups[1].keywords, isEmpty);
  });

  test('解码：list/keywords 缺省与空对象宽容', () async {
    for (final data in <String>[
      '{}',
      '{"list":null}',
      '{"list":{}}',
      '{"list":[{"name":"g","keywords":null}]}',
      '{"list":[{"name":"g","keywords":{}}]}',
    ]) {
      adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":$data}');
      final groups = await fetchSearchHot(session);
      expect(
        groups.expand((group) => group.keywords).toList(),
        isEmpty,
        reason: 'data=$data',
      );
    }
  });

  test('业务失败：errcode=152 → business(152)；errcode=20018 也是 business', () async {
    adapter.bytes = jsonBytes('{"status":0,"errcode":152,"data":{}}');
    await expectLater(
      fetchSearchHot(session),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"errcode":20018,"data":{}}');
    await expectLater(
      fetchSearchHot(session),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 20018,
        ),
      ),
      reason: 'errcode 键的 20018 不触发 authentication（上游只认 error_code 键）',
    );
  });

  test('decode：data 非 object / 分组项、关键词项非 object → decode', () async {
    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":"x"}');
    await expectLater(
      fetchSearchHot(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[null]}}',
    );
    await expectLater(
      fetchSearchHot(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[{"name":"g","keywords":[null]}]}}',
    );
    await expectLater(
      fetchSearchHot(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
