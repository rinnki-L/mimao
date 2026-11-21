/// 本地漫画落盘清单（payload JSON）。
///
/// 下载器把章节目录/页数/封面写进 `comic_local.payload`；本地详情与阅读器
/// 只读这份清单，不反查源站。手工导入的旧数据没有清单时，读取侧回退到扫描
/// 文件夹（见 [ComicLocalContent]）。
library;

import 'dart:convert';

/// 清单格式版本；未来字段变更时据此兼容旧下载。
const String localComicManifestFormat = 'mimao-local-v1';

/// 一章的落盘信息。[dir] 是漫画根目录下的相对目录名；空串表示根目录
/// （单章漫画）。
class LocalComicChapterInfo {
  final String id;
  final String title;
  final String dir;
  final int pages;

  const LocalComicChapterInfo({
    required this.id,
    required this.title,
    required this.dir,
    required this.pages,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'dir': dir,
    'pages': pages,
  };

  factory LocalComicChapterInfo.fromJson(Map<String, Object?> json) =>
      LocalComicChapterInfo(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        dir: json['dir']?.toString() ?? '',
        pages: (json['pages'] as num?)?.toInt() ?? 0,
      );
}

/// 一部本地漫画的落盘清单。
class LocalComicManifest {
  /// 原在线源 key（手工导入的本地漫画为空）。
  final String sourceName;

  /// 原源展示名（详情页「来源」行用）。
  final String sourceTitle;

  /// 原详情标识（将来换源/回源用；可为空）。
  final String detailUrl;

  final String description;

  /// 封面相对路径；空串表示没有本地封面。
  final String cover;

  final List<LocalComicChapterInfo> chapters;

  final DateTime? downloadedAt;

  const LocalComicManifest({
    this.sourceName = '',
    this.sourceTitle = '',
    this.detailUrl = '',
    this.description = '',
    this.cover = '',
    this.chapters = const <LocalComicChapterInfo>[],
    this.downloadedAt,
  });

  int get pageCount => chapters.fold(0, (sum, chapter) => sum + chapter.pages);

  Map<String, Object?> toJson() => <String, Object?>{
    'format': localComicManifestFormat,
    'sourceName': sourceName,
    'sourceTitle': sourceTitle,
    'detailUrl': detailUrl,
    'description': description,
    'cover': cover,
    'chapters': [for (final chapter in chapters) chapter.toJson()],
    'downloadedAt': downloadedAt?.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  /// 解析 payload；坏 JSON/非本格式返回 null，由调用方回退扫描文件夹。
  static LocalComicManifest? tryParse(String payload) {
    if (payload.trim().isEmpty || payload == '{}') return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) return null;
      if (decoded['format'] != localComicManifestFormat &&
          !decoded.containsKey('chapters')) {
        return null;
      }
      final rawChapters = decoded['chapters'];
      return LocalComicManifest(
        sourceName: decoded['sourceName']?.toString() ?? '',
        sourceTitle: decoded['sourceTitle']?.toString() ?? '',
        detailUrl: decoded['detailUrl']?.toString() ?? '',
        description: decoded['description']?.toString() ?? '',
        cover: decoded['cover']?.toString() ?? '',
        chapters: rawChapters is List
            ? [
                for (final item in rawChapters)
                  if (item is Map)
                    LocalComicChapterInfo.fromJson(
                      item.map((key, value) => MapEntry('$key', value)),
                    ),
              ]
            : const <LocalComicChapterInfo>[],
        downloadedAt: DateTime.tryParse(
          decoded['downloadedAt']?.toString() ?? '',
        ),
      );
    } on Object {
      return null;
    }
  }
}
