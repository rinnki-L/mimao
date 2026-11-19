/// song_url_auth（tracker）测试：24 参数、网关主机、key 现算、单位换算、
/// 失败/空地址语义、8 档质量映射。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/song_auth.dart';
import 'package:mimao/music/api/song_url_auth.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/music_models.dart';

import 'capture_adapter.dart';

const String _hash = 'abcdef0123456789abcdef0123456789';

const String _trackerWire =
    '{"status":1,"error_code":0,'
    '"hash":"abcdef0123456789abcdef0123456789",'
    '"url":["https://cdn.example/1.mp3","https://cdn.example/2.mp3"],'
    '"backupUrl":["https://cdn.example/b.mp3"],'
    '"fileSize":1048576,"bitRate":320,"timeLength":181,'
    '"std_hash_time":181000,"extName":"mp3","fileName":"f.mp3",'
    '"fileHead":0,"volume":-6.5,"volume_peak":0.98,"volume_gain":1.5}';

SongAuthorization songAuth() =>
    const SongAuthorization(authorization: 'SONG-AUTH', opensAt: 1700000123);

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(_trackerWire));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<MusicPlaybackSource> resolve({
    MusicQuality quality = MusicQuality.higher,
    String originPage = kugouDefaultOriginPage,
  }) => resolveSongUrl(
    client,
    identity,
    hash: _hash,
    albumId: 42,
    songId: 7301,
    quality: quality,
    songAuth: songAuth(),
    originPage: originPage,
  );

  test('24 个参数逐项存在且值正确；走网关主机 + 签名自验', () async {
    await resolve();

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://gateway.kugou.com/tracker/v5/url?',
      ),
      isTrue,
    );
    final query = capturedQuery(adapter.captured);

    const expected = <String, String>{
      'album_id': '42',
      'area_code': '1',
      'module': '',
      'hash': _hash,
      'need_m': '0',
      'ssa_flag': 'is_fromtrack',
      'version': '11430',
      'open_time': '1700000123',
      'ptype': '0',
      'need_ogg': '1',
      'page_id': '967177915',
      'auth': 'SONG-AUTH',
      'mtype': '0',
      'quality': '320',
      'album_audio_id': '7301',
      'behavior': 'play',
      'pid': '411',
      'module_id': '51',
      'cmd': '26',
      'ppage_id': '356753938,823673182,967485191',
      'clientver': '11561',
      'pidversion': '3001',
      'cdnBackup': '1',
    };
    for (final entry in expected.entries) {
      expect(query[entry.key], entry.value, reason: '参数 ${entry.key}');
    }
    expect(query['key'], kugouTrackerKey(_hash, identity.mid, identity.userId));

    // 24 个协议参数 + 传输默认（appid/clientver/clienttime/dfid/mid/uuid）
    // + signature。
    expect(expected.length + 1, 24, reason: 'map 里 23 项 + 单独断言的 key');
    expect(
      query.length,
      30,
      reason: '24 协议参数 + 5 个额外默认（clientver 被端点覆盖）+ signature',
    );
    final signature = query.remove('signature');
    expect(signature, kugouSignatureAndroid(query, const <int>[]));
  });

  test('ppage_id 可被调用方覆盖；album_audio_id 用 songId', () async {
    await resolve(originPage: '1,2,3');
    expect(capturedQuery(adapter.captured)['ppage_id'], '1,2,3');
  });

  test('解码：timeLength 秒→毫秒；std_hash_time 原样（不乘 1000）', () async {
    final source = await resolve();
    expect(source.durationMs, 181000);
    expect(source.standardDurationMs, 181000);
    expect(source.hash, _hash);
    expect(source.urls, <String>[
      'https://cdn.example/1.mp3',
      'https://cdn.example/2.mp3',
    ]);
    expect(source.primaryUrl, 'https://cdn.example/1.mp3');
    expect(source.backupUrls, <String>['https://cdn.example/b.mp3']);
    expect(source.fileSizeBytes, 1048576);
    expect(source.bitRateBps, 320);
    expect(source.extension, 'mp3');
    expect(source.fileName, 'f.mp3');
    expect(source.fileHead, 0);
    expect(source.loudness, -6.5);
    expect(source.peak, 0.98);
    expect(source.gain, 1.5);
  });

  test('status != 1 → business 且 code 透出（常见 20010）', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":20010}');
    await expectLater(
      resolve(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'business')
            .having((error) => error.code, 'code', 20010),
      ),
    );
  });

  test('status == 1 但 url 为空 → business（产品约束，提前失败）', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"hash":"$_hash","url":[]}',
    );
    await expectLater(
      resolve(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'business',
        ),
      ),
    );
  });

  test('质量映射：8 个枚举值逐一断言（automatic→128）', () {
    expect(trackerQuality(MusicQuality.standard), '128');
    expect(trackerQuality(MusicQuality.higher), '320');
    expect(trackerQuality(MusicQuality.flac), 'flac');
    expect(trackerQuality(MusicQuality.hiRes), 'high');
    expect(trackerQuality(MusicQuality.viperTape), 'viper_tape');
    expect(trackerQuality(MusicQuality.viperClear), 'viper_clear');
    expect(trackerQuality(MusicQuality.viperAtmos), 'viper_atmos');
    expect(trackerQuality(MusicQuality.automatic), '128');
  });
}
