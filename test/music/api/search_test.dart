/// 搜索端点测试：请求装配（捕获 adapter）+ wire 解码/音质折叠 + 错误分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/search.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

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

  setUp(() {
    adapter = _FakeAdapter(Uint8List(0));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
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
}
