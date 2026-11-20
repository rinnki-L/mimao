/// rank_list 端点测试：请求装配（固定三参）+ errcode 信封解码 + 边界分支。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/rank_list.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test('请求装配：GET /ocean/v6/rank/list + plat/withsong/parentid 固定三参', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"info":[]}}',
    );
    await fetchRankList(fixture.session);

    final request = fixture.adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, 'https://gateway.kugou.com/ocean/v6/rank/list');
    expect(request.headers['x-router'], isNull, reason: '上游 router 为 None');
    expect(request.query['plat'], '2');
    expect(request.query['withsong'], '1');
    expect(request.query['parentid'], '0');
    expect(request.query['signature'], isNotNull);
  });

  test('解码：info 条目映射 + 封面占位符替换（rank_catalog WireRank）', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"info":['
      '{"rankid":1234,"rankname":"飙升榜","imgurl":"http://imge.kugou.com/kpic/{size}/a.png",'
      '"intro":"desc","update_frequency":"每天更新","ranktype":1,"rank_id_publish_date":"2026-11-20"}'
      ']}}',
    );
    final ranks = await fetchRankList(fixture.session);

    final rank = ranks.single;
    expect(rank.id, 1234);
    expect(rank.title, '飙升榜');
    expect(rank.coverUrl, 'http://imge.kugou.com/kpic/240/a.png');
    expect(rank.description, 'desc');
    expect(rank.updateFrequency, '每天更新');
    expect(rank.category, 1);
    expect(rank.publishedAt, '2026-11-20');
  });

  test('数字/字符串宽容：rankid 走 optional、缺省字段给空展示', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"info":['
      '{"rankid":"88","rankname":null,"intro":true}'
      ']}}',
    );
    final ranks = await fetchRankList(fixture.session);

    final rank = ranks.single;
    expect(rank.id, 88, reason: 'optional 支持数字字符串');
    expect(rank.title, '', reason: 'text：null/bool 反序列化失败给空串');
    expect(rank.description, '', reason: 'bool 不当文本');
    expect(rank.publishedAt, isNull);
  });

  test('info 空对象宽容：tags 风格 {} 归空表；data 非 object → decode', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"info":{}}}',
    );
    expect(await fetchRankList(fixture.session), isEmpty);

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"info":"bad"}}',
    );
    await expectLater(
      fetchRankList(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('errcode 失败 → business 带码；errcode=20018 → authentication', () async {
    fixture.adapter.bytes = jsonBytes('{"status":0,"errcode":152,"data":{}}');
    await expectLater(
      fetchRankList(fixture.session),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('/152'),
        ),
      ),
    );

    fixture.adapter.bytes = jsonBytes('{"status":1,"errcode":20018,"data":{}}');
    await expectLater(
      fetchRankList(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });

  test('data 缺失/非 object → decode（上游 from_value 不吞）', () async {
    for (final body in <String>[
      '{"status":1,"errcode":0}',
      '{"status":1,"errcode":0,"data":[]}',
    ]) {
      fixture.adapter.bytes = jsonBytes(body);
      await expectLater(
        fetchRankList(fixture.session),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    }
  });
}
