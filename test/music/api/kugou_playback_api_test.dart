/// KugouPlaybackApi 链路测试：三/两段调用顺序、质量映射与回退、输入校验。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/kugou_playback_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';

import 'capture_adapter.dart';

class _FakeMusicApi implements MusicApi {
  _FakeMusicApi(this.identity);

  final KugouIdentity identity;

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async => const MusicPage<MusicSong>(items: <MusicSong>[]);

  @override
  Future<KugouIdentity> ensureDevice() async => identity;

  @override
  Future<KugouIdentity?> currentIdentity() async => identity;
}

class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromBytes(jsonBytes(body), 200);

ResponseBody _happyPath(RequestOptions options) {
  switch (Uri.parse(options.path).path) {
    case '/v1/user_verify':
      return _json(
        '{"status":1,"error_code":0,'
        '"data":{"valid":1,"auth":"USER-AUTH"}}',
      );
    case '/v1/authorization':
      return _json(
        '{"status":1,"error_code":0,'
        '"data":{"auth":"SONG-AUTH","open_time":1700000123}}',
      );
    case '/tracker/v5/url':
      return _json(
        '{"status":1,"error_code":0,'
        '"hash":"abcdef0123456789abcdef0123456789",'
        '"url":["https://cdn.example/1.mp3"],"timeLength":181}',
      );
  }
  throw StateError('unexpected path: ${options.path}');
}

MusicSong song({
  String id = '7301',
  String hash = 'abcdef0123456789abcdef0123456789',
  String albumId = '42',
  int? audioId = 9001,
}) => MusicSong(
  id: id,
  audioId: audioId,
  hash: hash,
  title: '稻香',
  artists: const <MusicArtistRef>[MusicArtistRef(name: '周杰伦')],
  albumId: albumId,
  albumTitle: '魔杰座',
  coverUrl: '',
);

void main() {
  late KugouIdentity identity;
  late _FakeMusicApi api;

  setUp(() {
    identity = KugouIdentity.anonymous();
    api = _FakeMusicApi(identity);
  });

  KugouPlaybackApi build(_RoutingAdapter adapter) => KugouPlaybackApi(
    KugouClient(dio: Dio()..httpClientAdapter = adapter),
    api,
  );

  test('未注入 authorization：user_verify → song_auth → tracker 三次请求', () async {
    final adapter = _RoutingAdapter(_happyPath);
    final source = await build(adapter).resolvePlayback(song());

    expect(
      adapter.requests.map((options) => Uri.parse(options.path).path),
      <String>['/v1/user_verify', '/v1/authorization', '/tracker/v5/url'],
    );
    expect(source.primaryUrl, 'https://cdn.example/1.mp3');
    // song_auth 收到的是 user_verify 的授权串。
    final songAuthRequest = adapter.requests[1];
    expect(capturedQuery(songAuthRequest)['authorization'], 'USER-AUTH');
  });

  test('注入 authorization：跳过 user_verify，只发两次', () async {
    final adapter = _RoutingAdapter(_happyPath);
    await build(adapter).resolvePlayback(song(), authorization: 'REUSE-AUTH');

    expect(
      adapter.requests.map((options) => Uri.parse(options.path).path),
      <String>['/v1/authorization', '/tracker/v5/url'],
    );
    expect(
      capturedQuery(adapter.requests.first)['authorization'],
      'REUSE-AUTH',
    );
  });

  test('默认质量 higher → tracker 收到 320', () async {
    final adapter = _RoutingAdapter(_happyPath);
    await build(adapter).resolvePlayback(song());
    expect(capturedQuery(adapter.requests.last)['quality'], '320');
  });

  test('默认质量 business 失败 → 回退 standard 重试一次', () async {
    final qualities = <String>[];
    var trackerCalls = 0;
    final adapter = _RoutingAdapter((options) {
      if (Uri.parse(options.path).path == '/tracker/v5/url') {
        qualities.add('${options.queryParameters['quality']}');
        trackerCalls++;
        if (trackerCalls == 1) {
          return _json('{"status":0,"error_code":20010}');
        }
        return _json(
          '{"status":1,"error_code":0,'
          '"hash":"abcdef0123456789abcdef0123456789",'
          '"url":["https://cdn.example/128.mp3"]}',
        );
      }
      return _happyPath(options);
    });

    final source = await build(adapter).resolvePlayback(song());
    expect(qualities, <String>['320', '128']);
    expect(source.primaryUrl, 'https://cdn.example/128.mp3');
  });

  test('authentication 不回退：只请求一次 tracker 并原样抛出', () async {
    final adapter = _RoutingAdapter((options) {
      if (Uri.parse(options.path).path == '/tracker/v5/url') {
        return _json('{"status":0,"error_code":20018}');
      }
      return _happyPath(options);
    });
    await expectLater(
      build(adapter).resolvePlayback(song()),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'authentication',
        ),
      ),
    );
    expect(
      adapter.requests
          .where((options) => Uri.parse(options.path).path == '/tracker/v5/url')
          .length,
      1,
    );
  });

  test('两次都失败：error 保留最后一次错误码', () async {
    var trackerCalls = 0;
    final adapter = _RoutingAdapter((options) {
      if (Uri.parse(options.path).path == '/tracker/v5/url') {
        trackerCalls++;
        return _json(
          '{"status":0,"error_code":${trackerCalls == 1 ? 20010 : 20011}}',
        );
      }
      return _happyPath(options);
    });
    await expectLater(
      build(adapter).resolvePlayback(song()),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 20011),
      ),
    );
    expect(trackerCalls, 2);
  });

  test('hash 非 32 位 hex → input，且不发任何请求', () async {
    final adapter = _RoutingAdapter(_happyPath);
    await expectLater(
      build(adapter).resolvePlayback(song(hash: 'SHORT')),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('song.id 不可解析 → input；不回退 audioId', () async {
    final adapter = _RoutingAdapter(_happyPath);
    await expectLater(
      build(adapter).resolvePlayback(song(id: 'abc', audioId: 9001)),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', contains('信息不完整')),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('albumId 不可解析 → input', () async {
    final adapter = _RoutingAdapter(_happyPath);
    await expectLater(
      build(adapter).resolvePlayback(song(albumId: '')),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });
  test('匿名 user_verify business(35002) → authentication（请先登录）', () async {
    final adapter = _RoutingAdapter((options) {
      if (Uri.parse(options.path).path == '/v1/user_verify') {
        return _json('{"status":0,"error_code":35002}');
      }
      return _happyPath(options);
    });
    await expectLater(
      build(adapter).resolvePlayback(song()),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'authentication')
            .having((error) => error.message, 'message', contains('请先登录'))
            .having((error) => error.code, 'code', 35002),
      ),
    );
    expect(adapter.requests.length, 1, reason: '拿不到授权就不进 song_auth');
  });

  test('已登录账号 user_verify business → 保持 business 并透出错误码', () async {
    api = _FakeMusicApi(
      KugouIdentity(
        userId: 12345,
        token: 'TOKEN',
        t1: '',
        mid: 'mid-123',
        dfid: 'dfid-123',
        uuid: '-',
        guid: 'guid-123',
        mac: '',
        deviceName: '',
        renderFingerprint: '',
      ),
    );
    final adapter = _RoutingAdapter((options) {
      if (Uri.parse(options.path).path == '/v1/user_verify') {
        return _json('{"status":0,"error_code":35002}');
      }
      return _happyPath(options);
    });
    await expectLater(
      build(adapter).resolvePlayback(song()),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 35002),
      ),
    );
    expect(adapter.requests.length, 1);
  });
}
