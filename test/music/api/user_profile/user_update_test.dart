/// 资料更新端点测试（user_update.rs）：字段校验 / cloud+clearDefaults 语义 / 回执。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_update.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
  });

  group('fields 校验（user_update.rs fields）', () {
    void expectInput(MusicUserUpdateQuery query, String message) {
      try {
        query.collectFields();
        fail('应当抛 input：$message');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
        expect(e.message, message);
      }
    }

    test('性别越界/负数 → 性别无效', () {
      expectInput(const MusicUserUpdateQuery(gender: 3), '性别无效');
      expectInput(const MusicUserUpdateQuery(gender: -1), '性别无效');
    });

    test('昵称/省市空串 → 资料字段不能为空；signature/birthday 允许空串', () {
      expectInput(const MusicUserUpdateQuery(nickname: ''), '资料字段不能为空');
      expectInput(const MusicUserUpdateQuery(province: ''), '资料字段不能为空');
      expectInput(const MusicUserUpdateQuery(city: ''), '资料字段不能为空');
      // 清除语义：空 signature/birthday 合法。
      expect(
        const MusicUserUpdateQuery(signature: '').collectFields(),
        <String, String>{'signature': ''},
      );
      expect(
        const MusicUserUpdateQuery(birthday: '').collectFields(),
        <String, String>{'birthday': ''},
      );
    });

    test('个性签名按 UTF-16 码元计量，>120 → input', () {
      expectInput(MusicUserUpdateQuery(signature: 'x' * 121), '个性签名最多120个字符');
      // 代理对（emoji）占 2 个码元：60 个 emoji=120 合法，61 个=122 超限。
      expect(
        MusicUserUpdateQuery(signature: '😀' * 60).collectFields()['signature'],
        '😀' * 60,
      );
      expectInput(MusicUserUpdateQuery(signature: '😀' * 61), '个性签名最多120个字符');
    });

    test('无变化 → 资料没有变化', () {
      expectInput(const MusicUserUpdateQuery(), '资料没有变化');
    });
  });

  test('请求装配：cloud+clearDefaults（空 query 无签名）+ body 键序', () async {
    final identity = accountIdentity();
    final session = fakeSession(fixedClient(adapter), identity);
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":""}');
    final result = await fetchUserUpdate(
      session,
      const MusicUserUpdateQuery(nickname: '新昵称', gender: 2),
    );
    expect(result.updated, isTrue);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v1/update_userinfo');
    expect(request.headers['x-router'], 'update.user.kugou.com');
    // request_grade：URL 无任何默认参数、无 token/userid、无签名。
    expect(request.query, isEmpty);
    expect(request.headers['clienttime'], isNull);
    expect(request.headers['dfid'], identity.dfid);
    expect(request.headers['mid'], identity.mid);
    expect(request.headers['Content-Type'], 'application/json');

    final body = capturedJsonBody(request);
    expect(body.keys.toList(), const <String>[
      'appid',
      'clienttime',
      'clientver',
      'data',
      'key',
      'mid',
      'p',
      'userid',
      'uuid',
    ]);
    expect(body['appid'], 3116);
    expect(body['clientver'], 11440);
    expect(body['clienttime'], kFixedSeconds);
    expect(body['uuid'], '-');
    expect(body['userid'], 421337);
    expect(
      body['key'],
      md5
          .convert(
            utf8.encode(
              '3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA11440$kFixedSeconds',
            ),
          )
          .toString(),
    );
    expect(
      body['p'],
      expectedPortrait(<String, Object?>{
        'clienttime': kFixedSeconds,
        'token': 'fixture-token',
      }),
    );
    // data 是 BTreeMap：序列化键序按字典序（sex 排在 nickname 前）。
    final data = Map<String, Object?>.from(body['data']! as Map);
    expect(data.keys.toList(), const <String>['nickname', 'sex']);
    expect(data['nickname'], '新昵称');
    expect(data['sex'], '2');
  });

  test('匿名 + 合法输入 → authentication（来自 submit_fields）', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    await expectLater(
      fetchUserUpdate(session, const MusicUserUpdateQuery(nickname: '昵称')),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('校验先于登录：匿名 + 非法输入 → input（不是 authentication）', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    await expectLater(
      fetchUserUpdate(session, const MusicUserUpdateQuery(gender: 9)),
      throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', 'input')),
    );
    expect(adapter.requests, isEmpty);
  });

  test('业务失败 → business 带码', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes('{"status":0,"error_code":30201,"data":""}');
    await expectLater(
      fetchUserUpdate(session, const MusicUserUpdateQuery(signature: '签名')),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 30201),
      ),
    );
  });
}
