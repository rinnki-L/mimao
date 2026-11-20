/// 风格推荐测试：tagids 参数与 `{}` 请求体、标签校验（长度/字符集/数量）、
/// 歌曲与标签组解码、错误分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/everyday_style_recommend.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

String styleWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <String, Object?>{
    'song_list': <Object?>[
      <String, Object?>{
        'album_audio_id': '777',
        'hash': 'H',
        'songname': '风格歌',
        'singerinfo': <Object?>[],
      },
    ],
    'tag_info': <Object?>[
      <String, Object?>{
        'name': '语种',
        'child': <Object?>[
          <String, Object?>{'id': '1', 'name': '国语', 'default': 1},
          <String, Object?>{'id': '2', 'name': '粤语'},
        ],
      },
      <String, Object?>{'name': '场景', 'child': <Object?>[]},
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

  test('请求装配：POST/无 x-router/tagids 逗号连接/请求体 {}', () async {
    adapter.bytes = jsonBytes(styleWire());
    const query = EverydayStyleRecommendQuery(tagIds: <String>['1', '2']);
    final result = await fetchEverydayStyleRecommend(session, query);
    expect(result.songs, hasLength(1));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path,
      'https://gateway.kugou.com/everydayrec.service/everyday_style_recommend',
    );
    expect(request.headers['x-router'], isNull);
    expect(request.query['tagids'], '1,2');
    expect(request.bodyText, '{}');
  });

  test('解码：歌曲摘要 + 标签组/子标签/default 勾选态', () async {
    adapter.bytes = jsonBytes(styleWire());
    final result = await fetchEverydayStyleRecommend(
      session,
      const EverydayStyleRecommendQuery(),
    );

    final song = result.songs.single.song;
    expect(song.id, '777');
    expect(song.title, '风格歌');
    expect(song.hash, 'H');

    expect(result.groups, hasLength(2));
    final group = result.groups[0];
    expect(group.name, '语种');
    expect(group.child, hasLength(2));
    expect(group.child[0].id, '1');
    expect(group.child[0].name, '国语');
    expect(group.child[0].selected, 1, reason: 'wire 键 default');
    expect(group.child[1].selected, isNull);
    expect(result.groups[1].child, isEmpty);
  });

  test('tag_info 空 object → 空组；child 空 object → 空子标签', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"song_list":[],"tag_info":{}}}',
    );
    final result = await fetchEverydayStyleRecommend(
      session,
      const EverydayStyleRecommendQuery(),
    );
    expect(result.groups, isEmpty);

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"song_list":[],"tag_info":'
      '[{"name":"g","child":{}}]}}',
    );
    final childEmpty = await fetchEverydayStyleRecommend(
      session,
      const EverydayStyleRecommendQuery(),
    );
    expect(childEmpty.groups.single.child, isEmpty);
  });

  test('标签校验：空/超 32/非字母数字/超 128 个 → input；合法边界通过', () {
    void expectInput(EverydayStyleRecommendQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (error) {
        expect(error.kind, 'input');
        expect(error.message, '风格标签无效');
      }
    }

    expectInput(EverydayStyleRecommendQuery(tagIds: <String>['ok', '']));
    expectInput(EverydayStyleRecommendQuery(tagIds: <String>['a' * 33]));
    expectInput(EverydayStyleRecommendQuery(tagIds: <String>['含-连字符']));
    expectInput(
      EverydayStyleRecommendQuery(
        tagIds: List<String>.generate(129, (int i) => 't$i'),
      ),
    );
    // 合法边界：32 字符、128 个。
    EverydayStyleRecommendQuery(tagIds: <String>['a' * 32]).validate();
    EverydayStyleRecommendQuery(
      tagIds: List<String>.generate(128, (int i) => 't$i'),
    ).validate();
    const EverydayStyleRecommendQuery().validate();
  });

  test('业务与解码失败：data 非 object / 标签组非 object / status=0', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":5}');
    await expectLater(
      fetchEverydayStyleRecommend(session, const EverydayStyleRecommendQuery()),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"song_list":[],"tag_info":[1]}}',
    );
    await expectLater(
      fetchEverydayStyleRecommend(session, const EverydayStyleRecommendQuery()),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes('{"status":0,"error_code":7}');
    await expectLater(
      fetchEverydayStyleRecommend(session, const EverydayStyleRecommendQuery()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 7,
        ),
      ),
    );
  });
}
