/// 歌词显示模型：显示模式、单行歌词与解析结果。
///
/// 与 `lib/music/models/lyric_models.dart` 的下载信封（`MusicLyricDownload`）
/// 分离：那边只负责 wire 数据，这里的模型服务于 Flutter 侧的解析与显示。
library;

import 'package:mimao/music/models/music_models.dart';

/// 歌词显示模式。
///
/// - [original]：只显示原文；
/// - [originalWithTranslation]：原文 + 翻译（缺失时退化为只显示原文）；
/// - [originalWithTransliteration]：原文 + 音译/罗马音（缺失时退化为只显示原文）。
enum LyricMode {
  original,
  originalWithTranslation,
  originalWithTransliteration,
}

/// 一行歌词。
class LyricLine {
  const LyricLine({
    required this.start,
    required this.end,
    required this.original,
    this.translation,
    this.transliteration,
  });

  /// 该行开始时间。
  final Duration start;

  /// 该行结束时间（下一行开始或按行时长/估算得到）。
  final Duration end;

  /// 原文（逐字标签已去除、该行所有字已拼接）。
  final String original;

  /// 中翻，可能为 null。
  final String? translation;

  /// 音译/罗马音，可能为 null。
  final String? transliteration;
}

/// 一次歌词解析的结果。
class ParsedLyric {
  const ParsedLyric({required this.lines});

  /// 按时间升序排列的歌词行；空列表表示无歌词。
  final List<LyricLine> lines;
}

/// 歌词加载缝：集成者按曲目取/解析歌词，返回 null 表示无歌词或失败。
///
/// 与 `loadClimax` 同款——UI 层只持闭包，不依赖任何具体 API。
typedef LoadLyric = Future<ParsedLyric?> Function(MusicSong song);
