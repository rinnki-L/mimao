/// rank_api 组门面测试：MusicRankApi 的 9 个方法都经 KugouRankApi 委托到
/// 对应端点函数（请求装配一致，无额外改写）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/rank_api.dart';
import 'package:mimao/music/api/rank_audio.dart';
import 'package:mimao/music/api/song_ranking.dart';
import 'package:mimao/music/api/song_ranking_filter.dart';
import 'package:mimao/music/api/top_playlist.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

void main() {
  late RankFixture fixture;
  late KugouRankApi api;

  setUp(() {
    fixture = RankFixture();
    api = KugouRankApi(fixture.session);
  });

  test('rankList/rankTop：门面调用与直连函数同路径', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"info":[]}}',
    );
    expect(await api.rankList(), isEmpty);

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[]}}',
    );
    expect(await api.rankTop(), isEmpty);

    expect(
      fixture.adapter.requests[0].path,
      'https://gateway.kugou.com/ocean/v6/rank/list',
    );
    expect(
      fixture.adapter.requests[1].path,
      'https://gateway.kugou.com/mobileservice/api/v5/rank/rec_rank_list',
    );
  });

  test('rankAudio/songRanking/songRankingFilter：门面透传查询参数', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"songlist":[]}}',
    );
    await api.rankAudio(const MusicRankAudioQuery(rankId: 1));
    expect(
      fixture.adapter.requests.last.path,
      'https://gateway.kugou.com/openapi/kmr/v2/rank/audio',
    );

    fixture.adapter.bytes = jsonBytes('{"status":1,"data":{"info":[]}}');
    await api.songRanking(const MusicSongRankingQuery(albumAudioId: 5));
    expect(
      fixture.adapter.requests.last.path,
      'https://gateway.kugou.com/grow/v1/song_ranking/play_page/ranking_info',
    );

    fixture.adapter.bytes = jsonBytes('{"status":1,"data":{"list":[]}}');
    await api.songRankingFilter(
      const MusicSongRankingFilterQuery(albumAudioId: 5, page: 3, pageSize: 9),
    );
    final query = fixture.adapter.requests.last.query;
    expect(query['pagesize'], '9');
    expect(query['page'], '3');
  });

  test('topAlbums/topIps/topPlaylists/topSongs：门面调用与直连函数同路径', () async {
    fixture.adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    final albums = await api.topAlbums();
    expect(albums.regions.keys.toList(), <String>['chn', 'eur', 'jpn', 'kor']);

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"list":[]}}',
    );
    await api.topIps();
    expect(
      fixture.adapter.requests.last.headers['x-router'],
      'musicadservice.kugou.com',
    );

    fixture.adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    await api.topPlaylists(const MusicTopPlaylistQuery(categoryId: '660'));
    expect(
      fixture.adapter.requests.last.path,
      'https://gateway.kugou.com/v2/special_recommend',
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"total":0,"data":[]}',
    );
    final songs = await api.topSongs();
    expect(songs.songs, isEmpty);
    expect(
      fixture.adapter.requests.last.path,
      'https://gateway.kugou.com/musicadservice/container/v1/newsong_publish',
    );
  });
}
