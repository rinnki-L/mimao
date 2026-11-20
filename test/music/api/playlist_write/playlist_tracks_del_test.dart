/// 云歌单删歌端点测试：空 params 装配（默认参数 + 签名 + router）+ 去重
/// 校验 + 最小解码。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_tracks_del.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

void main() {
  test('装配：params 为空（无 last_time/key/p），router 指向 cloudlist', () async {
    final adapter = CaptureAdapter(
      jsonBytes(
        '{"status":1,"error_code":0,"data":{"userid":42,"listid":"7",'
        '"status":0,"pre_list_ver":"3","list_ver":"4","count":"0"}}',
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    final change = await fetchPlaylistTracksDel(
      session,
      const PlaylistTracksDelQuery(cloudListId: 7, fileIds: [11, 12]),
    );

    expect(change.cloudListId, 7);
    expect(change.revision, 4);
    expect(change.songCount, 0);
    expect(change.outcomes, isNull);
    expect(change.replacedFileIds, isNull);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(capturedPath(request), '/v4/delete_songs');
    expect(request.headers['x-router'], 'cloudlist.service.kugou.com');
    final query = request.query;
    // 上游传空 params 表：只有默认参数与签名。
    expect(query.keys.toList()..sort(), <String>[
      'appid',
      'clienttime',
      'clientver',
      'dfid',
      'mid',
      'signature',
      'token',
      'userid',
      'uuid',
    ]);
    expect(query['uuid'], '-');
    expect(query['signature'], isNotEmpty);
    expect(
      request.bodyText,
      '{"data":[{"fileid":11},{"fileid":12}],"list_ver":0,"listid":7,'
      '"token":"tok-1","type":0,"userid":42}',
    );
  });

  test('校验：空/超 300、fileid 为 0、重复 → input', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    await expectLater(
      fetchPlaylistTracksDel(
        session,
        const PlaylistTracksDelQuery(cloudListId: 7, fileIds: []),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksDel(
        session,
        PlaylistTracksDelQuery(
          cloudListId: 7,
          fileIds: List.generate(301, (index) => index + 1),
        ),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksDel(
        session,
        const PlaylistTracksDelQuery(cloudListId: 7, fileIds: [11, 0]),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksDel(
        session,
        const PlaylistTracksDelQuery(cloudListId: 7, fileIds: [11, 11]),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksDel(
        session,
        const PlaylistTracksDelQuery(cloudListId: 0, fileIds: [11]),
      ),
      throwsA(kugouError('input')),
    );
    expect(adapter.requests, isEmpty);
  });

  test('匿名 → authentication；业务失败 → business', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":0,"error_code":311}'));
    final client = playlistWriteClient(adapter);
    await expectLater(
      fetchPlaylistTracksDel(
        fakePlaylistWriteSession(client, KugouIdentity.anonymous()),
        const PlaylistTracksDelQuery(cloudListId: 7, fileIds: [11]),
      ),
      throwsA(kugouError('authentication')),
    );
    await expectLater(
      fetchPlaylistTracksDel(
        fakePlaylistWriteSession(client, playlistWriteIdentity()),
        const PlaylistTracksDelQuery(cloudListId: 7, fileIds: [11]),
      ),
      throwsA(kugouError('business', code: 311)),
    );
    expect(adapter.requests, hasLength(1));
  });
}
