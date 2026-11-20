/// top_song 端点测试：POST 装配（rank_id=21608/userid/tags）+ 根级数组
/// wire 解码（资源/回退链/chart/别名码全链断言）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/top_song.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

/// top_song.rs Song 的可信 wire 样本（data 是根级数组）。
String topSongWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'total': 30,
  'data': <Object?>[
    <String, Object?>{
      'album_audio_id': '90001',
      'album_id': '556',
      'audio_id': 700,
      'hash': 'BASEHASH',
      'songname': 'New Song',
      'album_name': 'New Album',
      'album_sizable_cover': 'http://imge.kugou.com/stdmusic/{size}/n.png',
      'filename': 'Artist - New Song',
      'album_audio_remark': 'album remark',
      'recommend_reason': 'rec reason',
      'publish_date': '2026-11-18',
      'authors': <Object?>[
        <String, Object?>{
          'author_id': 3,
          'author_name': 'Artist 3',
          'sizable_avatar': 'http://imge.kugou.com/kpic/{size}/a3.png',
          'is_publish': 1,
        },
      ],
      'trans_param': <String, Object?>{
        'songname_suffix': '(Live)',
        'is_original': 1,
        'ogg_128_hash': 'OGG128',
        'ogg_128_filesize': 120,
        'qualitymap': <String, Object?>{'attr0': '7', 'bits': 'bits'},
        'union_cover': 'http://imge.kugou.com/coverprint/{size}/u.png',
        'cpy_grade': 4,
      },
      'privilege': 8,
      'pay_type': 1,
      'old_cpy': 0,
      'fail_process': 0,
      'has_obbligato': 0,
      'timelength': 234000,
      'bitrate': 128,
      'bitrate_flac': 901,
      'bitrate_high': 1420,
      'bitrate_super': 2000,
      'extname': 'mp3',
      'extname_super': 'flac',
      'video_hash': 'VIDHASH',
      'video_id': 42,
      'video_track': 7,
      'video_timelength': 31000,
      'video_filesize': 620000,
      'remarks': <Object?>[
        <String, Object?>{
          'rel_album_audio_id': 90002,
          'remark_type': 2,
          'remark': '伴奏版',
          'is_defaut_alias': '1',
        },
        <String, Object?>{'remark': '另一版本'},
      ],
      'rank_id': '21608',
      'issue': '2026W47',
      'rank_cid': 21608,
      'sort': -2,
      'last_sort': 4,
      'offset': -6,
      'hash_128': 'H128',
      'filesize_128': 3900000,
      'timelength_128': 234000,
      'privilege_128': 8,
      'pay_type_128': 0,
      'fail_process_128': 0,
      'status_128': 1,
      'hash_320': 'H320',
      'filesize_320': 9800000,
      'timelength_320': 234000,
      'privilege_320': 16,
      'pay_type_320': 1,
      'fail_process_320': 1,
      'status_320': 0,
      'hash_flac': 'HFLAC',
      'filesize_flac': 24000000,
      'timelength_flac': 234000,
      'privilege_flac': 16,
      'pay_type_flac': 2,
      'fail_process_flac': 0,
      'status_flac': 1,
      'hash_high': 'HHIGH',
      'filesize_high': 46000000,
      'timelength_high': 234000,
      'privilege_high': 16,
      'pay_type_high': 2,
      'fail_process_high': 0,
      'status_high': 1,
      'hash_super': 'HSUPER',
      'filesize_super': 69000000,
      'timelength_super': 234000,
      'privilege_super': 16,
      'pay_type_super': 2,
      'fail_process_super': 0,
      'status_super': 1,
    },
  ],
});

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test(
    '请求装配：POST /musicadservice/container/v1/newsong_publish 固定 body',
    () async {
      fixture.adapter.bytes = jsonBytes(topSongWire());
      await fetchTopSongs(fixture.session);

      final request = fixture.adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.path,
        'https://gateway.kugou.com/musicadservice/container/v1/newsong_publish',
      );
      expect(request.headers['x-router'], isNull);
      final body = jsonDecode(request.bodyText) as Map<String, Object?>;
      expect(body, <String, Object?>{
        'rank_id': 21608,
        'userid': 0,
        'page': 1,
        'pagesize': 30,
        'tags': <Object?>[],
      });
    },
  );

  test('账号身份：body userid 携带账号 id', () async {
    final accountFixture = RankFixture(
      withIdentity: KugouIdentity.anonymous().withAccount(
        userId: 777,
        token: 'tk',
      ),
    );
    accountFixture.adapter.bytes = jsonBytes(topSongWire());
    await fetchTopSongs(accountFixture.session);
    final body =
        jsonDecode(accountFixture.adapter.requests.single.bodyText)
            as Map<String, Object?>;
    expect(body['userid'], 777);
  });

  test('解码：摘要 + 根级 total/data + 五档资源回退链', () async {
    fixture.adapter.bytes = jsonBytes(topSongWire());
    final result = await fetchTopSongs(fixture.session);

    expect(result.total, 30);
    final newSong = result.songs.single;
    final song = newSong.song;
    expect(song.id, '90001');
    expect(song.audioId, 700);
    expect(song.hash, 'BASEHASH');
    expect(song.title, 'New Song');
    expect(song.albumTitle, 'New Album');
    expect(song.durationMs, 234000, reason: 'timelength 本就是毫秒');
    expect(song.coverUrl, 'http://imge.kugou.com/stdmusic/240/n.png');
    expect(song.privilege, 8);
    expect(song.artistText, 'Artist 3');

    // ogg 先入（trans_param），随后五档。
    expect(newSong.metadata.catalog.resources.map((r) => r.quality), <String>[
      'ogg_128',
      '128',
      '320',
      'flac',
      'high',
      'super',
    ], reason: 'ogg_320 hash/size 都缺省时跳过');

    final h128 = newSong.metadata.catalog.resources[1];
    expect(h128.hash, 'H128');
    expect(h128.sizeBytes, 3900000);
    expect(h128.durationMs, 234000);
    expect(h128.bitRateBps, 128000);
    expect(h128.extension, 'mp3');
    expect(h128.privilege, 8);
    expect(h128.paymentType, 0);
    expect(h128.failureCode, 0);
    expect(h128.downloadStatus, 1);

    final h320 = newSong.metadata.catalog.resources[2];
    expect(h320.privilege, 16);
    expect(h320.paymentType, 1);
    expect(h320.failureCode, 1);
    expect(h320.downloadStatus, 0);
    expect(h320.bitRateBps, isNull, reason: '上游 320 档显式 None');
    expect(h320.extension, isNull);

    final superQuality = newSong.metadata.catalog.resources[5];
    expect(superQuality.bitRateBps, 2000000);
    expect(superQuality.extension, 'flac');
  });

  test('解码：catalog 元数据 + chart + 默认别名码 + 视频条目', () async {
    fixture.adapter.bytes = jsonBytes(topSongWire());
    final newSong = (await fetchTopSongs(fixture.session)).songs.single;
    final catalog = newSong.metadata.catalog;

    expect(catalog.audioId, 700);
    expect(
      catalog.titleSuffix,
      '(Live)',
      reason: 'trans_param.songname_suffix',
    );
    expect(catalog.albumAudioRemark, 'album remark');
    expect(catalog.sourceFileName, 'Artist - New Song');
    expect(catalog.publishedAt, '2026-11-18');
    expect(catalog.originalityCode, 1, reason: 'rights.originality_code 回传');
    expect(
      catalog.hasAccompaniment,
      isFalse,
      reason: 'has_obbligato=0 → boolean false',
    );
    expect(catalog.accompanimentCode, 0);
    expect(catalog.paymentType, 1);
    expect(
      catalog.failureCode,
      0,
      reason: '顶层 fail_process（非 privilege_download）',
    );
    expect(catalog.oldCopyrightCode, 0);
    expect(catalog.rights.qualityMap?.attr0, 7);
    expect(catalog.rights.qualityMap?.bits, 'bits');
    expect(catalog.rights.copyrightGrade, 4);
    expect(
      catalog.rights.coverUrl,
      'http://imge.kugou.com/coverprint/240/u.png',
    );
    expect(catalog.recommendation.headline, 'rec reason');
    expect(
      catalog.ranking,
      isNull,
      reason: 'top_song 无 RankingPosition，用 chart',
    );

    final artist = catalog.artists.single;
    expect(artist.publicationCode, 1);
    expect(artist.avatarUrl, 'http://imge.kugou.com/kpic/240/a3.png');

    expect(catalog.videos, hasLength(1));
    final video = catalog.videos.single;
    expect(video.id, '42');
    expect(video.hash, 'VIDHASH');
    expect(video.track, '7');
    expect(video.durationMs, 31000);
    expect(video.sizeBytes, 620000);
    expect(video.kind, isNull, reason: 'video_hash 分支不填 kind');

    expect(catalog.relatedVersions.map((v) => v.albumAudioId), <String>[
      '90002',
      '',
    ], reason: 'rel_album_audio_id 缺省归空串');
    expect(catalog.relatedVersions.map((v) => v.kind), <int?>[2, null]);
    expect(newSong.metadata.defaultAliasCodes, <int?>[1, null]);
    expect(newSong.metadata.chart.rankId, '21608');
    expect(newSong.metadata.chart.issue, '2026W47');
    expect(newSong.metadata.chart.rankCid, 21608);
    expect(newSong.metadata.chart.position, -2, reason: 'i64 负数保留');
    expect(newSong.metadata.chart.previousPosition, 4);
    expect(newSong.metadata.chart.change, -6);
  });

  test('边界：video_hash 空 → 无视频；无 ogg/备注 → 空表；text bool → 空串', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"total":1,"data":['
      '{"songname":"t","video_hash":"","extname":false,"authors":[],'
      '"remarks":[{"is_defaut_alias":0}]}]}',
    );
    final newSong = (await fetchTopSongs(fixture.session)).songs.single;
    expect(newSong.metadata.catalog.videos, isEmpty);
    expect(newSong.metadata.catalog.resources.map((r) => r.quality), <String>[
      '128',
      '320',
      'flac',
      'high',
      'super',
    ]);
    expect(
      newSong.metadata.catalog.resources[0].extension,
      '',
      reason: 'extname text 失败归空串',
    );
    expect(newSong.song.title, 't');
    expect(newSong.metadata.defaultAliasCodes, <int?>[0]);
    expect(newSong.metadata.catalog.relatedVersions.single.albumAudioId, '');
  });

  test('业务失败 → business；data 非数组 → decode；条目非 object → decode', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":4,"total":0,"data":[]}',
    );
    await expectLater(
      fetchTopSongs(fixture.session),
      throwsA(
        predicate(
          (Object e) => '$e'.contains('business') && '$e'.contains('/4'),
        ),
      ),
    );

    // data 是空对象按 list 宽容归空表；非数组标量才 decode 失败。
    fixture.adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    expect((await fetchTopSongs(fixture.session)).songs, isEmpty);

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":"bad"}',
    );
    await expectLater(
      fetchTopSongs(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":[null]}',
    );
    await expectLater(
      fetchTopSongs(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('error_code=20018 → authentication（先于端点语义）', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":20018,"data":[]}',
    );
    await expectLater(
      fetchTopSongs(fixture.session),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });
}
