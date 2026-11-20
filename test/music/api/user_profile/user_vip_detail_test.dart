/// 联合会员端点测试（user_vip_detail.rs）：装配 / ISO 时间归一 / 边界。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_vip_detail.dart';
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
      fetchUserVipDetail(session),
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

  test('请求装配：vip 主机/GET/busi_type=concept/常规签名', () async {
    final identity = accountIdentity();
    final session = fakeSession(fixedClient(adapter), identity);
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"userid":421337}}',
    );
    await fetchUserVipDetail(session);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, 'https://kugouvip.kugou.com/v1/get_union_vip');
    // request_endpoint：无 x-router（router=None），常规签名 + 默认参数。
    expect(request.headers.containsKey('x-router'), isFalse);
    expect(request.headers.containsKey('Content-Type'), isFalse);
    final query = request.query;
    expect(query['busi_type'], 'concept');
    expect(query['appid'], '3116');
    expect(query['clientver'], '11440');
    expect(query['token'], 'fixture-token');
    expect(query['userid'], '421337');
    expect(query['uuid'], '-');
    expect(query.containsKey('signature'), isTrue);
  });

  test('解码：会员概览 + 产品列表 + active/active_code 链', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{'
      '"userid":"421337","vip_type":"6","user_type":33,'
      '"vip_begin_time":"2025-01-02 03:04:05","su_vip_begin_time":"",'
      '"vip_end_time":"2026-01-02 03:04:05","su_vip_end_time":"长期",'
      '"busi_vip":[{"is_vip":1,"product_type":"luxury","busi_type":"concept",'
      '"vip_begin_time":"2025-01-02 03:04:05","vip_end_time":"2026-01-02 03:04:05"},'
      '{"is_vip":0,"product_type":"super","busi_type":"book"},'
      '{"is_vip":5,"product_type":"unknown"}]}}',
    );
    final memberships = await fetchUserVipDetail(session);
    expect(memberships.userId, 421337);
    expect(memberships.vipTypeCode, 6);
    expect(memberships.userTypeCode, 33);
    // 「YYYY-MM-DD HH:MM:SS」→ ISO 本地时间（空格换 T）。
    expect(memberships.deluxeBeginsAt, '2025-01-02T03:04:05');
    expect(memberships.deluxeExpiresAt, '2026-01-02T03:04:05');
    // 空文本 → null；非 ASCII 不改写。
    expect(memberships.superBeginsAt, isNull);
    expect(memberships.superExpiresAt, '长期');

    expect(memberships.products, hasLength(3));
    expect(memberships.products[0].active, isTrue);
    expect(memberships.products[0].activeCode, 1);
    expect(memberships.products[0].product, 'luxury');
    expect(memberships.products[0].business, 'concept');
    expect(memberships.products[0].beginsAt, '2025-01-02T03:04:05');
    expect(memberships.products[1].active, isFalse);
    expect(memberships.products[1].activeCode, 0);
    // 未知码保留未知，不臆造布尔（numeric::boolean）。
    expect(memberships.products[2].active, isNull);
    expect(memberships.products[2].activeCode, 5);
    expect(memberships.products[2].beginsAt, isNull);
  });

  test('业务失败 → business 带码；data:null → decode', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes('{"status":0,"error_code":4001,"data":{}}');
    await expectLater(
      fetchUserVipDetail(session),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 4001),
      ),
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":null}');
    await expectLater(
      fetchUserVipDetail(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('产品项非 object → decode（不静默丢弃）', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"busi_vip":[1]}}',
    );
    await expectLater(
      fetchUserVipDetail(session),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
