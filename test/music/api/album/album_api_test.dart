/// 专辑组门面测试：KugouAlbumApi 四个方法都转发到同一条会话（装配即证据）。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/album_api.dart';
import 'package:mimao/music/api/album_dycover.dart';
import 'package:mimao/music/api/album_songs.dart';
import 'package:mimao/music/client/kugou_client.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouAlbumApi api;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    api = KugouAlbumApi(fakeMusicSession(client));
  });

  test('四个方法都走同一会话发出请求', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    expect(await api.albumDetail(8890), isNull);
    expect(adapter.requests[0].path, 'https://gateway.kugou.com/kmr/v2/albums');

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    expect(
      await api.albumDycover(const AlbumDycoverQuery(albumAudioId: 7301)),
      isNull,
    );
    expect(
      adapter.requests[1].path,
      'https://kmrcdn.service.kugou.com/v2/album/audio',
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"total":0},"extra":{}}',
    );
    final tracks = await api.albumSongs(const AlbumSongsQuery(id: 42));
    expect(tracks.page.items, isEmpty);
    expect(
      adapter.requests[2].path,
      'https://gateway.kugou.com/v1/album_audio/lite',
    );

    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{"list":[]}}');
    expect(await api.favoriteCount(<int>[1]), isEmpty);
    expect(
      adapter.requests[3].path,
      'https://gateway.kugou.com/count/v1/audio/mget_collect',
    );
  });
}
