/// 批量作者会员端点测试（user_batch_union_vipinfo.rs）：
/// 1..20 校验 / 签名装配 / busi_vip map 解码（字典序、flatten、宽容语义）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_batch_union_vipinfo.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
  });

  test('数量校验：空/21 → input；负数 id → input', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    for (final bad in <List<int>>[const <int>[], List<int>.filled(21, 1)]) {
      await expectLater(
        fetchUserBatchUnionVipinfo(session, bad),
        throwsA(
          isA<KugouApiException>()
              .having((e) => e.kind, 'kind', 'input')
              .having((e) => e.message, 'message', '作者会员每批最多20人'),
        ),
      );
    }
    await expectLater(
      fetchUserBatchUnionVipinfo(session, const <int>[-1]),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'input')
            .having((e) => e.message, 'message', '作者用户 id 无效'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('请求装配：vip 主机/body 键序/匿名签名（无 token）', () async {
    final identity = anonymousIdentity();
    final session = fakeSession(fixedClient(adapter), identity);
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"busi_vip":{}}}',
    );
    await fetchUserBatchUnionVipinfo(session, const <int>[1, 2, 3]);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://kugouvip.kugou.com/v2/batch_union_vipinfo');
    expect(request.headers['Content-Type'], 'application/json; charset=utf-8');
    expect(request.headers.containsKey('x-router'), isFalse);
    final query = request.query;
    // request_endpoint：常规默认参数 + 签名；匿名身份不注入 token/userid。
    expect(query['appid'], '3116');
    expect(query['clientver'], '11440');
    expect(query['dfid'], identity.dfid);
    expect(query['uuid'], '-');
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    expect(query.containsKey('signature'), isTrue);

    final body = capturedJsonBody(request);
    expect(body.keys.toList(), const <String>[
      'busi_type',
      'clientappid',
      'get_type',
      'useridlist',
    ]);
    expect(body['busi_type'], 'concept');
    expect(body['clientappid'], '');
    expect(body['get_type'], '2');
    expect(body['useridlist'], const <int>[1, 2, 3]);
  });

  test('解码：按 user_id 字典序展开 + 产品映射 + flatten 保留未知字段', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"busi_vip":{'
      '"2":[{"product_type":"concept","is_vip":1,"y_type":"0","extra":"x","level":null}],'
      '"10":[{"product_type":"book","is_vip":0}]}}}',
    );
    final products = await fetchUserBatchUnionVipinfo(session, const <int>[
      2,
      10,
    ]);
    // BTreeMap 迭代序：字符串字典序（"10" < "2"）。
    expect(products.map((p) => p.userId).toList(), const <String>['10', '2']);

    final first = products[0].products.single;
    expect(first.product, 'book');
    expect(first.activeCode, 0);
    expect(first.active, isFalse);
    expect(first.yearCode, isNull);
    expect(first.extension, isEmpty);

    final second = products[1].products.single;
    expect(second.activeCode, 1);
    expect(second.active, isTrue);
    expect(second.yearCode, 0);
    // flatten：除 product_type/is_vip/y_type 外原样保留（含 null）。
    expect(second.extension, <String, Object?>{'extra': 'x', 'level': null});
  });

  test('宽容语义：data 缺失/非对象/busi_vip 非法 → 空列表（不 decode）', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    const success = '{"status":1,"error_code":0,';
    for (final tail in const <String>[
      '"data":null}',
      '"data":"x"}',
      '"data":[]}',
      '"data":{"busi_vip":[]}}',
      '"data":{"busi_vip":{"1":1}}}',
      '"data":{"busi_vip":{"1":[1]}}}',
    ]) {
      adapter.bytes = jsonBytes('$success$tail');
      final products = await fetchUserBatchUnionVipinfo(session, const <int>[
        1,
      ]);
      expect(products, isEmpty, reason: tail);
    }
  });

  test('业务失败 → business 带码；status 缺失 → decode', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    adapter.bytes = jsonBytes('{"status":0,"error_code":7}');
    await expectLater(
      fetchUserBatchUnionVipinfo(session, const <int>[1]),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 7),
      ),
    );

    adapter.bytes = jsonBytes('{"error_code":0}');
    await expectLater(
      fetchUserBatchUnionVipinfo(session, const <int>[1]),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('error_code 缺省视为 0（Wire 默认字段语义）', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    adapter.bytes = jsonBytes(
      '{"status":1,"data":{"busi_vip":{"1":[{"product_type":"concept"}]}}}',
    );
    final products = await fetchUserBatchUnionVipinfo(session, const <int>[1]);
    expect(products.single.products.single.product, 'concept');
  });
}
