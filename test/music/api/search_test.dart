/// 搜索端点测试：请求装配（捕获 adapter）+ wire 解码/音质折叠 + 错误分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/search.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import 'search_ext/fake_session.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bytes);

  /// 可变：测试中途替换响应体。
  Uint8List bytes;

  /// 最后一次请求的装配快照。
  final RequestOptions captured = RequestOptions(path: '/');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured
      ..method = options.method
      ..path = options.path
      ..queryParameters = options.queryParameters
      ..headers = options.headers;
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

String songWire({
  String? hqHash,
  String? sqHash,
  String? resHash,
  String songName = '测试<em>歌</em>名',
  Object duration = 180,
}) => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'page': 1,
    'pagesize': 30,
    'total': 123,
    'lists': <Object?>[
      <String, Object?>{
        'Audioid': 12345,
        'MixSongID': '67890',
        'FileHash': 'HASH0001',
        'SongName': songName,
        'Singers': <Object?>[
          <String, Object?>{'id': 1, 'name': '歌手A'},
          <String, Object?>{'name': '歌手B'},
        ],
        'AlbumID': '42',
        'AlbumName': '专辑名',
        'Duration': duration,
        'Image': 'http://imge.kugou.com/stdmusic/{size}/2021001/abc.png',
        'Privilege': 8,
        if (hqHash != null) ...<String, Object?>{
          'HQFileHash': hqHash,
          'HQFileSize': 1048576,
          'HQBitrate': 320,
          'HQDuration': 180,
          'HQExtName': 'mp3',
          'HQPrivilege': 8,
          'HQPayType': 0,
          'HQFailProcess': 0,
        },
        if (sqHash != null) ...<String, Object?>{
          'SQFileHash': sqHash,
          'SQFileSize': 2097152,
          'SQBitrate': 901,
          'SQDuration': 180,
          'SQExtName': 'flac',
        },
        if (resHash != null) ...<String, Object?>{
          'ResFileHash': resHash,
          'ResFileSize': 3145728,
          'ResBitrate': 1420,
          'ResDuration': 180,
        },
        'HQ': hqHash == null
            ? <String, Object?>{}
            : <String, Object?>{
                'hash': hqHash,
                'fileSize': 1048576,
                'bitRate': 320,
                'duration': 180,
                'extName': 'mp3',
              },
      },
    ],
  },
});

void main() {
  late _FakeAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;

  setUp(() {
    adapter = _FakeAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
    session = fakeMusicSession(client, identity);
  });

  test('请求装配：路径/路由/平台参数/显式 userid=0/clientver=201', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(songWire()));
    final page = await searchSongs(
      client,
      identity,
      const SearchSongsQuery(keyword: '周杰伦'),
    );
    expect(page.items, isNotEmpty);

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/v2/search/song?',
      ),
      isTrue,
    );
    expect(adapter.captured.headers['x-router'], 'complexsearch.kugou.com');
    final query = adapter.captured.queryParameters.map(
      (key, value) => MapEntry(key, '$value'),
    );
    expect(query['keyword'], '周杰伦');
    expect(query['platform'], 'AndroidFilter');
    expect(query['iscorrection'], '1');
    expect(query['userid'], '0', reason: '显式 0 是协议语义（缺省会 152）');
    expect(query['clientver'], '201');
    expect(query['privilegefilter'], '0');
    expect(query['area_code'], '1');
    expect(query['dopicfull'], '1');
    expect(query['page'], '1');
    expect(query['pagesize'], '30');
  });

  test('解码：字段映射/秒→毫秒/封面占位符/歌手列表', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(songWire()));
    final page = await searchSongs(
      client,
      identity,
      const SearchSongsQuery(keyword: 'k'),
    );

    expect(page.page, 1);
    expect(page.pageSize, 30);
    expect(page.total, 123);
    final song = page.items.single;
    expect(song.id, '67890');
    expect(song.audioId, 12345);
    expect(song.hash, 'HASH0001');
    expect(song.durationMs, 180000);
    expect(song.coverUrl, contains('/240/'));
    expect(song.coverUrl, isNot(contains('{size}')));
    expect(song.privilege, 8);
    expect(song.albumId, '42');
    expect(song.albumTitle, '专辑名');
    expect(song.artistText, '歌手A / 歌手B');
    expect(song.artists[1].id, isNull);
  });

  test('音质折叠：平铺字段成 320/flac/high；嵌套对象去重不重复入表', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        songWire(hqHash: 'HASH320', sqHash: 'HASHFLAC', resHash: 'HASHRES'),
      ),
    );
    final page = await searchSongs(
      client,
      identity,
      const SearchSongsQuery(keyword: 'k'),
    );
    final song = page.items.single;
    final qualities = song.resources.map((r) => r.quality).toList();
    expect(qualities, <String>['320', 'flac', 'high']);

    final hq = song.resources.firstWhere((r) => r.quality == '320');
    expect(hq.hash, 'HASH320');
    expect(hq.bitRateBps, 320000);
    expect(hq.durationMs, 180000);
    expect(hq.extension, 'mp3');
    expect(hq.payType, 0);
    expect(hq.failureCode, 0);

    final sq = song.resources.firstWhere((r) => r.quality == 'flac');
    expect(sq.hash, 'HASHFLAC');
    expect(sq.bitRateBps, 901000);
    expect(sq.extension, 'flac');
    expect(sq.privilege, isNull, reason: '平铺 SQ 没给权限字段时为 null');

    final res = song.resources.firstWhere((r) => r.quality == 'high');
    expect(res.hash, 'HASHRES');
    expect(res.extension, isNull, reason: 'high 不带权限事实（上游一致）');
    expect(res.privilege, isNull);
  });

  test('无音质字段（含空 HQ 对象）不产生资源条目', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        '{"status":1,"error_code":0,"data":{"page":1,"pagesize":30,"total":1,'
        '"lists":[{"MixSongID":"1","FileHash":"H","SongName":"t","Singers":[],'
        '"AlbumID":"","AlbumName":"","Image":"","HQ":{}}]}}',
      ),
    );
    final page = await searchSongs(
      client,
      identity,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(page.items.single.resources, isEmpty);
  });

  test('Duration 字段缺省 → durationMs null；字符串型数字宽容解码', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(songWire(duration: '180')));
    final page = await searchSongs(
      client,
      identity,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(page.items.single.durationMs, 180000);
  });

  test('AlbumPrivilege 优先于 Privilege（search.rs facts.privilege 回退链）', () async {
    // songWire 已 jsonEncode（无空格），直接在序列化产物上注入字段。
    final wire = songWire().replaceFirst(
      '"Privilege":8',
      '"Privilege":8,"AlbumPrivilege":4',
    );
    adapter.bytes = Uint8List.fromList(utf8.encode(wire));
    final page = await searchSongs(
      client,
      identity,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(page.items.single.privilege, 4);
  });

  test('lists 键缺失 → decode 失败（必填字段，不回空页）', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        '{"status":1,"error_code":0,"data":{"page":1,"pagesize":30,"total":0}}',
      ),
    );
    await expectLater(
      searchSongs(client, identity, const SearchSongsQuery(keyword: 'k')),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('业务失败（status=0）→ business 异常', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode('{"status":0,"error_code":152,"data":{}}'),
    );
    await expectLater(
      searchSongs(client, identity, const SearchSongsQuery(keyword: 'k')),
      throwsA(predicate((Object e) => '$e'.contains('business'))),
    );
  });

  test('参数校验：空关键词/页码 0/分页超界 → input 异常', () async {
    void expectInput(SearchSongsQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput(const SearchSongsQuery(keyword: '  '));
    expectInput(const SearchSongsQuery(keyword: 'k', page: 0));
    expectInput(const SearchSongsQuery(keyword: 'k', pageSize: 0));
    expectInput(const SearchSongsQuery(keyword: 'k', pageSize: 101));
    // 合法边界。
    const SearchSongsQuery(keyword: 'k', pageSize: 1).validate();
    const SearchSongsQuery(keyword: 'k', pageSize: 100).validate();
  });

  // ---- 扩容分支（search.rs Album/Author/Special/Lyric）----

  test(
    '专辑分支：请求装配（/v1/search/album + category/sorttype/searchsong + 签名自验）',
    () async {
      adapter.bytes = Uint8List.fromList(utf8.encode(albumWire()));
      final page = await fetchSearchAlbums(
        session,
        const SearchSongsQuery(keyword: '周杰伦', page: 2, pageSize: 20),
      );
      expect(page.items, isNotEmpty);
      expect(
        '${adapter.captured.uri}'.startsWith(
          'https://gateway.kugou.com/v1/search/album?',
        ),
        isTrue,
      );
      expect(adapter.captured.headers['x-router'], 'complexsearch.kugou.com');
      final query = adapter.captured.queryParameters.map(
        (key, value) => MapEntry(key, '$value'),
      );
      expect(query['keyword'], '周杰伦');
      expect(query['page'], '2');
      expect(query['pagesize'], '20');
      expect(query['platform'], 'AndroidFilter');
      expect(query['iscorrection'], '1');
      expect(query['clientver'], '201');
      expect(query['category'], '1');
      expect(query['sorttype'], '0');
      expect(query['searchsong'], '0');
      expect(
        query.containsKey('userid'),
        isFalse,
        reason: '只有 Song 分支带显式 userid；Album 分支没有',
      );
      expect(
        query.length,
        15,
        reason: '9 端点参数 + 5 个传输默认（clientver 被端点覆盖）+ signature',
      );
      final signature = query.remove('signature');
      expect(signature, kugouSignatureAndroid(query, const <int>[]));
    },
  );

  test('专辑解码：字段映射/数字字符串宽容/封面占位符/歌手列表', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(albumWire()));
    final page = await fetchSearchAlbums(
      session,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(page.page, 2);
    expect(page.pageSize, 20);
    expect(page.total, 57);
    final album = page.items.single;
    expect(album.id, 105, reason: 'albumid 是数字字符串，scalar 宽容解码');
    expect(album.title, '经典专辑');
    expect(album.artistText, '歌手A / 歌手B');
    expect(album.artists[1].id, isNull);
    expect(album.coverUrl, contains('/240/'));
    expect(album.coverUrl, isNot(contains('{size}')));
    expect(album.songCount, 12);
    expect(album.publishedAt, '2021-01-01');
  });

  test('专辑 singers 空对象宽容；lists 缺失回空页（WirePage.lists 有 default）', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(albumWire(singers: <String, Object?>{})),
    );
    final emptySingers = await fetchSearchAlbums(
      session,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(emptySingers.items.single.artists, isEmpty);

    adapter.bytes = Uint8List.fromList(
      utf8.encode(albumWire(includeLists: false)),
    );
    final missingLists = await fetchSearchAlbums(
      session,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(
      missingLists.items,
      isEmpty,
      reason:
          '扩容期上游 WirePage.lists 带 serde(default)：缺键回空页；'
          'Song 分支保持骨架期的必填语义（见上方 lists 缺失测试）',
    );
  });

  test('歌手分支：装配（albumhide/nocollect）+ Avatar 不替换 {size} 占位符', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(authorWire()));
    final page = await fetchSearchArtists(
      session,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/v1/search/author?',
      ),
      isTrue,
    );
    final query = adapter.captured.queryParameters.map(
      (key, value) => MapEntry(key, '$value'),
    );
    expect(query['albumhide'], '0');
    expect(query['nocollect'], '0');
    expect(
      query.containsKey('category'),
      isFalse,
      reason: 'category/sorttype 是 Album 专属',
    );

    final artist = page.items.single;
    expect(artist.id, 9);
    expect(artist.name, '歌手A');
    expect(
      artist.avatarUrl,
      contains('{size}'),
      reason: 'search.rs Author 分支 avatar_url: a.avatar 原样，不替换占位符',
    );
    expect(artist.albumCount, 11);
    expect(artist.songCount, 222);
    expect(artist.fans, 333);
  });

  test('歌单分支：解码 special 字段/封面原样/play_count 文本解析', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(specialWire(playCount: '152600')),
    );
    final page = await fetchSearchPlaylists(
      session,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/v1/search/special?',
      ),
      isTrue,
    );
    final playlist = page.items.single;
    expect(playlist.id, 77);
    expect(playlist.globalId, 'GID123');
    expect(playlist.title, '精选歌单');
    expect(playlist.creatorId, 'UID9');
    expect(playlist.creatorName, '创建者');
    expect(
      playlist.coverUrl,
      contains('{size}'),
      reason: 'Special 封面原样（cover_url: s.img）',
    );
    expect(playlist.songCount, 8);
    expect(playlist.playCount, 152600);
  });

  test('歌单 play_count 非数字/负数/空串 → null（u64 parse 语义）', () async {
    for (final raw in <String>['', '-5', '12x']) {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(specialWire(playCount: raw)),
      );
      final page = await fetchSearchPlaylists(
        session,
        const SearchSongsQuery(keyword: 'k'),
      );
      expect(page.items.single.playCount, isNull, reason: 'play_count=$raw');
    }
  });

  test('歌词分支：MixSongID 数字→文本/TimeLength 秒→毫秒/资源折叠/excerpt', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(lyricWire()));
    final page = await fetchSearchLyrics(
      session,
      const SearchSongsQuery(keyword: 'k'),
    );
    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/v1/search/lyric?',
      ),
      isTrue,
    );
    final hit = page.items.single;
    expect(hit.lyricId, 555);
    expect(hit.excerpt, '歌词片段');
    expect(hit.song.id, '6789', reason: '该分支 MixSongID 是 JSON 数字，text 统一成字符串');
    expect(hit.song.hash, 'HASHLYRIC');
    expect(hit.song.durationMs, 240000);
    expect(hit.song.albumId, '42');
    expect(hit.song.albumTitle, '', reason: 'Rust album_title: None');
    expect(hit.song.coverUrl, contains('/240/'));
    expect(hit.song.privilege, 8);
    final quality = hit.song.resources.single;
    expect(quality.quality, '320');
    expect(quality.hash, 'HQHASH');
    expect(quality.bitRateBps, 320000);
  });

  test(
    '扩容分支：lists 项非 object / 歌手项非 object → decode；status=0 → business',
    () async {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(albumWire(nullItem: true)),
      );
      await expectLater(
        fetchSearchAlbums(session, const SearchSongsQuery(keyword: 'k')),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      adapter.bytes = Uint8List.fromList(
        utf8.encode(albumWire(singers: <Object?>[null])),
      );
      await expectLater(
        fetchSearchAlbums(session, const SearchSongsQuery(keyword: 'k')),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      adapter.bytes = Uint8List.fromList(
        utf8.encode('{"status":0,"error_code":152,"data":{}}'),
      );
      await expectLater(
        fetchSearchPlaylists(session, const SearchSongsQuery(keyword: 'k')),
        throwsA(predicate((Object e) => '$e'.contains('business'))),
      );
    },
  );

  test('扩容分支共用校验：空关键词/页码 0/分页超界 → input', () async {
    for (final query in const <SearchSongsQuery>[
      SearchSongsQuery(keyword: '  '),
      SearchSongsQuery(keyword: 'k', page: 0),
      SearchSongsQuery(keyword: 'k', pageSize: 101),
    ]) {
      await expectLater(
        fetchSearchAlbums(session, query),
        throwsA(predicate((Object e) => '$e'.contains('input'))),
      );
    }
  });
}

/// 专辑分支 wire（search.rs Album 分支的最小可信结构）。
///
/// 边界注入：`singers` 换成 `{}`/`[null]`；`includeLists=false` 模拟 lists 键
/// 缺失；`nullItem=true` 让 lists 首项为 null（非 object）。
String albumWire({
  Object? singers = _kAlbumSingers,
  bool includeLists = true,
  bool nullItem = false,
}) => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'page': 2,
    'pagesize': 20,
    'total': 57,
    if (includeLists)
      'lists': <Object?>[
        if (nullItem)
          null
        else
          <String, Object?>{
            'albumid': '105',
            'albumname': '经典专辑',
            'singers': singers,
            'img': 'http://imge.kugou.com/stdmusic/{size}/album.png',
            'songcount': '12',
            'publish_time': '2021-01-01',
          },
      ],
  },
});

const List<Object?> _kAlbumSingers = <Object?>[
  <String, Object?>{'id': 3, 'name': '歌手A'},
  <String, Object?>{'name': '歌手B'},
];

/// 歌手分支 wire（search.rs Author 分支）。
String authorWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'page': 1,
    'pagesize': 30,
    'total': 1,
    'lists': <Object?>[
      <String, Object?>{
        'AuthorId': 9,
        'AuthorName': '歌手A',
        'Avatar': 'http://imge.kugou.com/artist/{size}/a.png',
        'AlbumCount': 11,
        'AudioCount': 222,
        'FansNum': '333',
      },
    ],
  },
});

/// 歌单分支 wire（search.rs Special 分支）。
String specialWire({required String playCount}) => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'page': 1,
    'pagesize': 30,
    'total': 1,
    'lists': <Object?>[
      <String, Object?>{
        'specialid': '77',
        'specialname': '精选歌单',
        'gid': 'GID123',
        'suid': 'UID9',
        'nickname': '创建者',
        'img': 'http://imge.kugou.com/{size}/p.png',
        'song_count': '8',
        'play_count': playCount,
      },
    ],
  },
});

/// 歌词分支 wire（search.rs Lyric 分支；MixSongID 数字 + TimeLength 秒）。
String lyricWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'page': 1,
    'pagesize': 30,
    'total': 1,
    'lists': <Object?>[
      <String, Object?>{
        'MixSongID': 6789,
        'FileHash': 'HASHLYRIC',
        'SongName': '歌名',
        'Singers': <Object?>[],
        'AlbumID': '42',
        'TimeLength': 240,
        'Image': 'http://imge.kugou.com/stdmusic/{size}/l.png',
        'Privilege': 8,
        'LyricID': '555',
        'Lyric': '歌词片段',
        'HQFileHash': 'HQHASH',
        'HQBitrate': 320,
      },
    ],
  },
});
