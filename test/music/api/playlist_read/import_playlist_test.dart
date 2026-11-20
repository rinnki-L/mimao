/// 歌单导入端点测试：六个动作的请求装配（路径/参数/body 键序/clearDefaults
/// 语义）+ 各动作解码 + input/anonymous/business 分支（import_playlist.rs）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/import_playlist.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/playlist_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// 资产服务信封（errcode 字段）。
String assetWire({required Object? data, int status = 1, int errcode = 0}) =>
    jsonEncode(<String, Object?>{
      'status': status,
      'errcode': errcode,
      'data': data,
    });

/// pubsongs 明细信封（error_code 字段）。
String resultWire({required Object? data, int status = 1, int errorCode = 0}) =>
    jsonEncode(<String, Object?>{
      'status': status,
      'error_code': errorCode,
      'data': data,
    });

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity anonymous;
  late KugouIdentity account;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = capturedClient(adapter);
    anonymous = KugouIdentity.anonymous();
    account = accountIdentity();
  });

  /// 断言 URL 只带六个设备/应用字段 + signature（request_import clearDefaults）。
  void expectImportQuery(CapturedRequest request) {
    expect(request.query.keys.toSet(), <String>{
      'appid',
      'clientver',
      'clienttime',
      'dfid',
      'mid',
      'signature',
      'uuid',
    });
    expect(request.query['appid'], '3116');
    expect(request.query['clientver'], '11440');
    expect(request.query['mid'], account.mid);
    expect(request.query['dfid'], account.dfid);
    expect(request.query['uuid'], '-');
  }

  test('匿名 → authentication（所有动作都在动作校验之前拦截）', () async {
    const queries = <MusicImportQuery>[
      MusicImportLinkQuery('not-a-link'),
      MusicImportSubmitImageQuery(taskSn: '', imageBase64: ''),
      MusicImportScreenshotQuery(taskSn: '', cloudListId: 0, title: ''),
      MusicImportStatusQuery(<int>[]),
      MusicImportResultQuery(cloudListId: 0, page: 0, pageSize: 0),
      MusicImportCountQuery(),
    ];
    for (final query in queries) {
      await expectLater(
        fetchImportPlaylist(fakeMusicSession(anonymous, client), query),
        throwsA(
          predicate(
            (Object e) => e is KugouApiException && e.kind == 'authentication',
          ),
        ),
        reason: '$query 应先拦账号',
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('link 请求装配：add_task/body 键序与值/userid 是字符串', () async {
    adapter.bytes = jsonBytes(
      assetWire(
        data: <String, Object?>{
          'userid': 12345,
          'id': 9001,
          'listid': 5566,
          'source': 3,
          'task_type': 0,
          'status': 0,
        },
      ),
    );
    final outcome = await fetchImportPlaylist(
      fakeMusicSession(account, client),
      const MusicImportLinkQuery('https://t1.kugou.com/abc'),
    );
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/assetservice/import/v1/add_task',
      ),
      isTrue,
    );
    expect(request.headers.containsKey('x-router'), isFalse);
    expectImportQuery(request);

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'userid',
      'token',
      'source',
      'task_type',
      'url',
    ]);
    expect(body['userid'], '12345', reason: '导入 body 的 userid 是字符串');
    expect(body['token'], 'token-fixture');
    expect(body['source'], 3);
    expect(body['task_type'], 0);
    expect(body['url'], 'https://t1.kugou.com/abc');

    expect(outcome, isA<MusicImportCreatedOutcome>());
    final task = (outcome as MusicImportCreatedOutcome).task;
    expect(task.taskId, 9001);
    expect(task.userId, 12345);
    expect(task.cloudListId, 5566);
    expect(task.source, 3);
    expect(task.taskType, 0);
    expect(task.status, 0);
    expect(task.title, isEmpty);
    expect(task.message, isEmpty);
  });

  test('screenshot 请求装配：task_type=1/listid 是数字/list_name', () async {
    adapter.bytes = jsonBytes(
      assetWire(
        data: <String, Object?>{'id': 9002, 'listid': 5566, 'status': 1},
      ),
    );
    final outcome = await fetchImportPlaylist(
      fakeMusicSession(account, client),
      const MusicImportScreenshotQuery(
        taskSn: 'sn-001',
        cloudListId: 5566,
        title: '目标歌单',
      ),
    );
    final request = adapter.requests.single;
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/assetservice/import/v1/add_task',
      ),
      isTrue,
    );
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'userid',
      'token',
      'source',
      'task_type',
      'task_sn',
      'listid',
      'list_name',
    ]);
    expect(body['source'], 3);
    expect(body['task_type'], 1);
    expect(body['task_sn'], 'sn-001');
    expect(body['listid'], 5566, reason: 'add_task 的 listid 是数字');
    expect(body['list_name'], '目标歌单');
    expect((outcome as MusicImportCreatedOutcome).task.taskId, 9002);
  });

  test('submit_img 请求装配：img_base64 键；字符串确认 → uploaded', () async {
    adapter.bytes = jsonBytes(assetWire(data: 'done'));
    final outcome = await fetchImportPlaylist(
      fakeMusicSession(account, client),
      const MusicImportSubmitImageQuery(
        taskSn: 'sn-002',
        imageBase64: 'aGVsbG8=',
      ),
    );
    final request = adapter.requests.single;
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/assetservice/import/v1/submit_img',
      ),
      isTrue,
    );
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'userid',
      'token',
      'task_sn',
      'img_base64',
    ]);
    expect(body['task_sn'], 'sn-002');
    expect(body['img_base64'], 'aGVsbG8=');
    expect(
      outcome,
      isA<MusicImportUploadedOutcome>(),
      reason: '上游折叠成 {"uploaded":true}',
    );
  });

  test('status 请求装配：ids 数字数组；任务行解码（type → task_type）', () async {
    adapter.bytes = jsonBytes(
      assetWire(
        data: <Object?>[
          <String, Object?>{
            'userid': 12345,
            'id': 9001,
            'listid': 5566,
            'source': 3,
            'status': 2,
            'name': '我的歌单',
            'songs_num': 50,
            'matched_num': 40,
            'imported_num': 38,
            'missed_num': 2,
            'msg': '部分成功',
            'type': 0,
          },
          <String, Object?>{'id': 9003, 'name': true},
        ],
      ),
    );
    final outcome = await fetchImportPlaylist(
      fakeMusicSession(account, client),
      const MusicImportStatusQuery(<int>[9001, 9003]),
    );
    final request = adapter.requests.single;
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/assetservice/import/v1/query_task_status',
      ),
      isTrue,
    );
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>['userid', 'token', 'ids']);
    expect(body['ids'], <Object?>[9001, 9003]);

    final tasks = (outcome as MusicImportStatusOutcome).tasks;
    expect(tasks, hasLength(2));
    expect(tasks[0].taskId, 9001);
    expect(tasks[0].taskType, 0, reason: 'wire 的 type 键映射 task_type');
    expect(tasks[0].title, '我的歌单');
    expect(tasks[0].total, 50);
    expect(tasks[0].matched, 40);
    expect(tasks[0].imported, 38);
    expect(tasks[0].missed, 2);
    expect(tasks[0].message, '部分成功');
    expect(tasks[1].title, '', reason: 'text 的 bool → 空串');
    expect(tasks[1].total, isNull);
  });

  test('status 解码：data null → 空任务列表', () async {
    adapter.bytes = jsonBytes(assetWire(data: null));
    final outcome = await fetchImportPlaylist(
      fakeMusicSession(account, client),
      const MusicImportStatusQuery(<int>[1]),
    );
    expect((outcome as MusicImportStatusOutcome).tasks, isEmpty);
  });

  test('result 请求装配：query_task/listid 是字符串/show_missed=1', () async {
    adapter.bytes = jsonBytes(
      resultWire(
        data: <String, Object?>{
          'userid': 12345,
          'listid': 5566,
          'id': 9001,
          'source': 3,
          'status': 3,
          'name': '我的歌单',
          'songs_num': 50,
          'imported_num': 48,
          'missed_num': 2,
          'missed': <Object?>[
            <String, Object?>{
              'audio_name': '歌曲甲',
              'author_name': '歌手甲',
              'album_name': '专辑甲',
              'reason': '无版权',
            },
            <String, Object?>{'audio_name': '歌曲乙'},
          ],
        },
      ),
    );
    final outcome = await fetchImportPlaylist(
      fakeMusicSession(account, client),
      const MusicImportResultQuery(cloudListId: 5566, page: 2, pageSize: 50),
    );
    final request = adapter.requests.single;
    expect(
      request.path.startsWith(
        'https://gateway.kugou.com/pubsongs/v1/query_task',
      ),
      isTrue,
    );
    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'userid',
      'token',
      'listid',
      'page',
      'pagesize',
      'show_missed',
    ]);
    expect(body['listid'], '5566', reason: '明细接口的 listid 是字符串');
    expect(body['page'], 2);
    expect(body['pagesize'], 50);
    expect(body['show_missed'], 1);

    final result = (outcome as MusicImportResultOutcome).result;
    expect(result.page, 2);
    expect(result.pageSize, 50);
    expect(result.task.taskId, 9001);
    expect(result.task.cloudListId, 5566);
    expect(result.task.title, '我的歌单');
    expect(result.task.total, 50);
    expect(result.task.imported, 48);
    expect(result.task.missed, 2);
    expect(result.task.matched, isNull, reason: '明细不带 matched');
    expect(result.task.taskType, isNull);
    expect(result.missedTracks, hasLength(2));
    expect(result.missedTracks[0].title, '歌曲甲');
    expect(result.missedTracks[0].artist, '歌手甲');
    expect(result.missedTracks[0].album, '专辑甲');
    expect(result.missedTracks[0].reason, '无版权');
    expect(result.missedTracks[1].artist, '');
  });

  test(
    'count 请求装配：task_count/classify=1 → user_id/count/failed_count',
    () async {
      adapter.bytes = jsonBytes(
        assetWire(
          data: <String, Object?>{'userid': 12345, 'count': 7, 'fail_count': 1},
        ),
      );
      final outcome = await fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportCountQuery(),
      );
      final request = adapter.requests.single;
      expect(
        request.path.startsWith(
          'https://gateway.kugou.com/assetservice/import/v1/task_count',
        ),
        isTrue,
      );
      final body = jsonDecode(request.bodyText) as Map<String, Object?>;
      expect(body.keys.toList(), <String>['userid', 'token', 'classify']);
      expect(body['classify'], 1);

      expect(outcome, isA<MusicImportCountOutcome>());
      final count = outcome as MusicImportCountOutcome;
      expect(count.userId, 12345);
      expect(count.count, 7);
      expect(count.failedCount, 1);
    },
  );

  test('资产服务业务失败（errcode 非零）→ business；20018 → authentication', () async {
    adapter.bytes = jsonBytes(assetWire(status: 0, errcode: 31202, data: null));
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportLinkQuery('https://t1.kugou.com/abc'),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 31202,
        ),
      ),
    );
    // 资产服务的 errcode 不是 request 层的过期键：20018 落在 errcode 字段
    // 时按上游语义走 business（authentication_expiration 只认 error_code）。
    adapter.bytes = jsonBytes(assetWire(status: 0, errcode: 20018, data: null));
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportCountQuery(),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 20018,
        ),
      ),
    );
    // raw error_code=20018 → request 层统一 authentication。
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 0, 'error_code': 20018}),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportCountQuery(),
      ),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
    // 明细接口的过期语义（error_code 键）。
    adapter.bytes = jsonBytes(
      resultWire(status: 0, errorCode: 20018, data: null),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportResultQuery(cloudListId: 1, page: 1, pageSize: 10),
      ),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
  });

  test('资产服务 data 非 object → decode', () async {
    adapter.bytes = jsonBytes(assetWire(data: 5));
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportCountQuery(),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
  });

  test('link input 校验：缺 https:// / URL 超 8192 字节', () async {
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportLinkQuery('http://t1.kugou.com/abc'),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'input' &&
              e.message.contains('分享链接'),
        ),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        MusicImportLinkQuery('https://t1.kugou.com/${'a' * 8193}'),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('submit_img input 校验：task_sn 空/超 128/图片空', () async {
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportSubmitImageQuery(taskSn: '', imageBase64: 'aGk='),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        MusicImportSubmitImageQuery(taskSn: 'a' * 129, imageBase64: 'aGk='),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportSubmitImageQuery(taskSn: 'sn', imageBase64: ''),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
  });

  test('screenshot input 校验：task_sn/歌单/标题', () async {
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportScreenshotQuery(
          taskSn: '',
          cloudListId: 1,
          title: '标题',
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportScreenshotQuery(
          taskSn: 'sn',
          cloudListId: 0,
          title: '标题',
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportScreenshotQuery(
          taskSn: 'sn',
          cloudListId: 1,
          title: '   ',
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        MusicImportScreenshotQuery(
          taskSn: 'sn',
          cloudListId: 1,
          title: '曲' * 513,
        ),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
      reason: '513 个汉字 = 1539 字节 > 1024',
    );
  });

  test('status input 校验：空/超 100/含 0', () async {
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportStatusQuery(<int>[]),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        MusicImportStatusQuery(List<int>.generate(101, (i) => i + 1)),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportStatusQuery(<int>[1, 0, 2]),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
  });

  test('result input 校验：歌单/页码/分页 1..=100', () async {
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportResultQuery(cloudListId: 0, page: 1, pageSize: 10),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportResultQuery(cloudListId: 1, page: 0, pageSize: 10),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
    await expectLater(
      fetchImportPlaylist(
        fakeMusicSession(account, client),
        const MusicImportResultQuery(cloudListId: 1, page: 1, pageSize: 101),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
  });
}
