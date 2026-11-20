/// 信封加密测试——AES/RSA 黄金向量来自上游
/// EchoMusicNext tests/fixtures/protocol/register-dev-request-20261017.json
/// （本仓库已逐字节核对入库：test/music/fixtures/）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_crypto.dart';

/// 上游 DeviceProfile（黄金向量路径）。
Map<String, Object?> deviceProfile(String guid) => <String, Object?>{
  'availableRamSize': 4983533568,
  'availableRomSize': 48114719,
  'availableSDSize': 48114717,
  'basebandVer': '',
  'batteryLevel': 100,
  'batteryStatus': 3,
  'brand': 'Redmi',
  'buildSerial': 'unknown',
  'device': 'marble',
  'imei': guid,
  'imsi': '',
  'manufacturer': 'Xiaomi',
  'uuid': guid,
  'accelerometer': false,
  'accelerometerValue': '',
  'gravity': false,
  'gravityValue': '',
  'gyroscope': false,
  'gyroscopeValue': '',
  'light': false,
  'lightValue': '',
  'magnetic': false,
  'magneticValue': '',
  'orientation': false,
  'orientationValue': '',
  'pressure': false,
  'pressureValue': '',
  'step_counter': false,
  'step_counterValue': '',
  'temperature': false,
  'temperatureValue': '',
};

void main() {
  final fixtureFile = File(
    'test/music/fixtures/register_dev_request_20261017.json',
  );
  final fixture =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, Object?>;

  test('DeviceProfile 的 JSON 字节与上游 plain_text 逐字节一致', () {
    final plain = utf8.encode(
      jsonEncode(deviceProfile('0123456789abcdef0123456789abcdef')),
    );
    expect(utf8.decode(plain), fixture['plain_text']);
  });

  test('固定 seed 的信封密文与上游 ciphertext_base64 逐字节一致（AES-CBC-PKCS7）', () {
    final envelope = KugouRegistrationEnvelope.withSeed(
      deviceProfile('0123456789abcdef0123456789abcdef'),
      seed: fixture['seed']! as String,
      userId: 0,
      token: '',
    );
    expect(base64Encode(envelope.body), fixture['ciphertext_base64']);
  });

  test('信封解密还原明文（roundtrip）', () {
    final envelope = KugouRegistrationEnvelope.withSeed(
      deviceProfile('0123456789abcdef0123456789abcdef'),
      seed: fixture['seed']! as String,
      userId: 0,
      token: '',
    );
    expect(
      utf8.decode(envelope.decryptResponse(envelope.body)),
      fixture['plain_text'],
    );
  });

  test('RSA portrait：128 字节 hex 输出，被加密内容与上游 portrait_plain_text 语义一致', () {
    // RSA-PKCS1v15 带随机填充，无输出黄金向量；可验证的是：
    // 输出形状（128 字节 hex）与加密原文的字节序（上游 portrait_plain_text）。
    final envelope = KugouRegistrationEnvelope.withSeed(
      deviceProfile('0123456789abcdef0123456789abcdef'),
      seed: fixture['seed']! as String,
      userId: 0,
      token: '',
    );
    expect(envelope.portrait.length, 256);
    expect(RegExp(r'^[0-9A-F]{256}$').hasMatch(envelope.portrait), isTrue);
    // portrait 明文的构造口径：{"aes":seed,"uid":0,"token":""}
    expect(
      '{"aes":"${fixture['seed']}","uid":0,"token":""}',
      fixture['portrait_plain_text'],
    );
  });

  test('随机 seed：小写字母数字表、6 位', () {
    final envelope = KugouRegistrationEnvelope.registration(
      deviceProfile('0123456789abcdef0123456789abcdef'),
      userId: 0,
      token: '',
    );
    expect(envelope.seed.length, 6);
    expect(RegExp(r'^[0-9a-z]{6}$').hasMatch(envelope.seed), isTrue);
  });

  test('解不开的密文 → device_registration_decrypt 异常', () {
    final envelope = KugouRegistrationEnvelope.withSeed(
      deviceProfile('0123456789abcdef0123456789abcdef'),
      seed: 'iiiiii',
      userId: 0,
      token: '',
    );
    final garbage = Uint8List.fromList(List.filled(48, 0xAB));
    expect(
      () => envelope.decryptResponse(garbage),
      throwsA(
        predicate(
          (Object e) =>
              e is Exception && '$e'.contains('device_registration_decrypt'),
        ),
      ),
    );
  });

  // ── 扩容共享 crypto（crypto.rs 黄金向量）──

  test('AES-256-CBC hex 与上游 refresh 向量逐字节一致', () {
    expect(
      kugouAes256Hex(
        utf8.encode('fixture-t1|1700000000123'),
        utf8.encode('5e4ef500e9597fe004bd09a46d8add98'),
        utf8.encode('04bd09a46d8add98'),
      ),
      '54109b3de6f4ef96c75ee57eddfa19068e695b6a1d1edaa432cff9eaaf6f4d3d',
    );
  });

  test('参数信封（裸 RSA + AES-256）与上游向量逐字节一致', () {
    final envelope = kugouVerificationEnvelope(<String, Object?>{
      'code': '123456',
    }, seed: '0123456789abcdef');
    expect(
      envelope.portrait,
      '8f00be7ef062ab4a56be2cce9177273c52ff9c37cd2534deb222cffd3f9d0244'
      '25e520fef4fde78d48a6661f1814e13ecbb1dce7937417ae356fa21d097e11dd'
      '1a9f55b28f94715f9df841a2e8b0413974f157a1c64fc9e7c7c611d4dda8b37e'
      '58d27fc7266df185b68b2a2fbcc1e1c2b46242a68409d63d8879772bf7bb4735',
    );
    expect(
      envelope.params,
      'f6b8a061ddc6d8b1abb7222ae9d44b489e9f3f405c5a336864661bf8af172a65',
    );
  });

  test('凭证解密：JSON object / 原始字符串 / 非法密文', () {
    expect(
      utf8.decode(
        kugouDecryptCredentials(
          'f6b8a061ddc6d8b1abb7222ae9d44b489e9f3f405c5a336864661bf8af172a65',
          '0123456789abcdef',
        ),
      ),
      '{"code":"123456"}',
    );
    expect(
      () => kugouDecryptCredentials('00', '0123456789abcdef'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => kugouDecryptCredentials('not-hex', '0123456789abcdef'),
      throwsA(isA<Exception>()),
    );
  });

  test('歌单写入信封（AES-128）与上游向量逐字节一致', () {
    final envelope = KugouPlaylistEnvelope.withSeed(
      <String, Object?>{'listid': 123, 'type': 0},
      userId: 123,
      token: 'fixture-token',
      seed: 'A1b2C3',
    );
    expect(
      envelope.body
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
      '93a42d45891d448c849f3ab521eae7c6b837287d88d8bbe2426c07329c0278fb',
    );
    expect(
      utf8.decode(envelope.base64Body()),
      'k6QtRYkdRIyEnzq1Iernxrg3KH2I2LviQmwHMpwCePs=',
    );
    expect(envelope.portrait.length, 256);
    expect(
      utf8.decode(envelope.decrypt(envelope.body)),
      '{"listid":123,"type":0}',
    );
  });
}
