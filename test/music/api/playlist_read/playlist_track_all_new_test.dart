/// 云歌单曲目端点测试：匿名 → authentication、请求装配（body 键序）、
/// 解码（media_privilege/fsort/信封字段回显）、20017/input/business 分支
/// （playlist_track_all_new.rs）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_track_all_new.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 信封模板。
String cloudWire({required Object? data, int status = 1, int errorCode = 0}) =>
    jsonEncode(<String, Object?>{
      'status': status,
      'error_code': errorCode,
      'data': data,
    });

Map<String, Object?> cloudTrackWire({String mixsongid = '67890'}) =>
    <String, Object?>{
      'mixsongid': mixsongid,
      'hash': 'HASH0001',
      'name': '歌手A - 云端歌曲.flac',
      'timelen': 240000,
      'album_id': '42',
      'albuminfo': <String, Object?>{'id': 42, 'name': '云端专辑'},
      'singerinfo': <Object?>[
        <String, Object?>{'id': 1, 'name': '歌手A'},
      ],
      'cover': 'http://imge.kugou.com/stdmusic/{size}/c.png',
      'media_privilege': 8,
      'fileid': 900,
      'sort': 2,
      'fsort': 5,
      'collecttime': 1700000001,
      'audio_id': 12345,
      'size': 4096,
      'bitrate': 901,
      'extname': 'flac',
      'media_pay_type': 2,
      'media_fail_process': 4,
      'is_publish': 1,
    };

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity anonymous;
  late KugouIdentity account;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = capturedClient(adapter);
    anonymous = KugouIdentity.anonymous();
    account = accountIdentity();
  });

  test('匿名 → authentication（先于 input 校验，不发请求）', () async {
    await expectLater(
      fetchPlaylistTrackAllNew(
        fakeMusicSession(anonymous, client),
        const MusicPlaylistTrackAllNewQuery(
          cloudListId: 0,
          page: 0,
          pageSize: 0,
        ),
      ),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('请求装配：POST/路由/body 键序与值/query 注入账号', () async {
    adapter.bytes = jsonBytes(
      cloudWire(data: <String, Object?>{'info': <Object?>[], 'count': 0}),
    );
    await fetchPlaylistTrackAllNew(
      fakeMusicSession(account, client),
      const MusicPlaylistTrackAllNewQuery(
        cloudListId: 5566,
        page: 2,
        pageSize: 100,
      ),
    );
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/v4/get_list_all_file_v3',
      ),
      isTrue,
    );
    expect(request.headers['x-router'], 'cloudlist.service.kugou.com');
    // 普通带签名请求：账号字段同时注入 query（与 body 里的账号并存）。
    expect(request.query['token'], 'token-fixture');
    expect(request.query['userid'], '12345');
    expect(
      request.query.keys,
      containsAll(<String>[
        'appid',
        'clientver',
        'dfid',
        'mid',
        'signature',
        'uuid',
      ]),
    );

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'listid',
      'userid',
      'type',
      'page',
      'pagesize',
      'area_code',
      'allplatform',
      'show_cover',
      'token',
    ]);
    expect(body['listid'], 5566);
    expect(body['userid'], 12345);
    expect(body['type'], 0);
    expect(body['page'], 2);
    expect(body['pagesize'], 100);
    expect(body['area_code'], 1);
    expect(body['allplatform'], 1);
    expect(body['show_cover'], 1);
    expect(body['token'], 'token-fixture');
  });

  test('解码：歌曲映射/media_privilege/fsort/信封字段回显', () async {
    adapter.bytes = jsonBytes(
      cloudWire(
        data: <String, Object?>{
          'page': 2,
          'pagesize': 100,
          'count': 321,
          'info': <Object?>[cloudTrackWire()],
          'userid': 12345,
          'list_ver': 12,
          'listid': 5566,
        },
      ),
    );
    final result = await fetchPlaylistTrackAllNew(
      fakeMusicSession(account, client),
      const MusicPlaylistTrackAllNewQuery(
        cloudListId: 5566,
        page: 2,
        pageSize: 100,
      ),
    );
    // page/pageSize/total 取自 wire（不是请求回显）。
    expect(result.page.page, 2);
    expect(result.page.pageSize, 100);
    expect(result.page.total, 321);
    expect(result.userId, 12345);
    expect(result.cloudListId, 5566);
    expect(result.revision, 12);

    final track = result.page.items.single;
    expect(track.song.id, '67890');
    expect(track.song.title, '云端歌曲');
    expect(
      track.song.privilege,
      8,
      reason: '云歌单 privilege 字段是 media_privilege',
    );
    expect(track.song.albumId, '42');
    expect(track.song.albumTitle, '云端专辑');
    expect(track.song.durationMs, 240000);
    expect(track.fileId, 900);
    expect(track.sortIndex, 2);
    expect(track.fileSortIndex, 5, reason: 'fsort 是云歌单专有');
    expect(track.collectedAtSeconds, 1700000001);
    expect(
      track.metadata.paymentType,
      2,
      reason: 'media_pay_type 走 payment 入参',
    );
    expect(track.metadata.failureCode, 4);
    expect(track.metadata.publicationCode, 1);
    expect(
      track.metadata.hasAccompaniment,
      isNull,
      reason: '云歌单不带 has_obbligato',
    );
    // 主 hash 行：size/bitrate/extname 存在 → quality=bitrate 十进制。
    expect(track.metadata.resources.single.quality, '901');
    expect(track.metadata.resources.single.hash, 'HASH0001');
    expect(track.metadata.resources.single.bitRateBps, 901000);
    expect(track.metadata.resources.single.extension, 'flac');
    expect(track.metadata.resources.single.paymentType, 2);
    expect(track.metadata.resources.single.failureCode, 4);
  });

  test('专辑：空 albuminfo 与主 album_id 并存（身份字段保留）', () async {
    adapter.bytes = jsonBytes(
      cloudWire(
        data: <String, Object?>{
          'info': <Object?>[
            <String, Object?>{
              'mixsongid': '1',
              'hash': 'H1',
              'name': '歌',
              'album_id': '42',
              'albuminfo': <String, Object?>{},
              'singerinfo': <Object?>[
                <String, Object?>{'name': 'A'},
              ],
              'cover': '',
            },
          ],
        },
      ),
    );
    final track = (await fetchPlaylistTrackAllNew(
      fakeMusicSession(account, client),
      const MusicPlaylistTrackAllNewQuery(
        cloudListId: 5566,
        page: 1,
        pageSize: 30,
      ),
    )).page.items.single;
    expect(track.song.albumId, '42');
    expect(track.song.albumTitle, isEmpty);
  });

  test('info 缺省 → 空 items；info 空 object / 非数组 → decode', () async {
    adapter.bytes = jsonBytes(cloudWire(data: <String, Object?>{'count': 0}));
    final result = await fetchPlaylistTrackAllNew(
      fakeMusicSession(account, client),
      const MusicPlaylistTrackAllNewQuery(
        cloudListId: 5566,
        page: 1,
        pageSize: 30,
      ),
    );
    expect(result.page.items, isEmpty);

    adapter.bytes = jsonBytes(
      cloudWire(data: <String, Object?>{'info': <String, Object?>{}}),
    );
    await expectLater(
      fetchPlaylistTrackAllNew(
        fakeMusicSession(account, client),
        const MusicPlaylistTrackAllNewQuery(
          cloudListId: 5566,
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );

    adapter.bytes = jsonBytes(cloudWire(data: <String, Object?>{'info': 5}));
    await expectLater(
      fetchPlaylistTrackAllNew(
        fakeMusicSession(account, client),
        const MusicPlaylistTrackAllNewQuery(
          cloudListId: 5566,
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
  });

  test('行级 decode：非 object 条目带「云歌单第 N 首」前缀', () async {
    adapter.bytes = jsonBytes(
      cloudWire(
        data: <String, Object?>{
          'info': <Object?>[true],
        },
      ),
    );
    await expectLater(
      fetchPlaylistTrackAllNew(
        fakeMusicSession(account, client),
        const MusicPlaylistTrackAllNewQuery(
          cloudListId: 5566,
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'decode' &&
              e.message.contains('云歌单第1首'),
        ),
      ),
    );
  });

  test('专属过期码 20017 → authentication（先于 business 判定）', () async {
    adapter.bytes = jsonBytes(
      cloudWire(status: 0, errorCode: 20017, data: null),
    );
    await expectLater(
      fetchPlaylistTrackAllNew(
        fakeMusicSession(account, client),
        const MusicPlaylistTrackAllNewQuery(
          cloudListId: 5566,
          page: 1,
          pageSize: 30,
        ),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'authentication' &&
              e.code == 20017,
        ),
      ),
    );
  });

  test('业务失败（status=0 error_code=152）→ business', () async {
    adapter.bytes = jsonBytes(cloudWire(status: 0, errorCode: 152, data: null));
    await expectLater(
      fetchPlaylistTrackAllNew(
        fakeMusicSession(account, client),
        const MusicPlaylistTrackAllNewQuery(
          cloudListId: 5566,
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
  });

  test('input 校验：cloud_list_id=0/页码 0/分页 1..=300', () {
    void expectInput(MusicPlaylistTrackAllNewQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput(
      const MusicPlaylistTrackAllNewQuery(
        cloudListId: 0,
        page: 1,
        pageSize: 30,
      ),
    );
    expectInput(
      const MusicPlaylistTrackAllNewQuery(
        cloudListId: 1,
        page: 0,
        pageSize: 30,
      ),
    );
    expectInput(
      const MusicPlaylistTrackAllNewQuery(cloudListId: 1, page: 1, pageSize: 0),
    );
    expectInput(
      const MusicPlaylistTrackAllNewQuery(
        cloudListId: 1,
        page: 1,
        pageSize: 301,
      ),
    );
    const MusicPlaylistTrackAllNewQuery(
      cloudListId: 1,
      page: 1,
      pageSize: 1,
    ).validate();
    const MusicPlaylistTrackAllNewQuery(
      cloudListId: 1,
      page: 1,
      pageSize: 300,
    ).validate();
  });
}
