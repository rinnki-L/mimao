/// 专辑动态封面端点测试：裸主机装配（固定参数/专用签名/特殊头/不触发设备
/// 注册）+ h264 URL 过滤去重 + base.album_id 回退 + null/business 分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/album_dycover.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/signature.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
  });

  test('请求装配：裸主机/固定 5 参数/album_cover 签名/特殊头/无默认身份参数', () async {
    adapter.bytes = jsonBytes(dycoverWire());
    final cover = await fetchAlbumDycover(
      fakeMusicSession(client),
      const AlbumDycoverQuery(albumAudioId: 7301, albumId: 42),
    );
    expect(cover, isNotNull);

    final captured = adapter.requests.single;
    expect(captured.method, 'GET');
    expect(captured.path, 'https://kmrcdn.service.kugou.com/v2/album/audio');

    final query = captured.query;
    expect(query['appid'], '1005');
    expect(query['clientver'], '20489');
    expect(query['isCdn'], '1');
    expect(query['query'], 'audioPlay');
    // album_id > 0 才带（request.rs album_dynamic_cover）。
    expect(query['data'], '[{"album_audio_id":7301,"album_id":42}]');
    expect(
      query['signature'],
      kugouSignatureAlbumCover(<String, String>{
        'appid': '1005',
        'clientver': '20489',
        'data': '[{"album_audio_id":7301,"album_id":42}]',
        'isCdn': '1',
        'query': 'audioPlay',
      }),
    );

    // 特殊头：dfid 固定 '-'、mid 固定 undefined、clienttime 为秒级数字。
    expect(captured.headers['dfid'], '-');
    expect(captured.headers['mid'], 'undefined');
    expect(
      RegExp(r'^\d+$').hasMatch('${captured.headers['clienttime']}'),
      isTrue,
    );
    // 裸传输：不带身份默认参数（dfid/mid/token/userid/appid=3116 等），无 router。
    expect(query.containsKey('dfid'), isFalse);
    expect(query.containsKey('mid'), isFalse);
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    expect(captured.headers.containsKey('x-router'), isFalse);
  });

  test('album_id 缺省（0）时 data 只带 album_audio_id', () async {
    adapter.bytes = jsonBytes(dycoverWire());
    await fetchAlbumDycover(
      fakeMusicSession(client),
      const AlbumDycoverQuery(albumAudioId: 7301),
    );
    expect(adapter.requests.single.query['data'], '[{"album_audio_id":7301}]');
  });

  test('绝不触发 ensureDevice（上游 execute 无 identity，注册会产生多余联网）', () async {
    adapter.bytes = jsonBytes(dycoverWire());
    await fetchAlbumDycover(
      fakeMusicSession(client, ensureDevice: () async => fail('动态封面不得触发设备流程')),
      const AlbumDycoverQuery(albumAudioId: 7301),
    );
  });

  test('解码成功：主/备 URL 过滤去重、base.album_id 覆盖请求值', () async {
    adapter.bytes = jsonBytes(dycoverWire());
    final cover = await fetchAlbumDycover(
      fakeMusicSession(client),
      const AlbumDycoverQuery(albumAudioId: 7301, albumId: 42),
    );

    expect(cover!.albumId, '99');
    expect(cover.urls, <String>[
      'https://cdn.example/main.mp4',
      'https://cdn.example/b1.mp4',
    ]);
  });

  test('无 base 时 albumId 回退请求值；非法/非 http URL 与重复项被跳过', () async {
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{
        'status': 1,
        'error_code': 0,
        'data': <Object?>[
          <String, Object?>{
            'dycover': <String, Object?>{
              'h264_url': 'https://cdn.example/main.mp4',
              'h264_backup_url': <Object?>[
                'https://cdn.example/main.mp4',
                'ftp://cdn.example/x.mp4',
                'not a url',
                '',
                'http:/no-host',
                'https://cdn.example/b2.mp4',
              ],
            },
          },
        ],
      }),
    );
    final cover = await fetchAlbumDycover(
      fakeMusicSession(client),
      const AlbumDycoverQuery(albumAudioId: 7301, albumId: 42),
    );

    expect(cover!.albumId, '42');
    expect(cover.urls, <String>[
      'https://cdn.example/main.mp4',
      'https://cdn.example/b2.mp4',
    ]);
  });

  test('备份列表含非字符串元素 → 整组丢弃（Rust Vec<String> 失败归 None）', () async {
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{
        'status': 1,
        'error_code': 0,
        'data': <Object?>[
          <String, Object?>{
            'dycover': <String, Object?>{
              'h264_url': 'https://cdn.example/main.mp4',
              'h264_backup_url': <Object?>['https://cdn.example/b1.mp4', null],
            },
          },
        ],
      }),
    );
    final cover = await fetchAlbumDycover(
      fakeMusicSession(client),
      const AlbumDycoverQuery(albumAudioId: 7301, albumId: 42),
    );
    expect(cover!.urls, <String>['https://cdn.example/main.mp4']);
  });

  test('边界 → null：空 data / 无 dycover / 无合法 URL', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    expect(
      await fetchAlbumDycover(
        fakeMusicSession(client),
        const AlbumDycoverQuery(albumAudioId: 7301),
      ),
      isNull,
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[{}]}');
    expect(
      await fetchAlbumDycover(
        fakeMusicSession(client),
        const AlbumDycoverQuery(albumAudioId: 7301),
      ),
      isNull,
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":[{"dycover":{"h264_url":"ftp://x/y"}}]}',
    );
    expect(
      await fetchAlbumDycover(
        fakeMusicSession(client),
        const AlbumDycoverQuery(albumAudioId: 7301),
      ),
      isNull,
    );
  });

  test('input：album_audio_id 与 album_id 同时为 0 → 缺少专辑资源', () async {
    await expectLater(
      fetchAlbumDycover(
        fakeMusicSession(client),
        const AlbumDycoverQuery(albumAudioId: 0, albumId: 0),
      ),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'input')
            .having((e) => e.message, 'message', '缺少专辑资源'),
      ),
    );
    expect(adapter.requests, isEmpty, reason: '校验失败不得发请求');
  });

  test('status != 1 → business；error_code=20018 → authentication', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":3302,"data":[]}');
    await expectLater(
      fetchAlbumDycover(
        fakeMusicSession(client),
        const AlbumDycoverQuery(albumAudioId: 7301),
      ),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 3302),
      ),
    );

    adapter.bytes = jsonBytes('{"status":0,"error_code":20018,"data":[]}');
    await expectLater(
      fetchAlbumDycover(
        fakeMusicSession(client),
        const AlbumDycoverQuery(albumAudioId: 7301),
      ),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });
}

/// 最小可信动态封面 wire（album_dycover.rs 的采样形状）。
String dycoverWire() => jsonEncode(<String, Object?>{
  'status': 1,
  'error_code': 0,
  'data': <Object?>[
    <String, Object?>{
      'base': <String, Object?>{'album_id': 99},
      'dycover': <String, Object?>{
        'h264_url': 'https://cdn.example/main.mp4',
        'h264_backup_url': <Object?>[
          'https://cdn.example/b1.mp4',
          'https://cdn.example/main.mp4',
        ],
      },
    },
  ],
});
