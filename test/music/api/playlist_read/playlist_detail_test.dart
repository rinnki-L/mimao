/// 歌单详情端点测试：请求装配 + 解码/宽容分支 + input/business 边界
/// （playlist_detail.rs）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_detail.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 信封模板。
String detailWire({required Object? data}) =>
    jsonEncode(<String, Object?>{'status': 1, 'error_code': 0, 'data': data});

Map<String, Object?> detailItem() => <String, Object?>{
  'global_collection_id': 'gcol-1',
  'specialid': 777,
  'name': '歌单名',
  'intro': '简介',
  'pic': 'http://imge.kugou.com/stdmusic/{size}/2021001/abc.png',
  'list_create_userid': 42,
  'list_create_listid': 43,
  'list_create_username': '创建者',
  'create_user_pic': 'http://imge.kugou.com/artist/{size}/a.png',
  'count': 30,
  'list_ver': 9,
  'publish_date': '2021-01-01',
  'collect_total': 100,
  'is_pri': 0,
  'is_publish': 1,
  'tags': '华语,流行',
  'create_time': 1600000000,
  'update_time': 1610000000,
  'list_create_gid': 'gid-1',
  'source': 3,
  'is_custom_pic': 1,
  'is_def': 0,
  'musiclib_tags': <Object?>[
    <String, Object?>{'tag_id': '3', 'tag_name': '流行', 'parent_id': 1},
    <String, Object?>{'tag_id': 4, 'tag_name': '摇滚'},
  ],
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

  test('请求装配：POST/路由/body 键序/匿名不带账号 query', () async {
    adapter.bytes = jsonBytes(detailWire(data: <Object?>[detailItem()]));
    final details = await fetchPlaylistDetail(
      fakeMusicSession(identity, client),
      const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1', 'gcol-2']),
    );
    expect(details, hasLength(1));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path.startsWith('https://gateway.kugou.com/v3/get_list_info'),
      isTrue,
    );
    expect(request.headers['x-router'], 'pubsongs.kugou.com');
    // 普通带签名请求：默认参数 + signature；匿名不注入 token/userid。
    expect(request.query.keys.toSet(), <String>{
      'appid',
      'clientver',
      'clienttime',
      'dfid',
      'mid',
      'signature',
      'uuid',
    });
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>['data', 'userid', 'token']);
    expect(body['userid'], 0);
    expect(body['token'], '');
    expect(body['data'], <Object?>[
      <String, String>{'global_collection_id': 'gcol-1'},
      <String, String>{'global_collection_id': 'gcol-2'},
    ]);
  });

  test('解码：字段映射/封面占位符/0-1 布尔/musiclib_tags', () async {
    adapter.bytes = jsonBytes(detailWire(data: <Object?>[detailItem()]));
    final detail = (await fetchPlaylistDetail(
      fakeMusicSession(identity, client),
      const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1']),
    )).single;

    expect(detail.globalId, 'gcol-1');
    expect(detail.publicId, 777);
    expect(detail.title, '歌单名');
    expect(detail.description, '简介');
    expect(detail.coverUrl, contains('/240/'));
    expect(detail.creatorId, 42);
    expect(detail.creatorListId, 43);
    expect(detail.creatorName, '创建者');
    expect(detail.creatorAvatarUrl, contains('/240/'));
    expect(detail.songCount, 30);
    expect(detail.revision, 9);
    expect(detail.publishedAt, '2021-01-01');
    expect(detail.collectionCount, 100);
    expect(detail.private, isFalse);
    expect(detail.privateCode, 0);
    expect(detail.published, isTrue);
    expect(detail.publicationCode, 1);
    expect(detail.tags, '华语,流行');
    expect(detail.createdAtSeconds, 1600000000);
    expect(detail.updatedAtSeconds, 1610000000);
    expect(detail.creatorGlobalId, 'gid-1');
    expect(detail.sourceCode, 3);
    expect(detail.customCover, isTrue);
    expect(detail.customCoverCode, 1);
    expect(detail.defaultKind, 0);
    expect(detail.musicTags, hasLength(2));
    expect(detail.musicTags![0].id, '3');
    expect(detail.musicTags![0].name, '流行');
    expect(detail.musicTags![0].parentId, '1');
    expect(detail.musicTags![1].id, '4');
    expect(detail.musicTags![1].parentId, isNull);
  });

  test('边界：data 空 object → 空列表（采样的缺失合集）', () async {
    adapter.bytes = jsonBytes(detailWire(data: <String, Object?>{}));
    final details = await fetchPlaylistDetail(
      fakeMusicSession(identity, client),
      const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1']),
    );
    expect(details, isEmpty);
  });

  test(
    '宽容：text 的 bool → 空串；optional 非法 → null；musiclib_tags 非数组归 null',
    () async {
      adapter.bytes = jsonBytes(
        detailWire(
          data: <Object?>[
            <String, Object?>{
              'global_collection_id': 'gcol-1',
              'name': true,
              'specialid': false,
              'count': 'not-a-number',
              'tags': 42,
              'musiclib_tags': 'broken',
            },
          ],
        ),
      );
      final detail = (await fetchPlaylistDetail(
        fakeMusicSession(identity, client),
        const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1']),
      )).single;
      expect(detail.title, '');
      expect(detail.publicId, isNull);
      expect(detail.songCount, isNull);
      expect(detail.tags, '42', reason: 'optional<String> 数字仍转文本');
      expect(detail.musicTags, isNull);
    },
  );

  test('宽容：musiclib_tags 含非 object 条目 → 整体归 null（optional 吞错）', () async {
    adapter.bytes = jsonBytes(
      detailWire(
        data: <Object?>[
          <String, Object?>{
            'global_collection_id': 'gcol-1',
            'musiclib_tags': <Object?>[true],
          },
        ],
      ),
    );
    final detail = (await fetchPlaylistDetail(
      fakeMusicSession(identity, client),
      const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1']),
    )).single;
    expect(detail.musicTags, isNull);
  });

  test('decode：data 缺省/非数组、条目非 object → decode', () async {
    for (final data in <Object?>[
      null,
      'nope',
      <Object?>[true],
    ]) {
      adapter.bytes = jsonBytes(detailWire(data: data));
      await expectLater(
        fetchPlaylistDetail(
          fakeMusicSession(identity, client),
          const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1']),
        ),
        throwsA(
          predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
        ),
      );
    }
  });

  test('业务失败：status=0 → business 带 error_code', () async {
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{
        'status': 0,
        'error_code': 32201,
        'data': <Object?>[],
      }),
    );
    await expectLater(
      fetchPlaylistDetail(
        fakeMusicSession(identity, client),
        const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1']),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 32201,
        ),
      ),
    );
  });

  test('登录过期：error_code=20018 → authentication', () async {
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{
        'status': 0,
        'error_code': 20018,
        'data': null,
      }),
    );
    await expectLater(
      fetchPlaylistDetail(
        fakeMusicSession(identity, client),
        const MusicPlaylistDetailQuery(globalIds: <String>['gcol-1']),
      ),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
  });

  test('input 校验：空列表/超 100/空串/逗号/超 256', () {
    void expectInput(MusicPlaylistDetailQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput(const MusicPlaylistDetailQuery(globalIds: <String>[]));
    expectInput(
      MusicPlaylistDetailQuery(
        globalIds: List<String>.generate(101, (i) => 'id$i'),
      ),
    );
    expectInput(const MusicPlaylistDetailQuery(globalIds: <String>['']));
    expectInput(const MusicPlaylistDetailQuery(globalIds: <String>['a,b']));
    expectInput(MusicPlaylistDetailQuery(globalIds: <String>['a' * 257]));
    // 合法边界：100 个、256 字符。
    MusicPlaylistDetailQuery(
      globalIds: List<String>.generate(100, (i) => 'id$i'),
    ).validate();
    MusicPlaylistDetailQuery(globalIds: <String>['a' * 256]).validate();
  });
}
