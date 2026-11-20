/// 用户身份标签端点测试（user_info.rs）：装配 / key·p 协议 / 标签拆分 / 边界。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_info.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// user_protocol.rs timestamp_key：固定盐 + 毫秒。
String expectedKey(int milliseconds) => md5
    .convert(
      utf8.encode('3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA11440$milliseconds'),
    )
    .toString();

void main() {
  late CaptureAdapter adapter;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
  });

  test('匿名 → authentication，不发起请求', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    await expectLater(
      fetchUserInfo(session),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'authentication')
            .having((e) => e.message, 'message', '请先登录'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('请求装配：relation 主机/router/默认参数注入/毫秒 key/p', () async {
    final identity = accountIdentity();
    final session = fakeSession(fixedClient(adapter), identity);
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"tags":"摇滚"}}',
    );
    await fetchUserInfo(session);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    // client.request() 固定网关主机；relation.user.kugou.com 是 x-router。
    expect(request.path, 'https://gateway.kugou.com/v1/get_my_userinfo');
    expect(request.headers['x-router'], 'relation.user.kugou.com');
    expect(request.headers['Content-Type'], 'application/json');
    expect(request.headers['clienttime'], '$kFixedSeconds');
    expect(request.headers['dfid'], identity.dfid);
    expect(request.headers['mid'], identity.mid);

    final query = request.query;
    expect(query['appid'], '3116');
    expect(query['clientver'], '11440');
    expect(query['clienttime'], '$kFixedSeconds');
    expect(query['dfid'], identity.dfid);
    expect(query['mid'], identity.mid);
    expect(query['uuid'], '-');
    expect(query['token'], 'fixture-token');
    expect(query['userid'], '421337');
    // 常规签名（request → cloud=false, clearDefaults=false）。
    expect(query.containsKey('signature'), isTrue);

    final body = capturedJsonBody(request);
    // json! BTreeMap 字典序键序。
    expect(body.keys.toList(), const <String>[
      'appid',
      'clienttime',
      'clientver',
      'key',
      'mid',
      'p',
      'source',
      'userid',
      'uuid',
    ]);
    expect(body['appid'], 3116);
    expect(body['clientver'], 11440);
    expect(body['source'], 0);
    // clienttime 是**毫秒**（user_info.rs unix_milliseconds）。
    expect(body['clienttime'], kFixedMilliseconds);
    expect(body['uuid'], '-');
    expect(body['userid'], 421337);
    expect(body['mid'], identity.mid);
    expect(body['key'], expectedKey(kFixedMilliseconds));
    final portrait = body['p'] as String;
    expect(portrait, hasLength(256));
    expect(RegExp(r'^[0-9A-F]{256}$').hasMatch(portrait), isTrue);
    // p 明文 = {"clienttime":<ms>,"token":…}（json! 字典序）。
    expect(
      portrait,
      expectedPortrait(<String, Object?>{
        'clienttime': kFixedMilliseconds,
        'token': 'fixture-token',
      }),
    );
  });

  test('解码：学生身份 + 标签拆分（顺序/去重/空段）', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{'
      '"student_status":"2",'
      '"student_school":"测试大学",'
      '"student_expire_time":"2026-08-01",'
      '"tags":" 摇滚，旅行、摇滚; English 中文；\\n  "}}',
    );
    final tags = await fetchUserInfo(session);
    expect(tags.studentStatus, 2);
    expect(tags.studentSchool, '测试大学');
    expect(tags.studentExpireTime, '2026-08-01');
    // identity_labels：多分隔符、trim、去空、按序去重。
    expect(tags.tags, const <String>['摇滚', '旅行', 'English 中文']);
  });

  test('解码宽容：optional 非法 → null；text 布尔 → 空；数字 → 文本', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{'
      '"student_status":[1],"student_school":true,"tags":123}}',
    );
    final tags = await fetchUserInfo(session);
    expect(tags.studentStatus, isNull, reason: '数组对 optional 非法 → null');
    expect(tags.studentSchool, '', reason: '布尔对 text 反序列化失败 → 空串');
    expect(tags.tags, const <String>['123'], reason: '数字按文本拆分');
  });

  test('data:null / data 非对象 → decode', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    await expectLater(
      fetchUserInfo(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":"x"}');
    await expectLater(
      fetchUserInfo(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('业务失败 → business 带码；20018 → authentication', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes('{"status":0,"error_code":152,"data":{}}');
    await expectLater(
      fetchUserInfo(session),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 152),
      ),
    );

    adapter.bytes = jsonBytes('{"status":0,"error_code":20018,"data":null}');
    await expectLater(
      fetchUserInfo(session),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });
}
