/// song_auth 端点测试：五个参数装配 + 授权串校验 + open_time 必填。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/song_auth.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import 'capture_adapter.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  test('请求装配：五参数齐全、hash 小写、clientver=11561', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,'
      '"data":{"auth":"SONG-AUTH","open_time":1700000123}}',
    );
    final result = await songAuthorize(
      client,
      identity,
      hash: 'ABCDEF0123456789ABCDEF0123456789',
      songId: 7301,
      userAuth: 'USER-AUTH',
    );

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/v1/authorization?',
      ),
      isTrue,
    );
    expect(adapter.captured.headers['x-router'], 'trackercdngz.kugou.com');
    final query = capturedQuery(adapter.captured);
    expect(query['authorization'], 'USER-AUTH');
    expect(query['module_id'], '51');
    expect(query['album_audio_id'], '7301');
    expect(query['clientver'], '11561');
    expect(query['hash'], 'abcdef0123456789abcdef0123456789');

    expect(result.opensAt, 1700000123);
    final songAuth = result.authorization;
    expect(songAuth, 'SONG-AUTH');
  });

  test('auth 空 → authentication', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"auth":"","open_time":1}}',
    );
    await expectLater(
      songAuthorize(
        client,
        identity,
        hash: 'abcdef0123456789abcdef0123456789',
        songId: 1,
        userAuth: 'USER-AUTH',
      ),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('open_time 缺失/非标量 → decode；data 非 object → decode', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"auth":"A"}}',
    );
    await expectLater(
      songAuthorize(
        client,
        identity,
        hash: 'abcdef0123456789abcdef0123456789',
        songId: 1,
        userAuth: 'USER-AUTH',
      ),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    await expectLater(
      songAuthorize(
        client,
        identity,
        hash: 'abcdef0123456789abcdef0123456789',
        songId: 1,
        userAuth: 'USER-AUTH',
      ),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );
  });
}
