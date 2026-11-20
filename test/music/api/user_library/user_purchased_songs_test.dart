/// 已购单曲端点测试：body 键序与附加字段、audio_info/trans_param 的资源折叠
/// （ogg + 四档 hash、bitrate 只修饰 128）、hash 择优、权限链、
/// provider_extension 遗留键、宽容与业务分支。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_purchased_songs.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

String songsWire(List<Object?> goods, {int? total = 1}) =>
    jsonEncode(<String, Object?>{
      'status': 1,
      'error_code': 0,
      'data': <String, Object?>{'total': total, 'goods': goods},
    });

/// 全量行：四档 hash、trans_param 携带消费键与遗留键、未知键三层齐备。
Map<String, Object?> fullRow() => <String, Object?>{
  'album_audio_id': 9007199254741001,
  'album_id': 9007199254741002,
  'hash': 'rowhash0000000000000000000000000',
  'songname': '已购歌曲',
  'album_cover': 'http://imge.kugou.com/stdmusic/{size}/2021001/a.png',
  'author_name': '已购歌手',
  'author_avatar': 'http://imge.kugou.com/artistpic/{size}/a.png',
  'audio_info': <String, Object?>{
    'hash_128': 'h128000000000000000000000000000',
    'hash_320': 'h320000000000000000000000000000',
    'hash_flac': 'hflac00000000000000000000000000',
    'hash_high': 'hhigh00000000000000000000000000',
    'filesize_128': 100,
    'filesize_320': 200,
    'filesize_flac': 300,
    'filesize_high': 400,
    'privilege_128': 8,
    'privilege_320': 8,
    'privilege_flac': 8,
    'privilege_high': 16,
    'name': 'source.mp3',
    'album_name': '已购专辑',
    'album_id': 9007199254741003,
    'duration': 240000,
    'bitrate': 128,
    'pay_type': 1,
    'old_cpy': 0,
    'fail_process': 0,
    'trans_param': <String, Object?>{
      'language': '粤语',
      'cpy_attr0': 1,
      'is_original': 2,
      'union_cover': 'http://img.kugou.com/{size}/c.png',
      'hash_offset': <String, Object?>{'start_byte': 0, 'end_byte': 1024},
      'qualitymap': <String, Object?>{'attr0': 7, 'bits': 'abc'},
      'classmap': <String, Object?>{'a': '3', 'b': null, 'c': 'bad'},
      'voice_ad': <String, Object?>{
        'start_ms': 5000,
        'filesize': 20000,
        'hash': 'vh0000000000000000000000000000',
      },
      'ogg_128_hash': 'ogg1280000000000000000000000000',
      'ogg_128_filesize': 111,
      'ogg_320_hash': 'ogg3200000000000000000000000000',
      'ogg_320_filesize': 222,
      'cid': 99,
    },
  },
  'sku_extra': 'keep-me',
};

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = accountIdentity();
  });

  test('请求装配：body 键序按 BTreeMap，need_audio_info=1、area_code="1"', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(songsWire([fullRow()])));
    const query = MusicUserPagedQuery(page: 1, pageSize: 20);
    final page = await fetchUserPurchasedSongs(
      sessionFor(client, identity),
      query,
    );
    expect(page.items, hasLength(1));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/openapi/copyright/v1/audio/get_goods'));
    expect(request.headers['x-router'], isNull);
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'appid',
      'area_code',
      'clientver',
      'deleted',
      'need_audio_info',
      'page',
      'pagesize',
      'token',
      'userid',
    ]);
    expect(body['appid'], 3116);
    expect(body['area_code'], '1');
    expect(body['clientver'], '11440');
    expect(body['deleted'], 0);
    expect(body['need_audio_info'], 1);
    expect(body['page'], 1);
    expect(body['pagesize'], 20);
    expectValidAndroidSignature(request);
  });

  test('全量行解码：摘要、资源折叠顺序、版权事实、语言与遗留键', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(songsWire([fullRow()])));
    final page = await fetchUserPurchasedSongs(
      sessionFor(client, identity),
      const MusicUserPagedQuery(page: 1, pageSize: 20),
    );
    final song = page.items.single.song;
    expect(song.id, '9007199254741001');
    // 择优 hash：high > flac > 320 > 128 > 行顶。
    expect(song.hash, 'hhigh00000000000000000000000000');
    expect(song.title, '已购歌曲');
    expect(song.artists.single.name, '已购歌手');
    expect(song.artists.single.id, isNull);
    // audio.album_id > 0 优先于行顶。
    expect(song.albumId, '9007199254741003');
    expect(song.albumTitle, '已购专辑');
    expect(song.durationMs, 240000);
    expect(song.coverUrl, 'http://imge.kugou.com/stdmusic/400/2021001/a.png');
    expect(song.privilege, 16);

    final catalog = page.items.single.metadata;
    // 资源顺序：ogg_128、ogg_320（trans）在前，四档在后。
    expect(catalog.catalog.resources.map((r) => r.quality).toList(), <String>[
      'ogg_128',
      'ogg_320',
      '128',
      '320',
      'flac',
      'high',
    ]);
    final ogg = catalog.catalog.resources[0];
    expect(ogg.hash, 'ogg1280000000000000000000000000');
    expect(ogg.sizeBytes, 111);
    expect(ogg.extension, 'ogg');
    expect(ogg.bitRateBps, isNull);
    final standard = catalog.catalog.resources[2];
    expect(standard.hash, 'h128000000000000000000000000000');
    expect(standard.sizeBytes, 100);
    // bitrate 只修饰 128 档（×1000）。
    expect(standard.bitRateBps, 128000);
    expect(standard.privilege, 8);
    // 每档共享 pay_type/fail_process 事实。
    expect(standard.payType, 1);
    expect(standard.failureCode, 0);
    expect(catalog.catalog.resources[3].bitRateBps, isNull);

    expect(catalog.catalog.paymentType, 1);
    expect(catalog.catalog.failureCode, 0);
    expect(catalog.catalog.oldCopyrightCode, 0);
    // 目录事实的原创码来自 trans_param.is_original。
    expect(catalog.catalog.originalityCode, 2);
    final rights = catalog.catalog.rights!;
    expect(rights.originalityCode, 2);
    expect(rights.copyrightAttributes, 1);
    expect(rights.qualityMap!.attr0, 7);
    expect(rights.qualityMap!.bits, 'abc');
    // classmap：可读条目解析、不可读条目保留 null。
    expect(rights.classification, <String, int?>{'a': 3, 'b': null, 'c': null});
    expect(rights.preview!.startByte, 0);
    expect(rights.preview!.endByte, 1024);
    expect(rights.coverUrl, 'http://img.kugou.com/240/c.png');
    expect(rights.voiceAd!.startMs, 5000);
    expect(rights.voiceAd!.sizeBytes, 20000);

    expect(catalog.sourceFileName, 'source.mp3');
    expect(catalog.language, '粤语');
    expect(catalog.artists.single.name, '已购歌手');
    expect(
      catalog.artists.single.avatarUrl,
      'http://imge.kugou.com/artistpic/240/a.png',
    );

    final extension = catalog.providerExtension! as Map<String, Object?>;
    expect(extension.keys.toList(), <String>[
      'audio',
      'listed_album_id',
      'listed_hash',
      'purchase',
      'trans_param',
    ]);
    expect(extension['listed_album_id'], 9007199254741002);
    expect(extension['listed_hash'], 'rowhash0000000000000000000000000');
    expect(extension['purchase'], <String, Object?>{'sku_extra': 'keep-me'});
    expect(extension['audio'], <String, Object?>{});
    // trans_param 只留未消费键（cid）。
    expect(extension['trans_param'], <String, Object?>{'cid': 99});
  });

  test('空 audio_info：hash 回退行顶、无资源、album_id 取行顶、语言未知', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        songsWire([
          <String, Object?>{
            'album_audio_id': 7001,
            'album_id': 7002,
            'hash': 'rowhash0000000000000000000000000',
            'songname': '裸行',
            'album_cover': '',
            'author_name': '',
          },
        ]),
      ),
    );
    final page = await fetchUserPurchasedSongs(
      sessionFor(client, identity),
      const MusicUserPagedQuery(page: 1, pageSize: 20),
    );
    final item = page.items.single;
    expect(item.song.id, '7001');
    expect(item.song.hash, 'rowhash0000000000000000000000000');
    expect(item.song.albumId, '7002');
    expect(item.song.albumTitle, isNull);
    expect(item.song.privilege, isNull);
    expect(item.song.artists, isEmpty);
    expect(item.metadata.catalog.resources, isEmpty);
    // 空 trans_param 也产出全空 rights（Some(空事实)，不是 None）。
    expect(item.metadata.catalog.rights, isNotNull);
    expect(item.metadata.language, isNull);
    expect(item.metadata.artists, isEmpty);
    final extension = item.metadata.providerExtension! as Map<String, Object?>;
    expect(extension['purchase'], <String, Object?>{});
    expect(extension['listed_album_id'], 7002);
  });

  test('全空音质档跳过；仅 320 时择优取 320；audio_info 非 object 容忍', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        songsWire([
          <String, Object?>{
            'album_audio_id': 7001,
            'hash': 'rowhash0000000000000000000000000',
            'songname': '裸行',
            'album_cover': '',
            'author_name': '',
            'audio_info': <String, Object?>{
              'hash_320': 'h320000000000000000000000000000',
            },
          },
          <String, Object?>{
            'album_audio_id': 7002,
            'hash': 'rowhash2222222222222222222222222',
            'songname': '坏audio',
            'album_cover': '',
            'author_name': '',
            'audio_info': 'garbage',
          },
        ]),
      ),
    );
    final page = await fetchUserPurchasedSongs(
      sessionFor(client, identity),
      const MusicUserPagedQuery(page: 1, pageSize: 20),
    );
    expect(page.items, hasLength(2));
    final first = page.items[0];
    expect(
      first.metadata.catalog.resources.map((r) => r.quality).toList(),
      <String>['320'],
    );
    expect(first.song.hash, 'h320000000000000000000000000000');
    // audio_info 非 object → 全空默认（不 decode 失败）。
    final second = page.items[1];
    expect(second.song.hash, 'rowhash2222222222222222222222222');
    expect(second.metadata.catalog.resources, isEmpty);
  });

  test('分页校验文案为已购单曲；匿名 → authentication', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(songsWire([fullRow()])));
    await expectLater(
      fetchUserPurchasedSongs(
        sessionFor(client, identity),
        const MusicUserPagedQuery(page: 0, pageSize: 20),
      ),
      throwsKugou('input'),
    );
    await expectLater(
      fetchUserPurchasedSongs(
        sessionFor(client, identity),
        const MusicUserPagedQuery(page: 1, pageSize: 101),
      ),
      throwsKugou('input'),
    );
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    await expectLater(
      fetchUserPurchasedSongs(
        sessionFor(client, anonymous),
        const MusicUserPagedQuery(page: 1, pageSize: 20),
      ),
      throwsKugou('authentication'),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    '业务与解码分支：20017 → authentication、30001 → business、坏 data → decode',
    () async {
      for (final (code, kind) in <(int, String)>[
        (20017, 'authentication'),
        (30001, 'business'),
      ]) {
        adapter.bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'status': 0,
              'error_code': code,
              'data': <String, Object?>{'goods': 'invalid'},
            }),
          ),
        );
        await expectLater(
          fetchUserPurchasedSongs(
            sessionFor(client, identity),
            const MusicUserPagedQuery(page: 1, pageSize: 20),
          ),
          throwsKugou(kind, code: code),
        );
      }
      for (final data in <Object?>[
        null,
        <String, Object?>{
          'goods': <Object?>[null],
        },
      ]) {
        adapter.bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'status': 1,
              'error_code': 0,
              'data': data,
            }),
          ),
        );
        await expectLater(
          fetchUserPurchasedSongs(
            sessionFor(client, identity),
            const MusicUserPagedQuery(page: 1, pageSize: 20),
          ),
          throwsKugou('decode'),
        );
      }
    },
  );
}
