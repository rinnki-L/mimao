// 对称加解密单测：密钥长度决定 AES-128/192/256，DESede 只收 16/24 字节。
// 纯 Dart，不需要 native QuickJS。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/js/js_helpers.dart';

List<int> _hexBytes(String hex) => <int>[
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _hexText(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const plain = '明文ABC123';
  const desede = 'DESede/CBC/PKCS5Padding';

  // FIPS-197 Appendix C 的已知答案：密钥长度必须原样参与，截断就对不上。
  // 单块明文 + PKCS7 会多出整块填充，只比第一块密文即可。
  const nistPlain = '00112233445566778899aabbccddeeff';
  const nistKeyBase = '000102030405060708090a0b0c0d0e0f';
  const cases = <MapEntry<int, String>>[
    MapEntry(16, '69c4e0d86a7b0430d8cdb78070b4c55a'),
    MapEntry(24, 'dda97ca4864cdfe06eaf70a0ec0d7191'),
    MapEntry(32, '8ea2b7ca516745bfeafc49904b496089'),
  ];

  for (final entry in cases) {
    final keyLength = entry.key;
    final expected = entry.value;
    test('AES 密钥 $keyLength 字节不被截断（FIPS-197 KAT）', () {
      final key = _hexBytes(
        nistKeyBase +
            (keyLength > 16 ? '1011121314151617' : '') +
            (keyLength > 24 ? '18191a1b1c1d1e1f' : ''),
      );
      final out = symmetric(
        true,
        'AES/ECB/PKCS7Padding',
        key,
        null,
        _hexBytes(nistPlain),
      );
      expect(_hexText(out.sublist(0, 16)), expected);
    });
  }

  test('AES-256 CBC 加密后解密回到原文', () {
    final key = List<int>.generate(32, (i) => i + 1);
    final iv = List<int>.generate(16, (i) => i + 7);
    final cipher = symmetricEncryptBase64(
      'AES/CBC/PKCS5Padding',
      key,
      iv,
      plain,
    );
    expect(
      symmetricDecryptText('AES/CBC/PKCS5Padding', key, iv, cipher),
      plain,
    );
  });

  test('DES 8 字节密钥扩成 K1K1K1，不抛异常且能解密', () {
    final key = List<int>.generate(8, (i) => i + 1);
    final iv = List<int>.generate(8, (i) => i + 3);
    final cipher = symmetricEncryptBase64(
      'DES/CBC/PKCS5Padding',
      key,
      iv,
      plain,
    );
    expect(
      symmetricDecryptText('DES/CBC/PKCS5Padding', key, iv, cipher),
      plain,
    );
    expect(
      cipher,
      symmetricEncryptBase64(
        'DES/CBC/PKCS5Padding',
        <int>[...key, ...key, ...key],
        iv,
        plain,
      ),
    );
  });

  test('DESede 16 字节密钥按 K1K2K1 处理', () {
    final key = List<int>.generate(16, (i) => i + 1);
    final iv = List<int>.generate(8, (i) => i + 3);
    final cipher = symmetricEncryptBase64(desede, key, iv, plain);
    expect(symmetricDecryptText(desede, key, iv, cipher), plain);
    // 16 字节若被补零成 24 字节，K3=0 会与 K3!=K1 的结果不同。
    final key24 = <int>[...key, ...List<int>.generate(8, (i) => i + 9)];
    expect(cipher, isNot(symmetricEncryptBase64(desede, key24, iv, plain)));
  });

  test('DESede 24 字节密钥原样使用', () {
    final key = List<int>.generate(24, (i) => i + 1);
    final iv = List<int>.generate(8, (i) => i + 3);
    final cipher = symmetricEncryptBase64(desede, key, iv, plain);
    expect(symmetricDecryptText(desede, key, iv, cipher), plain);
  });

  test('对称加解密字节接口也走同一套密钥适配', () {
    final key = List<int>.generate(32, (i) => i + 1);
    final iv = List<int>.generate(16, (i) => i + 7);
    final bytes = symmetric(true, 'AES/CBC/PKCS5Padding', key, iv, plain);
    expect(
      utf8.decode(symmetric(false, 'AES/CBC/PKCS5Padding', key, iv, bytes)),
      plain,
    );
  });
}
