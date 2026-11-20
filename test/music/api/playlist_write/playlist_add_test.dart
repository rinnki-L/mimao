/// 歌单创建/收藏端点测试：明文 JSON 装配（write_params/收藏分支）+ 解码
/// 宽容 + 错误分支。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import '../capture_adapter.dart';
import 'playlist_write_test_support.dart';

void main() {
  test('自建分支：write_params 四参数 + 明文 JSON body 逐字节对齐', () async {
    final adapter = CaptureAdapter(
      jsonBytes(
        '{"status":1,"error_code":0,"data":{"userid":42,"total_ver":1,'
        '"info":{"listid":"555","status":0,"code":0}}}',
      ),
    );
    final client = playlistWriteClient(adapter);
    final session = fakePlaylistWriteSession(client, playlistWriteIdentity());

    final change = await fetchPlaylistAdd(
      session,
      const PlaylistAddQuery(title: '我的歌单', isPrivate: true),
    );

    expect(change.cloudListId, 555);
    expect(change.userId, 42);
    expect(change.totalRevision, 1);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(capturedPath(request), '/cloudlist.service/v5/add_list');
    expect(request.headers['x-router'], isNull);
    // serde_json BTreeMap 字典序（签名覆盖同一字节）。
    expect(
      request.bodyText,
      '{"from_shupinmv":0,"is_pri":1,"list_create_gid":"","name":"我的歌单",'
      '"source":1,"token":"tok-1","total_ver":0,"type":0,"userid":42}',
    );
    final query = request.query;
    expect(query['last_time'], '1700000000');
    expect(query['last_area'], 'gztx');
    expect(query['userid'], '42');
    expect(query['token'], 'tok-1');
    expect(query['signature'], isNotEmpty);
    expect(query['clienttime'], '1700000000');
  });

  test(
    'collection 分支：params 为空、body 覆盖 type/is_pri/source/list_create_*',
    () async {
      final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
      final client = playlistWriteClient(adapter);
      final session = fakePlaylistWriteSession(client, playlistWriteIdentity());

      await fetchPlaylistAdd(
        session,
        const PlaylistAddQuery(
          title: '收藏',
          isPrivate: true,
          collection: PlaylistAddCollection(
            source: 5,
            creatorId: 9,
            creatorListId: 77,
            creatorGlobalId: 'gid-1',
          ),
        ),
      );

      final request = adapter.requests.single;
      final query = request.query;
      expect(query.containsKey('last_time'), isFalse);
      expect(query.containsKey('last_area'), isFalse);
      // 默认参数仍注入（普通签名 request）。
      expect(query['token'], 'tok-1');
      expect(query['userid'], '42');
      expect(
        request.bodyText,
        '{"from_shupinmv":0,"is_pri":0,"list_create_gid":"gid-1",'
        '"list_create_listid":77,"list_create_userid":9,"name":"收藏","source":5,'
        '"token":"tok-1","total_ver":0,"type":1,"userid":42}',
      );
    },
  );

  test('collection 缺 creator_id 时不写 list_create_userid', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final client = playlistWriteClient(adapter);
    final session = fakePlaylistWriteSession(client, playlistWriteIdentity());

    await fetchPlaylistAdd(
      session,
      const PlaylistAddQuery(
        title: '收藏',
        isPrivate: false,
        collection: PlaylistAddCollection(
          source: 2,
          creatorListId: 77,
          creatorGlobalId: 'gid-2',
        ),
      ),
    );

    expect(
      adapter.requests.single.bodyText,
      contains('"list_create_gid":"gid-2"'),
    );
    expect(
      adapter.requests.single.bodyText,
      isNot(contains('list_create_userid')),
    );
  });

  test('解码宽容：数字字符串、缺省 data、info 非法形态', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final client = playlistWriteClient(adapter);
    final session = fakePlaylistWriteSession(client, playlistWriteIdentity());

    final change = await fetchPlaylistAdd(
      session,
      const PlaylistAddQuery(title: '歌单', isPrivate: false),
    );

    expect(change.userId, isNull);
    expect(change.cloudListId, isNull);
    expect(change.providerStatus, isNull);
  });

  test('业务失败 → business 带 code；20017 → authentication', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":0,"error_code":311,"data":{}}'),
    );
    // 按请求序取响应：第 1 次 311、第 2 次 20017。
    adapter.responses
      ..add(jsonBytes('{"status":0,"error_code":311,"data":{}}'))
      ..add(jsonBytes('{"status":0,"error_code":20017,"data":{}}'));
    final client = playlistWriteClient(adapter);
    final session = fakePlaylistWriteSession(client, playlistWriteIdentity());

    await expectLater(
      fetchPlaylistAdd(
        session,
        const PlaylistAddQuery(title: '歌单', isPrivate: false),
      ),
      throwsA(kugouError('business', code: 311)),
    );

    await expectLater(
      fetchPlaylistAdd(
        session,
        const PlaylistAddQuery(title: '歌单', isPrivate: false),
      ),
      throwsA(kugouError('authentication', code: 20017)),
    );
  });

  test('匿名身份 → authentication（cloudlist::account 前置）', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final client = playlistWriteClient(adapter);
    final session = fakePlaylistWriteSession(client, KugouIdentity.anonymous());

    await expectLater(
      fetchPlaylistAdd(
        session,
        const PlaylistAddQuery(title: '歌单', isPrivate: false),
      ),
      throwsA(kugouError('authentication')),
    );
    expect(adapter.requests, isEmpty);
  });

  test('输入校验：空标题 / 超长 / collection listid 为 0', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final client = playlistWriteClient(adapter);
    final session = fakePlaylistWriteSession(client, playlistWriteIdentity());

    await expectLater(
      fetchPlaylistAdd(
        session,
        const PlaylistAddQuery(title: '  ', isPrivate: false),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistAdd(
        session,
        PlaylistAddQuery(title: '歌' * 1025, isPrivate: false),
      ),
      throwsA(kugouError('input')),
    );
    await expectLater(
      fetchPlaylistAdd(
        session,
        const PlaylistAddQuery(
          title: '收藏',
          isPrivate: false,
          collection: PlaylistAddCollection(
            source: 1,
            creatorListId: 0,
            creatorGlobalId: 'g',
          ),
        ),
      ),
      throwsA(kugouError('input')),
    );
    expect(adapter.requests, isEmpty);
  });

  test('KugouPlaylistWriteApi.playlistAdd 委托同一装配', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":1,"error_code":0,"data":{}}'),
    );
    final client = playlistWriteClient(adapter);
    final api = KugouPlaylistWriteApi(
      fakePlaylistWriteSession(client, playlistWriteIdentity()),
    );
    final change = await api.playlistAdd(
      const PlaylistAddQuery(title: '门面', isPrivate: false),
    );
    expect(change.cloudListId, isNull);
    expect(
      capturedPath(adapter.requests.single),
      '/cloudlist.service/v5/add_list',
    );
  });
}
