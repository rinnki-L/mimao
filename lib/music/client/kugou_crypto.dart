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
Uint8List _rsaPkcs1v15Encrypt(List<int> plain, {Random? random}) {
  final engine = PKCS1Encoding(RSAEngine());
  engine.init(
    true,
    ParametersWithRandom<PublicKeyParameter<RSAPublicKey>>(
      PublicKeyParameter<RSAPublicKey>(
        RSAPublicKey(_liteModulus, _liteExponent),
      ),
      _fortunaRandom(random ?? Random.secure()),
    ),
  );
  return engine.process(Uint8List.fromList(plain));
}

/// 裸 RSA（右侧零补齐，非 PKCS#1/OAEP），输出大写 hex。
///
/// crypto.rs `user_portrait`：登录/资料/等级等端点把凭证画像直接 modpow，
/// 明文放在 128 字节大端整数的高位，低位补零。**不要**拿它做通用加密。
String kugouUserPortrait(List<int> plaintext) {
  const keySize = 128;
  if (plaintext.length > keySize) {
    throw const KugouApiException('input', '账号凭证长度超出协议限制');
  }
  final padded = Uint8List(keySize)..setRange(0, plaintext.length, plaintext);
  final cipher = _bytesToBigInt(padded).modPow(_liteExponent, _liteModulus);
  final output = _bigIntToBytes(cipher, keySize);
  return output
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
}

/// PKCS#1 v1.5 加密并 base64（crypto.rs `lite_pkcs1_base64`，CSCC 握手用）。
String kugouLitePkcs1Base64(List<int> plaintext, {Random? random}) =>
    base64Encode(_rsaPkcs1v15Encrypt(plaintext, random: random));

/// AES-256-CBC + PKCS7，返回小写 hex（crypto.rs `aes256_hex`）。
///
/// key 固定 32 字节（ASCII）、iv 16 字节；登录/验证/偏好信封共用。
String kugouAes256Hex(List<int> plaintext, List<int> key, List<int> iv) {
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    true,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      ParametersWithIV<KeyParameter>(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      ),
      null,
    ),
  );
  return cipher
      .process(Uint8List.fromList(plaintext))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// AES-256-CBC 解密 hex 凭证（crypto.rs `decrypt_credentials`）。
Uint8List kugouDecryptCredentials(String ciphertextHex, String seed) {
  final ciphertext = _unhex(ciphertextHex);
  final keyMaterial = utf8.encode(md5.convert(utf8.encode(seed)).toString());
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    false,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      ParametersWithIV<KeyParameter>(
        KeyParameter(Uint8List.fromList(keyMaterial)),
        Uint8List.fromList(keyMaterial.sublist(16)),
      ),
      null,
    ),
  );
  try {
    return cipher.process(ciphertext);
  } on Object {
    throw const KugouApiException('decode', '无法解密登录凭证');
  }
}

/// 登录凭证解密：JSON object 或原始 token 字符串；其它形态 → decode。
/// 绝不在异常/日志里回显明文。
Object? kugouDecodeLoginCredentials(String ciphertextHex, String seed) {
  final bytes = kugouDecryptCredentials(ciphertextHex, seed);
  Object? value;
  try {
    value = jsonDecode(utf8.decode(bytes));
  } on Object {
    try {
      value = utf8.decode(bytes);
    } on Object {
      throw const KugouApiException('decode', '登录凭证不是合法文本');
    }
  }
  if (value is Map || value is String) return value;
  throw const KugouApiException('decode', '登录凭证结构无效');
}

/// 登录参数信封（crypto.rs `ParameterEnvelope` / `login_parameter_envelope`）。
class KugouParameterEnvelope {
  const KugouParameterEnvelope({
    required this.portrait,
    required this.params,
    required this.seed,
  });

  /// RSA 画像 hex（`pk` 参数）。
  final String portrait;

  /// AES-256 密文 hex（`params` 参数）。
  final String params;

  /// 响应解密用的 seed；只在本次请求内使用，不持久化。
  final String seed;
}

/// 生成 8 字节随机 seed 的 hex（16 字符）。
String _randomHexSeed([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(8, (_) => source.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

/// 登录参数信封（带毫秒时间戳；portrait 保持大写）。
KugouParameterEnvelope kugouLoginParameterEnvelope(
  Map<String, Object?> value,
  int timestampMs, {
  String? seed,
  Random? random,
}) {
  final actualSeed = seed ?? _randomHexSeed(random);
  final envelope = _parameterEnvelopeWithSeed(value, actualSeed, timestampMs);
  return KugouParameterEnvelope(
    portrait: envelope.portrait,
    params: envelope.params,
    seed: actualSeed,
  );
}

/// 验证信封（verify_user_info；无时间戳，portrait 转小写）。
({String portrait, String params}) kugouVerificationEnvelope(
  Map<String, Object?> value, {
  String? seed,
  Random? random,
}) {
  final actualSeed = seed ?? _randomHexSeed(random);
  final envelope = _parameterEnvelopeWithSeed(value, actualSeed, null);
  return (portrait: envelope.portrait.toLowerCase(), params: envelope.params);
}

/// 密码登录信封（login.rs `login_envelope`；带毫秒时间戳，portrait 大写）。
({String portrait, String params}) kugouLoginEnvelope(
  Map<String, Object?> value,
  int timestampMs, {
  String? seed,
  Random? random,
}) {
  final actualSeed = seed ?? _randomHexSeed(random);
  return _parameterEnvelopeWithSeed(value, actualSeed, timestampMs);
}

/// 偏好信封（crypto.rs `preference_envelope`）：只加密 token，portrait 小写，
/// 公开 JSON 为 `{"clienttime":"<秒>","key":"<seed>"}`（BTreeMap 字典序）。
({String portrait, String params}) kugouPreferenceEnvelope(
  String token,
  int seconds, {
  String? seed,
  Random? random,
}) {
  final actualSeed = seed ?? _randomHexSeed(random);
  final keyMaterial = utf8.encode(
    md5.convert(utf8.encode(actualSeed)).toString(),
  );
  final params = kugouAes256Hex(
    utf8.encode(_sortedJson(<String, Object?>{'token': token})),
    keyMaterial,
    keyMaterial.sublist(16),
  );
  final public = _sortedJson(<String, Object?>{
    'clienttime': seconds.toString(),
    'key': actualSeed,
  });
  final portrait = kugouUserPortrait(utf8.encode(public)).toLowerCase();
  return (portrait: portrait, params: params);
}

({String portrait, String params}) _parameterEnvelopeWithSeed(
  Map<String, Object?> value,
  String seed,
  int? timestampMs,
) {
  final keyMaterial = utf8.encode(md5.convert(utf8.encode(seed)).toString());
  final params = kugouAes256Hex(
    utf8.encode(_sortedJson(value)),
    keyMaterial,
    keyMaterial.sublist(16),
  );
  final public = timestampMs == null
      ? <String, Object?>{'key': seed}
      : <String, Object?>{'clienttime_ms': timestampMs, 'key': seed};
  final portrait = kugouUserPortrait(utf8.encode(_sortedJson(public)));
  return (portrait: portrait, params: params);
}

/// serde_json 默认 Map 是 BTreeMap：`json!({...})` 的键按字典序输出（嵌套同理）。
String _sortedJson(Map<String, Object?> value) =>
    jsonEncode(_sortedValue(value));

Object? _sortedValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortedValue(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _sortedValue(item)];
  }
  return value;
}

/// 云盘/歌单写入协议的通用 AES-128 信封（crypto.rs `PlaylistEnvelope`）。
///
/// 与注册信封的区别：seed 字符表含大写、画像含 userid/token、密文以二进制
/// 或 base64 两种方式发送。响应解密用同一个 seed。
class KugouPlaylistEnvelope {
  const KugouPlaylistEnvelope._(this.seed, this.portrait, this.body);

  factory KugouPlaylistEnvelope.random(
    Map<String, Object?> value, {
    required int userId,
    required String token,
    Random? random,
  }) {
    final source = random ?? Random.secure();
    const alphabet =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final buffer = StringBuffer();
    while (buffer.length < 6) {
      final entropy = source.nextInt(256);
      if (entropy < 248) buffer.write(alphabet[entropy % 62]);
    }
    return KugouPlaylistEnvelope.withSeed(
      value,
      userId: userId,
      token: token,
      seed: buffer.toString(),
    );
  }

  factory KugouPlaylistEnvelope.withSeed(
    Map<String, Object?> value, {
    required int userId,
    required String token,
    required String seed,
  }) {
    final body = kugouAesCbcPkcs7(
      utf8.encode(_sortedJson(value)),
      seed,
      encrypt: true,
    );
    final portraitJson = jsonEncode(<String, Object?>{
      'aes': seed,
      'uid': userId,
      'token': token,
    });
    final portrait = _rsaPkcs1v15Encrypt(
      utf8.encode(portraitJson),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return KugouPlaylistEnvelope._(seed, portrait, body);
  }

  final String seed;
  final String portrait;
  final Uint8List body;

  /// base64(body) 的 ASCII 字节（部分端点用 base64 发送）。
  Uint8List base64Body() => utf8.encode(base64Encode(body));

  /// 用同一 seed 解密服务端响应。
  Uint8List decrypt(List<int> ciphertext) {
    try {
      return kugouAesCbcPkcs7(ciphertext, seed, encrypt: false);
    } on Object {
      throw const KugouApiException('decode', '无法解密歌单服务返回的数据');
    }
  }
}

BigInt _bytesToBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final output = Uint8List(length);
  var remaining = value;
  final mask = BigInt.from(0xff);
  for (var index = length - 1; index >= 0; index--) {
    output[index] = (remaining & mask).toInt();
    remaining = remaining >> 8;
  }
  return output;
}

Uint8List _unhex(String value) {
  if (value.isEmpty ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw const KugouApiException('decode', '密文不是合法 hex');
  }
  final output = Uint8List(value.length ~/ 2);
  for (var index = 0; index < output.length; index++) {
    output[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return output;
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
