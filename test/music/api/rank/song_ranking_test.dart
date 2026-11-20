/// song_ranking 端点测试：GET 装配 + errcode 可缺省判定 + data 宽容降级。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/song_ranking.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test(
    '请求装配：GET /grow/v1/song_ranking/play_page/ranking_info 只带 album_audio_id',
    () async {
      fixture.adapter.bytes = jsonBytes(
        '{"status":1,"errcode":0,"data":{"info":[]}}',
      );
      await fetchSongRanking(
        fixture.session,
        const MusicSongRankingQuery(albumAudioId: 31742),
      );

      final request = fixture.adapter.requests.single;
      expect(request.method, 'GET');
      expect(
        request.path,
        'https://gateway.kugou.com/grow/v1/song_ranking/play_page/ranking_info',
      );
      expect(request.headers['x-router'], isNull);
      expect(request.query['album_audio_id'], '31742');
      expect(
        request.query.containsKey('page'),
        isFalse,
        reason: '上游 Query 有 page/page_size 但 execute 不发送',
      );
      expect(request.query.containsKey('pagesize'), isFalse);
    },
  );

  test('解码：Ranking 字段映射 + info 成就列表', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{'
      '"album_audio_id":"31742","platform_num":"5","platform_total":10,'
      '"title1":"酷狗Top500","title2":"平台排名",'
      '"info":[{"platform":1,"ranking_num":"3","ranking_times":12,'
      '"platform_name":"Kugou","platform_logo":"http://logo/{size}/l.png",'
      '"last_time":"2026-11-20 10:00:00"}]}}',
    );
    final ranking = await fetchSongRanking(
      fixture.session,
      const MusicSongRankingQuery(albumAudioId: 31742),
    );

    expect(ranking.albumAudioId, 31742);
    expect(ranking.platformNum, 5);
    expect(ranking.platformTotal, 10);
    expect(ranking.title1, '酷狗Top500');
    expect(ranking.title2, '平台排名');
    final achievement = ranking.achievements.single;
    expect(achievement.platform, 1);
    expect(achievement.rankingNum, 3);
    expect(achievement.rankingTimes, 12);
    expect(achievement.platformName, 'Kugou');
    expect(achievement.platformLogo, 'http://logo/{size}/l.png');
    expect(achievement.lastTime, '2026-11-20 10:00:00');
  });

  test('errcode 缺省按 0 判定成功（optional）', () async {
    fixture.adapter.bytes = jsonBytes('{"status":1,"data":{"title1":"t"}}');
    final ranking = await fetchSongRanking(
      fixture.session,
      const MusicSongRankingQuery(albumAudioId: 31742),
    );
    expect(ranking.title1, 't');
  });

  test('errcode 非 0 → business 带码', () async {
    fixture.adapter.bytes = jsonBytes('{"status":1,"errcode":519,"data":{}}');
    await expectLater(
      fetchSongRanking(
        fixture.session,
        const MusicSongRankingQuery(albumAudioId: 31742),
      ),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('/519'),
        ),
      ),
    );
  });

  test('data 非法/条目非法 → object 反序列化归默认空值（不抛 decode）', () async {
    for (final body in <String>[
      '{"status":1,"errcode":0,"data":"bad"}',
      '{"status":1,"errcode":0,"data":{"info":"bad"}}',
      '{"status":1,"errcode":0,"data":{"info":[3]}}',
    ]) {
      fixture.adapter.bytes = jsonBytes(body);
      final ranking = await fetchSongRanking(
        fixture.session,
        const MusicSongRankingQuery(albumAudioId: 31742),
      );
      expect(ranking.achievements, isEmpty, reason: body);
      expect(ranking.title1, '', reason: 'unwrap_or_default 语义：整个 Ranking 归默认');
    }
  });

  test('status 非 1 → business；登录过期（msg 关键词）→ authentication', () async {
    fixture.adapter.bytes = jsonBytes('{"status":0,"errcode":0,"data":{}}');
    await expectLater(
      fetchSongRanking(
        fixture.session,
        const MusicSongRankingQuery(albumAudioId: 31742),
      ),
      throwsA(predicate((Object e) => '$e'.contains('business'))),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":0,"error_code":0,"msg":"登录已过期，请重新登录"}',
    );
    await expectLater(
      fetchSongRanking(
        fixture.session,
        const MusicSongRankingQuery(albumAudioId: 31742),
      ),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });
}
