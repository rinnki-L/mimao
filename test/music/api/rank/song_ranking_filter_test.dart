/// song_ranking_filter 端点测试：GET 装配（page/pagesize）+ list 解码。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/song_ranking_filter.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test('请求装配：album_audio_id + page + pagesize（默认 1/30）', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[]}}',
    );
    await fetchSongRankingFilter(
      fixture.session,
      const MusicSongRankingFilterQuery(albumAudioId: 88),
    );

    final request = fixture.adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      'https://gateway.kugou.com/grow/v1/song_ranking/unlock/v2/ranking_filter',
    );
    expect(request.query['album_audio_id'], '88');
    expect(request.query['page'], '1');
    expect(request.query['pagesize'], '30');
  });

  test('请求装配：分页覆盖', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[]}}',
    );
    await fetchSongRankingFilter(
      fixture.session,
      const MusicSongRankingFilterQuery(
        albumAudioId: 88,
        page: 2,
        pageSize: 15,
      ),
    );
    final query = fixture.adapter.requests.single.query;
    expect(query['page'], '2');
    expect(query['pagesize'], '15');
  });

  test('解码：筛选入口条目字段映射', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":['
      '{"area":"6","count":42,"platform":2,"top_ranking":1,'
      '"logo_pic":"http://logo/1.png","name":"内地榜",'
      '"platform_name":"Kugou","share_pic":"http://share/1.png"}'
      ']}}',
    );
    final filter = await fetchSongRankingFilter(
      fixture.session,
      const MusicSongRankingFilterQuery(albumAudioId: 88),
    );

    final option = filter.options.single;
    expect(option.area, 6);
    expect(option.count, 42);
    expect(option.platform, 2);
    expect(option.topRanking, 1);
    expect(option.logoPic, 'http://logo/1.png');
    expect(option.name, '内地榜');
    expect(option.platformName, 'Kugou');
    expect(option.sharePic, 'http://share/1.png');
  });

  test('list 缺省归空；errcode 非 0 → business', () async {
    fixture.adapter.bytes = jsonBytes('{"status":1,"data":{}}');
    expect(
      await fetchSongRankingFilter(
        fixture.session,
        const MusicSongRankingFilterQuery(albumAudioId: 88),
      ).then((value) => value.options),
      isEmpty,
    );

    fixture.adapter.bytes = jsonBytes('{"status":1,"errcode":301,"data":{}}');
    await expectLater(
      fetchSongRankingFilter(
        fixture.session,
        const MusicSongRankingFilterQuery(albumAudioId: 88),
      ),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('/301'),
        ),
      ),
    );
  });

  test('data/条目非法 → 默认空值（object 语义），status 缺失 → decode', () async {
    // list 非数组 → 整个 Ranking 归默认（unwrap_or_default，不抛 decode）。
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":"bad"}}',
    );
    final filter = await fetchSongRankingFilter(
      fixture.session,
      const MusicSongRankingFilterQuery(albumAudioId: 88),
    );
    expect(filter.options, isEmpty);

    // 条目本身合法、text 字段为 bool → 空串（不产生假文本）。
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[{"name":true}]}}',
    );
    final lenient = await fetchSongRankingFilter(
      fixture.session,
      const MusicSongRankingFilterQuery(albumAudioId: 88),
    );
    expect(lenient.options.single.name, '');

    fixture.adapter.bytes = jsonBytes('{"errcode":0,"data":{"list":[]}}');
    await expectLater(
      fetchSongRankingFilter(
        fixture.session,
        const MusicSongRankingFilterQuery(albumAudioId: 88),
      ),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
