/// 验证码提交端点测试：AES 黄金向量对拍、SID/EDT 本地生成（固定随机源可解）、
/// OAEP-SHA256 回环、23/32 的 code/verifycode 键差异、三键回退与业务/解码分支。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:mimao/music/api/verify_user_info.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:pointycastle/export.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

const String kTestSeed = '0123456789abcdef';
final DateTime kFixedNow = DateTime.fromMillisecondsSinceEpoch(
  1764000000000,
  isUtc: true,
);

/// 全零随机源：让指纹生成完全确定（事件取下界、jitter 全负、熵全零）。
class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

Uint8List _decryptEdt(String edtBase64, String keyText) {
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    false,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      ParametersWithIV<KeyParameter>(
        KeyParameter(utf8.encode(keyText)),
        utf8.encode('kugousecurity123'),
      ),
      null,
    ),
  );
  return cipher.process(base64Decode(edtBase64));
}

void main() {
  late CaptureAdapter adapter;
  late HostCaptureAdapter hostAdapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(Uint8List(0));
    hostAdapter = HostCaptureAdapter(adapter);
    client = KugouClient(dio: Dio()..httpClientAdapter = hostAdapter);
    identity = accountIdentity();
  });

  test('AES 黄金向量：与上游 generate_simulate.rs 测试逐字节一致', () {
    final encrypted = kugouSimulateAesCbcBase64(
      utf8.encode('native-fingerprint-golden'),
      utf8.encode('0123456789abcdef'),
      utf8.encode('kugousecurity123'),
    );
    expect(encrypted, 'KRTM4dgOPoV8Yj9lLvQp8wNMJcGgTTx6ruq1m5hHyno=');
  });

  test('指纹生成（固定随机源）：EDT 用派生密钥可解、明文形状对齐上游', () {
    final fingerprint = kugouGenerateVerifyFingerprint(
      identity,
      random: _ZeroRandom(),
      now: () => kFixedNow,
    );
    // 全零熵 → key = md5(16 个 0x00) hex 的前 16 个 ASCII 字符。
    final keyText = md5.convert(Uint8List(16)).toString().substring(0, 16);
    final plain = utf8.decode(_decryptEdt(fingerprint.edt, keyText));
    expect(
      plain,
      matches(
        RegExp(
          r'^mid=\d+;userid=9007199254741005;dfid=-;webgl=0;webdriver=0;'
          r'ts=1764000000000;data=',
        ),
      ),
    );
    // 全零随机源下事件取下界，序列首段可精确对拍。
    expect(
      plain,
      contains(
        'data=5,0,0:5,4294967295,0:5,0,0:5,4294967295,0:6,5,0,750,500:'
        '6,4294967295,0,750,500:5,85,1:5,4294967295,1:',
      ),
    );
    // SID：2048-bit 公钥的 OAEP 密文 → base64 解出 256 字节。
    final sidBytes = base64Decode(fingerprint.sid);
    expect(sidBytes, hasLength(256));
  });

  test('render_fingerprint 非空时原样进入 webgl 字段', () {
    final withPrint = identity.copyWithRenderFingerprintForTest('render-42');
    final fingerprint = kugouGenerateVerifyFingerprint(
      withPrint,
      random: _ZeroRandom(),
      now: () => kFixedNow,
    );
    final keyText = md5.convert(Uint8List(16)).toString().substring(0, 16);
    final plain = utf8.decode(_decryptEdt(fingerprint.edt, keyText));
    expect(plain, contains(';webgl=render-42;webdriver=0;'));
  });

  test('OAEP-SHA256 原语可解性：临时 RSA 密钥对回环解出同一密钥', () {
    final secureRandom = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List<int>.generate(32, (i) => i & 0xff)),
        ),
      );
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom<RSAKeyGeneratorParameters>(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 64),
          secureRandom,
        ),
      );
    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    final key = utf8.encode('0123456789abcdef');
    final encrypted = kugouVerifyOaepSha256Encrypt(key, publicKey);
    expect(encrypted, hasLength(128));

    final decryptor = OAEPEncoding.withSHA256(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final decrypted = decryptor.process(encrypted);
    expect(utf8.decode(decrypted), '0123456789abcdef');
  });

  test('请求装配（type=32）：verifyservice 主机、clientver=11510、body 键序', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    const query = MusicVerifyUserInfoQuery(
      eventId: 'event-1',
      verifyType: 32,
      proof: 'proof-123',
    );
    final ack = await fetchVerifyUserInfo(
      sessionFor(client, identity),
      query,
      fingerprint: const MusicVerifyFingerprint(
        sid: 'sid-sample',
        edt: 'edt-sample',
      ),
      seed: kTestSeed,
      now: () => kFixedNow,
    );
    expect(ack.acknowledged, isTrue);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, endsWith('/v4/verify_user_info'));
    expect(hostAdapter.uris.single.host, 'verifyservice.kugou.com');
    expect(request.headers['x-router'], isNull);
    expect(request.query['clientver'], '11510');
    expectValidAndroidSignature(request);

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
      'code',
      'edt',
      'eventid',
      'i',
      'params',
      'pk',
      'platid',
      'sid',
      'v_type',
      'userid',
      'wasm',
    ]);
    // type=32：验证码进 body 的 code 键 + 加密 envelope {"code": proof}。
    expect(body['code'], 'proof-123');
    expect(body['verifycode'], isNull);
    expect(body['edt'], 'edt-sample');
    expect(body['sid'], 'sid-sample');
    expect(body['eventid'], 'event-1');
    expect(body['i'], '');
    expect(body['platid'], 2);
    expect(body['v_type'], 32);
    expect(body['userid'], identity.userId);
    expect(body['wasm'], 1);
    final pk = body['pk']! as String;
    expect(RegExp(r'^[0-9a-f]{256}$').hasMatch(pk), isTrue);
    final decrypted = utf8.decode(
      kugouDecryptCredentials(body['params']! as String, kTestSeed),
    );
    expect(decrypted, '{"code":"proof-123"}');
  });

  test('请求装配（type=23）：verifycode 键 + 空 envelope（params 解出 {}）', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    const query = MusicVerifyUserInfoQuery(
      eventId: 'event-2',
      verifyType: 23,
      proof: 'AB12',
    );
    await fetchVerifyUserInfo(
      sessionFor(client, identity),
      query,
      fingerprint: const MusicVerifyFingerprint(sid: 'sid-23', edt: 'edt-23'),
      seed: kTestSeed,
    );
    final body =
        jsonDecode(adapter.requests.single.bodyText) as Map<String, Object?>;
    expect(body.keys.toList(), <String>[
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
    expect(body['verifycode'], 'AB12');
    expect(body['code'], isNull);
    expect(body['v_type'], 23);
    final decrypted = utf8.decode(
      kugouDecryptCredentials(body['params']! as String, kTestSeed),
    );
    expect(decrypted, '{}');
  });

  test('匿名身份可提交（无 require_account），userid=0 入 body', () async {
    final anonymous = KugouIdentity.anonymous(random: Random(1));
    adapter.bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    await fetchVerifyUserInfo(
      sessionFor(client, anonymous),
      const MusicVerifyUserInfoQuery(eventId: 'e', verifyType: 23, proof: 'x'),
      fingerprint: const MusicVerifyFingerprint(sid: 'sid', edt: 'edt'),
    );
    final body =
        jsonDecode(adapter.requests.single.bodyText) as Map<String, Object?>;
    expect(body['userid'], 0);
  });

  test('input 校验：事件/验证码空白或超长、类型非 23/32；16384/4096 边界放行', () async {
    adapter.bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(<String, Object?>{'status': 1, 'error_code': 0})),
    );
    MusicVerifyUserInfoQuery queryOf(String eventId, int type, String proof) =>
        MusicVerifyUserInfoQuery(
          eventId: eventId,
          verifyType: type,
          proof: proof,
        );
    const fingerprint = MusicVerifyFingerprint(sid: 'sid', edt: 'edt');
    Future<Object?> run(MusicVerifyUserInfoQuery query) => fetchVerifyUserInfo(
      sessionFor(client, identity),
      query,
      fingerprint: fingerprint,
    );

    await expectLater(run(queryOf(' ', 23, 'x')), throwsKugou('input'));
    await expectLater(run(queryOf('e', 23, ' ')), throwsKugou('input'));
    await expectLater(run(queryOf('x' * 4097, 23, 'x')), throwsKugou('input'));
    await expectLater(run(queryOf('e', 23, 'x' * 16385)), throwsKugou('input'));
    await expectLater(run(queryOf('e', 24, 'x')), throwsKugou('input'));
    await expectLater(run(queryOf('e', 0, 'x')), throwsKugou('input'));
    expect(adapter.requests, isEmpty);

    // 边界放行（trim 后非空、字节长度恰好达上限）。
    await run(queryOf('x' * 4096, 23, 'x' * 16384));
    expect(adapter.requests, hasLength(1));
  });

  test('响应宽容：status/错误码可为数字字符串，三键按序回退', () async {
    const fingerprint = MusicVerifyFingerprint(sid: 'sid', edt: 'edt');
    Future<Object?> run(String wire) async {
      adapter.bytes = Uint8List.fromList(utf8.encode(wire));
      return fetchVerifyUserInfo(
        sessionFor(client, identity),
        const MusicVerifyUserInfoQuery(
          eventId: 'e',
          verifyType: 23,
          proof: 'x',
        ),
        fingerprint: fingerprint,
      );
    }

    // 数字/字符串形态均成功。
    await run('{"status":1,"error_code":0}');
    await run('{"status":"1","error_code":"0"}');
    // error_code 缺省时依次回退 err_code / errcode。
    await run('{"status":1,"err_code":"0"}');
    await run('{"status":1,"errcode":0}');
    await run('{"status":1}');

    // data.msg 是描述文案，不是验收条件。
    final ack =
        await run('{"status":"1","error_code":0,"data":{"msg":"审核中"}}')
            as MusicVerifyAcknowledgement;
    expect(ack.acknowledged, isTrue);
  });

  test('业务失败：status≠1 或码≠0 → business 带码；登录过期 → authentication', () async {
    const fingerprint = MusicVerifyFingerprint(sid: 'sid', edt: 'edt');
    Future<Object?> run(String wire) async {
      adapter.bytes = Uint8List.fromList(utf8.encode(wire));
      return fetchVerifyUserInfo(
        sessionFor(client, identity),
        const MusicVerifyUserInfoQuery(
          eventId: 'e',
          verifyType: 23,
          proof: 'x',
        ),
        fingerprint: fingerprint,
      );
    }

    await expectLater(
      run('{"status":0,"error_code":7}'),
      throwsKugou('business', code: 7),
    );
    // status=1 但错误码非零同样拒绝。
    await expectLater(
      run('{"status":1,"err_code":20028}'),
      throwsKugou('business', code: 20028),
    );
    await expectLater(
      run('{"error_code":20018,"status":"1"}'),
      throwsKugou('authentication'),
    );
    await expectLater(
      run('{"msg":"用户登录已过期，请重新登录","status":1,"error_code":0}'),
      throwsKugou('authentication'),
    );
  });

  test('解码失败：status 缺失/不可解析；错误码存在但不可读（strict_optional）', () async {
    const fingerprint = MusicVerifyFingerprint(sid: 'sid', edt: 'edt');
    Future<Object?> run(String wire) async {
      adapter.bytes = Uint8List.fromList(utf8.encode(wire));
      return fetchVerifyUserInfo(
        sessionFor(client, identity),
        const MusicVerifyUserInfoQuery(
          eventId: 'e',
          verifyType: 23,
          proof: 'x',
        ),
        fingerprint: fingerprint,
      );
    }

    await expectLater(run('{}'), throwsKugou('decode'));
    await expectLater(run('{"status":"abc"}'), throwsKugou('decode'));
    await expectLater(run('{"status":1.5}'), throwsKugou('decode'));
    await expectLater(run('{"status":true}'), throwsKugou('decode'));
    // error_code 不可读：不得静默当 0 成功。
    await expectLater(
      run('{"status":1,"error_code":{"nested":1}}'),
      throwsKugou('decode'),
    );
    await expectLater(
      run('{"status":1,"errcode":"1x"}'),
      throwsKugou('decode'),
    );
    // error_code 前键不可读时也不得吞掉回退键。
    await expectLater(
      run('{"status":1,"error_code":[],"err_code":0}'),
      throwsKugou('decode'),
    );
  });
}

/// 身份的可写副本：仅测试用（真实身份由登录/设备注册负责）。
extension on KugouIdentity {
  KugouIdentity copyWithRenderFingerprintForTest(String renderFingerprint) =>
      KugouIdentity(
        userId: userId,
        token: token,
        t1: t1,
        mid: mid,
        dfid: dfid,
        uuid: uuid,
        guid: guid,
        mac: mac,
        deviceName: deviceName,
        renderFingerprint: renderFingerprint,
        nickname: nickname,
        avatarUrl: avatarUrl,
      );
}
