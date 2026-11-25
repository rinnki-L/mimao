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
  final isDes = name == 'DES' || name == 'DESEDE' || name == 'TRIPLEDES';
  // DESedeEngine 只收 16/24 字节，AES 收 16/24/32；长度合法就原样用，
  // 别把 24 字节密钥三倍拼成 72——引擎会 ArgumentError，被吞成"正文抓空"。
  final keyValue = isDes
      ? _fitDesEdeKey(keyBytes)
      : _fitKey(keyBytes, _aesKeySize(keyBytes.length));

  final cipher = mode == 'ECB' ? blockCipher : pc.CBCBlockCipher(blockCipher);
  final pc.CipherParameters rawParams = mode == 'ECB'
      ? pc.KeyParameter(keyValue)
      : pc.ParametersWithIV(
          pc.KeyParameter(keyValue),
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

/// 简→繁常用字表（高频逐字映射，键简体值繁体）。
/// 书源 t2s/s2t 多为搜索词/标题的字级转换；不在表内的字原样保留。
/// 这里只放有把握的一一对应字，避免像 OpenCC 短语级那样出错。
const Map<String, String> _simplifiedToTraditional = <String, String>{
  '万': '萬',
  '与': '與',
  '丑': '醜',
  '专': '專',
  '业': '業',
  '丛': '叢',
  '丝': '絲',
  '丢': '丟',
  '乔': '喬',
  '书': '書',
  '买': '買',
  '乱': '亂',
  '争': '爭',
  '于': '於',
  '亏': '虧',
  '云': '雲',
  '亚': '亞',
  '产': '產',
  '亩': '畝',
  '亲': '親',
  '亿': '億',
  '仅': '僅',
  '从': '從',
  '仑': '侖',
  '仓': '倉',
  '仪': '儀',
  '们': '們',
  '传': '傳',
  '伟': '偉',
  '侧': '側',
  '侦': '偵',
  '侨': '僑',
  '偿': '償',
  '储': '儲',
  '儿': '兒',
  '党': '黨',
  '内': '內',
  '冈': '岡',
  '册': '冊',
  '写': '寫',
  '军': '軍',
  '农': '農',
  '冯': '馮',
  '冲': '沖',
  '决': '決',
  '况': '況',
  '净': '淨',
  '凉': '涼',
  '减': '減',
  '凑': '湊',
  '几': '幾',
  '凤': '鳳',
  '凭': '憑',
  '凯': '凱',
  '击': '擊',
  '凿': '鑿',
  '划': '劃',
  '刘': '劉',
  '则': '則',
  '刚': '剛',
  '创': '創',
  '删': '刪',
  '别': '別',
  '制': '製',
  '刹': '剎',
  '刽': '劊',
  '剂': '劑',
  '剥': '剝',
  '剧': '劇',
  '议': '議',
  '讯': '訊',
  '记': '記',
  '订': '訂',
  '计': '計',
  '认': '認',
  '讥': '譏',
  '讨': '討',
  '让': '讓',
  '训': '訓',
  '访': '訪',
  '许': '許',
  '讼': '訟',
  '讽': '諷',
  '设': '設',
  '诀': '訣',
  '证': '證',
  '诅': '詛',
  '词': '詞',
  '诗': '詩',
  '诓': '誆',
  '诚': '誠',
  '诛': '誅',
  '话': '話',
  '诳': '誑',
  '说': '說',
  '读': '讀',
  '请': '請',
  '诸': '諸',
  '诺': '諾',
  '谋': '謀',
  '谓': '謂',
  '谦': '謙',
  '谨': '謹',
  '谣': '謠',
  '谷': '穀',
  '丰': '豐',
  '丽': '麗',
  '举': '舉',
  '么': '麼',
  '义': '義',
  '乌': '烏',
  '乐': '樂',
  '习': '習',
  '乡': '鄉',
  '亘': '亙',
  '对': '對',
  '导': '導',
  '寿': '壽',
  '将': '將',
  '尔': '爾',
  '尘': '塵',
  '尧': '堯',
  '届': '屆',
  '属': '屬',
  '屡': '屢',
  '屿': '嶼',
  '岁': '歲',
  '岂': '豈',
  '岗': '崗',
  '岚': '嵐',
  '岛': '島',
  '岭': '嶺',
  '峡': '峽',
  '崂': '嶗',
  '巅': '巔',
  '巩': '鞏',
  '币': '幣',
  '帅': '帥',
  '师': '師',
  '帘': '簾',
  '帜': '幟',
  '带': '帶',
  '帧': '幀',
  '帮': '幫',
  '广': '廣',
  '庄': '莊',
  '庆': '慶',
  '庐': '廬',
  '库': '庫',
  '应': '應',
  '庙': '廟',
  '庞': '龐',
  '废': '廢',
  '开': '開',
  '弃': '棄',
  '异': '異',
  '弯': '彎',
  '弹': '彈',
  '强': '強',
  '归': '歸',
  '当': '當',
  '录': '錄',
  '彦': '彥',
  '单': '單',
  '卖': '賣',
  '占': '佔',
  '卫': '衛',
  '却': '卻',
  '厌': '厭',
  '齐': '齊',
  '龄': '齡',
  '龙': '龍',
  '龟': '龜',
};

/// 繁→简常用字表（[_simplifiedToTraditional] 的反表，惰性构建）。
final Map<String, String> _traditionalToSimplified = <String, String>{
  for (final entry in _simplifiedToTraditional.entries)
    if (entry.value != entry.key) entry.value: entry.key,
};

/// DER DigestInfo 前缀（PKCS#1 v1.5 签名：OID + NULL + 摘要长度头）。
const Map<String, List<int>> _pkcs1DigestInfoPrefix = <String, List<int>>{
  'MD5': <int>[
    0x30,
    0x20,
    0x30,
    0x0c,
    0x06,
    0x08,
    0x2a,
    0x86,
    0x48,
    0x86,
    0xf7,
    0x0d,
    0x02,
    0x05,
    0x05,
    0x00,
    0x04,
    0x10,
  ],
  'SHA1': <int>[
    0x30,
    0x21,
    0x30,
    0x09,
    0x06,
    0x05,
    0x2b,
    0x0e,
    0x03,
    0x02,
    0x1a,
    0x05,
    0x00,
    0x04,
    0x14,
  ],
  'SHA224': <int>[
    0x30,
    0x2d,
    0x30,
    0x0d,
    0x06,
    0x09,
    0x60,
    0x86,
    0x48,
    0x01,
    0x65,
    0x03,
    0x04,
    0x02,
    0x04,
    0x05,
    0x00,
    0x04,
    0x1c,
  ],
  'SHA256': <int>[
    0x30,
    0x31,
    0x30,
    0x0d,
    0x06,
    0x09,
    0x60,
    0x86,
    0x48,
    0x01,
    0x65,
    0x03,
    0x04,
    0x02,
    0x01,
    0x05,
    0x00,
    0x04,
    0x20,
  ],
  'SHA384': <int>[
    0x30,
    0x41,
    0x30,
    0x0d,
    0x06,
    0x09,
    0x60,
    0x86,
    0x48,
    0x01,
    0x65,
    0x03,
    0x04,
    0x02,
    0x02,
    0x05,
    0x00,
    0x04,
    0x30,
  ],
  'SHA512': <int>[
    0x30,
    0x51,
    0x30,
    0x0d,
    0x06,
    0x09,
    0x60,
    0x86,
    0x48,
    0x01,
    0x65,
    0x03,
    0x04,
    0x02,
    0x03,
    0x05,
    0x00,
    0x04,
    0x40,
  ],
};

BigInt _bigIntOf(List<int> bytes) => bytes.fold<BigInt>(
  BigInt.zero,
  (acc, byte) => (acc << 8) | BigInt.from(byte),
);

Uint8List _toFixedBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

class _DerReader {
  _DerReader(this.bytes);
  final List<int> bytes;
  int _offset = 0;

  _DerReader readSequence() {
    _expect(0x30);
    return _DerReader(readValue());
  }

  List<int> readInteger() {
    _expect(0x02);
    return readValue();
  }

  void _expect(int tag) {
    if (_offset >= bytes.length || bytes[_offset] != tag) {
      throw const FormatException('bad DER tag');
    }
    _offset++;
  }

  List<int> readValue() {
    if (_offset >= bytes.length) throw const FormatException('bad DER length');
    var length = bytes[_offset++];
    if (length & 0x80 != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 4 || _offset + count > bytes.length) {
        throw const FormatException('bad DER long length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[_offset++];
      }
    }
    if (_offset + length > bytes.length) {
      throw const FormatException('DER value out of bounds');
    }
    final value = bytes.sublist(_offset, _offset + length);
    _offset += length;
    return value;
  }
}

/// 解析 base64 DER 的 PKCS#1 RSA 密钥，返回 {n, e, d?}。
/// 公钥 SEQUENCE{n, e}；私钥 SEQUENCE{n, e, d}（部分书源带 version 前缀）。
({BigInt n, BigInt e, BigInt? d})? rsaKeyParts(String encoded) {
  final bytes = _decodeBase64(encoded);
  if (bytes.isEmpty) return null;
  try {
    final seq = _DerReader(bytes).readSequence();
    final a = seq.readInteger();
    final b = seq.readInteger();
    if (a.isEmpty || b.isEmpty) return null;
    final first = _bigIntOf(a);
    final second = _bigIntOf(b);
    // 带 version=0 的私钥：SEQUENCE{version=0, n, e, d, ...}
    if (second == BigInt.zero) {
      final n = seq.readInteger();
      final e = seq.readInteger();
      final d = seq.readInteger();
      if (n.isEmpty || e.isEmpty || d.isEmpty) return null;
      return (n: _bigIntOf(n), e: _bigIntOf(e), d: _bigIntOf(d));
    }
    // 公钥 SEQUENCE{n, e} 没有第三个整数；用 try 区分。
    final List<int> c;
    try {
      c = seq.readInteger();
    } on Object {
      return (n: first, e: second, d: null);
    }
    if (c.isEmpty) return (n: first, e: second, d: null);
    // 省略 version 的私钥 SEQUENCE{n, e, d}：d 的位长接近 n。
    final third = _bigIntOf(c);
    if (third.bitLength > first.bitLength ~/ 2) {
      return (n: first, e: second, d: third);
    }
    return (n: first, e: second, d: null);
  } on Object {
    return null;
  }
}

/// 兼容旧调用：从 base64 DER 解析公钥。
pc.RSAPublicKey? rsaPublicKeyFromBase64(String encoded) {
  final parts = rsaKeyParts(encoded);
  if (parts == null) return null;
  return pc.RSAPublicKey(parts.n, parts.e);
}

/// 算法名 → crypto.Digest，并给出 PKCS#1 DigestInfo 前缀。
({crypto.Hash digest, List<int> prefix})? _digestAndPrefix(String algorithm) {
  final name = algorithm.toUpperCase().replaceAll('-', '');
  final digestName = name.contains('WITH')
      ? name.split('WITH').first
      : name.replaceAll('RSA', '');
  final digest = switch (digestName) {
    'MD5' => crypto.md5,
    'SHA1' => crypto.sha1,
    'SHA224' => crypto.sha224,
    'SHA256' => crypto.sha256,
    'SHA384' => crypto.sha384,
    'SHA512' => crypto.sha512,
    _ => null,
  };
  if (digest == null) return null;
  final prefix = _pkcs1DigestInfoPrefix[digestName];
  if (prefix == null) return null;
  return (digest: digest, prefix: prefix);
}

/// RSA/PKCS#1 v1.5 签名（对齐 legado Sign(algorithm) 的 SHA256withRSA）。
/// 纯 BigInt 模幂：m = EM^d mod n，不需要 p/q。
String rsaSignBase64(String data, String algorithm, String key) {
  final parts = rsaKeyParts(key);
  if (parts == null || parts.d == null) return '';
  final dp = _digestAndPrefix(algorithm);
  if (dp == null) return '';
  final k = (parts.n.bitLength + 7) ~/ 8;
  final t = <int>[...dp.prefix, ...dp.digest.convert(utf8.encode(data)).bytes];
  final psLength = k - t.length - 3;
  if (psLength < 8) return '';
  final em = <int>[0x00, 0x01, ...List<int>.filled(psLength, 0xff), 0x00, ...t];
  return base64Encode(
    _toFixedBytes(_bigIntOf(em).modPow(parts.d!, parts.n), k),
  );
}

/// 验签：s^e mod n 解出 EM，比对 PKCS#1 v1.5 结构。
bool rsaVerifyBase64(
  String data,
  String algorithm,
  String publicKey,
  String signatureBase64,
) {
  final parts = rsaKeyParts(publicKey);
  if (parts == null) return false;
  final dp = _digestAndPrefix(algorithm);
  if (dp == null) return false;
  final k = (parts.n.bitLength + 7) ~/ 8;
  final sigBytes = _decodeBase64(signatureBase64);
  if (sigBytes.length != k) return false;
  final em = _toFixedBytes(_bigIntOf(sigBytes).modPow(parts.e, parts.n), k);
  final t = <int>[...dp.prefix, ...dp.digest.convert(utf8.encode(data)).bytes];
  final psLength = k - t.length - 3;
  if (psLength < 8) return false;
  final expected = <int>[
    0x00,
    0x01,
    ...List<int>.filled(psLength, 0xff),
    0x00,
    ...t,
  ];
  for (var i = 0; i < k; i++) {
    if (em[i] != expected[i]) return false;
  }
  return true;
}

/// RSA/PKCS#1 v1.5 加密：EM = 00 02 || PS(>=8 随机非零) || 00 || M。
String rsaEncryptBase64(String data, String key) {
  final parts = rsaKeyParts(key);
  if (parts == null) return '';
  final k = (parts.n.bitLength + 7) ~/ 8;
  final m = utf8.encode(data);
  final psLength = k - m.length - 3;
  if (psLength < 8) return '';
  final random = Random.secure();
  final ps = <int>[for (var i = 0; i < psLength; i++) random.nextInt(255) + 1];
  final em = <int>[0x00, 0x02, ...ps, 0x00, ...m];
  return base64Encode(_toFixedBytes(_bigIntOf(em).modPow(parts.e, parts.n), k));
}

/// RSA/PKCS#1 v1.5 解密：c^d mod n，校验 00 02 || PS || 00 || M。
List<int> rsaDecryptBytes(String cipherBase64, String key) {
  final parts = rsaKeyParts(key);
  if (parts == null || parts.d == null) return const <int>[];
  final k = (parts.n.bitLength + 7) ~/ 8;
  final cipher = _decodeBase64(cipherBase64);
  if (cipher.length != k) return const <int>[];
  final em = _toFixedBytes(_bigIntOf(cipher).modPow(parts.d!, parts.n), k);
  if (em.length < 11 || em[0] != 0 || em[1] != 0x02) return const <int>[];
  var separator = -1;
  for (var i = 2; i < em.length; i++) {
    if (em[i] == 0) {
      separator = i;
      break;
    }
  }
  if (separator < 10) return const <int>[];
  return em.sublist(separator + 1);
}

String rsaDecryptText(String cipherBase64, String key) =>
    utf8.decode(rsaDecryptBytes(cipherBase64, key), allowMalformed: true);

/// 简体转繁体（高频逐字表）。
String toTraditional(String text) => text.split('').map((char) {
  return _simplifiedToTraditional[char] ?? char;
}).join();

/// 繁体转简体（高频逐字表）。
String toSimplified(String text) => text.split('').map((char) {
  return _traditionalToSimplified[char] ?? char;
}).join();

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

/// AES 密钥长度：16/24/32 原样用；短了补零，长了截到 32。
int _aesKeySize(int length) {
  if (length == 24 || length == 32) return length;
  if (length > 32) return 32;
  return 16;
}

/// DES/DESede 密钥：JCE 的 DESede 接受 16 字节（K1K2K1）或 24 字节
/// （K1K2K3），pointycastle 同款；单 DES 的 8 字节密钥扩成 K1K1K1。
Uint8List _fitDesEdeKey(List<int> key) {
  if (key.length == 16 || key.length == 24) {
    return Uint8List.fromList(key);
  }
  if (key.length == 8) {
    return Uint8List.fromList(<int>[...key, ...key, ...key]);
  }
  return _fitKey(key, 24);
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
