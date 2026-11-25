/// 编码嗅探与分段解码（TXT / Markdown 用）。
///
/// 思路对齐 legado 的 `CharsetDetector`（ICU 嗅探）：**先看 BOM，再严格试解**，
/// 只有「能完整解出来」的编码才进入候选；多个候选都能解时按字符合理性打分
/// （汉字/常用标点占比高、私用区与生僻块占比低者胜）。全部失败才回退 UTF-8
/// 宽松解码（坏字节变 U+FFFD）并标记 `lossy`，由导入页提示用户。
///
/// 判定只读文件头（默认 64 KB）：几 MB 的 TXT 不必整本进内存；真正解码某一章
/// 时按章区间单独解，见 [decodeNovelText]。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chinese_codec/chinese_codec.dart' as cc;

import 'local_models.dart';

/// 嗅探只看这么多字节（够 3 万字样本，且不会把大文件拖慢）。
const int novelSniffWindow = 64 * 1024;

/// 嗅探结果：编码 + 是否出现坏字节 + 可读警告。
class NovelEncodingGuess {
  const NovelEncodingGuess({
    required this.encoding,
    this.lossy = false,
    this.warning,
  });

  final NovelTextEncoding encoding;
  final bool lossy;
  final String? warning;
}

/// 对一段字节做编码嗅探。
///
/// [bytes] 可以是整份文件，也可以是文件头样本；判定只看前 [novelSniffWindow]
/// 字节。空输入按 UTF-8 处理（空文件不该报编码错误）。
NovelEncodingGuess sniffNovelEncoding(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const NovelEncodingGuess(encoding: NovelTextEncoding.utf8);
  }

  final bom = _bomEncoding(bytes);
  if (bom != null) {
    return NovelEncodingGuess(encoding: bom);
  }

  final sample = bytes.length > novelSniffWindow
      ? Uint8List.sublistView(bytes, 0, novelSniffWindow)
      : bytes;

  // UTF-8 优先：能严格解出来的字节，几乎不可能是 GBK/Big5 的巧合
  // （中文双字节里出现合法 UTF-8 多字节序列的概率极低）。
  if (cc.tryDecode(sample, utf8) != null) {
    return const NovelEncodingGuess(encoding: NovelTextEncoding.utf8);
  }

  // UTF-16 没有 BOM 时靠「零字节分布」判断：ASCII 为主的 UTF-16 文本里，
  // 每两个字节有一个是 0。
  final utf16 = _guessUtf16WithoutBom(sample);
  if (utf16 != null) {
    return NovelEncodingGuess(encoding: utf16);
  }

  final scored = <(NovelTextEncoding, double)>[];
  for (final entry in _chineseCandidates) {
    final text = cc.tryDecode(sample, entry.$2);
    if (text == null) continue;
    scored.add((entry.$1, _plausibility(text)));
  }
  if (scored.isNotEmpty) {
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // 分数太差（大量私用区/控制字符）说明这段字节根本不是这种中文编码。
    if (scored.first.$2 >= 0.55) {
      return NovelEncodingGuess(encoding: scored.first.$1);
    }
  }

  return const NovelEncodingGuess(
    encoding: NovelTextEncoding.utf8,
    lossy: true,
    warning:
        '没能识别出文件编码（不是 UTF-8/UTF-16/GBK/GB18030/Big5），'
        '已按 UTF-8 宽松解码，个别字可能显示成「�」。',
  );
}

/// 按指定编码解码一段字节；[lossy] 为真时坏字节变 U+FFFD 而不是抛异常。
///
/// 解码前剥掉 BOM（否则首章标题会带一个不可见字符，目录匹配与书签定位都会歪）。
String decodeNovelText(
  Uint8List bytes,
  NovelTextEncoding encoding, {
  bool lossy = false,
}) {
  switch (encoding) {
    case NovelTextEncoding.utf8:
      return _stripBom(utf8.decode(bytes, allowMalformed: lossy));
    case NovelTextEncoding.utf16le:
      return _stripBom(_decodeUtf16(bytes, littleEndian: true, lossy: lossy));
    case NovelTextEncoding.utf16be:
      return _stripBom(_decodeUtf16(bytes, littleEndian: false, lossy: lossy));
    case NovelTextEncoding.gbk:
      return _stripBom(
        (lossy ? const cc.GbkCodec(allowInvalid: true) : cc.gbk).decode(bytes),
      );
    case NovelTextEncoding.gb18030:
      return _stripBom(
        (lossy ? const cc.Gb18030Codec(allowInvalid: true) : cc.gb18030).decode(
          bytes,
        ),
      );
    case NovelTextEncoding.big5:
      return _stripBom(
        (lossy ? const cc.Big5Codec(allowInvalid: true) : cc.big5).decode(
          bytes,
        ),
      );
  }
}

/// 分段解码的**安全边界**：多字节字符可能被区段切开，解码前把末尾不完整
/// 的字节让给下一段。返回调整后的结束位置（可能小于 [end]）。
///
/// 只处理中文双字节与 UTF-8 多字节的尾部：宁可让一章少一两个字节（下一章
/// 开头会多出这几个字节的字符），也不要每章末尾冒一个「�」。
int safeDecodeEnd(Uint8List bytes, int start, int end, NovelTextEncoding enc) {
  if (end <= start) return start;
  if (enc.isUtf16) {
    // UTF-16 必须 2 字节对齐；奇数长度时退一个字节。
    return (end - start).isEven ? end : end - 1;
  }
  switch (enc) {
    case NovelTextEncoding.utf8:
      // 回退到最后一个 UTF-8 起始字节之前，若它声明的长度跨出 end 就砍掉。
      var index = end - 1;
      var back = 0;
      while (index > start && back < 3) {
        final byte = bytes[index];
        if (byte & 0xC0 == 0x80) {
          index--;
          back++;
          continue;
        }
        final need = byte >= 0xF0
            ? 4
            : byte >= 0xE0
            ? 3
            : byte >= 0xC0
            ? 2
            : 1;
        final consumed = end - index;
        return consumed >= need ? end : index;
      }
      return end;
    case NovelTextEncoding.gbk:
    case NovelTextEncoding.gb18030:
    case NovelTextEncoding.big5:
      // 双字节编码：若末尾字节是高位字节（>=0x81），它后面的低位字节不在本段。
      final last = bytes[end - 1];
      return last >= 0x81 && last <= 0xFE ? end - 1 : end;
    case NovelTextEncoding.utf16le:
    case NovelTextEncoding.utf16be:
      return end;
  }
}

// ── 内部 ────────────────────────────────────────────────────────────────

/// 中文候选（顺序即并列时的优先级）。
///
/// GBK 排在 GB18030 前面：GBK ⊂ GB18030（GB18030 只多出四字节序列），
/// 「GBK 能完整解出来」就说明它是 GBK 能表达的文件，标 GBK 更贴近用户认知；
/// 真含四字节生僻字的文件 GBK 解不出，自然落到 GB18030。
final List<(NovelTextEncoding, Encoding)> _chineseCandidates =
    <(NovelTextEncoding, Encoding)>[
      (NovelTextEncoding.gbk, cc.gbk),
      (NovelTextEncoding.gb18030, cc.gb18030),
      (NovelTextEncoding.big5, cc.big5),
    ];

NovelTextEncoding? _bomEncoding(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return NovelTextEncoding.utf8;
  }
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) return NovelTextEncoding.utf16le;
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) return NovelTextEncoding.utf16be;
  }
  return null;
}

/// 无 BOM 的 UTF-16：统计奇偶位置的零字节比例。
NovelTextEncoding? _guessUtf16WithoutBom(Uint8List sample) {
  final usable = sample.length - (sample.length % 2);
  if (usable < 16) return null;
  var zeroEven = 0;
  var zeroOdd = 0;
  final limit = usable.clamp(0, 4096);
  for (var i = 0; i < limit; i += 2) {
    if (sample[i] == 0) zeroEven++;
    if (sample[i + 1] == 0) zeroOdd++;
  }
  final pairs = limit ~/ 2;
  if (pairs == 0) return null;
  final evenRatio = zeroEven / pairs;
  final oddRatio = zeroOdd / pairs;
  if (oddRatio > 0.3 && evenRatio < 0.05) return NovelTextEncoding.utf16le;
  if (evenRatio > 0.3 && oddRatio < 0.05) return NovelTextEncoding.utf16be;
  return null;
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  required bool lossy,
}) {
  final usable = bytes.length - (bytes.length % 2);
  final units = Uint16List(usable ~/ 2);
  final data = ByteData.sublistView(bytes, 0, usable);
  for (var i = 0; i < units.length; i++) {
    units[i] = data.getUint16(i * 2, littleEndian ? Endian.little : Endian.big);
  }
  // allowMalformed 只影响孤立代理项：成对的代理项仍会正确合成 emoji 等字符。
  return String.fromCharCodes(units);
}

String _stripBom(String text) =>
    text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF ? text.substring(1) : text;

/// 一段解码文本的「像不像中文正文」打分（0..1）。
///
/// 分项：CJK 汉字与中文标点得分，ASCII 可见字符（含换行）少量得分，
/// 私用区/控制字符/替换字符扣分。GBK 与 Big5 的字节空间重叠，靠这个分数
/// 在两者都能严格解出来时选更合理的一边。
double _plausibility(String text) {
  if (text.isEmpty) return 0;
  var good = 0;
  var bad = 0;
  for (final rune in text.runes) {
    if (rune == 0xFFFD) {
      bad += 3;
    } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
      good += 2;
    } else if (rune >= 0x3400 && rune <= 0x4DBF) {
      good += 1;
    } else if (rune >= 0x3000 && rune <= 0x303F) {
      good += 2; // 中文标点
    } else if (rune >= 0xFF00 && rune <= 0xFFEF) {
      good += 1; // 全角
    } else if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
      good += 1;
    } else if (rune >= 0x20 && rune <= 0x7E) {
      good += 1;
    } else if (rune >= 0xE000 && rune <= 0xF8FF) {
      bad += 4; // 私用区：几乎只会出现在「编码猜错了」
    } else if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      bad += 4; // 控制字符
    } else {
      // 其余（韩文/日文/拉丁扩展等）中性偏负：中文正文里占比很低。
      bad += 1;
    }
  }
  final score = (good - bad) / (good + bad);
  return score.isFinite ? score.clamp(0.0, 1.0) : 0;
}
