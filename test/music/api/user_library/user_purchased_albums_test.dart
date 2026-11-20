/// 已购专辑端点测试：body 键序（BTreeMap）、分页边界、id>0 过滤、歌手/封面
/// 投影、未知键进 provider_extension、list 宽容与业务/解码分支。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_purchased_albums.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

Map<String, Object?> albumRow({
  Object? albumId = 9007199254740995,
  String albumName = '已购专辑',
  String singerName = '已购歌手',
  String cover = 'http://imge.kugou.com/stdmusic/{size}/2021001/a.png',
  int? isPublish = 1,
}) => <String, Object?>{
  'album_id': albumId,
  'album_name': albumName,
  'singer_name': singerName,
  'cover': cover,
  'is_publish': isPublish,
  'sku_price': '12.0',
};

String albumsWire(List<Object?> goods, {int? total = 1}) =>
    jsonEncode(<String, Object?>{
      'status': 1,
      'error_code': 0,
      'data': <String, Object?>{'total': total, 'goods': goods},
    });

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = accountIdentity();
  });

  test('请求装配：body 键序按 BTreeMap，clientver 为字符串、deleted=0', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(albumsWire([albumRow()])));
    const query = MusicUserPagedQuery(page: 3, pageSize: 20);
    final page = await fetchUserPurchasedAlbums(
      sessionFor(client, identity),
      query,
    );
    expect(page.page, 3);
    expect(page.pageSize, 20);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/openapi/v1/copyright/get_album_goods'));
    expect(request.headers['x-router'], isNull);
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'appid',
      'clientver',
      'deleted',
      'page',
      'pagesize',
      'token',
      'userid',
    ]);
    expect(body['appid'], 3116);
    expect(body['clientver'], '11440');
    expect(body['deleted'], 0);
    expect(body['page'], 3);
    expect(body['pagesize'], 20);
    expect(body['token'], identity.token);
    expect(body['userid'], identity.userId);
    expectValidAndroidSignature(request);
  });

  test('分页校验：page=0 / pageSize 越界 → input；1..=100 边界放行', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(albumsWire([albumRow()])));
    for (final (page, pageSize) in <(int, int)>[(0, 20), (1, 0), (1, 101)]) {
      await expectLater(
        fetchUserPurchasedAlbums(
          sessionFor(client, identity),
          MusicUserPagedQuery(page: page, pageSize: pageSize),
        ),
        throwsKugou('input'),
      );
    }
    expect(adapter.requests, isEmpty);
    for (final pageSize in const [1, 100]) {
      adapter.bytes = Uint8List.fromList(utf8.encode(albumsWire([albumRow()])));
      await fetchUserPurchasedAlbums(
        sessionFor(client, identity),
        MusicUserPagedQuery(page: 1, pageSize: pageSize),
      );
    }
    expect(adapter.requests, hasLength(2));
  });

  test('匿名身份 → authentication，不发出请求', () async {
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    adapter.bytes = Uint8List.fromList(utf8.encode(albumsWire([albumRow()])));
    await expectLater(
      fetchUserPurchasedAlbums(
        sessionFor(client, anonymous),
        const MusicUserPagedQuery(page: 1, pageSize: 20),
      ),
      throwsKugou('authentication'),
    );
    expect(adapter.requests, isEmpty);
  });

  test('解码：id>0 过滤、空歌手名 → 空表、封面 {size}→400、未知键保留', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        albumsWire([
          albumRow(),
          albumRow(
            albumId: 0,
            singerName: '',
            cover: 'http://imge.kugou.com/400/a.png',
            isPublish: null,
          ),
        ]),
      ),
    );
    final page = await fetchUserPurchasedAlbums(
      sessionFor(client, identity),
      const MusicUserPagedQuery(page: 1, pageSize: 20),
    );
    expect(page.total, 1);
    expect(page.items, hasLength(2));

    final first = page.items[0];
    expect(first.album.id, 9007199254740995);
    expect(first.album.title, '已购专辑');
    expect(first.album.artists.single.name, '已购歌手');
    expect(first.album.artists.single.id, isNull);
    expect(
      first.album.coverUrl,
      'http://imge.kugou.com/stdmusic/400/2021001/a.png',
    );
    expect(first.album.songCount, isNull);
    expect(first.album.publishedAt, '');
    expect(first.publicationCode, 1);
    expect(first.providerExtension, <String, Object?>{'sku_price': '12.0'});

    // album_id=0 → null（filter >0）；歌手空串 → 无歌手；is_publish 缺省 → null。
    final second = page.items[1];
    expect(second.album.id, isNull);
    expect(second.album.artists, isEmpty);
    expect(second.album.coverUrl, 'http://imge.kugou.com/400/a.png');
    expect(second.publicationCode, isNull);
  });

  test('goods 空对象/null → 空表；total 缺省 → null', () async {
    for (final goods in <Object?>[<String, Object?>{}, null]) {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 1,
            'error_code': 0,
            'data': <String, Object?>{'goods': goods},
          }),
        ),
      );
      final page = await fetchUserPurchasedAlbums(
        sessionFor(client, identity),
        const MusicUserPagedQuery(page: 1, pageSize: 20),
      );
      expect(page.items, isEmpty);
      expect(page.total, isNull);
    }
  });

  test('解码失败：data null / goods 非法 / 行为 null', () async {
    for (final data in <Object?>[
      null,
      <String, Object?>{'goods': 'invalid'},
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
        fetchUserPurchasedAlbums(
          sessionFor(client, identity),
          const MusicUserPagedQuery(page: 1, pageSize: 20),
        ),
        throwsKugou('decode'),
      );
    }
  });

  test('业务失败：20017 → authentication（优先于坏 data），30001 → business', () async {
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
        fetchUserPurchasedAlbums(
          sessionFor(client, identity),
          const MusicUserPagedQuery(page: 1, pageSize: 20),
        ),
        throwsKugou(kind, code: code),
      );
    }
  });
}
