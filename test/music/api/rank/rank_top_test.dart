/// rank_top 端点测试：请求装配（无端点参数）+ data.list 解码 + 边界分支。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/rank_top.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test('请求装配：GET /mobileservice/api/v5/rank/rec_rank_list 无端点参数', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[]}}',
    );
    await fetchRankTop(fixture.session);

    final request = fixture.adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      'https://gateway.kugou.com/mobileservice/api/v5/rank/rec_rank_list',
    );
    expect(request.headers['x-router'], isNull);
    expect(
      request.query.containsKey('plat'),
      isFalse,
      reason: '上游 BTreeMap::new()',
    );
    expect(request.query['signature'], isNotNull);
    expect(request.query['mid'], fixture.identity.mid);
  });

  test('解码：list 条目与 rank_list 同结构（rank_catalog WireRank）', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":['
      '{"rankid":"10","rankname":"热歌榜","imgurl":"",'
      '"update_frequency":"每周一更新","rank_id_publish_date":"2026-11-16"}'
      ']}}',
    );
    final ranks = await fetchRankTop(fixture.session);

    expect(ranks.single.id, 10);
    expect(ranks.single.title, '热歌榜');
    expect(ranks.single.updateFrequency, '每周一更新');
    expect(ranks.single.publishedAt, '2026-11-16');
    expect(ranks.single.category, isNull);
  });

  test('list 缺省/空对象归空表；info 键不存在于本端点', () async {
    for (final body in <String>[
      '{"status":1,"errcode":0,"data":{}}',
      '{"status":1,"errcode":0,"data":{"list":null}}',
      '{"status":1,"errcode":0,"data":{"list":{}}}',
    ]) {
      fixture.adapter.bytes = jsonBytes(body);
      expect(await fetchRankTop(fixture.session), isEmpty, reason: body);
    }
  });

  test('errcode 非 0 → business；条目非 object → decode', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":7,"data":{"list":[]}}',
    );
    await expectLater(
      fetchRankTop(fixture.session),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('/7'),
        ),
      ),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[1]}}',
    );
    await expectLater(
      fetchRankTop(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
