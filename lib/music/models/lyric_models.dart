/// 歌词下载模型——EchoMusicNext `crates/echo-api/src/module/lyric.rs`
/// `DownloadedLyrics` 的翻译。
///
/// 上游契约：歌词文档的解码（base64 → krc/lrc/text 解析）明确归 C++ 歌词
/// 服务；客户端只透传信封里的原文，不在这里解 base64、不解析歌词文档。
library;

/// 歌词下载结果（lyric.rs `DownloadedLyrics`）。
class MusicLyricDownload {
  const MusicLyricDownload({
    required this.format,
    required this.encoding,
    required this.content,
  });

  /// wire `contenttype` 的映射：0→`krc`、1→`lrc`、2→`text`（其它值上游按
  /// unsupported 拒绝，不会出现在成功结果里）。
  final String format;

  /// 固定 `base64`——内容保持服务端原样，客户端不解码。
  final String encoding;

  /// base64 文档原文（原样透传，不改写、不校验）。
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'encoding': encoding,
    'content': content,
  };

  factory MusicLyricDownload.fromJson(Map<String, Object?> json) =>
      MusicLyricDownload(
        format: '${json['format'] ?? ''}',
        encoding: '${json['encoding'] ?? ''}',
        content: '${json['content'] ?? ''}',
      );
}
