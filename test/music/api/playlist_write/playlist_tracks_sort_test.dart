/// 云歌单曲目排序端点测试：cloud 传输 + 去重校验 + 返回 fileid/sort 独立。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_tracks_sort.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

const _seed = 'Tt4R5Y6';

PlaylistTracksSortQuery _query({List<PlaylistTrackSortPosition>? positions}) =>
    PlaylistTracksSortQuery(
      cloudListId: 7,
      revision: 4,
      positions:
          positions ??
          const [
            PlaylistTrackSortPosition(fileId: 11, position: 2),
            PlaylistTrackSortPosition(fileId: 12, position: 5),
          ],
    );

void main() {
  test('装配：cloud 语义 + 密文 body（listid/list_ver/type/data）', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse(
        '{"status":1,"error_code":0,"data":{"userid":42,"listid":"7",'
        '"pre_list_ver":"3","list_ver":"5","count":"2",'
        '"info":[{"sort":5,"fileid":12,"code":0},{"sort":2,"fileid":11,"code":0}]}}',
        _seed,
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    final change = await fetchPlaylistTracksSort(
      session,
      _query(),
      seed: _seed,
    );

    // 返回的 fileid/sort 对独立于请求顺序保留（上游注释）。
    expect(change.outcomes, hasLength(2));
    expect(change.outcomes![0].fileId, 12);
    expect(change.outcomes![0].position, 5);
    expect(change.outcomes![1].fileId, 11);
    expect(change.outcomes![1].songId, isNull);
    expect(change.revision, 5);
    expect(change.previousRevision, 3);
    expect(change.replacedFileIds, isNull);

    final request = adapter.requests.single;
    expect(capturedPath(request), '/v1/modify_song_sort');
    expect(request.headers['x-router'], 'cloudlist.service.kugou.com');
    expect(request.headers['kg-rc'], '1');
    expect(request.headers['kg-rf'], 'B9EDA08A64250DEFFBCADDEE00F8F25F');
    final query = request.query;
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    expect(query.containsKey('uuid'), isFalse);
    expect(query.containsKey('signature'), isFalse);
    expect(query['key'], 'bad0ee207bf429bd91402b77fc8f7a5b');
    expect(RegExp('^[0-9A-F]{256}\$').hasMatch(query['p']!), isTrue);
    final plain = jsonDecode(
      utf8.decode(
        kugouAesCbcPkcs7(request.data! as Uint8List, _seed, encrypt: false),
      ),
    );
    expect(plain, <String, Object?>{
      'listid': 7,
      'list_ver': 4,
      'type': 0,
      'data': <Object?>[
        <String, Object?>{'fileid': 11, 'sort': 2},
        <String, Object?>{'fileid': 12, 'sort': 5},
      ],
    });
  });

  test('校验：空集合 / fileid 为 0 / 重复 id / 重复位置 → input', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":1,"error_code":0}', _seed),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    await expectLater(
      fetchPlaylistTracksSort(
        session,
        PlaylistTracksSortQuery(
          cloudListId: 7,
          revision: 4,
          positions: const [],
        ),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksSort(
        session,
        _query(
          positions: const [PlaylistTrackSortPosition(fileId: 0, position: 1)],
        ),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    const same = PlaylistTrackSortPosition(fileId: 11, position: 1);
    await expectLater(
      fetchPlaylistTracksSort(
        session,
        _query(positions: [same, same]),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistTracksSort(
        session,
        _query(
          positions: const [
            PlaylistTrackSortPosition(fileId: 11, position: 1),
            PlaylistTrackSortPosition(fileId: 12, position: 1),
          ],
        ),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    expect(adapter.requests, isEmpty);
  });

  test('匿名 → authentication；解密失败 → decode；业务失败 → business', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":0,"error_code":311}', _seed),
    );
    final client = playlistWriteClient(adapter);

    await expectLater(
      fetchPlaylistTracksSort(
        fakePlaylistWriteSession(client, KugouIdentity.anonymous()),
        _query(),
        seed: _seed,
      ),
      throwsA(kugouError('authentication')),
    );
    await expectLater(
      fetchPlaylistTracksSort(
        fakePlaylistWriteSession(client, playlistWriteIdentity()),
        _query(),
        seed: _seed,
      ),
      throwsA(kugouError('business', code: 311)),
    );

    final broken = CaptureAdapter(Uint8List.fromList(List.filled(32, 1)));
    await expectLater(
      fetchPlaylistTracksSort(
        fakePlaylistWriteSession(
          playlistWriteClient(broken),
          playlistWriteIdentity(),
        ),
        _query(),
        seed: _seed,
      ),
      throwsA(kugouError('decode')),
    );
  });
}
