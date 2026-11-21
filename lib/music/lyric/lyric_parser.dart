/// 歌词解析器：把 `MusicLyricDownload` 里的 base64 文档解成时间轴歌词。
///
/// 支持三种 wire 格式（与上游 `contenttype` 对应）：
/// - `krc`：base64 → 校验 `krc1` 魔数 → 16 字节固定密钥循环 XOR →
///   zlib 解压 → UTF-8；行格式 `[startMs,durationMs]字标签<offset,duration,ext>文本`；
///   同时解析明文里的 `[language:<base64 JSON>]`（type 1 翻译、type 0 音译）。
/// - `lrc`：base64 → UTF-8，解析 `[mm:ss.xx]文本`（支持一行多个时间戳）。
/// - `text`：base64 → UTF-8 纯文本，按行给递增的伪时间轴。
///
/// `parseLyric` 不抛异常：格式未知、base64 损坏、KRC 魔数/解压失败等一律
/// 返回空行列表，交给 UI 显示「暂无歌词」。
library;

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/models/lyric_models.dart';

/// KRC 固定 16 字节 XOR 密钥。
///
/// 来源：上游 `hoowhoami/EchoMusicNext` 的 `services/lyrics/LyricParser.cpp`
/// `unpackKrc()`（与社区 KRC 解析器一致）：
/// `{0x40,0x47,0x61,0x77,0x5e,0x32,0x74,0x47,0x51,0x36,0x31,0x2d,0xce,0xd2,0x6e,0x69}`。
const List<int> _krcXorKey = <int>[
  0x40,
  0x47,
  0x61,
  0x77,
  0x5e,
  0x32,
  0x74,
  0x47,
  0x51,
  0x36,
  0x31,
  0x2d,
  0xce,
  0xd2,
  0x6e,
  0x69,
];

/// 无歌词结果（所有失败路径共用一个常量，避免反复分配）。
const ParsedLyric _emptyLyric = ParsedLyric(lines: <LyricLine>[]);

/// KRC 行头：`[startMs,durationMs]`。
final RegExp _krcLinePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');

/// KRC 逐字标签：`<offset,duration,ext>`（ext 一般为 0）。
final RegExp _krcWordTagPattern = RegExp(r'<\d+,\d+,-?\d+>');

/// LRC 时间戳：`[mm:ss]`、`[mm:ss.xx]` 或 `[mm:ss.xxx]`。
final RegExp _lrcTimestampPattern = RegExp(
  r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
);

/// 解析歌词下载结果。[parseLyric] 永不抛异常，失败返回空行列表。
ParsedLyric parseLyric(MusicLyricDownload download) {
  try {
    switch (download.format.toLowerCase()) {
      case 'krc':
        return _parseKrc(download.content);
      case 'lrc':
        return _parseLrc(download.content);
      case 'text':
        return _parseText(download.content);
      default:
        return _emptyLyric;
    }
  } catch (_) {
    // 解析属于展示增强，任何异常都降级为「无歌词」，不影响播放主链路。
    return _emptyLyric;
  }
}

/// KRC：完整解密链后按行解析，并应用 `[language:...]` 翻译/音译。
ParsedLyric _parseKrc(String content) {
  final plain = _decryptKrc(content);
  if (plain == null) return _emptyLyric;

  final builders = <_KrcLineBuilder>[];
  final translations = <int, String>{};
  final transliterations = <int, String>{};

  for (final raw in const LineSplitter().convert(plain)) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;

    final language = _decodeLanguageTag(line);
    if (language != null) {
      for (final entry in language) {
        final type = _asInt(entry['type']);
        final rows = entry['lyricContent'];
        if (type == null || (type != 0 && type != 1) || rows is! List) {
          continue;
        }
        // 只接受 language==0（或未给出）的条目，与上游 enrich 一致。
        final languageCode = _asInt(entry['language']);
        if (languageCode != null && languageCode != 0) continue;

        for (var i = 0; i < rows.length; i++) {
          final row = rows[i];
          if (row is! List) continue;
          final text = row.whereType<String>().join().trim();
          if (text.isEmpty) continue;
          if (type == 1) {
            translations[i] = text;
          } else {
            transliterations[i] = text;
          }
        }
      }
      continue;
    }

    final match = _krcLinePattern.firstMatch(line);
    if (match == null) continue;

    final startMs = int.tryParse(match.group(1)!);
    final durationMs = int.tryParse(match.group(2)!);
    if (startMs == null || durationMs == null) continue;

    final body = match.group(3)!.replaceAll(_krcWordTagPattern, '');
    final index = builders.length;
    builders.add(
      _KrcLineBuilder(
        order: index,
        start: Duration(milliseconds: startMs),
        duration: Duration(milliseconds: durationMs),
        original: body,
        translation: translations[index],
        transliteration: transliterations[index],
      ),
    );
  }

  // 语言行可能在正文之后出现，这里再按最终行索引补一次。
  for (var i = 0; i < builders.length; i++) {
    builders[i].translation = translations[i];
    builders[i].transliteration = transliterations[i];
  }

  if (builders.isEmpty) return _emptyLyric;

  builders.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.order.compareTo(b.order);
  });

  final lines = <LyricLine>[];
  for (var i = 0; i < builders.length; i++) {
    final current = builders[i];
    var end = current.duration > Duration.zero
        ? current.start + current.duration
        : _lineEndFallback(current.start, builders, i);
    if (end <= current.start) {
      end = _lineEndFallback(current.start, builders, i);
    }
    lines.add(
      LyricLine(
        start: current.start,
        end: end,
        original: current.original,
        translation: current.translation,
        transliteration: current.transliteration,
      ),
    );
  }
  return ParsedLyric(lines: lines);
}

/// 行结束时间兜底：下一行开始，否则开始 + 4 秒。
Duration _lineEndFallback(
  Duration start,
  List<_KrcLineBuilder> builders,
  int index,
) {
  if (index + 1 < builders.length) {
    final next = builders[index + 1].start;
    if (next > start) return next;
  }
  return start + const Duration(seconds: 4);
}

/// 校验魔数并解密 KRC；失败返回 null。
String? _decryptKrc(String content) {
  try {
    final packed = base64Decode(content.replaceAll(RegExp(r'\s'), ''));
    // 至少要有 4 字节魔数 + 1 字节载荷。
    if (packed.length <= 4) return null;
    final isKrc =
        packed[0] == 0x6b && // k
        packed[1] == 0x72 && // r
        packed[2] == 0x63 && // c
        packed[3] == 0x31; // 1
    if (!isKrc) return null;

    final decrypted = Uint8List(packed.length - 4);
    for (var i = 0; i < decrypted.length; i++) {
      decrypted[i] = packed[i + 4] ^ _krcXorKey[i % _krcXorKey.length];
    }
    final inflated = ZLibDecoder().convert(decrypted);
    return utf8.decode(inflated, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// 解析 `[language:<base64 JSON>]`；不是语言行返回 null。
List<Map<String, Object?>>? _decodeLanguageTag(String line) {
  if (!line.startsWith('[language:') || !line.endsWith(']')) return null;
  final encoded = line.substring(10, line.length - 1);
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Decode(encoded.replaceAll(RegExp(r'\s'), ''))),
    );
    if (decoded is! Map) return const <Map<String, Object?>>[];
    final content = decoded['content'];
    if (content is! List) return const <Map<String, Object?>>[];
    return content.whereType<Map>().map((entry) {
      return entry.map((key, value) => MapEntry('$key', value));
    }).toList();
  } catch (_) {
    // 语言块损坏不影响正文歌词展示。
    return const <Map<String, Object?>>[];
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// LRC：解析 `[mm:ss.xx]文本`，一行可带多个时间戳。
ParsedLyric _parseLrc(String content) {
  final text = _decodeBase64Text(content);
  if (text == null) return _emptyLyric;

  final entries = <_LrcEntry>[];
  var order = 0;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimRight();
    final matches = _lrcTimestampPattern.allMatches(line).toList();
    if (matches.isEmpty) continue;

    final body = line.substring(matches.last.end).trim();
    if (body.isEmpty) continue;

    for (final match in matches) {
      final minutes = int.tryParse(match.group(1)!);
      final seconds = int.tryParse(match.group(2)!);
      if (minutes == null || seconds == null) continue;
      final fractionText = match.group(3);
      var fractionMs = 0;
      if (fractionText != null && fractionText.isNotEmpty) {
        // `.x` = 100ms、`.xx` = 10ms、`.xxx` = 1ms。
        final value = int.parse(fractionText.padRight(3, '0'));
        fractionMs = value;
      }
      final start = Duration(
        milliseconds: minutes * 60 * 1000 + seconds * 1000 + fractionMs,
      );
      entries.add(_LrcEntry(start: start, text: body, order: order++));
    }
  }

  if (entries.isEmpty) return _emptyLyric;

  entries.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.order.compareTo(b.order);
  });

  final lines = <LyricLine>[];
  for (var i = 0; i < entries.length; i++) {
    final current = entries[i];
    var end = i + 1 < entries.length
        ? entries[i + 1].start
        : current.start + const Duration(seconds: 4);
    if (end <= current.start) {
      end = current.start + const Duration(seconds: 4);
    }
    lines.add(
      LyricLine(start: current.start, end: end, original: current.text),
    );
  }
  return ParsedLyric(lines: lines);
}

/// 纯文本：无时间戳，按行给 4 秒递增的伪时间轴，仅供列表显示/高亮。
ParsedLyric _parseText(String content) {
  final text = _decodeBase64Text(content);
  if (text == null) return _emptyLyric;

  final lines = <LyricLine>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final start = Duration(seconds: 4 * lines.length);
    lines.add(
      LyricLine(
        start: start,
        end: start + const Duration(seconds: 4),
        original: line,
      ),
    );
  }
  return ParsedLyric(lines: lines);
}

/// 按契约 content 恒为 base64；解码失败返回 null（由调用方降级为空歌词）。
String? _decodeBase64Text(String content) {
  try {
    return utf8.decode(
      base64Decode(content.replaceAll(RegExp(r'\s'), '')),
      allowMalformed: true,
    );
  } catch (_) {
    return null;
  }
}

/// KRC 解析过程中的可变行（翻译/音译按原始行索引回填）。
class _KrcLineBuilder {
  _KrcLineBuilder({
    required this.order,
    required this.start,
    required this.duration,
    required this.original,
    this.translation,
    this.transliteration,
  });

  final Duration start;
  final Duration duration;
  final String original;

  /// 原始文件顺序，用于同一时间戳下的稳定排序。
  final int order;

  String? translation;
  String? transliteration;
}

/// LRC 中间条目。
class _LrcEntry {
  const _LrcEntry({
    required this.start,
    required this.text,
    required this.order,
  });

  final Duration start;
  final String text;
  final int order;
}
