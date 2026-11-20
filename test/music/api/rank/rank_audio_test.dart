/// rank_audio 端点测试：POST 装配（固定 body + kg-tid）+ 大结构解码
/// （ogg/五档资源、privilege_download 回退链、版权事实、榜内位置）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/rank_audio.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

/// rank_audio.rs Song 的可信 wire 样本（覆盖 rights/资源/位置/视频全链）。
String rankAudioWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'total': 100,
    'songlist': <Object?>[
      <String, Object?>{
        'album_audio_id': '31742',
        'album_id': '142',
        'audio_id': 99,
        'songname': 'Song Title',
        'authors': <Object?>[
          <String, Object?>{
            'author_id': 7,
            'author_name': 'Artist',
            'sizable_avatar': 'http://imge.kugou.com/kpic/{size}/a.png',
          },
        ],
        'audio_info': <String, Object?>{
          'hash_128': 'H128',
          'duration_128': 245000,
          'filesize_128': 3900000,
          'bitrate': 128,
          'extname': 'mp3',
          'hash_320': 'H320',
          'duration_320': 245000,
          'filesize_320': 9800000,
          'hash_flac': 'HFLAC',
          'duration_flac': 245000,
          'filesize_flac': 24000000,
          'bitrate_flac': 901,
          'hash_high': 'HHIGH',
          'duration_high': 245000,
          'filesize_high': 46000000,
          'bitrate_high': 1420,
          'hash_super': 'HSUPER',
          'duration_super': 245000,
          'filesize_super': 69000000,
          'bitrate_super': 2000,
          'extname_super': 'flac',
        },
        'album_info': <String, Object?>{
          'album_name': 'Album',
          'sizable_cover': 'http://imge.kugou.com/stdmusic/{size}/c.png',
        },
        'privilege_download': <String, Object?>{
          'privilege': 8,
          'privilege_128': 8,
          'privilege_320': 16,
          'fail_process': 0,
          'fail_process_128': 0,
          'fail_process_320': 1,
        },
        'user_download': <String, Object?>{'status_128': 1, 'status_320': 0},
        'trans_param': <String, Object?>{
          'qualitymap': <String, Object?>{'attr0': 15, 'bits': 'flac;high'},
          'classmap': <String, Object?>{'known': '2', 'bad': 'x'},
          'ipmap': <String, Object?>{
            'attr0': '281629629091840',
            'bits': 'attr',
          },
          'cpy_attr0': 123,
          'cpy_map': 'scope',
          'cpy_grade': 2,
          'cpy_level': 3,
          'display': 1,
          'display_rate': 50,
          'pay_block_tpl': 1,
          'appid_block': '1000',
          'musicpack_advance': 1,
          'is_original': 1,
          'hash_offset': <String, Object?>{'start_byte': 0, 'end_byte': 1024},
          'hash_multitrack': 'MT',
          'union_cover': 'http://imge.kugou.com/coverprint/{size}/u.png',
          'ogg_128_hash': 'OGG128',
          'ogg_128_filesize': 100,
          'ogg_320_hash': 'OGG320',
          'audio_privilege': 2,
          'free_for_ad': 0,
          'free_limited': 1,
          'voice_ad': <String, Object?>{
            'start_ms': 1000,
            'filesize': 50,
            'hash': 'VH',
          },
        },
        'deprecated': <String, Object?>{
          'pay_type': 1,
          'old_cpy': 0,
          'pay_type_128': 0,
          'pay_type_320': 1,
          'pay_type_flac': 2,
          'pay_type_high': 2,
          'pay_type_super': 2,
        },
        'business': <String, Object?>{
          'filename': 'Artist - Song',
          'album_audio_remark': 'remark',
          'recommend_reason': 'reason',
          'rank_id': '1234',
          'issue': '2026W47',
          'sort': 3,
          'last_sort': 5,
          'original_index': 9,
          'last_original_index': 2,
          'offset': 2,
          'rank_id_publish_date': '2026-11-20',
        },
        'mvdata': <Object?>[
          <String, Object?>{
            'id': '11',
            'hash': 'MVH',
            'typ': 2,
            'trk': 'MVTRK',
          },
        ],
        'video_info': <String, Object?>{
          'video_id': 22,
          'video_hash': 'VIDH',
          'video_timelength': 3000,
          'video_filesize': 5000,
          'video_track': 33,
        },
        'remarks': <Object?>[
          <String, Object?>{
            'rel_album_audio_id': 55,
            'remark': 'Original version',
            'type': 1,
          },
        ],
        'rank_cid': 2160,
        'is_publish': 1,
        'has_obbligato': 1,
      },
    ],
  },
});

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test('请求装配：POST /openapi/kmr/v2/rank/audio + 固定 body + kg-tid=369', () async {
    fixture.adapter.bytes = jsonBytes(rankAudioWire());
    await fetchRankAudio(
      fixture.session,
      const MusicRankAudioQuery(rankId: 1234),
    );

    final request = fixture.adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/openapi/kmr/v2/rank/audio');
    expect(request.headers['x-router'], isNull);
    expect(request.headers['kg-tid'], '369');
    expect(request.headers['Content-Type'], 'application/json');
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body, <String, Object?>{
      'show_portrait_mv': 1,
      'show_type_total': 1,
      'filter_original_remarks': 1,
      'area_code': 1,
      'pagesize': 100,
      'rank_cid': 0,
      'type': 1,
      'page': 1,
      'rank_id': 1234,
    });
  });

  test('input 校验：rank_id 为 0/负数 → input「排行榜无效」', () async {
    await expectLater(
      fetchRankAudio(fixture.session, const MusicRankAudioQuery(rankId: 0)),
      throwsA(predicate((Object e) => '$e'.contains('input'))),
    );
    await expectLater(
      fetchRankAudio(fixture.session, const MusicRankAudioQuery(rankId: -1)),
      throwsA(predicate((Object e) => '$e'.contains('input'))),
    );
    expect(fixture.adapter.requests, isEmpty, reason: '校验失败不发起请求');
  });

  test('解码：摘要 + ogg/五档资源 + privilege_download 回退链', () async {
    fixture.adapter.bytes = jsonBytes(rankAudioWire());
    final result = await fetchRankAudio(
      fixture.session,
      const MusicRankAudioQuery(rankId: 1234),
    );

    expect(result.total, 100);
    final song = result.songs.single;
    expect(song.song.id, '31742');
    expect(song.song.audioId, 99);
    expect(song.song.hash, 'H128');
    expect(song.song.title, 'Song Title');
    expect(song.song.albumId, '142');
    expect(song.song.albumTitle, 'Album');
    expect(song.song.durationMs, 245000, reason: 'wire 本就是毫秒，不乘 1000');
    expect(song.song.coverUrl, 'http://imge.kugou.com/stdmusic/240/c.png');
    expect(song.song.privilege, 8);
    expect(song.song.artistText, 'Artist');

    // trans_param 先出 ogg 两档（只压 hash/size 至少其一者），再压五档。
    final qualities = song.metadata.resources.map((r) => r.quality).toList();
    expect(qualities, <String>[
      'ogg_128',
      'ogg_320',
      '128',
      '320',
      'flac',
      'high',
      'super',
    ]);

    final ogg128 = song.metadata.resources.first;
    expect(ogg128.hash, 'OGG128');
    expect(ogg128.sizeBytes, 100);
    expect(ogg128.extension, 'ogg');
    final ogg320 = song.metadata.resources[1];
    expect(ogg320.hash, 'OGG320');
    expect(ogg320.sizeBytes, isNull, reason: 'ogg_320_filesize 缺省时 hash 单独成条');

    final h128 = song.metadata.resources[2];
    expect(h128.hash, 'H128');
    expect(h128.sizeBytes, 3900000);
    expect(h128.durationMs, 245000);
    expect(h128.bitRateBps, 128000);
    expect(h128.extension, 'mp3');
    expect(h128.privilege, 8);
    expect(h128.paymentType, 0);
    expect(h128.failureCode, 0);
    expect(h128.downloadStatus, 1);

    final h320 = song.metadata.resources[3];
    expect(h320.bitRateBps, isNull, reason: '上游 320 档 bitrate 显式 None');
    expect(h320.extension, isNull);
    expect(h320.privilege, 16);
    expect(h320.paymentType, 1);
    expect(h320.failureCode, 1);
    expect(h320.downloadStatus, 0);

    final flac = song.metadata.resources[4];
    expect(flac.bitRateBps, 901000);
    expect(flac.paymentType, 2);
    final superQuality = song.metadata.resources[6];
    expect(superQuality.extension, 'flac');
    expect(superQuality.bitRateBps, 2000000);
  });

  test('解码：版权事实（catalog_rights WireTrans）+ 试听范围过滤 + voice_ad', () async {
    fixture.adapter.bytes = jsonBytes(rankAudioWire());
    final song = (await fetchRankAudio(
      fixture.session,
      const MusicRankAudioQuery(rankId: 1234),
    )).songs.single;
    final rights = song.metadata.rights;

    expect(rights.qualityMap?.attr0, 15);
    expect(rights.qualityMap?.bits, 'flac;high');
    expect(rights.classification, <String, int?>{
      'known': 2,
      'bad': null,
    }, reason: 'number_map：不可解析值归 null 不丢键');
    expect(rights.ipMap?.attr0, 281629629091840);
    expect(rights.copyrightAttributes, 123);
    expect(rights.copyrightScope, 'scope');
    expect(rights.copyrightGrade, 2);
    expect(rights.copyrightLevel, 3);
    expect(rights.displayCode, 1);
    expect(rights.displayRate, 50);
    expect(rights.paymentTemplate, 1);
    expect(rights.blockedApplications, '1000');
    expect(rights.originalityCode, 1);
    expect(rights.advanceCode, 1);
    expect(rights.preview?.startByte, 0);
    expect(rights.preview?.endByte, 1024);
    expect(rights.multitrackHash, 'MT');
    expect(rights.coverUrl, 'http://imge.kugou.com/coverprint/240/u.png');
    expect(rights.audioPrivilege, 2);
    expect(rights.freeForAd, 0);
    expect(rights.freeLimited, 1);
    expect(rights.voiceAd?.startMs, 1000);
    expect(rights.voiceAd?.sizeBytes, 50);
    expect(rights.voiceAd?.hash, 'VH');

    // 顶层元数据事实链。
    expect(
      song.metadata.originalityCode,
      1,
      reason: 'rights.originality_code 回传',
    );
    expect(
      song.metadata.hasAccompaniment,
      isTrue,
      reason: 'has_obbligato=1 → boolean true',
    );
    expect(song.metadata.accompanimentCode, 1);
    expect(song.metadata.paymentType, 1, reason: 'deprecated.pay_type');
    expect(
      song.metadata.failureCode,
      0,
      reason: 'privilege_download.fail_process',
    );
    expect(song.metadata.oldCopyrightCode, 0, reason: 'deprecated.old_cpy');
    expect(song.metadata.publicationCode, 1, reason: 'is_publish');
    expect(song.metadata.albumAudioRemark, 'remark');
    expect(song.metadata.sourceFileName, 'Artist - Song');
    expect(song.metadata.recommendation.headline, 'reason');

    // 榜内位置。
    final ranking = song.metadata.ranking!;
    expect(ranking.rankId, '1234');
    expect(ranking.issue, '2026W47');
    expect(ranking.rankCid, 2160);
    expect(ranking.position, 3);
    expect(ranking.previousPosition, 5);
    expect(ranking.originalPosition, 9);
    expect(ranking.previousOriginalPosition, 2);
    expect(ranking.change, 2);
    expect(ranking.publishedAt, '2026-11-20');

    // 歌手详情 + MV/视频 + 相关版本。
    final artist = song.metadata.artists.single;
    expect(artist.id, 7);
    expect(artist.avatarUrl, 'http://imge.kugou.com/kpic/240/a.png');
    expect(song.metadata.videos.map((v) => v.hash), <String?>[
      'MVH',
      'VIDH',
    ], reason: 'mvdata 先出，video_info 命中条件补一条');
    expect(song.metadata.videos[1].id, '22');
    expect(song.metadata.videos[1].track, '33');
    expect(song.metadata.videos[1].durationMs, 3000);
    expect(song.metadata.relatedVersions.single.albumAudioId, '55');
    expect(song.metadata.relatedVersions.single.kind, 1);
  });

  test('边界：trans_param 全空 → 默认版权；video_info 全零不补视频', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"songlist":['
      '{"songname":"t","trans_param":{"hash_offset":{}},'
      '"video_info":{"video_hash":""},"authors":[],"mvdata":[],"remarks":[]}'
      ']}}',
    );
    final song = (await fetchRankAudio(
      fixture.session,
      const MusicRankAudioQuery(rankId: 1234),
    )).songs.single;

    expect(song.metadata.rights.qualityMap, isNull);
    expect(
      song.metadata.rights.preview,
      isNull,
      reason: '全空试听范围按上游 is_empty 过滤',
    );
    expect(song.metadata.resources.map((r) => r.quality), <String>[
      '128',
      '320',
      'flac',
      'high',
      'super',
    ], reason: '无 ogg 事实；五档仍无条件压入');
    expect(song.metadata.videos, isEmpty, reason: 'video_hash 空且其余全零');
    expect(song.metadata.ranking!.rankId, '');
    expect(song.metadata.ranking!.publishedAt, '');
  });

  test('业务失败（error_code 非 0）→ business；songlist 非数组 → decode', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":152,"data":{}}',
    );
    await expectLater(
      fetchRankAudio(fixture.session, const MusicRankAudioQuery(rankId: 1)),
      throwsA(predicate((Object e) => '$e'.contains('business'))),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"songlist":"bad"}}',
    );
    await expectLater(
      fetchRankAudio(fixture.session, const MusicRankAudioQuery(rankId: 1)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('error_code=20018 → authentication（信封层统一映射）', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":20018,"data":{}}',
    );
    await expectLater(
      fetchRankAudio(fixture.session, const MusicRankAudioQuery(rankId: 1)),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });
}
