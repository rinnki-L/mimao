/// 酷狗信封加密——EchoMusicNext `crates/echo-api/src/util/crypto.rs` 的骨架期
/// 翻译子集（docs/architecture.md §4.3：`music/client/` ← util，Rust 只读）。
///
/// 骨架只落设备注册链路（register_dev）需要的部分：
/// - AES-128-CBC + PKCS7：key/iv 取 seed 的 MD5 hex 的前/后 16 字节（ASCII）；
/// - RSA PKCS#1 v1.5 加密「信封画像」（seed/uid/token）为 hex portrait；
/// - 确定性可测：seed 可注入，黄金向量来自上游
///   `tests/fixtures/protocol/register-dev-request-20261017.json`。
///
/// 其余函数（user_portrait 裸 RSA、login/preference/verification 信封、
/// CSCC 握手）随后续登录/云盘切片按同一上游文件对照补齐。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'kugou_error.dart';

/// 协议固定公钥（crypto.rs `LITE_PUBLIC_KEY`，SPKI PEM）拆出的参数。
/// 1024-bit 模数；e = 0x010001（65537）。提取脚本见 test/music/client/ 注释。
const String _kLiteModulusHex =
    '00c40a2d0da76511f3bb1cc2bbd3afbd8bea83b4d6b05b6c13eb8920c53f1af7679b32ba0d'
    '0edb843240ef1b836efed3ee240734c14c1399fd6594d16af22f52525d14d72e0155c6dcc8'
    '638d4f7bb94f3a0b1f4c29f991972f2a160a25eb0a9e724336be7f69bbd319ffab1c6dd847'
    '0b021dc434f3faba89f4a2a01b33bdbdd08b';
const String _kLiteExponentHex = '010001';

final BigInt _liteModulus = BigInt.parse(_kLiteModulusHex, radix: 16);
final BigInt _liteExponent = BigInt.parse(_kLiteExponentHex, radix: 16);

/// registration 信封——crypto.rs `PlaylistEnvelope::registration` 的翻译。
///
/// body = AES-128-CBC-PKCS7(明文 JSON, key/iv = md5(seed) hex 两半)；
/// portrait = RSA-PKCS1v15({"aes":seed,"uid":uid,"token":token}) 的 hex。
class KugouRegistrationEnvelope {
  KugouRegistrationEnvelope._(
    this.seed,
    this.plainText,
    this.body,
    this.portrait,
  );

  /// 用随机 seed 构造（registration 用小写字母+数字表，带上游同款取模偏置规避）。
  factory KugouRegistrationEnvelope.registration(
    Map<String, Object?> plainJson, {
    required int userId,
    required String token,
    Random? random,
  }) {
    final seed = _randomSeed(
      random ?? Random.secure(),
      alphabet: '0123456789abcdefghijklmnopqrstuvwxyz',
      rejectFrom: 252,
    );
    return KugouRegistrationEnvelope.withSeed(
      plainJson,
      seed: seed,
      userId: userId,
      token: token,
    );
  }

  /// 用固定 seed 构造（测试黄金向量路径；生产不走这里）。
  factory KugouRegistrationEnvelope.withSeed(
    Map<String, Object?> plainJson, {
    required String seed,
    required int userId,
    required String token,
  }) {
    // registration 保持 JSON 字段顺序（上游注释：注册在加密前保留字段序）。
    final plain = utf8.encode(jsonEncode(plainJson));
    final body = kugouAesCbcPkcs7(plain, seed, encrypt: true);
    final portraitJson = utf8.encode(
      '{"aes":"$seed","uid":$userId,"token":${jsonEncode(token)}}',
    );
    // 上游 portrait hex 用大写（{b:02X}）。
    final portrait = _rsaPkcs1v15Encrypt(
      portraitJson,
    ).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
    return KugouRegistrationEnvelope._(seed, plain, body, portrait);
  }

  /// 6 位 seed（黄金向量对拍用；生产用 [KugouRegistrationEnvelope.registration]）。
  final String seed;

  /// 加密前的明文 JSON 字节（黄金向量对拍用）。
  final Uint8List plainText;

  /// AES 密文。
  final Uint8List body;

  /// RSA 画像 hex（作为 `p` 参数发送）。
  final String portrait;

  /// 发送体：base64(body) 的 ASCII 字节（上游 base64_body）。
  Uint8List base64Body() => utf8.encode(base64Encode(body));

  /// 用信封自己的 seed 解密服务端返回的二进制响应。
  Uint8List decryptResponse(List<int> ciphertext) {
    try {
      return kugouAesCbcPkcs7(ciphertext, seed, encrypt: false);
    } on Object {
      throw const KugouApiException(
        'device_registration_decrypt',
        '无法解密设备服务返回的数据',
      );
    }
  }
}

/// AES-128-CBC + PKCS7；key = md5(seed) hex 前 16 字节，iv = 后 16 字节（ASCII）。
/// 公开为协议原语（上游 crypto.rs 即 pub）：信封构造、响应解密与后续登录
/// 切片共用；测试用它以固定 seed 构造黄金密文。
Uint8List kugouAesCbcPkcs7(
  List<int> input,
  String seed, {
  required bool encrypt,
}) {
  final digest = md5.convert(utf8.encode(seed)).toString();
  final keyMaterial = Uint8List.fromList(utf8.encode(digest));
  final key = Uint8List.sublistView(keyMaterial, 0, 16);
  final iv = Uint8List.sublistView(keyMaterial, 16, 32);

  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    encrypt,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
      null,
    ),
  );
  return cipher.process(Uint8List.fromList(input));
}

/// RSA PKCS#1 v1.5 加密，输出 128 字节。
Uint8List _rsaPkcs1v15Encrypt(List<int> plain) {
  final engine = PKCS1Encoding(RSAEngine());
  engine.init(
    true,
    ParametersWithRandom<PublicKeyParameter<RSAPublicKey>>(
      PublicKeyParameter<RSAPublicKey>(
        RSAPublicKey(_liteModulus, _liteExponent),
      ),
      _fortunaRandom(Random.secure()),
    ),
  );
  return engine.process(Uint8List.fromList(plain));
}

/// 上游同款取模偏置规避的随机 6 位 seed。
String _randomSeed(
  Random random, {
  required String alphabet,
  required int rejectFrom,
}) {
  final buffer = StringBuffer();
  while (buffer.length < 6) {
    final entropy = random.nextInt(256);
    if (entropy < rejectFrom) {
      buffer.write(alphabet[entropy % alphabet.length]);
    }
  }
  return buffer.toString();
}

SecureRandom _fortunaRandom(Random source) {
  final seedBytes = Uint8List(32);
  for (var i = 0; i < seedBytes.length; i++) {
    seedBytes[i] = source.nextInt(256);
  }
  return FortunaRandom()..seed(KeyParameter(seedBytes));
}
