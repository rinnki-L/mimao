/// 云歌单端点测试：x-router/params/body 键序（struct 声明序）、分页校验、
/// 云歌单种类与标志码、info 缺省/空对象宽容、业务/认证分支。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_playlist.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_library_models.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

Map<String, Object?> playlistItem({
  int listid = 8001,
  String type = '1',
  Object? intro = '简介',
  Object? tags = '流行',
  String globalCollectionId = 'col-1001',
}) => <String, Object?>{
  'listid': listid,
  'global_collection_id': globalCollectionId,
  'list_create_gid': 'gid-$listid',
  'name': '云歌单$listid',
  'intro': intro,
  'tags': tags,
  'pic': 'http://imge.kugou.com/stdmusic/{size}/2021001/$listid.png',
  'list_create_userid': 9007199254741005,
  'list_create_username': '创建者$listid',
  'list_create_listid': 7000 + listid,
  'count': 12,
  'list_ver': 42,
  'sort': -3,
  'source': 5,
  'type': type,
  'is_edit': 1,
  'is_pri': 0,
  'is_publish': 2,
  'is_del': 0,
  'is_drop': 1,
  'is_custom_pic': 3,
  'is_def': 1,
  'create_time': 1700000000,
  'update_time': 1700000600,
  'sku_unknown': 'keep',
};

String playlistsWire(List<Map<String, Object?>> items) =>
    jsonEncode(<String, Object?>{
      'status': 1,
      'error_code': 0,
      'data': <String, Object?>{
        'info': items,
        'userid': 9007199254741005,
        'total_ver': 979,
        'list_count': items.length,
        'collect_count': items.length - 1,
        'album_count': 4,
      },
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

  test('请求装配：x-router、显式 plat/userid/token、body 按 struct 声明序', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(playlistsWire([])));
    const query = MusicUserPlaylistQuery(page: 2, pageSize: 50);
    final result = await fetchUserPlaylist(sessionFor(client, identity), query);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/v7/get_all_list'));
    expect(request.headers['x-router'], 'cloudlist.service.kugou.com');
    expect(request.query['plat'], '1');
    expect(request.query['userid'], '${identity.userId}');
    expect(request.query['token'], identity.token);
    // Rust 具名 struct（serde 按字段声明序）：userid, token, total_ver, type,
    // page, pagesize。
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'userid',
      'token',
      'total_ver',
      'type',
      'page',
      'pagesize',
    ]);
    expect(body['total_ver'], 979);
    expect(body['type'], 2);
    expect(body['page'], 2);
    expect(body['pagesize'], 50);
    expect(body['token'], identity.token);
    expectValidAndroidSignature(request);
    // page/pageSize 回显请求值。
    expect(result.page.page, 2);
    expect(result.page.pageSize, 50);
  });

  test('匿名身份 → authentication，不发出请求', () async {
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    adapter.bytes = Uint8List.fromList(utf8.encode(playlistsWire([])));
    await expectLater(
      fetchUserPlaylist(
        sessionFor(client, anonymous),
        const MusicUserPlaylistQuery(page: 1, pageSize: 30),
      ),
      throwsKugou('authentication'),
    );
    expect(adapter.requests, isEmpty);
  });

  test('分页校验：page=0、pagesize 越界 → input（账号检查在前）', () async {
    adapter.bytes = Uint8List.fromList(utf8.encode(playlistsWire([])));
    for (final (page, pageSize) in <(int, int)>[(0, 30), (1, 0), (1, 201)]) {
      await expectLater(
        fetchUserPlaylist(
          sessionFor(client, identity),
          MusicUserPlaylistQuery(page: page, pageSize: pageSize),
        ),
        throwsKugou('input'),
      );
    }
    expect(adapter.requests, isEmpty);
    // 边界放行：page=1 / pageSize=1 / pageSize=200。
    for (final pageSize in const [1, 200]) {
      adapter.bytes = Uint8List.fromList(utf8.encode(playlistsWire([])));
      await fetchUserPlaylist(
        sessionFor(client, identity),
        MusicUserPlaylistQuery(page: 1, pageSize: pageSize),
      );
    }
    expect(adapter.requests, hasLength(2));
  });

  test('解码：种类映射/布尔投影独立于标志码/负排序/封面尺寸', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        playlistsWire([
          playlistItem(listid: 1, type: '0'),
          playlistItem(listid: 2, type: '1'),
          playlistItem(listid: 3, type: '7'),
        ]),
      ),
    );
    final result = await fetchUserPlaylist(
      sessionFor(client, identity),
      const MusicUserPlaylistQuery(page: 1, pageSize: 30),
    );
    expect(result.userId, 9007199254741005);
    expect(result.totalRevision, 979);
    expect(result.collectionCount, 2);
    expect(result.albumCount, 4);
    expect(result.page.total, 3);

    final owned = result.page.items[0];
    expect(owned.kind, MusicCloudPlaylistKind.owned);
    expect(owned.kindCode, 0);
    final collected = result.page.items[1];
    expect(collected.kind, MusicCloudPlaylistKind.collected);
    expect(collected.kindCode, 1);
    final unknown = result.page.items[2];
    expect(unknown.kind, MusicCloudPlaylistKind.unknown);
    expect(unknown.kindCode, 7);

    // 布尔投影：0→false、1→true、2→null；码值独立保留。
    for (final item in result.page.items) {
      expect(item.editable, isTrue);
      expect(item.private, isFalse);
      expect(item.published, isNull);
      expect(item.deleted, isFalse);
      expect(item.dropped, isTrue);
      expect(item.customCover, isNull);
      expect(item.flagCodes.editable, 1);
      expect(item.flagCodes.private, 0);
      expect(item.flagCodes.published, 2);
      expect(item.flagCodes.customCover, 3);
      expect(item.defaultKind, 1);
    }

    final first = result.page.items[0];
    expect(first.cloudListId, 1);
    expect(first.globalId, 'col-1001');
    expect(first.creatorGlobalId, 'gid-1');
    expect(first.title, '云歌单1');
    expect(first.descriptionPresent, isTrue);
    expect(first.tagsPresent, isTrue);
    expect(first.description, '简介');
    expect(first.tags, '流行');
    expect(first.coverUrl, 'http://imge.kugou.com/stdmusic/240/2021001/1.png');
    expect(first.creatorId, 9007199254741005);
    expect(first.creatorListId, 7001);
    expect(first.songCount, 12);
    expect(first.revision, 42);
    expect(first.sortIndex, -3);
    expect(first.sourceCode, 5);
    expect(first.createdAtSeconds, 1700000000);
    expect(first.updatedAtSeconds, 1700000600);
  });

  test('intro/tags 缺省或 null → 有无标志 false、展示空串', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        playlistsWire([playlistItem(listid: 1, intro: null, tags: null)]),
      ),
    );
    final result = await fetchUserPlaylist(
      sessionFor(client, identity),
      const MusicUserPlaylistQuery(page: 1, pageSize: 30),
    );
    final item = result.page.items.single;
    expect(item.descriptionPresent, isFalse);
    expect(item.tagsPresent, isFalse);
    expect(item.description, '');
    expect(item.tags, '');
  });

  test('info 缺省/null → 空表；空 object → decode（上游 Vec 反序列化失败）', () async {
    for (final info in <Object?>[null]) {
      adapter.bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'status': 1,
            'error_code': 0,
            'data': <String, Object?>{
              'info': info,
              'list_count': 0,
              'collect_count': 0,
            },
          }),
        ),
      );
      final result = await fetchUserPlaylist(
        sessionFor(client, identity),
        const MusicUserPlaylistQuery(page: 1, pageSize: 30),
      );
      expect(result.page.items, isEmpty);
      expect(result.page.total, 0);
    }
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 0,
          'data': <String, Object?>{'info': <String, Object?>{}},
        }),
      ),
    );
    await expectLater(
      fetchUserPlaylist(
        sessionFor(client, identity),
        const MusicUserPlaylistQuery(page: 1, pageSize: 30),
      ),
      throwsKugou('decode'),
    );
  });

  test('info 元素非 object → decode；业务失败与 20017 分支', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 0,
          'data': <String, Object?>{
            'info': <Object?>[null],
          },
        }),
      ),
    );
    await expectLater(
      fetchUserPlaylist(
        sessionFor(client, identity),
        const MusicUserPlaylistQuery(page: 1, pageSize: 30),
      ),
      throwsKugou('decode'),
    );

    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'status': 0,
          'error_code': 30001,
          'data': <String, Object?>{'info': 'invalid'},
        }),
      ),
    );
    await expectLater(
      fetchUserPlaylist(
        sessionFor(client, identity),
        const MusicUserPlaylistQuery(page: 1, pageSize: 30),
      ),
      throwsKugou('business', code: 30001),
    );

    adapter.bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'status': 0,
          'error_code': 20017,
          'data': <String, Object?>{'info': 'invalid'},
        }),
      ),
    );
    await expectLater(
      fetchUserPlaylist(
        sessionFor(client, identity),
        const MusicUserPlaylistQuery(page: 1, pageSize: 30),
      ),
      throwsKugou('authentication', code: 20017),
    );
  });
}
