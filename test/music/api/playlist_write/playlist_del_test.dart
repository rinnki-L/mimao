/// 歌单删除端点测试：信封装配（base64 body + keyed_time 黄金向量）+
/// 密文可解 + 解码回退 + 错误分支。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_del.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

const _seed = 'A1b2C3';

void main() {
  test('装配：p 大写 256 位 hex、keyed_time 黄金向量、body 为可解密文', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse(
        '{"status":1,"error_code":0,"data":{"userid":42,'
        '"info":[{"listid":123,"status":0,"code":0}]}}',
        _seed,
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    final change = await fetchPlaylistDel(
      session,
      const PlaylistDelQuery(cloudListId: 123),
      seed: _seed,
    );

    expect(change.cloudListId, 123);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(capturedPath(request), '/v2/delete_list');
    expect(request.headers['x-router'], 'cloudlist.service.kugou.com');
    final query = request.query;
    // 普通签名 request：uuid/token/userid 都在，signature 恒有。
    expect(query['uuid'], '-');
    expect(query['token'], 'tok-1');
    expect(query['userid'], '42');
    expect(query['signature'], isNotEmpty);
    expect(query['clienttime'], '1700000000');
    expect(query['last_area'], 'gztx');
    expect(query['last_time'], '1700000000');
    // 上游黄金向量：cloudlist::keyed_time(1700000000)。
    expect(query['key'], 'bad0ee207bf429bd91402b77fc8f7a5b');
    expect(RegExp('^[0-9A-F]{256}\$').hasMatch(query['p']!), isTrue);
    // body 是 base64 密文，同 seed 可解。
    final plain = utf8.decode(
      kugouAesCbcPkcs7(base64Decode(request.bodyText), _seed, encrypt: false),
    );
    expect(jsonDecode(plain), <String, Object?>{
      'listid': 123,
      'total_ver': 0,
      'type': 1,
    });
  });

  test('解码：info 首项 listid 缺省回退请求 id；数字字符串宽容', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse(
        '{"status":1,"error_code":0,"data":{"userid":"42",'
        '"pre_total_ver":"7","total_ver":"8","list_count":"2","info":[]}}',
        _seed,
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    final change = await fetchPlaylistDel(
      session,
      const PlaylistDelQuery(cloudListId: 999),
      seed: _seed,
    );

    expect(change.cloudListId, 999);
    expect(change.userId, 42);
    expect(change.previousTotalRevision, 7);
    expect(change.totalRevision, 8);
    expect(change.playlistCount, 2);
    expect(change.providerStatus, isNull);
    expect(change.resourceCode, isNull);
  });

  test('解密失败（响应不是该 seed 的密文）→ decode', () async {
    final adapter = CaptureAdapter(Uint8List.fromList(List.filled(64, 0x11)));
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    await expectLater(
      fetchPlaylistDel(
        session,
        const PlaylistDelQuery(cloudListId: 123),
        seed: _seed,
      ),
      throwsA(kugouError('decode')),
    );
  });

  test('匿名 → authentication；id=0 → input；业务失败 → business', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":0,"error_code":311}', _seed),
    );
    final client = playlistWriteClient(adapter);
    final anonymousSession = fakePlaylistWriteSession(
      client,
      KugouIdentity.anonymous(),
    );
    await expectLater(
      fetchPlaylistDel(
        anonymousSession,
        const PlaylistDelQuery(cloudListId: 123),
        seed: _seed,
      ),
      throwsA(kugouError('authentication')),
    );

    final session = fakePlaylistWriteSession(client, playlistWriteIdentity());
    await expectLater(
      fetchPlaylistDel(
        session,
        const PlaylistDelQuery(cloudListId: 0),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistDel(
        session,
        const PlaylistDelQuery(cloudListId: 123),
        seed: _seed,
      ),
      throwsA(kugouError('business', code: 311)),
    );
    expect(adapter.requests, hasLength(1));
  });
}
