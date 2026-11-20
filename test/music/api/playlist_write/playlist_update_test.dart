/// 歌单编辑端点测试：cloud 传输语义（无 token/userid/uuid/签名、密文 body、
/// 固定头）+ 封面引用校验 + 解码。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_update.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

const _seed = 'Zz9Yx8';

void main() {
  test('装配：cloud 模式 query 无 token/userid/uuid/签名，body 为可解密文', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse(
        '{"status":1,"error_code":0,"data":{"userid":42,"total_ver":"6",'
        '"info":{"listid":7,"status":0,"code":0,"pic":"http://img/{size}/c.png"}}}',
        _seed,
      ),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    final change = await fetchPlaylistUpdate(
      session,
      const PlaylistUpdateQuery(
        cloudListId: 7,
        totalRevision: 5,
        sortIndex: 3,
        title: '新名',
        description: '简介',
        tags: '流行',
        coverReference: 'custom/abc-1.png',
      ),
      seed: _seed,
    );

    // pic 非空 → cover_url（{size} → 240）。
    expect(change.coverUrl, 'http://img/240/c.png');
    expect(change.totalRevision, 6);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(capturedPath(request), '/v1/modify_list');
    expect(request.headers['x-router'], 'cloudlist.service.kugou.com');
    expect(request.headers['kg-rc'], '1');
    expect(request.headers['kg-thash'], '5d816a0');
    expect(request.headers['kg-rec'], '1');
    expect(request.headers['kg-rf'], 'B9EDA08A64250DEFFBCADDEE00F8F25F');
    expect(request.headers['Content-Type'], 'application/json;charset=utf-8');
    final query = request.query;
    expect(query.keys.toList()..sort(), <String>[
      'appid',
      'clienttime',
      'clientver',
      'dfid',
      'key',
      'mid',
      'p',
    ]);
    expect(query['key'], 'bad0ee207bf429bd91402b77fc8f7a5b');
    expect(RegExp('^[0-9A-F]{256}\$').hasMatch(query['p']!), isTrue);
    // body 是二进制密文，同 seed 可解；字段与覆盖逐条对齐。
    final plain = jsonDecode(
      utf8.decode(
        kugouAesCbcPkcs7(request.data! as Uint8List, _seed, encrypt: false),
      ),
    );
    expect(plain, <String, Object?>{
      'intro': '简介',
      'listid': 7,
      'name': '新名',
      'pic': 'custom/abc-1.png',
      'sort': 3,
      'tags': '流行',
      'total_ver': 5,
      'type': 0,
    });
  });

  test('kind=collected → type=1；缺省封面/标题不写 name/pic', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":1,"error_code":0}', _seed),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    await fetchPlaylistUpdate(
      session,
      const PlaylistUpdateQuery(
        cloudListId: 7,
        kind: MusicPlaylistKind.collected,
        totalRevision: 5,
        sortIndex: -1,
        description: '',
        tags: '',
      ),
      seed: _seed,
    );

    final plain = jsonDecode(
      utf8.decode(
        kugouAesCbcPkcs7(
          adapter.requests.single.data! as Uint8List,
          _seed,
          encrypt: false,
        ),
      ),
    );
    expect(plain, <String, Object?>{
      'intro': '',
      'listid': 7,
      'sort': -1,
      'tags': '',
      'total_ver': 5,
      'type': 1,
    });
  });

  test('封面引用校验：custom/ 合法名通过，URL/空名/坏字符拒绝', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":1,"error_code":0}', _seed),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );
    const query = (
      cloudListId: 7,
      totalRevision: 5,
      sortIndex: 0,
      description: '',
      tags: '',
    );

    await fetchPlaylistUpdate(
      session,
      PlaylistUpdateQuery(
        cloudListId: query.cloudListId,
        totalRevision: query.totalRevision,
        sortIndex: query.sortIndex,
        description: query.description,
        tags: query.tags,
        coverReference: 'custom/a_b-C9.png',
      ),
      seed: _seed,
    );
    expect(adapter.requests, hasLength(1));

    for (final bad in <String>[
      'http://img/a.png',
      'custom/.png',
      'custom/坏.png',
      'custom/a.png ',
      'customs/a.png',
    ]) {
      await expectLater(
        fetchPlaylistUpdate(
          session,
          PlaylistUpdateQuery(
            cloudListId: query.cloudListId,
            totalRevision: query.totalRevision,
            sortIndex: query.sortIndex,
            description: query.description,
            tags: query.tags,
            coverReference: bad,
          ),
          seed: _seed,
        ),
        throwsA(kugouError('input')),
        reason: bad,
      );
    }
    expect(adapter.requests, hasLength(1));
  });

  test('输入校验顺序：description 含 NUL / title 为空 / id 为 0 → input', () async {
    final adapter = CaptureAdapter(
      sealCloudListResponse('{"status":1,"error_code":0}', _seed),
    );
    final session = fakePlaylistWriteSession(
      playlistWriteClient(adapter),
      playlistWriteIdentity(),
    );

    await expectLater(
      fetchPlaylistUpdate(
        session,
        const PlaylistUpdateQuery(
          cloudListId: 7,
          totalRevision: 5,
          sortIndex: 0,
          description: 'a\x00b',
          tags: '',
        ),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistUpdate(
        session,
        const PlaylistUpdateQuery(
          cloudListId: 7,
          totalRevision: 5,
          sortIndex: 0,
          title: ' ',
          description: '',
          tags: '',
        ),
        seed: _seed,
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistUpdate(
        session,
        const PlaylistUpdateQuery(
          cloudListId: 0,
          totalRevision: 5,
          sortIndex: 0,
          description: '',
          tags: '',
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
    final anonymousSession = fakePlaylistWriteSession(
      client,
      KugouIdentity.anonymous(),
    );
    await expectLater(
      fetchPlaylistUpdate(
        anonymousSession,
        const PlaylistUpdateQuery(
          cloudListId: 7,
          totalRevision: 5,
          sortIndex: 0,
          description: '',
          tags: '',
        ),
        seed: _seed,
      ),
      throwsA(kugouError('authentication')),
    );

    final session = fakePlaylistWriteSession(client, playlistWriteIdentity());
    await expectLater(
      fetchPlaylistUpdate(
        session,
        const PlaylistUpdateQuery(
          cloudListId: 7,
          totalRevision: 5,
          sortIndex: 0,
          description: '',
          tags: '',
        ),
        seed: _seed,
      ),
      throwsA(kugouError('business', code: 311)),
    );

    final broken = CaptureAdapter(Uint8List.fromList(List.filled(32, 1)));
    await expectLater(
      fetchPlaylistUpdate(
        fakePlaylistWriteSession(
          playlistWriteClient(broken),
          playlistWriteIdentity(),
        ),
        const PlaylistUpdateQuery(
          cloudListId: 7,
          totalRevision: 5,
          sortIndex: 0,
          description: '',
          tags: '',
        ),
        seed: _seed,
      ),
      throwsA(kugouError('decode')),
    );
  });
}
