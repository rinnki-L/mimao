/// 专辑歌曲端点测试：POST 装配 + 分页校验 + 歌曲/版权/音质事实全量解码 +
/// trans_param 回退（失败归空、ogg 跳过、preview 空区间丢弃）+ decode/business。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/album_songs.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/album_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
  });

  Future<MusicAlbumTracks> fetch(AlbumSongsQuery query) =>
      fetchAlbumSongs(fakeMusicSession(client), query);

  test(
    '请求装配：POST /v1/album_audio/lite + router + kg-tid + body 字段序 + 签名自验',
    () async {
      adapter.bytes = jsonBytes(songsWire());
      await fetch(const AlbumSongsQuery(id: 42, page: 2, pageSize: 50));

      final captured = adapter.requests.single;
      expect(captured.method, 'POST');
      expect(captured.path, 'https://gateway.kugou.com/v1/album_audio/lite');
      expect(captured.headers['x-router'], 'openapi.kugou.com');
      expect(captured.headers['kg-tid'], '255');

      final body = jsonDecode(captured.bodyText) as Map<String, Object?>;
      expect(body.keys.toList(), <String>[
        'album_id',
        'is_buy',
        'page',
        'pagesize',
      ]);
      expect(body['album_id'], '42');
      expect(body['is_buy'], '');
      expect(body['page'], 2);
      expect(body['pagesize'], 50);

      final query = Map<String, String>.from(captured.query);
      expect(query['dfid'], '-');
      expect(query['mid'], fixedIdentity().mid);
      final signature = query.remove('signature');
      expect(
        signature,
        kugouSignatureAndroid(query, utf8.encode(captured.bodyText)),
      );
    },
  );

  test('input 校验：page<1 与 pageSize 出 1..=100 → 专辑分页参数无效', () async {
    for (final query in const <AlbumSongsQuery>[
      AlbumSongsQuery(id: 42, page: 0),
      AlbumSongsQuery(id: 42, page: -1),
      AlbumSongsQuery(id: 42, pageSize: 0),
      AlbumSongsQuery(id: 42, pageSize: 101),
    ]) {
      await expectLater(
        fetch(query),
        throwsA(
          isA<KugouApiException>()
              .having((e) => e.kind, 'kind', 'input')
              .having((e) => e.message, 'message', '专辑分页参数无效'),
        ),
      );
    }
    expect(adapter.requests, isEmpty, reason: '校验失败不得发请求');
  });

  test('解码成功：歌曲字段 + 碟片/曲序/伴奏 + 版权事实 + 七行资源（ogg 两行在前）', () async {
    adapter.bytes = jsonBytes(songsWire());
    final tracks = await fetch(const AlbumSongsQuery(id: 42));

    expect(tracks.discCount, 2);
    expect(tracks.page.page, 1);
    expect(tracks.page.pageSize, 30);
    expect(tracks.page.total, 2);
    expect(tracks.page.items, hasLength(1));

    final track = tracks.page.items.single;
    expect(track.disc, 1);
    expect(track.position, 3);
    expect(track.hasAccompaniment, isTrue);
    expect(track.accompanimentCode, 1);

    final song = track.song;
    expect(song.id, '7301');
    expect(song.hash, 'FULLHASH');
    expect(song.title, '歌曲名');
    expect(song.artists, hasLength(2));
    expect(song.artists[0].id, 11);
    expect(song.artists[1].id, isNull);
    expect(song.albumId, '42');
    expect(song.albumTitle, '专辑名');
    expect(song.durationMs, 181000, reason: 'audio_info.duration 已是毫秒');
    expect(song.coverUrl, 'http://imge.kugou.com/album/240/cover.jpg');
    expect(song.privilege, 8);

    final facts = track.metadata;
    expect(facts.paymentType, 1);
    expect(facts.failureCode, isNull);
    expect(facts.oldCopyrightCode, 0);
    expect(facts.originalityCode, 1);
    expect(facts.rights, isNotNull);

    final rights = facts.rights!;
    expect(rights.qualityMap!.attr0, 1082130432, reason: '数字字符串精确解码');
    expect(rights.qualityMap!.attr1, 0);
    expect(rights.qualityMap!.bits, '128');
    expect(rights.classification, <String, int?>{'0': 1, '2': null});
    expect(rights.ipMap!.attr0, 281629629091840);
    expect(rights.ipMap!.bits, '96');
    expect(rights.copyrightAttributes, 4);
    expect(rights.copyrightScope, 'abc');
    expect(rights.copyrightGrade, 1);
    expect(rights.copyrightLevel, 2);
    expect(rights.displayCode, 1);
    expect(rights.displayRate, 0);
    expect(rights.paymentTemplate, 1);
    expect(rights.blockedApplications, '1001,1002');
    expect(rights.originalityCode, 1);
    expect(rights.advanceCode, isNull);
    expect(rights.multitrackHash, 'MT');
    expect(rights.coverUrl, 'http://imge.kugou.com/union/240/u.jpg');
    expect(rights.audioPrivilege, 8);
    expect(rights.freeForAd, 0);
    expect(rights.freeLimited, 1);
    expect(rights.voiceAd!.startMs, 30000);
    expect(rights.voiceAd!.sizeBytes, 100000);
    expect(rights.voiceAd!.hash, 'AD');
    expect(rights.preview!.startByte, 0);
    expect(rights.preview!.endByte, 1048576);
    expect(rights.preview!.startMs, 0);
    expect(rights.preview!.endMs, 30000);
    expect(rights.preview!.offsetHash, 'PREVIEWHASH');
    expect(rights.preview!.fileType, 0);
    expect(rights.preview!.clipHash, 'CLIPHASH');

    // 资源行顺序：ogg_128、ogg_320（trans_param）→ 128/320/flac/high/super。
    expect(facts.resources.map((r) => r.quality).toList(), <String>[
      'ogg_128',
      'ogg_320',
      '128',
      '320',
      'flac',
      'high',
      'super',
    ]);
    final ogg = facts.resources[0];
    expect(ogg.hash, 'OGG128');
    expect(ogg.sizeBytes, 1200000);
    expect(ogg.extension, 'ogg');
    expect(ogg.durationMs, isNull);
    expect(ogg.bitRateBps, isNull);
    expect(ogg.privilege, isNull);
    expect(ogg.payType, isNull, reason: 'pay_type 只喂给五档常规音质行');
    final ogg320 = facts.resources[1];
    expect(ogg320.quality, 'ogg_320');
    expect(ogg320.hash, '', reason: '空串 hash 照样入表（Some("")）');
    expect(ogg320.sizeBytes, 0);
    final row320 = facts.resources[3];
    expect(row320.hash, 'H320');
    expect(row320.sizeBytes, 7000000);
    expect(row320.durationMs, 180000);
    expect(row320.bitRateBps, isNull, reason: '320 行不带速率');
    expect(row320.extension, isNull);
    expect(row320.privilege, 8);
    expect(row320.payType, 1);
    final row128 = facts.resources[2];
    expect(row128.hash, 'H128');
    expect(row128.bitRateBps, 128000, reason: '128 行用通用 bitrate × 1000');
    expect(row128.extension, 'mp3');
    expect(row128.privilege, 8);
    final rowFlac = facts.resources[4];
    expect(rowFlac.bitRateBps, 900000);
    expect(rowFlac.privilege, 1);
    final rowHigh = facts.resources[5];
    expect(rowHigh.bitRateBps, 1400000);
    expect(rowHigh.privilege, isNull);
    final rowSuper = facts.resources[6];
    expect(rowSuper.bitRateBps, 2100000);
    expect(rowSuper.extension, 'flac');
    expect(rowSuper.privilege, isNull);
  });

  test('trans_param 缺失 → 全空 rights 仍在场（上游 default 转换恒 Ok）+ 仅五档常规行', () async {
    adapter.bytes = jsonBytes(songsWire(transParam: null));
    final tracks = await fetch(const AlbumSongsQuery(id: 42));

    final facts = tracks.page.items.single.metadata;
    // WireTrans::default().convert() → Ok(全 None 的 CatalogRights)——Err 分支
    // 是死代码，所以 rights 永不缺席，只是各字段未知。
    expect(facts.rights, isNotNull);
    expect(facts.rights!.qualityMap, isNull);
    expect(facts.rights!.preview, isNull);
    expect(facts.rights!.voiceAd, isNull);
    expect(facts.originalityCode, isNull);
    expect(facts.resources.map((r) => r.quality).toList(), <String>[
      '128',
      '320',
      'flac',
      'high',
      'super',
    ]);
  });

  test('回退链：ogg 哈希与大小都缺省才跳过；空 preview 区间被丢弃；hash_offset 有效则保留', () async {
    adapter.bytes = jsonBytes(
      songsWire(
        transParam: <String, Object?>{
          'ogg_320_hash': 'OGG320',
          'ogg_320_filesize': 2400000,
          'hash_offset': <String, Object?>{},
        },
      ),
    );
    final tracks = await fetch(const AlbumSongsQuery(id: 42));

    final resources = tracks.page.items.single.metadata.resources;
    expect(resources.map((r) => r.quality).toList(), <String>[
      'ogg_320',
      '128',
      '320',
      'flac',
      'high',
      'super',
    ], reason: 'ogg_128 全缺省跳过；ogg_320 带哈希保留');
    final rights = tracks.page.items.single.metadata.rights!;
    expect(rights.preview, isNull, reason: '空区间被 filter 丢弃');
    expect(rights.voiceAd, isNull);
    expect(rights.qualityMap, isNull);
    expect(rights.coverUrl, isNull);
  });

  test('空 songs 容忍（null/空对象）；extra 缺失 → discCount null', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"total":0},"extra":{}}',
    );
    final empty = await fetch(const AlbumSongsQuery(id: 42));
    expect(empty.page.items, isEmpty);
    expect(empty.page.total, 0);
    expect(empty.discCount, isNull);

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"total":0,"songs":{}},"extra":"x"}',
    );
    final tolerant = await fetch(const AlbumSongsQuery(id: 42));
    expect(tolerant.page.items, isEmpty, reason: 'list 把 {} 视为空集合');
    expect(tolerant.discCount, isNull, reason: 'extra 非 object → 默认节');
  });

  test('decode：data 非 object / songs 条目非 object / authors 错配', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    await expectLater(
      fetch(const AlbumSongsQuery(id: 42)),
      throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', 'decode')),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"songs":["str"]}}',
    );
    await expectLater(
      fetch(const AlbumSongsQuery(id: 42)),
      throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', 'decode')),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"songs":[{"authors":{"a":1}}]}}',
    );
    await expectLater(
      fetch(const AlbumSongsQuery(id: 42)),
      throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', 'decode')),
    );
  });

  test('业务失败 → business 携带码；20018 / msg 文案 → authentication', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":32002,"data":{}}');
    await expectLater(
      fetch(const AlbumSongsQuery(id: 42)),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 32002),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":20018}');
    await expectLater(
      fetch(const AlbumSongsQuery(id: 42)),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );

    adapter.bytes = jsonBytes(
      '{"status":0,"error_code":0,"msg":"用户登录已过期，请重新登录"}',
    );
    await expectLater(
      fetch(const AlbumSongsQuery(id: 42)),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });
}

/// 完整单曲 wire（album_songs.rs 的采样形状；id/数值混用字符串与数字）。
String songsWire({Object? transParam = _fullTransParam}) => jsonEncode(
  <String, Object?>{
    'status': 1,
    'error_code': 0,
    'data': <String, Object?>{
      'total': 2,
      'songs': <Object?>[
        <String, Object?>{
          'base': <String, Object?>{
            'album_id': '42',
            'album_audio_id': '7301',
            'audio_name': '歌曲名',
          },
          'audio_info': <String, Object?>{
            'hash': 'FULLHASH',
            'hash_128': 'H128',
            'hash_320': 'H320',
            'hash_flac': 'HFLAC',
            'hash_high': 'HHIGH',
            'hash_super': 'HSUPER',
            'extname': 'mp3',
            'extname_super': 'flac',
            'duration': 181000,
            'duration_128': 181000,
            'duration_320': 180000,
            'duration_flac': 181000,
            'duration_high': 182000,
            'duration_super': 181000,
            'filesize_128': 2900000,
            'filesize_320': 7000000,
            'filesize_flac': 25000000,
            'filesize_high': 50000000,
            'filesize_super': 60000000,
            'bitrate': 128,
            'bitrate_flac': 900,
            'bitrate_high': 1400,
            'bitrate_super': 2100,
          },
          'album_info': <String, Object?>{
            'album_name': '专辑名',
            'cover': 'http://imge.kugou.com/album/{size}/cover.jpg',
          },
          'authors': <Object?>[
            <String, Object?>{'author_id': 11, 'author_name': '歌手A'},
            <String, Object?>{'author_name': '歌手B'},
          ],
          'copyright': <String, Object?>{
            'privilege': 8,
            'privilege_128': 8,
            'privilege_320': 8,
            'privilege_flac': 1,
          },
          'deprecated': <String, Object?>{'pay_type': 1, 'old_cpy': 0},
          if (transParam != null) 'trans_param': transParam,
          'extend': <String, Object?>{'disc': 1, 'sort': 3, 'has_obbligato': 1},
        },
      ],
    },
    'extra': <String, Object?>{'disc_cnt': 2},
  },
);

/// trans_param 全字段采样（catalog_rights.rs `WireTrans`）。
const Map<String, Object?> _fullTransParam = <String, Object?>{
  'qualitymap': <String, Object?>{
    'attr0': '1082130432',
    'attr1': 0,
    'bits': '128',
  },
  'classmap': <String, Object?>{'0': '1', '2': 'bad-value'},
  'ipmap': <String, Object?>{'attr0': '281629629091840', 'bits': '96'},
  'cpy_attr0': 4,
  'cpy_map': 'abc',
  'cpy_grade': 1,
  'cpy_level': 2,
  'display': 1,
  'display_rate': 0,
  'pay_block_tpl': 1,
  'appid_block': '1001,1002',
  'is_original': 1,
  'hash_offset': <String, Object?>{
    'start_byte': 0,
    'end_byte': 1048576,
    'start_ms': 0,
    'end_ms': 30000,
    'offset_hash': 'PREVIEWHASH',
    'file_type': 0,
    'clip_hash': 'CLIPHASH',
  },
  'hash_multitrack': 'MT',
  'union_cover': 'http://imge.kugou.com/union/{size}/u.jpg',
  'ogg_128_hash': 'OGG128',
  'ogg_128_filesize': 1200000,
  // 空串/0 不跳过（上游 Some("")/Some(0) 照样入表——与搜索端点刻意不同）。
  'ogg_320_hash': '',
  'ogg_320_filesize': 0,
  'audio_privilege': 8,
  'free_for_ad': 0,
  'free_limited': 1,
  'voice_ad': <String, Object?>{
    'start_ms': 30000,
    'filesize': 100000,
    'hash': 'AD',
  },
};
