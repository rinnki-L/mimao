/// sidedt 测试：verification 信封/指纹 AES 的上游黄金向量、请求装配（键序化
/// 请求体 + 签名自验）、指纹结构、WireNumber/strict_optional 解码分支与
/// input 校验。
///
/// 2048 位验证公钥的模数提取：SPKI PEM 经 `openssl rsa -pubin -modulus` 解出
/// （上游 include_str!("verification-public-key.pem") 的同一把钥匙）。
library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/sidedt.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
    session = fakeMusicSession(client, identity);
  });

  test('黄金向量：verification 信封（上游 parameter_envelope_with_seed, None 分支）', () {
    final (pk, params) = kugouSidedtVerificationEnvelopeWithSeed(
      <String, Object?>{'code': '123456'},
      '0123456789abcdef',
    );
    expect(
      pk,
      '8f00be7ef062ab4a56be2cce9177273c52ff9c37cd2534deb222cffd3f9d024425e520fef4fde78d48a6661f1814e13ecbb1dce7937417ae356fa21d097e11dd1a9f55b28f94715f9df841a2e8b0413974f157a1c64fc9e7c7c611d4dda8b37e58d27fc7266df185b68b2a2fbcc1e1c2b46242a68409d63d8879772bf7bb4735',
      reason: '裸 RSA（lite 公钥）+ 大写 hex + 转小写，逐字符对拍',
    );
    expect(
      params,
      'f6b8a061ddc6d8b1abb7222ae9d44b489e9f3f405c5a336864661bf8af172a65',
      reason: 'AES-256-CBC-PKCS7（key/iv = md5(seed) hex 的 ASCII 字节）+ 小写 hex',
    );
  });

  test('黄金向量：指纹 AES（上游 generate_simulate 的 cryptojs 对拍向量）', () {
    final encrypted = kugouSidedtAesCbcPkcs7(
      utf8.encode('native-fingerprint-golden'),
      utf8.encode('0123456789abcdef'),
      kugouSidedtAesIv,
    );
    expect(
      base64Encode(encrypted),
      'KRTM4dgOPoV8Yj9lLvQp8wNMJcGgTTx6ruq1m5hHyno=',
      reason: 'AES-128-CBC + PKCS7，IV 固定 kugousecurity123',
    );
  });

  test('指纹明文模板：mid/userid/dfid/webgl/webdriver/ts/data 逐段对拍', () {
    final identity = KugouIdentity.anonymous();
    final plaintext = sidedtFingerprintPlaintext(
      identity,
      fingerprint: 'fixture-fp',
      events: const <String>['5,0,0:5,4294967295,0', '3,7,1,512,128'],
      nowMilliseconds: 1700000000123,
    );
    expect(
      plaintext,
      'mid=${identity.mid};userid=0;dfid=-;webgl=fixture-fp;webdriver=0;'
      'ts=1700000000123;data=5,0,0:5,4294967295,0:3,7,1,512,128',
    );
  });

  test(
    '请求装配（verify_type=23）：verifyservice/v4/verify_user_info + 键序化请求体 + 签名自验',
    () async {
      adapter.bytes = jsonBytes('{"status":1,"error_code":0}');
      final ack = await fetchSideDt(
        session,
        const MusicSideDtQuery(
          eventId: 'event-1',
          verifyType: 23,
          proof: 'proof-1',
        ),
        random: Random(7),
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(ack.acknowledged, isTrue);

      expect(
        '${adapter.captured.uri}'.startsWith(
          'https://verifyservice.kugou.com/v4/verify_user_info?',
        ),
        isTrue,
      );
      expect(adapter.captured.method, 'POST');
      expect(adapter.captured.headers.containsKey('x-router'), isFalse);
      expect(adapter.captured.headers['Content-Type'], 'application/json');
      final query = capturedQuery(adapter.captured);
      expect(query['clientver'], '11510');
      expect(
        query.length,
        7,
        reason: 'clientver + 5 传输默认 + signature（匿名无 token/userid）',
      );
      final signature = query.remove('signature');
      expect(
        signature,
        kugouSignatureAndroid(
          query,
          utf8.encode(adapter.requests.last.bodyText),
        ),
      );

      // 请求体键序与 serde_json BTreeMap 一致；23 走 verifycode 键。
      final body =
          jsonDecode(adapter.requests.last.bodyText) as Map<String, Object?>;
      expect(
        adapter.requests.last.bodyText.indexOf('"verifycode"'),
        lessThan(adapter.requests.last.bodyText.indexOf('"wasm"')),
        reason: '键按字典序：verifycode 位于 userid 之后、wasm 之前',
      );
      expect(body.keys, <String>[
        'edt',
        'eventid',
        'i',
        'params',
        'pk',
        'platid',
        'sid',
        'v_type',
        'userid',
        'verifycode',
        'wasm',
      ]);
      expect(body['eventid'], 'event-1');
      expect(body['platid'], 2);
      expect(body['v_type'], 23);
      expect(body['wasm'], 1);
      expect(body['i'], '');
      expect(body['userid'], 0);

      // 指纹/信封结构：pk 256 位小写 hex；params 偶长 hex；sid 2048 位 RSA 密文；
      // edt 是 16 字节对齐的 AES 密文。
      final pk = body['pk']! as String;
      expect(pk, matches(RegExp(r'^[0-9a-f]{256}$')));
      expect(body['params'], matches(RegExp(r'^(?:[0-9a-f]{2})+$')));
      final sid = base64Decode(body['sid']! as String);
      expect(sid, hasLength(256), reason: '2048 位 RSA-OAEP 输出 256 字节');
      final edt = base64Decode(body['edt']! as String);
      expect(edt.length % 16, 0, reason: 'AES-CBC 密文按块对齐');
    },
  );

  test('请求装配（verify_type=32）：code 键进信封与请求体', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0}');
    await fetchSideDt(
      session,
      const MusicSideDtQuery(
        eventId: 'event-2',
        verifyType: 32,
        proof: '123456',
      ),
      random: Random(7),
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final body =
        jsonDecode(adapter.requests.last.bodyText) as Map<String, Object?>;
    expect(body.keys.first, 'code', reason: '"code" 字典序最先');
    expect(body['code'], '123456');
    expect(body.containsKey('verifycode'), isFalse);
    expect(body['v_type'], 32);
    // 信封明文同样带 code：params 由 {"code":"123456"} 加密而来（黄金向量路径）。
    expect(body['params'], matches(RegExp(r'^(?:[0-9a-f]{2})+$')));
  });

  test(
    'convert：status 文本宽容 / err_code、errcode 回退键 / business / authentication / decode',
    () async {
      adapter.bytes = jsonBytes('{"status":"1","error_code":"0"}');
      expect(
        (await fetchSideDt(
          session,
          const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
        )).acknowledged,
        isTrue,
        reason: 'WireNumber 接受整数字符串',
      );

      adapter.bytes = jsonBytes('{"status":1,"err_code":152}');
      await expectLater(
        fetchSideDt(
          session,
          const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 152,
          ),
        ),
        reason: 'error_code 缺失回退到 err_code',
      );

      adapter.bytes = jsonBytes('{"status":1,"errcode":7}');
      await expectLater(
        fetchSideDt(
          session,
          const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 7,
          ),
        ),
      );

      adapter.bytes = jsonBytes('{"status":0,"error_code":0}');
      await expectLater(
        fetchSideDt(
          session,
          const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 0,
          ),
        ),
        reason: 'status!=1 → business(0)',
      );

      adapter.bytes = jsonBytes('{"status":1,"error_code":20018}');
      await expectLater(
        fetchSideDt(
          session,
          const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
        ),
        throwsA(
          predicate(
            (Object e) => e is KugouApiException && e.kind == 'authentication',
          ),
        ),
      );

      adapter.bytes = jsonBytes('{"status":1,"error_code":"12x"}');
      await expectLater(
        fetchSideDt(
          session,
          const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
        reason: 'strict_optional：错误键提供了但读不出来 → decode，不吞成成功',
      );

      adapter.bytes = jsonBytes('{"status":"x","error_code":0}');
      await expectLater(
        fetchSideDt(
          session,
          const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    },
  );

  test('input：空事件/超长 proof/非法 verify_type → input', () async {
    for (final query in const <MusicSideDtQuery>[
      MusicSideDtQuery(eventId: '  ', verifyType: 23, proof: 'p'),
      MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: ' '),
      MusicSideDtQuery(eventId: 'e', verifyType: 24, proof: 'p'),
      MusicSideDtQuery(eventId: 'e', verifyType: 0, proof: 'p'),
    ]) {
      expect(
        () => query.validate(),
        throwsA(
          predicate((Object e) => e is KugouApiException && e.kind == 'input'),
        ),
      );
    }
    // 合法边界。
    const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p').validate();
    const MusicSideDtQuery(eventId: 'e', verifyType: 32, proof: 'p').validate();
    final longProof = 'x' * 16384;
    MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: longProof).validate();
    final tooLongProof = 'x' * 16385;
    expect(
      () => MusicSideDtQuery(
        eventId: 'e',
        verifyType: 23,
        proof: tooLongProof,
      ).validate(),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'input'),
      ),
    );
  });
}
