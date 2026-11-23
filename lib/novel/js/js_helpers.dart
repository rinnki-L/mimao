/// 书源 JS 扩展的纯 Dart 实现：摘要/HMAC/Base64/Hex/AES/DES/时间格式化/
/// 中文数字。宿主只负责把 JS 参数转进来，便于单测。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

/// MD5（小写 hex）。
String md5Hex(String text) => crypto.md5.convert(utf8.encode(text)).toString();

/// MD5 的 8..24 位（书源里常用于文件名/缓存键）。
String md5Hex16(String text) {
  final hex = md5Hex(text);
  return hex.length >= 24 ? hex.substring(8, 24) : hex;
}

String base64EncodeText(String text, [List<int>? bytes]) =>
    base64Encode(bytes ?? utf8.encode(text));

String base64DecodeText(String text, {String? charset}) {
  final bytes = _decodeBase64(text);
  return _decodeText(bytes, charset);
}

Uint8List base64ToBytes(String text) => Uint8List.fromList(_decodeBase64(text));

String hexEncode(String text) {
  final bytes = utf8.encode(text);
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String hexDecode(String hex) {
  final bytes = _hexToBytes(hex);
  return utf8.decode(bytes, allowMalformed: true);
}

String encodeUriComponentText(String text, [String? charset]) {
  final encoding = charset == null || charset.isEmpty
      ? utf8
      : (Charset.getByName(charset) ?? utf8);
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    final code = char.codeUnitAt(0);
    if ((code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        (code >= 0x30 && code <= 0x39) ||
        char == '*' ||
        char == '-' ||
        char == '.' ||
        char == '_') {
      buffer.write(char);
    } else if (char == ' ') {
      buffer.write('+');
    } else {
      for (final byte in encoding.encode(char)) {
        buffer
          ..write('%')
          ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
  }
  return buffer.toString();
}

/// 摘要 hex（algorithm 大小写不敏感：MD5/SHA-1/SHA-256/SHA-384/SHA-512）。
String digestHex(String data, String algorithm) {
  return _digest(algorithm, utf8.encode(data)).toString();
}

String digestBase64(String data, String algorithm) {
  return base64Encode(_digest(algorithm, utf8.encode(data)).bytes);
}

String hmacHex(String data, String algorithm, String key) {
  final hmac = _hmac(algorithm, utf8.encode(key));
  return hmac.convert(utf8.encode(data)).toString();
}

String hmacBase64(String data, String algorithm, String key) {
  final hmac = _hmac(algorithm, utf8.encode(key));
  return base64Encode(hmac.convert(utf8.encode(data)).bytes);
}

crypto.Digest _digest(String algorithm, List<int> data) {
  switch (algorithm.toUpperCase().replaceAll('-', '')) {
    case 'SHA1':
      return crypto.sha1.convert(data);
    case 'SHA256':
      return crypto.sha256.convert(data);
    case 'SHA384':
      return crypto.sha384.convert(data);
    case 'SHA512':
      return crypto.sha512.convert(data);
    default:
      return crypto.md5.convert(data);
  }
}

crypto.Hmac _hmac(String algorithm, List<int> key) {
  switch (algorithm.toUpperCase().replaceAll('-', '')) {
    case 'SHA1':
      return crypto.Hmac(crypto.sha1, key);
    case 'SHA256':
      return crypto.Hmac(crypto.sha256, key);
    case 'SHA384':
      return crypto.Hmac(crypto.sha384, key);
    case 'SHA512':
      return crypto.Hmac(crypto.sha512, key);
    default:
      return crypto.Hmac(crypto.md5, key);
  }
}

/// 对称加解密（AES / DES / DESede，CBC/ECB，PKCS7/NoPadding）。
///
/// [key] / [iv] 支持 String（UTF-8 字节）或字节数组；加密返回字节，解密返回
/// UTF-8 文本。密文输入按 base64 → hex → 原文 UTF-8 的优先级尝试。
Uint8List symmetric(
  bool encrypt,
  String transformation,
  Object? key,
  Object? iv,
  Object? data,
) {
  final parts = transformation.split('/');
  final name = parts.isEmpty ? 'AES' : parts[0].toUpperCase();
  final mode = parts.length > 1 ? parts[1].toUpperCase() : 'CBC';
  final padding = parts.length > 2
      ? parts[2].toUpperCase().replaceAll('PADDING', '')
      : 'PKCS5';

  final keyBytes = _bytesOf(key);
  final ivBytes = _bytesOf(iv);
  final input = encrypt ? _bytesOf(data) : _cipherTextBytes(data);

  final pc.BlockCipher blockCipher = switch (name) {
    'DES' => pc.DESedeEngine(),
    'DESEDE' || 'TRIPLEDES' => pc.DESedeEngine(),
    _ => pc.AESEngine(),
  };
  final blockSize = blockCipher.blockSize;
  final keyValue = _fitKey(keyBytes, switch (name) {
    'DES' => 24,
    'DESEDE' || 'TRIPLEDES' => 24,
    _ => 16,
  });

  final effectiveKey = name == 'DES'
      ? Uint8List.fromList(<int>[...keyValue, ...keyValue, ...keyValue])
      : keyValue;
  final cipher = mode == 'ECB' ? blockCipher : pc.CBCBlockCipher(blockCipher);
  final pc.CipherParameters rawParams = mode == 'ECB'
      ? pc.KeyParameter(effectiveKey)
      : pc.ParametersWithIV(
          pc.KeyParameter(effectiveKey),
          _fitIv(ivBytes, blockSize),
        );
  final inputBytes = Uint8List.fromList(input);

  if (padding == 'NOPADDING') {
    cipher.init(encrypt, rawParams);
    final out = Uint8List(inputBytes.length);
    var offset = 0;
    while (offset < inputBytes.length) {
      offset += cipher.processBlock(inputBytes, offset, out, offset);
    }
    return out;
  }

  final padded = pc.PaddedBlockCipherImpl(pc.PKCS7Padding(), cipher)
    ..init(
      encrypt,
      pc.PaddedBlockCipherParameters<
        pc.CipherParameters?,
        pc.CipherParameters?
      >(rawParams, null),
    );
  return padded.process(inputBytes);
}

String symmetricDecryptText(
  String transformation,
  Object? key,
  Object? iv,
  Object? data,
) {
  final bytes = symmetric(false, transformation, key, iv, data);
  return utf8.decode(bytes, allowMalformed: true);
}

String symmetricEncryptBase64(
  String transformation,
  Object? key,
  Object? iv,
  Object? data,
) => base64Encode(symmetric(true, transformation, key, iv, data));

String symmetricEncryptHex(
  String transformation,
  Object? key,
  Object? iv,
  Object? data,
) {
  final bytes = symmetric(true, transformation, key, iv, data);
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// `timeFormat` 默认格式。
String formatTime(DateTime time) => _format(time, 'yyyy-MM-dd HH:mm:ss');

/// `timeFormatUTC(time, format, sh)`：固定时区偏移（小时）。
String formatTimeUtc(DateTime time, String format, int offsetHours) {
  final shifted = time.toUtc().add(Duration(hours: offsetHours));
  return _format(shifted, format.isEmpty ? 'yyyy-MM-dd HH:mm:ss' : format);
}

String _format(DateTime date, String pattern) {
  final map = <String, String>{
    'yyyy': date.year.toString().padLeft(4, '0'),
    'yy': (date.year % 100).toString().padLeft(2, '0'),
    'MM': date.month.toString().padLeft(2, '0'),
    'dd': date.day.toString().padLeft(2, '0'),
    'HH': date.hour.toString().padLeft(2, '0'),
    'mm': date.minute.toString().padLeft(2, '0'),
    'ss': date.second.toString().padLeft(2, '0'),
    'SSS': date.millisecond.toString().padLeft(3, '0'),
  };
  var result = pattern;
  for (final entry in map.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

/// 章节标题里的中文数字转阿拉伯数字（`第一百二十三章` → `第123章`）。
String toNumChapter(String title) {
  final match = RegExp(
    r'^([^\d]*?)([零〇一二三四五六七八九十百千万两]+)(.*)$',
  ).firstMatch(title);
  if (match == null) return title;
  final value = chineseToInt(match.group(2)!);
  if (value == null) return title;
  return '${match.group(1)}$value${match.group(3)}';
}

int? chineseToInt(String text) {
  const digits = <String, int>{
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  const units = <String, int>{'十': 10, '百': 100, '千': 1000, '万': 10000};
  var total = 0;
  var section = 0;
  var number = 0;
  for (final char in text.split('')) {
    if (digits.containsKey(char)) {
      number = digits[char]!;
      continue;
    }
    final unit = units[char];
    if (unit == null) continue;
    if (unit == 10000) {
      section += number;
      total += (section == 0 ? 1 : section) * unit;
      section = 0;
      number = 0;
    } else {
      section += (number == 0 ? 1 : number) * unit;
      number = 0;
    }
  }
  final result = total + section + number;
  return result == 0 && !text.contains('零') && !text.contains('〇')
      ? null
      : result;
}

String randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

List<int> _decodeBase64(String text) {
  var value = text.trim().replaceAll(RegExp(r'\s'), '');
  value = value.replaceAll('-', '+').replaceAll('_', '/');
  final padding = value.length % 4;
  if (padding == 2) {
    value += '==';
  } else if (padding == 3) {
    value += '=';
  }
  try {
    return base64Decode(value);
  } on Object {
    return const <int>[];
  }
}

List<int> _cipherTextBytes(Object? data) {
  if (data is List) return data.map((e) => e is num ? e.toInt() : 0).toList();
  final text = data?.toString() ?? '';
  final base64Bytes = _decodeBase64(text);
  if (base64Bytes.isNotEmpty) return base64Bytes;
  final hexBytes = _hexToBytes(text);
  if (hexBytes.isNotEmpty) return hexBytes;
  return utf8.encode(text);
}

List<int> _bytesOf(Object? value) {
  if (value == null) return <int>[];
  if (value is Uint8List) return value;
  if (value is List) {
    return value.map((e) => e is num ? e.toInt() : 0).toList();
  }
  return utf8.encode(value.toString());
}

List<int> _hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (clean.length.isOdd || clean.isEmpty) return const <int>[];
  return <int>[
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}

Uint8List _fitKey(List<int> key, int size) {
  final out = Uint8List(size);
  out.setRange(0, min(key.length, size), key);
  return out;
}

Uint8List _fitIv(List<int> iv, int size) {
  final out = Uint8List(size);
  if (iv.isNotEmpty) out.setRange(0, min(iv.length, size), iv);
  return out;
}

String _decodeText(List<int> bytes, String? charset) {
  if (charset == null || charset.isEmpty || charset.toLowerCase() == 'utf-8') {
    return utf8.decode(bytes, allowMalformed: true);
  }
  final encoding = Charset.getByName(charset);
  if (encoding == null) return utf8.decode(bytes, allowMalformed: true);
  try {
    return encoding.decode(bytes);
  } on Object {
    return utf8.decode(bytes, allowMalformed: true);
  }
}
