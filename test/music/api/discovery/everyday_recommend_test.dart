/// 每日推荐测试：请求装配（x-router/platform/空请求体）+ recommendation_song
/// 协议解码（资源/歌手/视频/标签/版权）+ ips_tags 形态宽容 + 错误分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/everyday_recommend.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// ips_tags 的默认取值（显式传 null 时 wire 上就是 null）。
const Object _defaultIpsTags = <Object?>[
  <String, Object?>{'ip_id': 'ip1', 'name': 'IP名', 'pid': '0'},
];

String dailyWire({Object? ipsTags = _defaultIpsTags}) =>
    jsonEncode(<String, Object?>{
      'status': 1,
      'error_code': 0,
      'data': <String, Object?>{
        'song_list': <Object?>[_dailySong(ipsTags: ipsTags)],
        'creation_date': '2026-11-21',
        'sub_title': '副标题',
      },
    });

Map<String, Object?> _dailySong({Object? ipsTags = _defaultIpsTags}) =>
    <String, Object?>{
      'album_audio_id': '12345',
      'album_id': '66',
      'hash': 'HASHMAIN',
      'songname': '歌曲',
      'album_name': '专辑',
      'time_length': 200,
      'sizable_cover': 'http://imge.kugou.com/{size}/c.png',
      'privilege': 8,
      'relate_goods': <String, Object?>{'x': 1},
      'singerinfo': <Object?>[
        <String, Object?>{'id': '100', 'name': '歌手A', 'is_publish': '1'},
        <String, Object?>{'name': '歌手B', 'id': 'abc'},
      ],
      'songid': 555,
      'ori_audio_name': '原名',
      'official_songname': '官方名',
      'suffix_audio_name': '副名',
      'album_audio_remark': '备注',
      'filename': 'file',
      'language': '国语',
      'publish_date': '2020-01-01',
      'is_publish': 1,
      'is_original': 0,
      'has_accompany': 1,
      'pay_type': 2,
      'fail_process': 3,
      'old_cpy': 4,
      'hash_128': 'H128',
      'hash_192': 'H192',
      'hash_320': 'H320',
      'hash_flac': 'HFLAC',
      'hash_ape': 'HAPE',
      'hash_other': 'HOTH',
      'filesize_128': 1,
      'filesize_192': 2,
      'filesize_320': 3,
      'filesize_flac': 4,
      'filesize_ape': 5,
      'filesize_other': 6,
      'timelength_320': 200000,
      'bitrate': 128,
      'extname': 'mp3',
      'mv_hash': 'MVH',
      'mv_type': 2,
      'trans_param': <String, Object?>{
        'cpy_attr0': 7,
        'union_cover': 'http://u/{size}/uc.png',
        'ogg_320_hash': 'OGG320',
        'language': '粤语',
        'cid': 'c',
      },
      'tags': <Object?>[
        <String, Object?>{'tag_id': 't1', 'tag_name': '流行', 'parent_id': '0'},
      ],
      'ips_tags': ipsTags,
      'rec_copy_write': '主文案',
      'rec_sub_copy_write': '副文案',
      'rank_label': '热',
    };

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = anonymousIdentity();
    session = fakeMusicSession(client, identity);
  });

  test(
    '请求装配：POST/x-router=everydayrec.service.kugou.com/platform=ios/空请求体',
    () async {
      adapter.bytes = jsonBytes(dailyWire());
      final result = await fetchEverydayRecommend(session);
      expect(result.songs, hasLength(1));

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, 'https://gateway.kugou.com/everyday_song_recommend');
      expect(request.headers['x-router'], 'everydayrec.service.kugou.com');
      expect(request.query['platform'], 'ios');
      expect(request.query.containsKey('userid'), isFalse);
      expect(request.bodyText, '');
    },
  );

  test('解码：摘要/元数据/七档资源/歌手/视频/标签/推荐文案', () async {
    adapter.bytes = jsonBytes(dailyWire());
    final result = await fetchEverydayRecommend(session);

    expect(result.date, '2026-11-21');
    expect(result.subtitle, '副标题');
    final song = result.songs.single;

    final summary = song.song;
    expect(summary.id, '12345', reason: '推荐歌曲协议用 album_audio_id 作主键');
    expect(summary.hash, 'HASHMAIN');
    expect(summary.title, '歌曲');
    expect(summary.albumId, '66');
    expect(summary.albumTitle, '专辑');
    expect(summary.durationMs, 200000, reason: 'time_length 秒 → 毫秒');
    expect(summary.coverUrl, 'http://imge.kugou.com/240/c.png');
    expect(summary.privilege, 8);
    expect(summary.artistText, '歌手A / 歌手B');

    final metadata = song.metadata;
    expect(metadata.audioId, 555);
    expect(metadata.originalTitle, '原名');
    expect(metadata.officialTitle, '官方名');
    expect(metadata.titleSuffix, '副名');
    expect(metadata.albumAudioRemark, '备注');
    expect(metadata.sourceFileName, 'file');
    expect(metadata.language, '国语');
    expect(metadata.publishedAt, '2020-01-01');
    expect(metadata.publicationCode, 1);
    expect(metadata.originalityCode, 0);
    expect(metadata.hasAccompaniment, isTrue);
    expect(metadata.paymentType, 2);
    expect(metadata.failureCode, 3);
    expect(metadata.oldCopyrightCode, 4);
    expect(metadata.relatedGoodsExtension, <String, Object?>{'x': 1});
    expect(metadata.recommendation.headline, '主文案');
    expect(metadata.recommendation.detail, '副文案');
    expect(metadata.recommendation.rankLabel, '热');

    final artists = metadata.artists;
    expect(artists[0].id, 100);
    expect(artists[0].publicationCode, 1, reason: 'is_publish 串 decimal');
    expect(artists[1].id, isNull, reason: '"abc" 不是十进制串');
    expect(artists[1].publicationCode, isNull);

    expect(metadata.videos.single.hash, 'MVH');
    expect(metadata.videos.single.kind, 2);
    expect(metadata.videos.single.id, isNull);

    expect(metadata.tags.single.id, 't1');
    expect(metadata.ipTags.single.id, 'ip1');

    final qualities = metadata.resources.map((r) => r.quality).toList();
    expect(qualities, <String>[
      'ogg_320',
      '128',
      '192',
      '320',
      'flac',
      'ape',
      'other',
    ]);
    final ogg = metadata.resources.first;
    expect(ogg.hash, 'OGG320');
    expect(ogg.extension, 'ogg');
    final standard = metadata.resources[1];
    expect(standard.hash, 'H128');
    expect(standard.sizeBytes, 1);
    expect(standard.durationMs, 200000, reason: '128 档用 time_length');
    expect(standard.bitRateBps, 128000, reason: 'bitrate 只给 128 档且乘 1000');
    expect(standard.extension, 'mp3');
    final high = metadata.resources[2];
    expect(high.hash, 'H192');
    expect(high.bitRateBps, isNull);
    final sq = metadata.resources[3];
    expect(sq.hash, 'H320');
    expect(
      sq.durationMs,
      200000000,
      reason: '320 档 timelength_320 同样乘 1000（上游 push 循环）',
    );
    expect(metadata.resources[4].hash, 'HFLAC');
    expect(metadata.resources[5].hash, 'HAPE');
    expect(metadata.resources[6].hash, 'HOTH');

    expect(metadata.rights.copyrightAttributes, 7);
    expect(metadata.rights.coverUrl, 'http://u/240/uc.png');
  });

  test('ips_tags：单对象形态收一条；空对象/非列表对象/非法元素 → 空表', () async {
    adapter.bytes = jsonBytes(
      dailyWire(ipsTags: <String, Object?>{'ip_id': '9', 'name': '单条'}),
    );
    expect(
      (await fetchEverydayRecommend(session)).songs.single.metadata.ipTags,
      hasLength(1),
    );

    // 三字段全缺省的单条 Entry → 空表（Entry 专属语义）。
    adapter.bytes = jsonBytes(dailyWire(ipsTags: <String, Object?>{}));
    expect(
      (await fetchEverydayRecommend(session)).songs.single.metadata.ipTags,
      isEmpty,
    );

    // object 语义：null/数字/非法元素 → 字段回默认空表，不报 decode。
    adapter.bytes = jsonBytes(dailyWire(ipsTags: null));
    expect(
      (await fetchEverydayRecommend(session)).songs.single.metadata.ipTags,
      isEmpty,
    );
    adapter.bytes = jsonBytes(dailyWire(ipsTags: 5));
    expect(
      (await fetchEverydayRecommend(session)).songs.single.metadata.ipTags,
      isEmpty,
    );
    adapter.bytes = jsonBytes(dailyWire(ipsTags: <Object?>['x']));
    expect(
      (await fetchEverydayRecommend(session)).songs.single.metadata.ipTags,
      isEmpty,
    );
  });

  test('边界：song_list 空 object → 空表；日期缺省 → 空串', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"song_list":{},"creation_date":"d"}}',
    );
    final result = await fetchEverydayRecommend(session);
    expect(result.songs, isEmpty);
    expect(result.date, 'd');
    expect(result.subtitle, '');
  });

  test('业务与解码失败：data 非 object / 元素非 object / status=0', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    await expectLater(
      fetchEverydayRecommend(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"song_list":["x"]}}',
    );
    await expectLater(
      fetchEverydayRecommend(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes('{"status":0,"error_code":152}');
    await expectLater(
      fetchEverydayRecommend(session),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
    );
  });

  test('登录过期：error_code=20018 → authentication；msg 文案也触发', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":20018}');
    await expectLater(
      fetchEverydayRecommend(session),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"msg":"登录已过期"}');
    await expectLater(
      fetchEverydayRecommend(session),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
  });
}
