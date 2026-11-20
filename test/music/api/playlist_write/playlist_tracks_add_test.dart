/// 云歌单加歌端点测试：明文 JSON 装配（逐字节）+ hash/数量校验 + 逐项结果
/// 与 del_fileids 宽容解码。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_tracks_add.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

const _track = PlaylistTrackInput(
  title: '歌',
  hash: '0123456789abcdef0123456789ABCDEF',
  albumId: 9,
  songId: 3,
);

void main() {
  test('装配：write_params + body 逐字节（scene/slow_upload/逐项字段）', () async {
    final adapter = CaptureAdapter(
      jsonBytes(
        '{"status":1,"error_code":0,"data":{"userid":42,"listid":"7",'
        '"status":0,"pre_list_ver":"3","list_ver":"4","count":"1",'
        '"info":[{"fileid":11,"mixsongid":3,"code":0}]}}',
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    final change = await fetchPlaylistTracksAdd(
      session,
      const PlaylistTracksAddQuery(cloudListId: 7, tracks: [_track]),
    );

    expect(change.cloudListId, 7);
    expect(change.providerStatus, 0);
    expect(change.previousRevision, 3);
    expect(change.revision, 4);
    expect(change.songCount, 1);
    expect(change.outcomes, hasLength(1));
    expect(change.outcomes!.single.fileId, 11);
    expect(change.outcomes!.single.songId, 3);
    expect(change.replacedFileIds, isNull);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(capturedPath(request), '/cloudlist.service/v6/add_song');
    expect(request.headers['x-router'], isNull);
    // hash 大小写原样上送；字段按 BTreeMap 字典序。
    expect(
      request.bodyText,
      '{"data":[{"album_id":9,"bitrate":0,"hash":"0123456789abcdef0123456789ABCDEF",'
      '"mixsongid":3,"name":"歌","number":1,"size":0,"sort":0,"timelen":0}],'
      '"list_ver":0,"listid":7,"scene":"false;null","slow_upload":1,'
      '"token":"tok-1","type":0,"userid":42}',
    );
    final query = request.query;
    expect(query['last_time'], '1700000000');
    expect(query['last_area'], 'gztx');
    expect(query['userid'], '42');
    expect(query['token'], 'tok-1');
    expect(query['signature'], isNotEmpty);
  });

  test('del_fileids：数组逐项宽容（坏项为 null），非数组/缺省 → null', () async {
    final adapter = CaptureAdapter(Uint8List(0));
    // 按请求序：第 1 次返回数组，第 2 次返回非数组对象。
    adapter.responses
      ..add(
        jsonBytes(
          '{"status":1,"error_code":0,"data":{"listid":7,'
          '"del_fileids":[1,"2",null,"x"]}}',
        ),
      )
      ..add(
        jsonBytes('{"status":1,"error_code":0,"data":{"del_fileids":{"a":1}}}'),
      );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );
    final change = await fetchPlaylistTracksAdd(
      session,
      const PlaylistTracksAddQuery(cloudListId: 7, tracks: [_track]),
    );
    expect(change.replacedFileIds, <int?>[1, 2, null, null]);

    // 第 2 次请求：del_fileids 不是数组 → null（未知，不是失败）。
    final withoutArray = await fetchPlaylistTracksAdd(
      session,
      const PlaylistTracksAddQuery(cloudListId: 7, tracks: [_track]),
    );
    expect(withoutArray.replacedFileIds, isNull);
  });

  test('逐项 code=206/fileid=0 也只是结果事实，不判失败', () async {
    final adapter = CaptureAdapter(
      jsonBytes(
        '{"status":1,"error_code":0,"data":{"listid":7,'
        '"info":[{"fileid":0,"mixsongid":3,"code":206}]}}',
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );
    final change = await fetchPlaylistTracksAdd(
      session,
      const PlaylistTracksAddQuery(cloudListId: 7, tracks: [_track]),
    );
    expect(change.outcomes!.single.fileId, 0);
    expect(change.outcomes!.single.resourceCode, 206);
  });

  test('校验：空/超 300 首、空标题、31 位与非 hex hash → input', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );
    const query = PlaylistTracksAddQuery(cloudListId: 7, tracks: [_track]);

    await expectLater(
      fetchPlaylistTracksAdd(
        session,
        const PlaylistTracksAddQuery(cloudListId: 7, tracks: []),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksAdd(
        session,
        PlaylistTracksAddQuery(
          cloudListId: 7,
          tracks: List.generate(301, (_) => _track),
        ),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksAdd(
        session,
        const PlaylistTracksAddQuery(
          cloudListId: 7,
          tracks: [
            PlaylistTrackInput(
              title: ' ',
              hash: '0123456789abcdef0123456789ABCDEF',
              albumId: 9,
              songId: 3,
            ),
          ],
        ),
      ),
      throwsA(kugouError('input')),
    );
    for (final hash in <String>[
      '0123456789abcdef0123456789abcde',
      '0123456789abcdef0123456789abcdeg',
    ]) {
      await expectLater(
        fetchPlaylistTracksAdd(
          session,
          PlaylistTracksAddQuery(
            cloudListId: 7,
            tracks: [
              PlaylistTrackInput(title: '歌', hash: hash, albumId: 9, songId: 3),
            ],
          ),
        ),
        throwsA(kugouError('input')),
        reason: hash,
      );
    }
    // 300 首是合法上限。
    await fetchPlaylistTracksAdd(
      session,
      PlaylistTracksAddQuery(
        cloudListId: 7,
        tracks: List.generate(300, (_) => _track),
      ),
    );
    expect(adapter.requests, hasLength(1));
    expect(query, isNotNull);
  });

  test('匿名 → authentication；id=0 → input；业务失败 → business', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":0,"error_code":311}'));
    final client = playlistWriteClient(adapter);
    await expectLater(
      fetchPlaylistTracksAdd(
        fakePlaylistWriteSession(client, KugouIdentity.anonymous()),
        const PlaylistTracksAddQuery(cloudListId: 7, tracks: [_track]),
      ),
      throwsA(kugouError('authentication')),
    );
    await expectLater(
      fetchPlaylistTracksAdd(
        fakePlaylistWriteSession(client, playlistWriteIdentity()),
        const PlaylistTracksAddQuery(cloudListId: 0, tracks: [_track]),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksAdd(
        fakePlaylistWriteSession(client, playlistWriteIdentity()),
        const PlaylistTracksAddQuery(cloudListId: 7, tracks: [_track]),
      ),
      throwsA(kugouError('business', code: 311)),
    );
    expect(adapter.requests, hasLength(1));
  });
}
