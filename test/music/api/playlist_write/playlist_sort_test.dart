/// 歌单库排序端点测试：cloud 传输 + 去重校验 + Kind 编解码。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_sort.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

const _seed = 'Qq1W2E3';

PlaylistSortQuery _query({
  int totalRevision = 5,
  List<PlaylistSortPosition> positions = const [],
}) => PlaylistSortQuery(totalRevision: totalRevision, positions: positions);

void main() {
  test('装配：cloud 语义 + 密文 body 与请求同序可解', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse(
        '{"status":1,"error_code":0,"data":{"userid":42,"total_ver":"6",'
        '"list_count":"9","info":[{"listid":1,"type":0,"sort":0,"code":0},'
        '{"listid":2,"type":1,"sort":3,"code":0},{"listid":3,"type":9,"sort":4}]}}',
        _seed,
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    final change = await fetchPlaylistSort(
      session,
      _query(
        positions: [
          const PlaylistSortPosition(
            cloudListId: 1,
            kind: MusicPlaylistKind.owned,
            position: 0,
          ),
          const PlaylistSortPosition(
            cloudListId: 2,
            kind: MusicPlaylistKind.collected,
            position: 3,
          ),
        ],
      ),
      seed: _seed,
    );

    // 位置事实独立保留；type=9 是未知种类：kind 为 null 但 kindCode 保留。
    expect(change.positions, hasLength(3));
    expect(change.positions[0].kind, MusicPlaylistKind.owned);
    expect(change.positions[1].kind, MusicPlaylistKind.collected);
    expect(change.positions[2].kind, isNull);
    expect(change.positions[2].kindCode, 9);
    expect(change.positions[2].position, 4);
    expect(change.totalRevision, 6);
    expect(change.playlistCount, 9);

    final request = adapter.requests.single;
    expect(capturedPath(request), '/v1/modify_list_sort');
    expect(request.headers['x-router'], 'cloudlist.service.kugou.com');
    expect(request.headers['kg-rc'], '1');
    final query = request.query;
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    expect(query.containsKey('uuid'), isFalse);
    expect(query.containsKey('signature'), isFalse);
    expect(query['clienttime'], '1700000000');
    expect(RegExp('^[0-9A-F]{256}\$').hasMatch(query['p']!), isTrue);
    final plain = jsonDecode(
      utf8.decode(
        kugouAesCbcPkcs7(request.data! as Uint8List, _seed, encrypt: false),
      ),
    );
    expect(plain, <String, Object?>{
      'total_ver': 5,
      'data': <Object?>[
        <String, Object?>{'listid': 1, 'type': 0, 'sort': 0},
        <String, Object?>{'listid': 2, 'type': 1, 'sort': 3},
      ],
    });
  });

  test('校验：空集合 / id 为 0 / 重复 id / 同类重复位置 → input', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":1,"error_code":0}', _seed),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    await expectLater(
      fetchPlaylistSort(session, _query(), seed: _seed),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistSort(
        session,
        _query(
          positions: const [
            PlaylistSortPosition(
              cloudListId: 0,
              kind: MusicPlaylistKind.owned,
              position: 1,
            ),
          ],
        ),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    const duplicateId = PlaylistSortPosition(
      cloudListId: 1,
      kind: MusicPlaylistKind.owned,
      position: 1,
    );
    await expectLater(
      fetchPlaylistSort(
        session,
        _query(positions: [duplicateId, duplicateId]),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistSort(
        session,
        _query(
          positions: const [
            PlaylistSortPosition(
              cloudListId: 1,
              kind: MusicPlaylistKind.owned,
              position: 2,
            ),
            PlaylistSortPosition(
              cloudListId: 2,
              kind: MusicPlaylistKind.owned,
              position: 2,
            ),
          ],
        ),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    // 不同类的相同位置是合法的（去重键是 (kind, position)）。
    await fetchPlaylistSort(
      session,
      _query(
        positions: const [
          PlaylistSortPosition(
            cloudListId: 1,
            kind: MusicPlaylistKind.owned,
            position: 2,
          ),
          PlaylistSortPosition(
            cloudListId: 2,
            kind: MusicPlaylistKind.collected,
            position: 2,
          ),
        ],
      ),
      seed: _seed,
    );
    expect(adapter.requests, hasLength(1));
  });

  test('匿名 → authentication；解密失败 → decode；业务失败 → business', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":0,"error_code":311}', _seed),
    );
    final client = playlistWriteClient(adapter);
    final query = _query(
      positions: const [
        PlaylistSortPosition(
          cloudListId: 1,
          kind: MusicPlaylistKind.owned,
          position: 0,
        ),
      ],
    );

    await expectLater(
      fetchPlaylistSort(
        fakePlaylistWriteSession(client, KugouIdentity.anonymous()),
        query,
        seed: _seed,
      ),
      throwsA(kugouError('authentication')),
    );
    await expectLater(
      fetchPlaylistSort(
        fakePlaylistWriteSession(client, playlistWriteIdentity()),
        query,
        seed: _seed,
      ),
      throwsA(kugouError('business', code: 311)),
    );

    final broken = CaptureAdapter(Uint8List.fromList(List.filled(32, 1)));
    await expectLater(
      fetchPlaylistSort(
        fakePlaylistWriteSession(
          playlistWriteClient(broken),
          playlistWriteIdentity(),
        ),
        query,
        seed: _seed,
      ),
      throwsA(kugouError('decode')),
    );
  });
}
