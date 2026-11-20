/// 听歌等级端点测试（user_grade_info.rs）：10597 盐 key / 10597 专用
/// 头与 Content-Type / 匿名查他人 / data 解码。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_grade_info.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
  });

  test('请求装配：只带 dfid 的 query/10597 头组/body 键序与字符串 appid', () async {
    // 匿名 + 显式 user_id：查询他人等级不要求登录（上游注释）。
    final identity = anonymousIdentity();
    final session = fakeSession(fixedClient(adapter), identity);
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"p_grade":9}}',
    );
    await fetchUserGradeInfo(session, const MusicUserGradeQuery(userId: 77));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v2/get_grade_info');
    expect(request.headers['x-router'], 'userinfo.user.kugou.com');
    // request_grade（cloud+clearDefaults）：URL 只有 dfid，无签名。
    expect(request.query, <String, String>{'dfid': identity.dfid});
    // 端点自有 Content-Type 与 UA；thash 是 7 位小写 hex。
    expect(request.headers['Content-Type'], 'text/plain; charset=ISO-8859-1');
    expect(
      request.headers['User-Agent'],
      'Android15-1070-10597-201-0-get_user_grade_info-wifi',
    );
    expect(request.headers['KG-Rec'], '1');
    expect(request.headers['KG-RC'], '1');
    expect(
      RegExp(r'^[0-9a-f]{7}$').hasMatch('${request.headers['KG-THash']}'),
      isTrue,
    );
    expect(request.headers['clienttime'], isNull);

    final body = capturedJsonBody(request);
    expect(body.keys.toList(), const <String>[
      'appid',
      'clienttime',
      'clientver',
      'key',
      'mid',
      'p',
      'type',
      'userid',
      'uuid',
    ]);
    // 此端点 appid/clientver 是字符串（与 user_info 的数字不同）。
    expect(body['appid'], '3116');
    expect(body['clientver'], '10597');
    expect(body['clienttime'], kFixedSeconds);
    expect(body['type'], 1);
    expect(body['userid'], 77);
    expect(body['uuid'], identity.uuid);
    expect(body['mid'], identity.mid);
    expect(
      body['key'],
      md5
          .convert(
            utf8.encode(
              '3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA10597$kFixedSeconds',
            ),
          )
          .toString(),
    );
    final portrait = body['p'] as String;
    expect(portrait, hasLength(256));
    expect(RegExp(r'^[0-9A-F]{256}$').hasMatch(portrait), isTrue);
    // p 明文 = {"clienttime":<秒>,"userid":<查询目标>}。
    expect(
      portrait,
      expectedPortrait(<String, Object?>{
        'clienttime': kFixedSeconds,
        'userid': 77,
      }),
    );
  });

  test('user_id 缺省取当前账号；注入随机可复现 thash', () async {
    final identity = accountIdentity();
    final session = fakeSession(fixedClient(adapter), identity);
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    await fetchUserGradeInfo(
      session,
      const MusicUserGradeQuery(),
      random: Random(42),
    );
    final body = capturedJsonBody(adapter.requests.single);
    expect(body['userid'], 421337);

    // 独立复算 Random(42) 的 u32 & 0x0fffffff。
    final source = Random(42);
    final value =
        (source.nextInt(256) << 24) |
        (source.nextInt(256) << 16) |
        (source.nextInt(256) << 8) |
        source.nextInt(256);
    expect(
      adapter.requests.single.headers['KG-THash'],
      (value & 0x0FFFFFFF).toRadixString(16).padLeft(7, '0'),
    );
  });

  test('user_id=0（含匿名缺省）→ input 账号不存在；负数 → input', () async {
    final anonymousSession = fakeSession(
      fixedClient(adapter),
      anonymousIdentity(),
    );
    await expectLater(
      fetchUserGradeInfo(anonymousSession, const MusicUserGradeQuery()),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'input')
            .having((e) => e.message, 'message', '账号不存在'),
      ),
    );
    await expectLater(
      fetchUserGradeInfo(
        anonymousSession,
        const MusicUserGradeQuery(userId: 0),
      ),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'input')
            .having((e) => e.message, 'message', '账号不存在'),
      ),
    );
    await expectLater(
      fetchUserGradeInfo(
        anonymousSession,
        const MusicUserGradeQuery(userId: -1),
      ),
      throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', 'input')),
    );
    expect(adapter.requests, isEmpty);
  });

  test('解码：等级/成长值字段 + 数字字符串宽容', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{'
      '"userid":"421337","p_grade":"9","d_sec":36000,'
      '"p_current_point":100,"p_grade_point":900,'
      '"p_next_grade_point":"1200","p_next_grade":10}}',
    );
    final grade = await fetchUserGradeInfo(
      session,
      const MusicUserGradeQuery(userId: 421337),
    );
    expect(grade.userId, 421337);
    expect(grade.grade, 9);
    expect(grade.listeningSeconds, 36000);
    expect(grade.currentPoints, 100);
    expect(grade.gradePoints, 900);
    expect(grade.nextGradePoints, 1200);
    expect(grade.nextGrade, 10);
  });

  test('业务失败 → business 带码；data:null → decode', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes('{"status":0,"error_code":473,"data":{}}');
    await expectLater(
      fetchUserGradeInfo(session, const MusicUserGradeQuery(userId: 1)),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 473),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    await expectLater(
      fetchUserGradeInfo(session, const MusicUserGradeQuery(userId: 1)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
