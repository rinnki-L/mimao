/// 歌单标签端点测试：请求装配（固定标签体）+ 分组/子标签解码 +
/// decode_envelope 兜底与 list 宽容（playlist_tags.rs）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_tags.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 信封模板。
String tagsWire({required Object? data, int status = 1, int errorCode = 0}) =>
    jsonEncode(<String, Object?>{
      'status': status,
      'error_code': errorCode,
      'data': data,
    });

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = capturedClient(adapter);
    identity = KugouIdentity.anonymous();
  });

  test('请求装配：POST/固定 body 键序与值/无 router', () async {
    adapter.bytes = jsonBytes(tagsWire(data: <Object?>[]));
    await fetchPlaylistTags(fakeMusicSession(identity, client));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/pubsongs/v1/get_tags_by_type',
      ),
      isTrue,
    );
    expect(request.headers.containsKey('x-router'), isFalse);
    expect(request.bodyText, '{"tag_type":"collection","tag_id":0,"source":3}');
  });

  test('解码：分组与子标签保持字符串 id 与服务端顺序，sort 进 position', () async {
    adapter.bytes = jsonBytes(
      tagsWire(
        data: <Object?>[
          <String, Object?>{
            'tag_id': '100',
            'tag_name': '语种',
            'parent_id': '0',
            'sort': '1',
            'son': <Object?>[
              <String, Object?>{
                'tag_id': '101',
                'tag_name': '华语',
                'parent_id': '100',
                'sort': '2',
              },
              <String, Object?>{
                'tag_id': '102',
                'tag_name': '欧美',
                'parent_id': '100',
                'sort': 3,
              },
            ],
          },
          <String, Object?>{
            'tag_id': '200',
            'tag_name': '场景',
            'parent_id': '0',
            'sort': 'not-number',
            'son': <String, Object?>{},
          },
        ],
      ),
    );
    final categories = await fetchPlaylistTags(
      fakeMusicSession(identity, client),
    );
    expect(categories, hasLength(2));
    expect(categories[0].id, '100');
    expect(categories[0].name, '语种');
    expect(categories[0].parentId, '0');
    expect(categories[0].position, 1);
    expect(categories[0].children, hasLength(2));
    expect(categories[0].children[0].id, '101');
    expect(categories[0].children[0].position, 2);
    expect(
      categories[0].children[0].children,
      isEmpty,
      reason: 'children 只递归一层',
    );
    // 数字 sort 走 text → 十进制文本 → position。
    expect(categories[0].children[1].position, 3);
    // u64 解析失败 → position null（不抛）。
    expect(categories[1].position, isNull);
    expect(categories[1].children, isEmpty, reason: 'son 空 object → 空表');
  });

  test('list 宽容：data 缺省/空 object → 空分类', () async {
    adapter.bytes = jsonBytes(tagsWire(data: null));
    expect(
      await fetchPlaylistTags(fakeMusicSession(identity, client)),
      isEmpty,
    );
    adapter.bytes = jsonBytes(tagsWire(data: <String, Object?>{}));
    expect(
      await fetchPlaylistTags(fakeMusicSession(identity, client)),
      isEmpty,
    );
  });

  test('decode：data 非数组 / 分组非 object → decode', () async {
    adapter.bytes = jsonBytes(tagsWire(data: 'nope'));
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
    adapter.bytes = jsonBytes(tagsWire(data: <Object?>[true]));
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
  });

  test('decode_envelope 兜底：信封键缺失但 error_code 非零/status=0 → business', () async {
    // status 缺失 → 结构解析 decode；兜底按 error_code 上报业务失败。
    adapter.bytes = jsonBytes('{"error_code":308,"data":[]}');
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 308,
        ),
      ),
    );
    // error_code 缺失但 status=0 → 兜底按业务失败（code 0）上报。
    adapter.bytes = jsonBytes('{"status":0,"data":[]}');
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 0,
        ),
      ),
    );
  });

  test('信封完整但 data 非数组且业务码为零 → business（status=0 分支）', () async {
    adapter.bytes = jsonBytes(tagsWire(status: 0, errorCode: 308, data: 5));
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 308,
        ),
      ),
    );
  });

  test('结构坏但无业务信号 → 仍 decode', () async {
    adapter.bytes = jsonBytes(tagsWire(data: 5));
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
  });

  test('业务失败（status=1 error_code=152 不算成功）→ business', () async {
    adapter.bytes = jsonBytes(tagsWire(errorCode: 152, data: <Object?>[]));
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
    );
  });

  test('登录过期：error_code=20018 → authentication', () async {
    adapter.bytes = jsonBytes(tagsWire(errorCode: 20018, data: <Object?>[]));
    await expectLater(
      fetchPlaylistTags(fakeMusicSession(identity, client)),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
  });
}
