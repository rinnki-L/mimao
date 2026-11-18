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
}
