/// 歌手专辑端点测试：请求装配 + 根平铺信封解码 + 作者回退 + 兜底/校验分支。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/artist_albums.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// albums.rs `Wire`：total/data 是信封根上的平铺字段。
String albumsWire({Object? total = 42, Object? data}) =>
    jsonEncode(<String, Object?>{
      'status': 1,
      'error_code': 0,
      if (total != null) 'total': total,
      'data':
          data ??
          <Object?>[
            <String, Object?>{
              'album_id': 7,
              'album_name': '叶惠美',
              'author_name': '周杰伦',
              'authors': <Object?>[
                <String, Object?>{'author_id': 123, 'author_name': '周杰伦'},
                <String, Object?>{'author_id': 9, 'author_name': ''},
              ],
              'sizable_cover':
                  'http://imge.kugou.com/stdmusic/{size}/2003/cov.png',
              'publish_date': '2003-07-31',
            },
          ],
    });

void main() {
  late CaptureAdapter adapter;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    session = fakeMusicSession(artistTestClient(adapter), artistTestIdentity());
  });

  test('请求装配：POST /kmr/v1/author/albums + body 六键 + sort 映射', () async {
    adapter.bytes = jsonBytes(albumsWire());
    final page = await fetchArtistAlbums(
      session,
      const MusicArtistAlbumsQuery(id: 123),
    );
    expect(page.items, isNotEmpty);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path,
      startsWith('https://gateway.kugou.com/kmr/v1/author/albums'),
    );
    expect(request.headers['x-router'], 'openapi.kugou.com');
    expect(request.headers['kg-tid'], '36');
    final body = request.bodyText;
    expect(body, contains('"author_id":123'));
    expect(body, contains('"pagesize":30'));
    expect(body, contains('"page":1'));
    expect(body, contains('"sort":3'), reason: 'hot → 3');
    expect(body, contains('"category":1'));
    expect(body, contains('"area_code":"all"'));
  });

  test('sort=new → wire sort=1', () async {
    adapter.bytes = jsonBytes(albumsWire());
    await fetchArtistAlbums(
      session,
      const MusicArtistAlbumsQuery(id: 1, sort: 'new'),
    );
    expect(adapter.requests.single.bodyText, contains('"sort":1'));
  });

  test('解码：专辑字段/作者过滤与回退/封面 {size}→240/page 原样回填', () async {
    adapter.bytes = jsonBytes(albumsWire());
    final page = await fetchArtistAlbums(
      session,
      const MusicArtistAlbumsQuery(id: 123, page: 2, pageSize: 50),
    );

    expect(page.page, 2);
    expect(page.pageSize, 50);
    expect(page.total, 42);
    final album = page.items.single;
    expect(album.id, 7);
    expect(album.title, '叶惠美');
    expect(album.artists, hasLength(1), reason: '空名作者被过滤');
    expect(album.artists.single.id, 123);
    expect(album.artists.single.name, '周杰伦');
    expect(album.coverUrl, 'http://imge.kugou.com/stdmusic/240/2003/cov.png');
    expect(album.publishedAt, '2003-07-31');
    expect(album.songCount, isNull, reason: '上游不产出 song_count');
  });

  test('authors 全空（或缺省）时回退平铺 author_name（id=null）', () async {
    adapter.bytes = jsonBytes(
      albumsWire(
        data: <Object?>[
          <String, Object?>{
            'album_id': '8',
            'album_name': '依然范特西',
            'author_name': '周杰伦',
            'sizable_cover': '',
            'publish_date': '',
          },
        ],
      ),
    );
    final album = (await fetchArtistAlbums(
      session,
      const MusicArtistAlbumsQuery(id: 1),
    )).items.single;
    expect(album.id, 8, reason: '字符串型数字宽容');
    expect(album.artists.single.id, isNull);
    expect(album.artists.single.name, '周杰伦');
  });

  test('data 缺省 → 空页；data 空对象 {} 按 list 宽容 → 空页', () async {
    adapter.bytes = jsonBytes(albumsWire(data: <Object?>[]));
    var page = await fetchArtistAlbums(
      session,
      const MusicArtistAlbumsQuery(id: 1),
    );
    expect(page.items, isEmpty);
    expect(page.total, 42);

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"total":5,"data":{}}',
    );
    page = await fetchArtistAlbums(
      session,
      const MusicArtistAlbumsQuery(id: 1),
    );
    expect(page.items, isEmpty);
    expect(page.total, 5);
  });

  test('结构缺陷：data 非空 object → decode；authors 元素非 object → decode', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{"a":1}}');
    await expectLater(
      fetchArtistAlbums(session, const MusicArtistAlbumsQuery(id: 1)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":[{"authors":["文本"]}]}',
    );
    await expectLater(
      fetchArtistAlbums(session, const MusicArtistAlbumsQuery(id: 1)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('业务失败（status=0）→ business 带码', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":152,"data":[]}');
    await expectLater(
      fetchArtistAlbums(session, const MusicArtistAlbumsQuery(id: 1)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
    );
  });

  test(
    'decode_envelope 兜底：缺 status 但 error_code 非 0 → business；status=0 → business(0)',
    () async {
      adapter.bytes = jsonBytes('{"error_code":302}');
      await expectLater(
        fetchArtistAlbums(session, const MusicArtistAlbumsQuery(id: 1)),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 302,
          ),
        ),
      );

      adapter.bytes = jsonBytes('{"status":0}');
      await expectLater(
        fetchArtistAlbums(session, const MusicArtistAlbumsQuery(id: 1)),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 0,
          ),
        ),
      );
    },
  );

  test('登录过期码 20018 → authentication（无 status 也判）', () async {
    adapter.bytes = jsonBytes('{"error_code":20018}');
    await expectLater(
      fetchArtistAlbums(session, const MusicArtistAlbumsQuery(id: 1)),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });

  test('input 校验：分页 0/越界、非法排序拒绝；合法边界通过', () async {
    void expectInput(MusicArtistAlbumsQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput(const MusicArtistAlbumsQuery(id: 1, page: 0));
    expectInput(const MusicArtistAlbumsQuery(id: 1, pageSize: 0));
    expectInput(const MusicArtistAlbumsQuery(id: 1, pageSize: 101));
    expectInput(const MusicArtistAlbumsQuery(id: 1, sort: 'time'));
    expectInput(const MusicArtistAlbumsQuery(id: -1));
    // 合法边界。
    const MusicArtistAlbumsQuery(id: 1, pageSize: 1).validate();
    const MusicArtistAlbumsQuery(id: 1, pageSize: 100).validate();
    const MusicArtistAlbumsQuery(id: 1, sort: 'new').validate();
  });
}
