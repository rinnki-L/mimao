/// 主页资料端点测试（user_detail.rs）：装配（struct 字段序）/ 完整映射 / 边界。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_detail.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
  });

  test('匿名 → authentication，不发起请求', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    await expectLater(
      fetchUserDetail(session),
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

  test('请求装配：usercenter router/plat=1/struct 字段序/秒级 p', () async {
    final identity = accountIdentity();
    final session = fakeSession(fixedClient(adapter), identity);
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"nickname":"昵称"}}',
    );
    await fetchUserDetail(session);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v3/get_my_info');
    expect(request.headers['x-router'], 'usercenter.kugou.com');
    expect(request.headers['Content-Type'], 'application/json');
    final query = request.query;
    expect(query['plat'], '1');
    expect(query['token'], 'fixture-token');
    expect(query['userid'], '421337');
    expect(query.containsKey('signature'), isTrue);

    final body = capturedJsonBody(request);
    // Body struct 声明序：visit_time/usertype/p/userid（非字典序）。
    expect(body.keys.toList(), const <String>[
      'visit_time',
      'usertype',
      'p',
      'userid',
    ]);
    expect(body['visit_time'], kFixedSeconds);
    expect(body['usertype'], 1);
    expect(body['userid'], 421337);
    final portrait = body['p'] as String;
    expect(portrait, hasLength(256));
    // Portrait struct 声明序：token 在前、clienttime（秒）在后。
    expect(
      portrait,
      expectedPortrait(<String, Object?>{
        'token': 'fixture-token',
        'clienttime': kFixedSeconds,
      }),
    );
  });

  test('解码：资料全字段 + 认证身份事实（含负数旧星标）', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{'
      '"nickname":"昵称","pic":"http://img/{size}/a.png",'
      '"gender":"1","vip_type":6,"follows":"10","fans":20,'
      '"descri":"简介","friends":30,"p_grade":"8","duration":99,'
      '"hvisitors":5,"rtime":1600000000,'
      '"province":"广东","city":"深圳","loc":"广东·深圳","birthday":"2000-01-01",'
      '"kq_talent":3,"actor_status":1,"biz_status":0,"tme_star_status":"1",'
      '"singer_status":0,"is_star":-1,'
      '"auth_info":"原创歌手，认证A","auth_info_talent":"","auth_info_singer":"X"}}',
    );
    final profile = await fetchUserDetail(session);
    expect(profile.id, 421337);
    expect(profile.nickname, '昵称');
    expect(profile.gender, 1);
    expect(profile.vipType, 6);
    expect(profile.follows, 10);
    expect(profile.fans, 20);
    expect(profile.biography, '简介');
    expect(profile.friends, 30);
    expect(profile.grade, 8);
    expect(profile.listeningMinutes, 99);
    expect(profile.visitors, 5);
    expect(profile.registeredAtSeconds, 1600000000);
    expect(profile.province, '广东');
    expect(profile.city, '深圳');
    expect(profile.ipLocation, '广东·深圳');
    expect(profile.birthday, '2000-01-01');
    final identity = profile.identity;
    expect(identity.actorCode, 1);
    expect(identity.businessCode, 0);
    expect(identity.starCode, 1);
    expect(identity.singerCode, 0);
    expect(identity.legacyStarCode, -1);
    expect(identity.talentBits, 3);
    expect(identity.actor, isTrue);
    expect(identity.business, isFalse, reason: '码 0 不算认证');
    expect(identity.star, isTrue);
    expect(identity.singer, isFalse, reason: '两个歌手标志都不是 1');
    expect(identity.authorizations, const <String>['原创歌手', '认证A']);
    expect(identity.talentAuthorizations, isEmpty);
    expect(identity.singerAuthorizations, const <String>['X']);
  });

  test('歌手标志：is_star=1 时旧标志也点亮 singer', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"is_star":1}}',
    );
    final profile = await fetchUserDetail(session);
    expect(profile.identity.singer, isTrue);
    expect(profile.identity.actor, isFalse);
  });

  test('status=0 + 20018（data:null）→ authentication', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes('{"status":0,"error_code":20018,"data":null}');
    await expectLater(
      fetchUserDetail(session),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );
  });

  test('业务失败 → business 带码；data:null → decode', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes('{"status":0,"error_code":451,"data":{}}');
    await expectLater(
      fetchUserDetail(session),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 451),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    await expectLater(
      fetchUserDetail(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
