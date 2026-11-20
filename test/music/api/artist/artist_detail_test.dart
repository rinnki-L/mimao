/// 歌手详情端点测试：请求装配 + 解码/封面回退链 + data 空缺分支 + 错误分支。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/artist_detail.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// detail.rs 采样结构（最小可信 wire）。
String detailWire({String authorId = '12345', Object? isPublish = 1}) =>
    jsonEncode(<String, Object?>{
      'status': 1,
      'error_code': 0,
      'data': <String, Object?>{
        'author_id': authorId,
        'author_name': '周杰伦',
        'sizable_avatar': 'http://imge.kugou.com/stdmusic/{size}/2021/av.png',
        'birthday': '1979-01-18',
        'fansnums': '999',
        'album_count': 45,
        'mv_count': 6,
        'is_publish': isPublish,
        'long_intro': <Object?>[
          <String, Object?>{'content': '第一段简介'},
          <String, Object?>{'content': ''},
          <String, Object?>{'content': '第三段简介'},
        ],
      },
    });

void main() {
  late CaptureAdapter adapter;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    session = fakeMusicSession(artistTestClient(adapter), artistTestIdentity());
  });

  test(
    '请求装配：POST /kmr/v3/author + x-router + kg-tid + author_id body',
    () async {
      adapter.bytes = jsonBytes(detailWire());
      final detail = await fetchArtistDetail(session, 123);
      expect(detail, isNotNull);

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.path,
        startsWith('https://gateway.kugou.com/kmr/v3/author'),
      );
      expect(request.headers['x-router'], 'openapi.kugou.com');
      expect(request.headers['kg-tid'], '36');
      // POST body：{"author_id":123}（u64 原样数字）。
      expect(request.bodyText, '{"author_id":123}');
      final query = request.query;
      expect(query['appid'], '3116');
      expect(query['clientver'], '11440');
      expect(query['dfid'], '-');
      expect(query['signature'], isNotEmpty);
    },
  );

  test('解码：字段映射/long_intro 空行连接/封面 {size}→240/字符串数字宽容', () async {
    adapter.bytes = jsonBytes(detailWire());
    final detail = (await fetchArtistDetail(session, 123))!;

    expect(detail.id, 12345);
    expect(detail.name, '周杰伦');
    // 封面回退链：sizable_avatar 的 {size} 占位符替换为 240。
    expect(detail.avatarUrl, 'http://imge.kugou.com/stdmusic/240/2021/av.png');
    expect(detail.avatarUrl, isNot(contains('{size}')));
    // 空段被过滤，其余用空行连接（不加展示性标题）。
    expect(detail.description, '第一段简介\n\n第三段简介');
    expect(detail.birthday, '1979-01-18');
    expect(detail.fans, 999, reason: '数字字符串按 scalar 宽容解析');
    expect(detail.albumCount, 45);
    expect(detail.mvCount, 6);
    expect(detail.published, isTrue);
  });

  test('data 为 null / 空 object → null（不算失败）', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    expect(await fetchArtistDetail(session, 123), isNull);
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    expect(await fetchArtistDetail(session, 123), isNull);
    // data 键缺省（serde default → Null）同样回 null。
    adapter.bytes = jsonBytes('{"status":1,"error_code":0}');
    expect(await fetchArtistDetail(session, 123), isNull);
  });

  test('author_id 非纯数字 → id null；is_publish 未知码 → published null', () async {
    adapter.bytes = jsonBytes(detailWire(authorId: 'abc', isPublish: 7));
    final detail = (await fetchArtistDetail(session, 123))!;
    expect(detail.id, isNull);
    expect(detail.published, isNull);
  });

  test('long_intro 元素不是 object → decode 失败', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"author_id":"1","long_intro":["文本"]}}',
    );
    await expectLater(
      fetchArtistDetail(session, 123),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('data 是字符串 → decode 失败（不吞成 null）', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":"oops"}');
    await expectLater(
      fetchArtistDetail(session, 123),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('业务失败（status=0）→ business', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":152,"data":null}');
    await expectLater(
      fetchArtistDetail(session, 123),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
    );
  });

  test('登录过期码 20018 → authentication', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":20018}');
    await expectLater(
      fetchArtistDetail(session, 123),
      throwsA(predicate((Object e) => '$e'.contains('authentication'))),
    );
  });

  test('input 校验：负数 id（u64 输入域）拒绝，0 合法', () async {
    await expectLater(
      fetchArtistDetail(session, -1),
      throwsA(predicate((Object e) => '$e'.contains('input'))),
    );
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    expect(await fetchArtistDetail(session, 0), isNull);
  });
}
