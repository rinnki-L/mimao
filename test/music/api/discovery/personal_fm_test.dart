/// 私人 FM 测试：require_account / body 键序与 md5 key 黄金向量 / 可选键
/// filter / FM 专属覆盖（mixsongid、作者回退、封面回退、专辑名回退、
/// relate_goods 资源）+ provider_extension 键丢弃语义 + 边界。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/personal_fm.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 最小可信 FM wire：单曲（Song 协议字段 + FM 专属字段 + 供应商扩展）。
String fmWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'song_list': <Object?>[
      <String, Object?>{
        'album_audio_id': '111',
        'hash': 'HASHFM',
        'songname': 'FM歌',
        'time_length': 100,
        'sizable_cover': '',
        'privilege': 8,
        'singerinfo': <Object?>[],
        'songid': 55,
        'author_name': '兜底',
        'cur_mark': 'entry-mark',
        'rec_song_info': <String, Object?>{
          'rec_desc': '主文案',
          'rec_desc2': '副文案',
          'similar_desc': '相似',
          'alg_path': 'alg',
          'cur_mark': 'rec-mark',
          'rec_custom': 'keep-rec',
        },
        'relate_goods': <Object?>[
          <String, Object?>{
            'quality': '128',
            'hash': 'GH',
            'albumname': 'GD专辑',
            'privilege': 8,
            'pay_type': 0,
            'fail_process': 1,
            'status': 2,
            'info': <String, Object?>{
              'filesize': 10,
              'duration': 999,
              'bitrate': 128,
              'extname': 'mp3',
            },
          },
        ],
        'climax_start_time': '5000',
        'climax_end_time': 20000,
        'climax_timelength': 15000,
        'trans_param': <String, Object?>{
          'union_cover': 'http://u/{size}/x.png',
          'cid': 'keep-cid',
        },
        'tracker_info': <String, Object?>{'auth': 'EPHEMERAL', 'extra': 'keep'},
        'rec_extra': 'keep-me',
      },
    ],
    'cur_mark': 'batch-mark',
    'other_top': 'top',
  },
});

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity account;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    account = accountIdentity();
    session = fakeMusicSession(client, account);
  });

  test('请求装配：POST/x-router/请求体键序与固定协议值/md5 key 黄金向量', () async {
    adapter.bytes = jsonBytes(fmWire());
    final result = await fetchPersonalFm(
      session,
      const MusicPersonalFmQuery(),
      timeMs: 1700000000000,
    );
    expect(result.songs, hasLength(1));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v2/personal_recommend');
    expect(request.headers['x-router'], 'persnfm.service.kugou.com');

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    // serde_json BTreeMap：键序按字典序（签名覆盖请求体字节）。
    expect(body.keys.toList(), <String>[
      'action',
      'appid',
      'area_code',
      'callerid',
      'clienttime',
      'clientver',
      'fakem',
      'is_overplay',
      'key',
      'kguid',
      'm_type',
      'mid',
      'mode',
      'platform',
      'recommend_source_locked',
      'remain_songcnt',
      'song_pool_id',
      'token',
      'userid',
    ]);
    expect(body['action'], 'play');
    expect(body['appid'], 3116);
    expect(body['area_code'], 1);
    expect(body['callerid'], 0);
    expect(body['clienttime'], 1700000000000);
    expect(body['clientver'], 11440);
    expect(body['fakem'], 'ca981cfc583a4c37f28d2d49000013c16a0a');
    expect(body['is_overplay'], 0);
    expect(body['key'], 'd0ea4884a9807886a7c7e582cda713fa');
    expect(body['kguid'], 12345);
    expect(body['m_type'], 1);
    expect(body['mid'], 'mid-1');
    expect(body['mode'], 'normal');
    expect(body['platform'], 'ios');
    expect(body['recommend_source_locked'], 0);
    expect(body['remain_songcnt'], 0);
    expect(body['song_pool_id'], 0);
    expect(body['token'], 'token-abc');
    expect(body['userid'], 12345);
    expect(body.containsKey('hash'), isFalse);
    expect(body.containsKey('cur_mark'), isFalse);
    expect(body.containsKey('songid'), isFalse);
    expect(body.containsKey('playtime'), isFalse);
  });

  test('可选键：非空/非零才带；模式与动作 snake_case；is_overplay 0/1', () async {
    adapter.bytes = jsonBytes(fmWire());
    await fetchPersonalFm(
      session,
      const MusicPersonalFmQuery(
        mode: MusicPersonalFmMode.peak,
        action: MusicPersonalFmAction.changeSongPool,
        songPoolId: 2,
        remainSongcnt: 5,
        isOverplay: true,
        hash: 'H',
        songId: 7,
        playtime: 3,
        curMark: 'M',
      ),
      timeMs: 1700000000000,
    );
    final body =
        jsonDecode(adapter.requests.single.bodyText) as Map<String, Object?>;
    expect(body['mode'], 'peak');
    expect(body['action'], 'change_song_pool');
    expect(body['song_pool_id'], 2);
    expect(body['remain_songcnt'], 5);
    expect(body['is_overplay'], 1);
    expect(body['hash'], 'H');
    expect(body['songid'], 7);
    expect(body['playtime'], 3);
    expect(body['cur_mark'], 'M');

    // songid/playtime 为 0 时按 filter 语义省略。
    await fetchPersonalFm(
      session,
      const MusicPersonalFmQuery(songId: 0, playtime: 0),
      timeMs: 1700000000000,
    );
    final zero =
        jsonDecode(adapter.requests[1].bodyText) as Map<String, Object?>;
    expect(zero.containsKey('songid'), isFalse);
    expect(zero.containsKey('playtime'), isFalse);
  });

  test('require_account：匿名身份 → authentication，且不发请求', () async {
    final anonymous = fakeMusicSession(client, anonymousIdentity());
    await expectLater(
      fetchPersonalFm(anonymous, const MusicPersonalFmQuery()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'authentication' &&
              e.code == null,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('input：song_pool_id > 2 → input（账号校验之后），且不发请求', () async {
    await expectLater(
      fetchPersonalFm(session, const MusicPersonalFmQuery(songPoolId: 3)),
      throwsA(predicate((Object e) => '$e'.contains('input'))),
    );
    expect(adapter.requests, isEmpty);
  });

  test('解码：FM 专属覆盖（作者回退/封面回退/专辑名回退/商品资源/高潮/文案/批标记）', () async {
    adapter.bytes = jsonBytes(fmWire());
    final result = await fetchPersonalFm(
      session,
      const MusicPersonalFmQuery(),
      timeMs: 1700000000000,
    );

    expect(result.batchMark, 'batch-mark');
    expect(result.providerExtension, <String, Object?>{'other_top': 'top'});

    final fm = result.songs.single;
    final song = fm.song.song;
    expect(song.id, '111', reason: 'mixsongid 缺省 → Song 协议的 album_audio_id');
    expect(song.hash, 'HASHFM');
    expect(song.title, 'FM歌');
    expect(
      song.coverUrl,
      'http://u/240/x.png',
      reason: 'sizable_cover 空 → rights.cover_url',
    );
    expect(song.albumTitle, 'GD专辑', reason: '专辑名空 → relate_goods 首条 albumname');
    expect(song.artistText, '兜底', reason: 'singerinfo 空 → author_name 回退');
    expect(fm.song.metadata.artists.single.name, '兜底');

    final resources = fm.song.metadata.resources;
    // Song 协议六档（无 ogg）+ relate_goods 一条。
    expect(resources.map((r) => r.quality).toList(), <String>[
      '128',
      '192',
      '320',
      'flac',
      'ape',
      'other',
      '128',
    ]);
    final good = resources.last;
    expect(good.hash, 'GH');
    expect(good.sizeBytes, 10);
    expect(good.durationMs, 999, reason: 'good.info.duration 不乘 1000（上游一致）');
    expect(good.bitRateBps, 128000);
    expect(good.extension, 'mp3');
    expect(good.privilege, 8);
    expect(good.paymentType, 0);
    expect(good.failureCode, 1);
    expect(good.downloadStatus, 2, reason: 'good.status → download_status');

    expect(fm.song.metadata.relatedGoodsExtension, hasLength(1));
    expect(fm.song.metadata.recommendation.headline, '主文案');
    expect(fm.song.metadata.recommendation.detail, '副文案');

    final fmMeta = fm.personalFm;
    expect(fmMeta.mark, 'rec-mark', reason: 'rec.cur_mark 非空优先');
    expect(fmMeta.similarity, '相似');
    expect(fmMeta.algorithm, 'alg');
    expect(fmMeta.climaxStartMs, 5000, reason: '十进制串宽容');
    expect(fmMeta.climaxEndMs, 20000);
    expect(fmMeta.climaxDurationMs, 15000);
  });

  test(
    'provider_extension：tracker_info 只丢 auth；trans_param/rec_song_info 留余键；平铺键丢弃',
    () async {
      adapter.bytes = jsonBytes(fmWire());
      final result = await fetchPersonalFm(
        session,
        const MusicPersonalFmQuery(),
        timeMs: 1700000000000,
      );
      final extension =
          result.songs.single.song.metadata.providerExtension!
              as Map<String, Object?>;

      final tracker = extension['tracker_info']! as Map<String, Object?>;
      expect(tracker, <String, Object?>{'extra': 'keep'});
      final trans = extension['trans_param']! as Map<String, Object?>;
      expect(trans, <String, Object?>{'cid': 'keep-cid'});
      final rec = extension['rec_song_info']! as Map<String, Object?>;
      expect(rec, <String, Object?>{'rec_custom': 'keep-rec'});
      expect(extension['rec_extra'], 'keep-me');
      expect(extension.containsKey('album_audio_id'), isFalse);
      expect(extension.containsKey('relate_goods'), isFalse);
      expect(extension.containsKey('cur_mark'), isFalse);
      expect(extension.containsKey('climax_start_time'), isFalse);
      expect(extension.containsKey('author_name'), isFalse);
    },
  );

  test('mark 回退：rec.cur_mark 空用条目 cur_mark；mixsongid 覆盖 id', () async {
    final wire = jsonEncode(<String, Object?>{
      'status': 1,
      'error_code': 0,
      'data': <String, Object?>{
        'song_list': <Object?>[
          <String, Object?>{
            'mixsongid': '222',
            'album_audio_id': '111',
            'hash': '',
            'cur_mark': 'entry-only',
            'rec_song_info': <String, Object?>{},
          },
        ],
      },
    });
    adapter.bytes = jsonBytes(wire);
    final result = await fetchPersonalFm(
      session,
      const MusicPersonalFmQuery(),
      timeMs: 1700000000000,
    );
    final fm = result.songs.single;
    expect(fm.song.song.id, '222', reason: 'mixsongid 非空覆盖 Song 协议 id');
    expect(fm.personalFm.mark, 'entry-only', reason: 'rec.cur_mark 空 → 条目级');
    expect(fm.personalFm.similarity, '');
    expect(fm.personalFm.algorithm, '');
  });

  test(
    '边界：error_code 缺省 → 成功；data 非 object → 空数据；song_list/relate_goods 非法元素 → decode',
    () async {
      adapter.bytes = jsonBytes('{"status":1}');
      final noError = await fetchPersonalFm(
        session,
        const MusicPersonalFmQuery(),
        timeMs: 1700000000000,
      );
      expect(noError.songs, isEmpty);
      expect(noError.batchMark, '');

      adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":"str"}');
      final badData = await fetchPersonalFm(
        session,
        const MusicPersonalFmQuery(),
        timeMs: 1700000000000,
      );
      expect(badData.songs, isEmpty);

      adapter.bytes = jsonBytes(
        '{"status":1,"error_code":0,"data":{"song_list":[5]}}',
      );
      await expectLater(
        fetchPersonalFm(
          session,
          const MusicPersonalFmQuery(),
          timeMs: 1700000000000,
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      adapter.bytes = jsonBytes(
        '{"status":1,"error_code":0,"data":{"song_list":[{"relate_goods":[5]}]}}',
      );
      await expectLater(
        fetchPersonalFm(
          session,
          const MusicPersonalFmQuery(),
          timeMs: 1700000000000,
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      // 空对象 relate_goods → list 语义空表（资源仍走六档）。
      adapter.bytes = jsonBytes(
        '{"status":1,"error_code":0,"data":{"song_list":[{"album_audio_id":"1","relate_goods":{}}]}}',
      );
      final emptyGoods = await fetchPersonalFm(
        session,
        const MusicPersonalFmQuery(),
        timeMs: 1700000000000,
      );
      expect(emptyGoods.songs.single.song.metadata.resources, hasLength(6));
      expect(emptyGoods.songs.single.song.song.albumTitle, isNull);
    },
  );

  test('登录过期：error_code=20018 → authentication；status=0 → business', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":20018}');
    await expectLater(
      fetchPersonalFm(session, const MusicPersonalFmQuery()),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );

    adapter.bytes = jsonBytes('{"status":0,"error_code":35}');
    await expectLater(
      fetchPersonalFm(session, const MusicPersonalFmQuery()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 35,
        ),
      ),
    );
  });
}
