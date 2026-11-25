// RSA 非对称加签/验签/加解密回归：用 pointycastle 现场生成 RSA 密钥对，
// 导出成书源常用的 PKCS#1 DER + base64，经 js_helpers 跑真实加签验签与加解密。
//
// 纯 Dart，不依赖 native QuickJS、不访问网络。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/js/js_helpers.dart' as helpers;
import 'package:pointycastle/export.dart' as pc;

/// 现场生成 1024 位 RSA 密钥对（测试足够快）。
({BigInt mod, BigInt exp, BigInt priv}) _generateKey() {
  final random = pc.FortunaRandom()
    ..seed(
      pc.KeyParameter(
        Uint8List.fromList(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)),
        ),
      ),
    );
  final generator = pc.RSAKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 5),
        random,
      ),
    );
  final pair = generator.generateKeyPair();
  final pub = pair.publicKey as pc.RSAPublicKey;
  final priv = pair.privateKey as pc.RSAPrivateKey;
  return (mod: pub.n!, exp: pub.publicExponent!, priv: priv.privateExponent!);
}

/// 极简 ASN.1 DER 编码：INTEGER 与 SEQUENCE。
List<int> _derInteger(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  var body = <int>[
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  // DER INTEGER 是有符号大端：最高位为 1 时前置 0x00 表示正数。
  if (body.isNotEmpty && (body[0] & 0x80) != 0) body = <int>[0, ...body];
  final len = body.length;
  final lengthBytes = len < 128
      ? <int>[len]
      : <int>[0x81, len]; // 1024-bit 密钥最多 129 字节，单字节长形式足够。
  return <int>[0x02, ...lengthBytes, ...body];
}

List<int> _derSequence(List<int> body) {
  final length = body.length;
  if (length < 128) return <int>[0x30, length, ...body];
  final lenBytes = <int>[
    for (var shift = 24; shift >= 0; shift -= 8)
      if ((length >> shift) & 0xFF != 0 || shift == 0) (length >> shift) & 0xFF,
  ];
  // 只保留有效长度字节（从第一个非零开始）。
  var start = 0;
  while (start < lenBytes.length - 1 && lenBytes[start] == 0) {
    start++;
  }
  final effective = lenBytes.sublist(start);
  return <int>[0x30, 0x80 | effective.length, ...effective, ...body];
}

String _publicKeyBase64({required BigInt mod, required BigInt exp}) =>
    base64Encode(_derSequence(<int>[..._derInteger(mod), ..._derInteger(exp)]));

String _privateKeyBase64({
  required BigInt mod,
  required BigInt exp,
  required BigInt priv,
}) => base64Encode(
  _derSequence(<int>[
    ..._derInteger(mod),
    ..._derInteger(exp),
    ..._derInteger(priv),
  ]),
);

void main() {
  test('PKCS#1 DER 公钥解析 n/e', () {
    final key = _generateKey();
    final parsed = helpers.rsaPublicKeyFromBase64(
      _publicKeyBase64(mod: key.mod, exp: key.exp),
    );
    expect(parsed, isNotNull);
    expect(parsed!.n, key.mod);
    expect(parsed.publicExponent, key.exp);
  });

  test('RSA SHA256withRSA 签名 → 验签通过，篡改数据验签失败', () {
    final key = _generateKey();
    final private = _privateKeyBase64(
      mod: key.mod,
      exp: key.exp,
      priv: key.priv,
    );
    final public = _publicKeyBase64(mod: key.mod, exp: key.exp);
    const data = '《书名》与作者——sign me';
    final signature = helpers.rsaSignBase64(data, 'SHA256withRSA', private);
    expect(signature, isNotEmpty);
    expect(
      helpers.rsaVerifyBase64(data, 'SHA256withRSA', public, signature),
      isTrue,
    );
    expect(
      helpers.rsaVerifyBase64('$data!', 'SHA256withRSA', public, signature),
      isFalse,
    );
  });

  test('RSA PKCS#1 v1.5 加密 → 解密还原明文', () {
    final key = _generateKey();
    final private = _privateKeyBase64(
      mod: key.mod,
      exp: key.exp,
      priv: key.priv,
    );
    final public = _publicKeyBase64(mod: key.mod, exp: key.exp);
    const plain = 'session=abc; uid=7';
    final cipher = helpers.rsaEncryptBase64(plain, public);
    expect(cipher, isNotEmpty);
    expect(cipher, isNot(plain));
    expect(helpers.rsaDecryptText(cipher, private), plain);
  });
}
