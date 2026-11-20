/// 公开歌单曲目端点测试：请求装配 + 歌曲事实折叠 + display 规则 +
/// list/optional 宽容 + input/business 边界（playlist_track_all.rs +
/// util/playlist_song.rs）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_track_all.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

Map<String, Object?> trackWire() => <String, Object?>{
  'mixsongid': '67890',
  'hash': 'HASH0001',
  'name': '歌手A - 歌曲名.mp3',
  'timelen': 180000,
  'album_id': '42',
  'albuminfo': <String, Object?>{'id': 42, 'name': '专辑名'},
  'singerinfo': <Object?>[
    <String, Object?>{
      'id': 1,
      'name': '歌手A',
      'avatar': 'http://imge.kugou.com/artist/{size}/a.png',
      'publish': 1,
    },
  ],
  'cover': 'http://imge.kugou.com/stdmusic/{size}/2021001/abc.png',
  'privilege': 8,
  'fileid': 999,
  'sort': 3,
  'collecttime': 1700000000,
  'audio_id': 12345,
  'language': '国语',
  'publish_date': '2021-01-01',
  'media_old_cpy': 1,
  'size': 1048576,
  'bitrate': 320,
  'extname': 'mp3',
  'trans_param': <String, Object?>{
    'songname_suffix': '（Live）',
    'cpy_grade': 9,
    'classmap': <String, Object?>{'a': 1, 'b': 'not-number'},
    'qualitymap': <String, Object?>{'attr0': 1, 'attr1': '2', 'bits': '16'},
    'ogg_128_hash': 'OGG128',
    'ogg_128_filesize': 2048,
    'hash_offset': <String, Object?>{'start_byte': 0, 'end_byte': 100},
    'union_cover': 'http://imge.kugou.com/union/{size}/u.png',
    'voice_ad': <String, Object?>{
      'start_ms': 500,
      'filesize': 1024,
      'hash': 'AD',
    },
  },
  'tagmap': <String, Object?>{'genre': '1', 'other': <String, Object?>{}},
  'relate_goods': <Object?>[
    <String, Object?>{
      'hash': 'HASH320',
      'size': 500,
      'bitrate': 320,
      'privilege': 8,
      'level': 4,
    },
    <String, Object?>{'hash': 'HASHFLAC', 'size': 600, 'level': 5},
    <String, Object?>{'hash': 'HASHUNKNOWN', 'level': 99},
  ],
  'download': <Object?>[
    <String, Object?>{
      'hash': 'HASH320',
      'status': 1,
      'pay_type': 0,
      'fail_process': 0,
    },
    <String, Object?>{
      'hash': 'HASH0001',
      'status': 2,
      'pay_type': 1,
      'fail_process': 3,
    },
  ],
  'has_obbligato': 1,
};

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = capturedClient(adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<MusicPage<MusicPlaylistTrack>> fetchTrackAll(
    MusicPlaylistTrackAllQuery query,
  ) async {
    adapter.bytes = jsonBytes(
      trackAllWire(
        data: <String, Object?>{
          'count': 1,
          'songs': <Object?>[trackWire()],
        },
      ),
    );
    return fetchPlaylistTrackAll(fakeMusicSession(identity, client), query);
  }

  test('请求装配：GET/无 router/九个固定参数/begin_idx 偏移', () async {
    await fetchTrackAll(
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 3,
        pageSize: 30,
      ),
    );
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/pubsongs/v2/get_other_list_file_nofilt',
      ),
      isTrue,
    );
    expect(request.headers.containsKey('x-router'), isFalse);
    final query = request.query;
    expect(query['area_code'], '1');
    expect(query['begin_idx'], '60', reason: '(page-1)*page_size');
    expect(query['plat'], '1');
    expect(query['type'], '1');
    expect(query['mode'], '1');
    expect(query['personal_switch'], '1');
    expect(query['extend_fields'], 'abtags,hot_cmt,popularization');
    expect(query['pagesize'], '30');
    expect(query['global_collection_id'], 'gcol-1');
  });

  test('解码：SongSummary 展示规则/毫秒/封面/歌手', () async {
    final page = await fetchTrackAll(
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 1,
        pageSize: 30,
      ),
    );
    expect(page.page, 1);
    expect(page.pageSize, 30);
    final track = page.items.single;
    expect(track.song.id, '67890');
    expect(track.song.hash, 'HASH0001');
    expect(track.song.title, '歌曲名', reason: '首个「 - 」后取展示标题并去掉 .mp3');
    expect(track.song.artistText, '歌手A');
    expect(track.song.albumId, '42');
    expect(track.song.albumTitle, '专辑名');
    expect(track.song.durationMs, 180000, reason: '公开列表 timelen 已是毫秒');
    expect(track.song.coverUrl, contains('/240/'));
    expect(track.song.privilege, 8);
    expect(track.fileId, 999);
    expect(track.sortIndex, 3);
    expect(track.collectedAtSeconds, 1700000000);
    expect(track.fileSortIndex, isNull, reason: 'fsort 是云歌单专有');
    expect(track.metadata.audioId, 12345);
    expect(track.metadata.albumDetailsId, 42);
    expect(track.metadata.language, '国语');
    expect(track.metadata.publishedAt, '2021-01-01');
    expect(track.metadata.sourceFileName, '歌手A - 歌曲名.mp3', reason: '原始文件名保留');
    expect(track.metadata.filenameArtistName, isNull, reason: '歌手行非空时不从文件名补');
    expect(track.metadata.oldCopyrightCode, 1);
    expect(track.metadata.hasAccompaniment, isTrue);
    expect(track.metadata.accompanimentCode, 1);
    expect(track.metadata.artists.single.name, '歌手A');
    expect(track.metadata.artists.single.avatarUrl, contains('/240/'));
    expect(track.metadata.artists.single.publicationCode, 1);
    expect(track.metadata.relatedResources, hasLength(3));
    expect(track.metadata.downloads, hasLength(2));
    expect(track.metadata.genreMap, <String, int?>{'genre': 1, 'other': null});
  });

  test('资源折叠：ogg/relate_goods level 词表/主 hash 行/下载授权回填', () async {
    final track = (await fetchTrackAll(
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 1,
        pageSize: 30,
      ),
    )).items.single;
    final resources = track.metadata.resources;
    final qualities = resources.map((r) => r.quality).toList();
    expect(qualities, <String>[
      'ogg_128',
      '320',
      'flac',
      'unspecified',
      '320',
    ], reason: 'trans ogg 资源在前，relate_goods 按服务端顺序，主 hash 行最后');

    final ogg = resources[0];
    expect(ogg.hash, 'OGG128');
    expect(ogg.sizeBytes, 2048);
    expect(ogg.extension, 'ogg');

    final related320 = resources[1];
    expect(related320.hash, 'HASH320');
    expect(related320.sizeBytes, 500);
    expect(related320.bitRateBps, 320000);
    expect(related320.durationMs, isNull, reason: '非主 hash 不带时长');
    expect(related320.extension, isNull);
    expect(related320.privilege, 8);
    expect(related320.paymentType, 0);
    expect(related320.failureCode, 0);
    expect(related320.downloadStatus, 1);

    final flac = resources[2];
    expect(flac.quality, 'flac');
    expect(flac.paymentType, isNull, reason: 'download 无此 hash 时授权留空');

    expect(resources[3].quality, 'unspecified', reason: 'level 99 不在词表');

    final base = resources[4];
    expect(base.hash, 'HASH0001');
    expect(base.quality, '320', reason: '主 hash 行 quality 用 bitrate 十进制');
    expect(base.sizeBytes, 1048576);
    expect(base.durationMs, 180000);
    expect(base.bitRateBps, 320000);
    expect(base.extension, 'mp3');
    expect(
      base.paymentType,
      isNull,
      reason: '主 hash 行的 payment/failure 取入参（公开歌单两参皆空）',
    );
    expect(base.failureCode, isNull);
    expect(base.downloadStatus, 2, reason: 'download[HASH0001].status');

    expect(track.metadata.paymentType, 1, reason: 'payment 缺省回退 base_download');
    expect(track.metadata.failureCode, 3);
  });

  test('权益事实：trans_param 折叠成 rights + titleSuffix', () async {
    final track = (await fetchTrackAll(
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 1,
        pageSize: 30,
      ),
    )).items.single;
    expect(track.metadata.titleSuffix, '（Live）');
    final rights = track.metadata.rights!;
    expect(rights.qualityMap!.attr0, 1);
    expect(rights.qualityMap!.attr1, 2, reason: '数字字符串按 scalar 宽容');
    expect(rights.qualityMap!.bits, '16');
    expect(rights.classification, <String, int?>{'a': 1, 'b': null});
    expect(rights.copyrightGrade, 9);
    expect(rights.preview!.startByte, 0);
    expect(rights.preview!.endByte, 100);
    expect(rights.coverUrl, contains('/240/'));
    expect(rights.voiceAd!.startMs, 500);
    expect(rights.voiceAd!.sizeBytes, 1024);
    expect(rights.voiceAd!.hash, 'AD');
  });

  test('display 规则：无分隔符保留原样；多段分隔符只切第一个；文件名歌手', () async {
    adapter.bytes = jsonBytes(
      trackAllWire(
        data: <String, Object?>{
          'count': 2,
          'songs': <Object?>[
            <String, Object?>{
              'mixsongid': '1',
              'hash': 'H1',
              'name': 'A - B - C.flac',
              'album_id': '',
              'albuminfo': <String, Object?>{},
              'singerinfo': <Object?>[],
              'cover': '',
            },
            <String, Object?>{
              'mixsongid': '2',
              'hash': 'H2',
              'name': '纯名字.wav',
              'album_id': '',
              'albuminfo': <String, Object?>{},
              'singerinfo': <Object?>[],
              'cover': '',
            },
          ],
        },
      ),
    );
    final page = await fetchPlaylistTrackAll(
      fakeMusicSession(identity, client),
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 1,
        pageSize: 30,
      ),
    );
    expect(page.items[0].song.title, 'B - C');
    expect(page.items[0].song.artists.single.name, 'A');
    expect(page.items[0].song.artists.single.id, isNull, reason: '文件名歌手不给 id');
    expect(page.items[1].song.title, '纯名字');
    expect(page.items[1].song.artists, isEmpty);
    expect(page.items[1].metadata.filenameArtistName, isNull);
  });

  test('list 宽容：songs {} / 缺省 → 空 items；count 回填 total', () async {
    adapter.bytes = jsonBytes(
      trackAllWire(
        data: <String, Object?>{'count': 0, 'songs': <String, Object?>{}},
      ),
    );
    final page = await fetchPlaylistTrackAll(
      fakeMusicSession(identity, client),
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 2,
        pageSize: 50,
      ),
    );
    expect(page.items, isEmpty);
    expect(page.page, 2);
    expect(page.pageSize, 50);
    expect(page.total, 0);

    adapter.bytes = jsonBytes(trackAllWire(data: <String, Object?>{}));
    final empty = await fetchPlaylistTrackAll(
      fakeMusicSession(identity, client),
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 1,
        pageSize: 30,
      ),
    );
    expect(empty.items, isEmpty);
    expect(empty.total, isNull);
  });

  test('decode：data 非 object / songs 非数组 / 歌手行非 object → decode', () async {
    adapter.bytes = jsonBytes(trackAllWire(data: 'nope'));
    await expectLater(
      fetchPlaylistTrackAll(
        fakeMusicSession(identity, client),
        const MusicPlaylistTrackAllQuery(
          globalId: 'gcol-1',
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
    adapter.bytes = jsonBytes(
      trackAllWire(data: <String, Object?>{'songs': 'nope'}),
    );
    await expectLater(
      fetchPlaylistTrackAll(
        fakeMusicSession(identity, client),
        const MusicPlaylistTrackAllQuery(
          globalId: 'gcol-1',
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
    adapter.bytes = jsonBytes(
      trackAllWire(
        data: <Object?>[
          <String, Object?>{
            'mixsongid': '1',
            'singerinfo': <Object?>[true],
          },
        ],
      ),
    );
    await expectLater(
      fetchPlaylistTrackAll(
        fakeMusicSession(identity, client),
        const MusicPlaylistTrackAllQuery(
          globalId: 'gcol-1',
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
  });

  test('optional 宽容：relate_goods 非法条目整体归空，text 的 bool → 空串', () async {
    adapter.bytes = jsonBytes(
      trackAllWire(
        data: <String, Object?>{
          'count': 1,
          'songs': <Object?>[
            <String, Object?>{
              'mixsongid': true,
              'hash': 'H1',
              'name': 3.5,
              'album_id': false,
              'relate_goods': <Object?>['broken'],
              'download': <Object?>[true],
            },
          ],
        },
      ),
    );
    final track = (await fetchPlaylistTrackAll(
      fakeMusicSession(identity, client),
      const MusicPlaylistTrackAllQuery(
        globalId: 'gcol-1',
        page: 1,
        pageSize: 30,
      ),
    )).items.single;
    expect(track.song.id, '');
    expect(track.song.title, '3.5', reason: '数字仍进 text');
    expect(track.song.albumId, '');
    expect(track.metadata.relatedResources, isEmpty);
    expect(track.metadata.downloads, isEmpty);
    expect(
      track.metadata.resources,
      isEmpty,
      reason: 'size/bitrate/extname/下载授权全空 → 主 hash 行不产生',
    );
  });

  test('业务失败与登录过期', () async {
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 0, 'error_code': 152}),
    );
    await expectLater(
      fetchPlaylistTrackAll(
        fakeMusicSession(identity, client),
        const MusicPlaylistTrackAllQuery(
          globalId: 'gcol-1',
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
    );
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'error_code': 20018}),
    );
    await expectLater(
      fetchPlaylistTrackAll(
        fakeMusicSession(identity, client),
        const MusicPlaylistTrackAllQuery(
          globalId: 'gcol-1',
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
  });

  test('input 校验：页码/分页 1..=200/global_id', () {
    void expectInput(MusicPlaylistTrackAllQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput(
      const MusicPlaylistTrackAllQuery(globalId: 'g', page: 0, pageSize: 30),
    );
    expectInput(
      const MusicPlaylistTrackAllQuery(globalId: 'g', page: 1, pageSize: 0),
    );
    expectInput(
      const MusicPlaylistTrackAllQuery(globalId: 'g', page: 1, pageSize: 201),
    );
    expectInput(
      const MusicPlaylistTrackAllQuery(globalId: '', page: 1, pageSize: 30),
    );
    expectInput(
      MusicPlaylistTrackAllQuery(globalId: 'a' * 257, page: 1, pageSize: 30),
    );
    const MusicPlaylistTrackAllQuery(
      globalId: 'g',
      page: 1,
      pageSize: 1,
    ).validate();
    const MusicPlaylistTrackAllQuery(
      globalId: 'g',
      page: 1,
      pageSize: 200,
    ).validate();
  });
}

/// 信封模板。
String trackAllWire({required Object? data}) =>
    jsonEncode(<String, Object?>{'status': 1, 'error_code': 0, 'data': data});
