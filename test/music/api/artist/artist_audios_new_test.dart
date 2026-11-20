/// 歌手歌曲端点测试：请求装配 + 嵌套解码 + 权限/封面/原创回退链 + 错误分支。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/artist_audios_new.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 完整歌曲采样（audios_new.rs `Song` 的 wire 形状）。
Map<String, Object?> baseSong() => <String, Object?>{
  'album_audio_id': '67890',
  'audio_name': '晴天',
  'album_id': '42',
  'authors': <Object?>[
    <String, Object?>{
      'author_id': 1,
      'author_name': '',
      // base 非空 → 名称与 id 都以 base 为准。
      'base': <String, Object?>{'author_id': 123, 'author_name': '周杰伦'},
    },
    <String, Object?>{
      'author_id': 9,
      'author_name': '伴唱',
      'base': <String, Object?>{},
    },
    // 名称全空 → 整条丢弃。
    <String, Object?>{'author_name': ''},
  ],
  'audio_info': <String, Object?>{
    'hash': 'HASH128',
    'hash_320': 'HASH320',
    'hash_flac': 'HASHFLAC',
    'hash_high': 'HASHHIGH',
    'hash_super': 'HASHVIVID',
    'extname': 'mp3',
    'extname_super': 'viper',
    'timelength': 180000,
    'timelength_320': 180123,
    'timelength_flac': 180456,
    'timelength_high': 180789,
    'timelength_super': 181000,
    'filesize': 1048576,
    'filesize_320': 2097152,
    'filesize_flac': 3145728,
    'filesize_high': 4194304,
    'filesize_super': 5242880,
    'bitrate': 128,
    'bitrate_flac': 901,
    'bitrate_high': 1420,
    'bitrate_super': 1441,
  },
  'album_info': <String, Object?>{
    'album_name': '叶惠美',
    'cover': 'http://imge.kugou.com/stdmusic/{size}/2003/cov.png',
  },
  'copyright': <String, Object?>{
    'old_cpy': 1,
    'trans_param_departed': <String, Object?>{
      'ogg_128_hash': 'OGGHASH128',
      'ogg_128_filesize': 262144,
      'ogg_320_hash': 'OGGHASH320',
      'ogg_320_filesize': 524288,
      'union_cover': 'http://imge.kugou.com/union/{size}/u.png',
      'is_original': 2,
      'classmap': <String, Object?>{
        'known': '7',
        'broken': <String, Object?>{},
      },
      'qualitymap': <String, Object?>{'attr0': 1, 'bits': '16'},
      'hash_offset': <String, Object?>{'start_ms': 0, 'end_ms': 30000},
      'voice_ad': <String, Object?>{
        'start_ms': 5000,
        'filesize': 2048,
        'hash': 'ADHASH',
      },
      'cpy_attr0': 3,
      'cpy_grade': '5',
      'audio_privilege': 8,
    },
  },
  'goods_info': <String, Object?>{'audio_pay_type': 1},
  // extra.is_original 缺省 → 回退 trans_param.is_original。
  'extra': <String, Object?>{},
  'privilege_download': <String, Object?>{
    'privilege': 8,
    'privilege_128': 4,
    'privilege_320': 8,
    'privilege_flac': 12,
    'privilege_high': 16,
    'privilege_super': 20,
    'fail_process_128': 0,
  },
};

String songsWire(Object data) =>
    jsonEncode(<String, Object?>{'status': 1, 'error_code': 0, 'data': data});

String songsOf(List<Object?> songs) =>
    songsWire(<String, Object?>{'total': 2, 'songs': songs});

void main() {
  late CaptureAdapter adapter;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    session = fakeMusicSession(artistTestClient(adapter), artistTestIdentity());
  });

  test(
    '请求装配：GET /openapi/kmr/v2/audio_group/author + 无 x-router + kg-tid',
    () async {
      adapter.bytes = jsonBytes(songsOf(<Object?>[baseSong()]));
      final page = await fetchArtistAudiosNew(
        session,
        const MusicArtistAudiosQuery(id: 123),
      );
      expect(page.items, isNotEmpty);

      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(
        request.path,
        startsWith(
          'https://gateway.kugou.com/openapi/kmr/v2/audio_group/author',
        ),
      );
      expect(
        request.headers.containsKey('x-router'),
        isFalse,
        reason: '上游 router=None',
      );
      expect(request.headers['kg-tid'], '36');
      final query = request.query;
      expect(query['author_id'], '123');
      expect(query['area_code'], 'all');
      expect(query['sort'], '2', reason: '缺省 new → 2');
      expect(query['page'], '1');
      expect(query['pagesize'], '100');
      expect(query['replace_api_version'], '1');
      expect(query['mvdata_need'], '1');
      expect(query['show_audio_honor'], '1');
      expect(query['show_audio_tag'], '1');
      expect(query['replace_need'], '1');
    },
  );

  test('sort=hot → wire sort=1', () async {
    adapter.bytes = jsonBytes(songsOf(<Object?>[baseSong()]));
    await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 1, sort: 'hot', pageSize: 30, page: 3),
    );
    final query = adapter.requests.single.query;
    expect(query['sort'], '1');
    expect(query['page'], '3');
    expect(query['pagesize'], '30');
  });

  test('解码：歌曲嵌套字段/authors base 优先/毫秒 timelength/专辑名', () async {
    adapter.bytes = jsonBytes(songsOf(<Object?>[baseSong()]));
    final page = await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 123),
    );

    expect(page.page, 1);
    expect(page.pageSize, 100);
    expect(page.total, 2);
    final song = page.items.single;
    expect(song.id, '67890');
    expect(song.hash, 'HASH128');
    expect(song.title, '晴天');
    expect(song.albumId, '42');
    expect(song.albumTitle, '叶惠美');
    expect(song.durationMs, 180000, reason: 'timelength 本来就是毫秒');
    expect(song.artistText, '周杰伦 / 伴唱', reason: '全空作者丢弃、base 名优先');
    expect(song.artists.first.id, 123, reason: 'base.author_id 优先');
    expect(song.privilege, 8, reason: 'privilege 优先于 privilege_128');
    expect(song.metadata.paymentType, 1);
    expect(song.metadata.failureCode, 0);
    expect(song.metadata.oldCopyrightCode, 1);
    expect(song.metadata.originalityCode, 2, reason: 'extra 缺省回退 trans');
  });

  test('资源表：ogg 在前 + 128/320/flac/high/super 字段与权限逐条对齐', () async {
    adapter.bytes = jsonBytes(songsOf(<Object?>[baseSong()]));
    final song = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 123),
    )).items.single;

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

    final ogg128 = song.metadata.resources[0];
    expect(ogg128.hash, 'OGGHASH128');
    expect(ogg128.sizeBytes, 262144);
    expect(ogg128.extension, 'ogg');
    expect(ogg128.privilege, isNull);
    expect(ogg128.payType, isNull);

    final ogg320 = song.metadata.resources[1];
    expect(ogg320.hash, 'OGGHASH320');
    expect(ogg320.sizeBytes, 524288);

    final std = song.metadata.resources[2];
    expect(std.hash, 'HASH128');
    expect(std.sizeBytes, 1048576);
    expect(std.durationMs, 180000);
    expect(std.bitRateBps, 128000);
    expect(std.extension, 'mp3');
    expect(std.privilege, 4);
    expect(std.payType, 1);
    expect(std.failureCode, 0);

    final hq = song.metadata.resources[3];
    expect(hq.hash, 'HASH320');
    expect(hq.durationMs, 180123);
    expect(hq.bitRateBps, isNull, reason: '320 无 bitrate 字段');
    expect(hq.extension, isNull);
    expect(hq.privilege, 8);

    final sq = song.metadata.resources[4];
    expect(sq.hash, 'HASHFLAC');
    expect(sq.bitRateBps, 901000);
    expect(sq.privilege, 12);

    final high = song.metadata.resources[5];
    expect(high.hash, 'HASHHIGH');
    expect(high.bitRateBps, 1420000);
    expect(high.privilege, 16);

    final vivid = song.metadata.resources[6];
    expect(vivid.hash, 'HASHVIVID');
    expect(vivid.durationMs, 181000);
    expect(vivid.bitRateBps, 1441000);
    expect(vivid.extension, 'viper', reason: 'extname_super 只给 super');
    expect(vivid.privilege, 20);
  });

  test('版权事实：classmap 宽容/qualitymap/preview/voiceAd/union_cover', () async {
    adapter.bytes = jsonBytes(songsOf(<Object?>[baseSong()]));
    final song = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 123),
    )).items.single;

    final rights = song.metadata.rights!;
    expect(rights.qualityMap!.attr0, 1);
    expect(rights.qualityMap!.bits, '16');
    expect(rights.classification, <String, int?>{
      'known': 7,
      'broken': null,
    }, reason: 'optional_map：解析不了的值保留 null 键位');
    expect(rights.copyrightAttributes, 3);
    expect(rights.copyrightGrade, 5);
    expect(rights.audioPrivilege, 8);
    expect(rights.preview!.startMs, 0);
    expect(rights.preview!.endMs, 30000);
    expect(rights.voiceAd!.startMs, 5000);
    expect(rights.voiceAd!.sizeBytes, 2048);
    expect(rights.voiceAd!.hash, 'ADHASH');
    // 封面回退链第一级：union_cover（已过 {size}→240）。
    expect(song.coverUrl, 'http://imge.kugou.com/union/240/u.png');
  });

  test('封面回退链：union_cover 缺省 → album_info.cover；两者都缺 → 空串', () async {
    final song = baseSong();
    (song['copyright']! as Map<String, Object?>)['trans_param_departed'] =
        <String, Object?>{'ogg_128_hash': 'OGG'};
    adapter.bytes = jsonBytes(songsOf(<Object?>[song]));
    var result = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 1),
    )).items.single;
    expect(result.coverUrl, 'http://imge.kugou.com/stdmusic/240/2003/cov.png');

    final bare = baseSong();
    (bare['copyright']! as Map<String, Object?>)['trans_param_departed'] =
        <String, Object?>{};
    (bare['album_info']! as Map<String, Object?>)['cover'] = '';
    adapter.bytes = jsonBytes(songsOf(<Object?>[bare]));
    result = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 1),
    )).items.single;
    expect(result.coverUrl, '');
  });

  test('原创回退链：extra.is_original 优先于 trans_param.is_original', () async {
    final song = baseSong();
    (song['extra']! as Map<String, Object?>)['is_original'] = 1;
    adapter.bytes = jsonBytes(songsOf(<Object?>[song]));
    final result = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 1),
    )).items.single;
    expect(result.metadata.originalityCode, 1);
  });

  test('权限回退：privilege 缺省回退 privilege_128；全缺 → null', () async {
    final song = baseSong();
    (song['privilege_download']! as Map<String, Object?>).remove('privilege');
    adapter.bytes = jsonBytes(songsOf(<Object?>[song]));
    var result = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 1),
    )).items.single;
    expect(result.privilege, 4);

    final bare = baseSong();
    (bare['privilege_download']! as Map<String, Object?>)
      ..remove('privilege')
      ..remove('privilege_128');
    adapter.bytes = jsonBytes(songsOf(<Object?>[bare]));
    result = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 1),
    )).items.single;
    expect(result.privilege, isNull);
  });

  test(
    'id/albumTitle 回退：album_audio_id 空 → hash；album_name 空 → null',
    () async {
      final song = baseSong()
        ..['album_audio_id'] = ''
        ..['album_name'] = null;
      (song['album_info']! as Map<String, Object?>)['album_name'] = '';
      adapter.bytes = jsonBytes(songsOf(<Object?>[song]));
      final result = (await fetchArtistAudiosNew(
        session,
        const MusicArtistAudiosQuery(id: 1),
      )).items.single;
      expect(result.id, 'HASH128');
      expect(result.albumTitle, isNull);
    },
  );

  test('audio_info 非 object → 全默认结构（object 宽容，不报错）', () async {
    final song = baseSong()
      ..['audio_info'] = 3
      // trans 也清空：无 ogg 事实。
      ..['copyright'] = <String, Object?>{
        'trans_param_departed': <String, Object?>{},
      };
    adapter.bytes = jsonBytes(songsOf(<Object?>[song]));
    final result = (await fetchArtistAudiosNew(
      session,
      const MusicArtistAudiosQuery(id: 1),
    )).items.single;
    expect(result.hash, '');
    expect(result.durationMs, isNull);
    expect(result.metadata.resources.map((r) => r.quality), <String>[
      '128',
      '320',
      'flac',
      'high',
      'super',
    ], reason: 'trans 缺省时无 ogg；五条平铺资源 hash 为空串仍入表');
  });

  test('结构缺陷：data null → decode；songs 元素非 object → decode', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    await expectLater(
      fetchArtistAudiosNew(session, const MusicArtistAudiosQuery(id: 1)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(songsOf(<Object?>['文本']));
    await expectLater(
      fetchArtistAudiosNew(session, const MusicArtistAudiosQuery(id: 1)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('业务失败 → business 带码；20018 → authentication', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":152,"data":{}}');
    await expectLater(
      fetchArtistAudiosNew(session, const MusicArtistAudiosQuery(id: 1)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":20018}');
    await expectLater(
      fetchArtistAudiosNew(session, const MusicArtistAudiosQuery(id: 1)),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });

  test('input 校验：分页 0/越界、非法排序拒绝；合法边界通过', () async {
    void expectInput(MusicArtistAudiosQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput(const MusicArtistAudiosQuery(id: 1, page: 0));
    expectInput(const MusicArtistAudiosQuery(id: 1, pageSize: 0));
    expectInput(const MusicArtistAudiosQuery(id: 1, pageSize: 101));
    expectInput(const MusicArtistAudiosQuery(id: 1, sort: 'random'));
    expectInput(const MusicArtistAudiosQuery(id: -1));
    // 合法边界。
    const MusicArtistAudiosQuery(id: 1, pageSize: 1).validate();
    const MusicArtistAudiosQuery(id: 1, pageSize: 100).validate();
    const MusicArtistAudiosQuery(id: 1, sort: 'hot').validate();
  });
}
