/// 备份文件的密码加密：AES-256-GCM + PBKDF2-HMAC-SHA256。
///
/// 为什么是 GCM 不是 CBC：GCM 带认证标签，密码错与文件被截断/篡改都能明确
/// 区分出来并给可读错误；CBC 解出来是乱码，只能报"解析失败"。
///
/// 外层信封自带算法参数（kdf / iterations / salt / nonce），换参数不影响老文件
/// 的解读——解密只认信封里记的那套。
///
/// 这一层同样是纯 Dart（pointycastle），没有 IO，可在单测里直接跑。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/novel/backup/backup_document.dart';
import 'package:pointycastle/export.dart' as pc;

/// 默认 PBKDF2 迭代次数。数值越大越慢越好；备份/恢复是低频操作，取了偏高的档。
const int novelBackupKdfIterations = 150000;

/// 信封版本。
const String novelBackupCipherName = 'AES-256-GCM';
const String novelBackupKdfName = 'PBKDF2-HMAC-SHA256';

const int _keyBytes = 32;
const int _saltBytes = 16;
const int _nonceBytes = 12;
const int _tagBits = 128;

/// 密码不对 / 文件损坏。两者在 GCM 下无法区分（认证标签都会失败），
/// 所以提示必须把两种可能都写出来。
class NovelBackupCryptoException implements Exception {
  const NovelBackupCryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一个可解密的备份包（信封本身）。
class NovelBackupEnvelope {
  const NovelBackupEnvelope({
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.payload,
  });

  final int iterations;
  final List<int> salt;
  final List<int> nonce;

  /// 密文 + 认证标签（GCM 输出格式）。
  final List<int> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': novelBackupEncryptedFormat,
    'version': novelBackupEnvelopeVersion,
    'cipher': novelBackupCipherName,
    'kdf': novelBackupKdfName,
    'iterations': iterations,
    'salt': base64Encode(salt),
    'nonce': base64Encode(nonce),
    'payload': base64Encode(payload),
  };

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  static NovelBackupEnvelope decode(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! int || version > novelBackupEnvelopeVersion) {
      throw const NovelBackupCryptoException('加密备份的版本不受支持，请升级应用');
    }
    if ('${json['cipher'] ?? ''}' != novelBackupCipherName ||
        '${json['kdf'] ?? ''}' != novelBackupKdfName) {
      throw const NovelBackupCryptoException('加密备份用了不认识的算法');
    }
    final iterations = json['iterations'];
    return NovelBackupEnvelope(
      iterations: iterations is num
          ? iterations.toInt()
          : novelBackupKdfIterations,
      salt: _bytesOf(json['salt']),
      nonce: _bytesOf(json['nonce']),
      payload: _bytesOf(json['payload']),
    );
  }

  /// 解密并返回备份文档文本；密码错/损坏抛 [NovelBackupCryptoException]。
  String decrypt(String password) {
    if (password.isEmpty) {
      throw const NovelBackupCryptoException('这份备份设了密码，需要先输入密码');
    }
    final Uint8List plain;
    try {
      plain = _gcm(
        encrypt: false,
        key: _deriveKey(password, salt, iterations),
        nonce: nonce,
        input: payload,
      );
    } on Object {
      throw const NovelBackupCryptoException('密码不对，或者备份文件已损坏');
    }
    try {
      return utf8.decode(plain);
    } on Object {
      throw const NovelBackupCryptoException('备份内容不是有效的 UTF-8 文本，文件可能已损坏');
    }
  }
}

/// 把明文备份文本加密成一个信封 JSON 文本。
NovelBackupEnvelope encryptNovelBackupText(
  String documentText,
  String password, {
  int iterations = novelBackupKdfIterations,
  Random? random,
}) {
  if (password.isEmpty) {
    throw const NovelBackupCryptoException('加密备份必须设置密码');
  }
  final source = random ?? Random.secure();
  final salt = _randomBytes(_saltBytes, source);
  final nonce = _randomBytes(_nonceBytes, source);
  final payload = _gcm(
    encrypt: true,
    key: _deriveKey(password, salt, iterations),
    nonce: nonce,
    input: Uint8List.fromList(utf8.encode(documentText)),
  );
  return NovelBackupEnvelope(
    iterations: iterations,
    salt: salt,
    nonce: nonce,
    payload: payload,
  );
}

/// 解密结果：要么是明文文档，要么是待解密的信封。
sealed class NovelBackupBundle {
  const NovelBackupBundle();

  /// 备份里的设备名（信封形态拿不到，返回空串）。
  String get deviceName;

  /// 导出时间（信封形态拿不到，返回 null）。
  DateTime? get exportedAt;
}

/// 明文文档包。
class NovelBackupPlainBundle extends NovelBackupBundle {
  const NovelBackupPlainBundle(this.document);

  final NovelBackupDocument document;

  @override
  String get deviceName => document.deviceName;

  @override
  DateTime? get exportedAt => document.exportedAt;
}

/// 需要密码的加密包。
class NovelBackupEncryptedBundle extends NovelBackupBundle {
  const NovelBackupEncryptedBundle(this.envelope);

  final NovelBackupEnvelope envelope;

  @override
  String get deviceName => '';

  @override
  DateTime? get exportedAt => null;

  /// 解开成文档；密码错/损坏抛 [NovelBackupCryptoException]。
  NovelBackupDocument decrypt(String password) =>
      NovelBackupDocument.decode(envelope.decrypt(password));
}

/// 嗅探远端拿到的文本是明文文档还是加密包。
///
/// 两者都不是时抛 [FormatException]——不要把任意 JSON 当备份。
NovelBackupBundle parseNovelBackupBundle(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on Object {
    throw const FormatException('备份文件不是 JSON');
  }
  if (decoded is! Map) throw const FormatException('备份文件不是 JSON 对象');
  final map = Map<String, Object?>.from(decoded);
  if (map['format'] == novelBackupEncryptedFormat) {
    return NovelBackupEncryptedBundle(NovelBackupEnvelope.decode(map));
  }
  return NovelBackupPlainBundle(NovelBackupDocument.decode(text));
}

Uint8List _deriveKey(String password, List<int> salt, int iterations) {
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
    ..init(
      pc.Pbkdf2Parameters(
        Uint8List.fromList(salt),
        iterations <= 0 ? novelBackupKdfIterations : iterations,
        _keyBytes,
      ),
    );
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List _gcm({
  required bool encrypt,
  required Uint8List key,
  required List<int> nonce,
  required List<int> input,
}) {
  final cipher = pc.GCMBlockCipher(pc.AESEngine())
    ..init(
      encrypt,
      pc.AEADParameters(
        pc.KeyParameter(key),
        _tagBits,
        Uint8List.fromList(nonce),
        Uint8List(0),
      ),
    );
  return cipher.process(Uint8List.fromList(input));
}

Uint8List _randomBytes(int length, Random random) => Uint8List.fromList(<int>[
  for (var i = 0; i < length; i++) random.nextInt(256),
]);

List<int> _bytesOf(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    throw const NovelBackupCryptoException('加密备份缺少必要字段，文件已损坏');
  }
  try {
    return base64Decode(raw);
  } on Object {
    throw const NovelBackupCryptoException('加密备份的字段不是合法 base64，文件已损坏');
  }
}
