/// 首页发现推荐测试：请求装配（POST/参数/请求体键序）+ song 条目嵌套解码
/// + unmapped 保留 + 信封错误分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/home_discover.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 最小可信 wire：1 个 song 条目（完整 song_info/trans_param）+ 3 个
/// unmapped 形态（无 song_info 的 song、非 song 类型、非 object 条目）。
String homeWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'errcode': 0,
  'data': <String, Object?>{
    'items': <Object?>[
      <String, Object?>{
        'item_type': 'song',
        'item_id': 'i1',
        'alg_path': 'alg1',
        'extra': <String, Object?>{'start_time': '120'},
        'song_info': <String, Object?>{
          'mixsongid': '999',
          'album_audio_id': 888,
          'audio_id': 777,
          'ori_album_id': 42,
          'album_name': '专辑A',
          'album_cover': 'http://imge.kugou.com/{size}/a.png',
          'songname': '歌名',
          'author_name': '歌手',
          'privilege': 8,
          'pay_type': 0,
          'fail_process': 1,
          'has_obbligato': 1,
          'hash_128': 'H128',
          'hash_320': 'H320',
          'hash_flac': 'HFLAC',
          'filesize_128': 1000,
          'filesize_320': 2000,
          'filesize_flac': 3000,
          'timelength_128': 180000,
          'timelength_320': 180000,
          'timelength_flac': 180000,
          'trans_param': <String, Object?>{
            'cpy_attr0': 123,
            'cpy_grade': 2,
            'union_cover': 'http://union/{size}/c.png',
            'ogg_128_hash': 'OGG128',
            'ogg_128_filesize': 500,
            'qualitymap': <String, Object?>{
              'attr0': '281629629091840',
              'bits': '128',
            },
            'classmap': <String, Object?>{'known': '5', 'bad': '1.25'},
            'language': '普通话',
            'cid': 'keep-me',
          },
          'cid': 'cid-keep',
        },
      },
      <String, Object?>{'item_type': 'song', 'item_id': 'i2'},
      <String, Object?>{'item_type': 'playlist', 'id': 'p1'},
      12345,
    ],
  },
});

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

  test('请求装配：POST/无 x-router/参数与 clientver=20809/请求体 BTreeMap 键序', () async {
    adapter.bytes = jsonBytes(homeWire());
    final result = await fetchHomeDiscover(session, const HomeDiscoverQuery());
    expect(result.items, hasLength(1));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path,
      'https://gateway.kugou.com/homediscoverrec/v1/client/home_discover_rec',
    );
    expect(request.headers['x-router'], isNull);
    final query = request.query;
    expect(query['module_key'], 'home_discover_rec');
    expect(query['module_id'], '1');
    expect(query['area_code'], '1');
    expect(query['platform'], 'android');
    expect(query['userid'], '0');
    expect(query['clientver'], '20809');

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    // serde_json BTreeMap：键序按字典序（签名覆盖请求体字节）。
    expect(body.keys.toList(), <String>[
      'go_ky_extra',
      'pagesize',
      'recall_type',
      'support',
      'today_play_num',
      'userid',
    ]);
    expect(body['pagesize'], 4);
    expect(body['recall_type'], 'song');
    expect(body['support'], 'only_song');
    expect(body['today_play_num'], 0);
    expect(body['userid'], 0);
    expect(body['go_ky_extra'], <Object?>[
      <String, String>{'key': 'network', 'val': '2'},
      <String, String>{'key': 'play_mode', 'val': '2'},
      <String, String>{'key': 'no_mv_ret', 'val': '1'},
    ]);
  });

  test('page_size=0 选默认一批四；显式值透传', () async {
    adapter.bytes = jsonBytes(homeWire());
    await fetchHomeDiscover(session, const HomeDiscoverQuery(pageSize: 0));
    expect(
      (jsonDecode(adapter.requests[0].bodyText)
          as Map<String, Object?>)['pagesize'],
      4,
    );
    await fetchHomeDiscover(session, const HomeDiscoverQuery(pageSize: 8));
    expect(
      (jsonDecode(adapter.requests[1].bodyText)
          as Map<String, Object?>)['pagesize'],
      8,
    );
  });

  test('解码：song 条目嵌套模型/trans_param 版权事实/ogg 资源/开始时刻', () async {
    adapter.bytes = jsonBytes(homeWire());
    final result = await fetchHomeDiscover(session, const HomeDiscoverQuery());
    expect(result.unmappedItems, hasLength(3));

    final item = result.items.single;
    expect(item.itemId, 'i1');
    expect(item.algPath, 'alg1');
    expect(item.startTime, '120');

    final song = item.song.song;
    expect(song.id, '999', reason: 'mixsongid 优先于 album_audio_id');
    expect(song.hash, 'H128');
    expect(song.title, '歌名');
    expect(song.artistText, '歌手');
    expect(song.albumId, '42', reason: 'ori_album_id 是本响应的专辑 id');
    expect(song.albumTitle, '专辑A');
    expect(song.durationMs, 180000, reason: 'timelength_128 原样毫秒');
    expect(song.coverUrl, 'http://imge.kugou.com/240/a.png');
    expect(song.privilege, 8);

    final metadata = item.song.metadata;
    expect(metadata.audioId, 777);
    expect(metadata.language, '普通话');
    expect(metadata.hasAccompaniment, isTrue, reason: 'has_obbligato=1');
    expect(metadata.accompanimentCode, 1);
    expect(metadata.paymentType, 0);
    expect(metadata.failureCode, 1);
    expect(metadata.originalTitle, isNull);
    expect(metadata.publishedAt, isNull);

    final rights = metadata.rights;
    expect(rights.copyrightAttributes, 123);
    expect(rights.copyrightGrade, 2);
    expect(rights.coverUrl, 'http://union/240/c.png');
    expect(rights.qualityMap?.attr0, 281629629091840);
    expect(rights.qualityMap?.bits, '128');
    expect(rights.classification, <String, int?>{'known': 5, 'bad': null});

    final qualities = metadata.resources.map((r) => r.quality).toList();
    expect(qualities, <String>['ogg_128', '128', '320', 'flac']);
    final ogg = metadata.resources.first;
    expect(ogg.hash, 'OGG128');
    expect(ogg.sizeBytes, 500);
    expect(ogg.extension, 'ogg');
    final standard = metadata.resources[1];
    expect(standard.hash, 'H128');
    expect(standard.sizeBytes, 1000);
    expect(standard.durationMs, 180000);
    expect(standard.extension, isNull);

    // provider_extension：song_info 平铺消费键已丢，cid 留在根与 trans_param 里。
    final extension = metadata.providerExtension! as Map<String, Object?>;
    expect(extension['cid'], 'cid-keep');
    expect(extension.containsKey('mixsongid'), isFalse);
    expect(extension.containsKey('hash_128'), isFalse);
    final trans = extension['trans_param']! as Map<String, Object?>;
    expect(trans['cid'], 'keep-me');
    expect(trans.containsKey('cpy_attr0'), isFalse);
    expect(trans.containsKey('qualitymap'), isFalse);
  });

  test(
    '回退链：mixsongid 缺省用 album_audio_id；hash_128 缺省用 hash_320；专辑名空 → null',
    () async {
      final wire = jsonEncode(<String, Object?>{
        'status': 1,
        'errcode': 0,
        'data': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'item_type': 'song',
              'song_info': <String, Object?>{
                'album_audio_id': 888,
                'hash_320': 'H320',
              },
            },
          ],
        },
      });
      adapter.bytes = jsonBytes(wire);
      final result = await fetchHomeDiscover(
        session,
        const HomeDiscoverQuery(),
      );
      final song = result.items.single.song.song;
      expect(song.id, '888');
      expect(song.hash, 'H320');
      expect(song.albumTitle, isNull);
      expect(song.albumId, '');
    },
  );

  test('items 空 object/缺 data → 空结果；items 非数组 → decode', () async {
    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{"items":{}}}');
    final empty = await fetchHomeDiscover(session, const HomeDiscoverQuery());
    expect(empty.items, isEmpty);
    expect(empty.unmappedItems, isEmpty);

    adapter.bytes = jsonBytes('{"status":1,"errcode":0}');
    final noData = await fetchHomeDiscover(session, const HomeDiscoverQuery());
    expect(noData.items, isEmpty);

    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{"items":5}}');
    await expectLater(
      fetchHomeDiscover(session, const HomeDiscoverQuery()),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test(
    'errcode 缺失 → decode；status=0 → business（errcode=20018 仍是 business）',
    () async {
      adapter.bytes = jsonBytes('{"status":1}');
      await expectLater(
        fetchHomeDiscover(session, const HomeDiscoverQuery()),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      adapter.bytes = jsonBytes('{"status":0,"errcode":31}');
      await expectLater(
        fetchHomeDiscover(session, const HomeDiscoverQuery()),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 31,
          ),
        ),
      );

      // 原始过期扫描只认 error_code 键；errcode 键上的 20018 走 success() → business。
      adapter.bytes = jsonBytes('{"status":1,"errcode":20018}');
      await expectLater(
        fetchHomeDiscover(session, const HomeDiscoverQuery()),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'business' &&
                e.code == 20018,
          ),
        ),
      );
    },
  );

  test('登录过期：error_code=20018 或 msg 含「登录已过期」→ authentication', () async {
    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"error_code":20018}');
    await expectLater(
      fetchHomeDiscover(session, const HomeDiscoverQuery()),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"error_code":999,"msg":"用户登录已过期"}',
    );
    await expectLater(
      fetchHomeDiscover(session, const HomeDiscoverQuery()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'authentication' &&
              e.code == 999,
        ),
      ),
    );
  });

  test('input：page_size 为负（Rust u32 不可表示）→ input，且不发请求', () async {
    await expectLater(
      fetchHomeDiscover(session, const HomeDiscoverQuery(pageSize: -1)),
      throwsA(predicate((Object e) => '$e'.contains('input'))),
    );
    expect(adapter.requests, isEmpty);
  });
}
