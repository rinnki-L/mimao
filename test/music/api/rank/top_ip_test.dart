/// top_ip 端点测试：POST 装配（router + 固定参数 + tags 空对象 body）+
/// kind==1 过滤 + errcode 信封。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/top_ip.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test('请求装配：POST /v1/daily_recommend + x-router + body {"tags":{}}', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[]}}',
    );
    await fetchTopIps(fixture.session);

    final request = fixture.adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v1/daily_recommend');
    expect(request.headers['x-router'], 'musicadservice.kugou.com');
    expect(request.query['clientver'], '12349');
    expect(request.query['area_code'], '1');
    expect(jsonDecode(request.bodyText), <String, Object?>{
      'tags': <String, Object?>{},
    });
  });

  test('解码：仅保留 type==1 的歌单条目并映射卡片', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":['
      '{"type":1,"title":"IP歌单","sizable_image_url":"http://img/{size}/i.png",'
      '"extra":{"global_collection_id":"gcol_1","global_special_id":"gs_1",'
      '"specialid":"300","suid":9,"play_count":"12345"}},'
      '{"type":2,"title":"非歌单条目","sizable_image_url":"x","extra":{}},'
      '{"title":"type 缺省条目","sizable_image_url":"x","extra":{}}'
      ']}}',
    );
    final cards = await fetchTopIps(fixture.session);

    expect(cards, hasLength(1), reason: 'kind != 1 的条目按上游 filter 丢弃');
    final card = cards.single;
    expect(card.id, 'gcol_1');
    expect(card.title, 'IP歌单');
    expect(card.creator, '', reason: 'top_ip 卡片 creator 恒空');
    expect(card.coverUrl, 'http://img/240/i.png');
    expect(card.songCount, isNull);
    expect(card.metadata.publicId, 300);
    expect(card.metadata.alternateGlobalId, 'gs_1');
    expect(card.metadata.creatorId, 9);
    expect(card.metadata.playCount, 12345);
    expect(card.metadata.kindCode, 1);
    expect(card.metadata.description, isNull);
    expect(card.metadata.tags, isEmpty);
  });

  test('extra 缺省/非法 → 默认（id 归空串不抛）', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":['
      '{"type":1,"title":"t","sizable_image_url":"","extra":"bad"}'
      ']}}',
    );
    final cards = await fetchTopIps(fixture.session);
    expect(
      cards.single.id,
      '',
      reason: 'global_collection_id 缺省 unwrap_or_default',
    );
    expect(cards.single.metadata.publicId, isNull);
  });

  test('errcode 失败 → business；list 非数组 → decode', () async {
    fixture.adapter.bytes = jsonBytes('{"status":0,"errcode":66,"data":{}}');
    await expectLater(
      fetchTopIps(fixture.session),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('/66'),
        ),
      ),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":9}}',
    );
    await expectLater(
      fetchTopIps(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
