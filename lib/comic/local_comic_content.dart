import 'dart:io';

import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/local_comic_manifest.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:path/path.dart' as p;

/// 本地漫画内容读取：把 `comic_local` 行 + 磁盘目录变成详情页/阅读器要的
/// 章节与图片地址。
///
/// 两种数据来源：
/// - 下载器落盘的清单（[LocalComicManifest]）——章节目录/页数权威；
/// - 手工导入的旧文件夹——没有清单时扫描子目录：每个含图片的子目录是一章，
///   没有子目录则整个根目录算单章。
///
/// 页序用自然排序（001、2、10 按数值而非字典序），避免十页之后的漫画错序。
class ComicLocalContent {
  final ComicLocalService localService;

  ComicLocalContent(this.localService);

  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  };

  Future<ComicLocalEntry?> find(ComicRef ref) => localService.find(ref);

  /// 本地漫画详情：章节列表 + 封面路径 + 简介。
  Future<ComicDetail> detail(ComicLocalEntry entry) async {
    final manifest = LocalComicManifest.tryParse(entry.payload);
    final root = Directory(entry.folderPath);
    final chapters = await _chapters(entry, manifest, root);
    final cover = await _coverPath(entry, manifest, root, chapters);
    return ComicDetail(
      title: entry.title,
      coverUrl: cover,
      detailUrl: manifest?.detailUrl ?? '',
      description: manifest?.description ?? '',
      sourceName: (manifest?.sourceTitle.isNotEmpty ?? false)
          ? manifest!.sourceTitle
          : '本地',
      chapters: <ComicChapter>[
        for (var i = 0; i < chapters.length; i++)
          ComicChapter(
            number: i + 1,
            title: chapters[i].title,
            url: localChapterUrl(i),
          ),
      ],
    );
  }

  /// 阅读器章节：每章的全部本地图片地址（`file://` URI）。
  Future<List<LocalChapterContent>> readerChapters(
    ComicLocalEntry entry,
  ) async {
    final manifest = LocalComicManifest.tryParse(entry.payload);
    final root = Directory(entry.folderPath);
    final chapters = await _chapters(entry, manifest, root);
    final result = <LocalChapterContent>[];
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final dir = chapter.dir.isEmpty
          ? root
          : Directory(p.join(root.path, chapter.dir));
      final images = await _imagesIn(dir);
      if (images.isEmpty) continue;
      result.add(
        LocalChapterContent(
          index: i,
          title: chapter.title,
          imageUrls: [for (final file in images) file.uri.toString()],
        ),
      );
    }
    return result;
  }

  /// 删除本地漫画：先删磁盘目录，再删元数据行。
  ///
  /// 目录删除失败时仍删行（否则用户无法移除坏条目），但会把错误抛给调用方
  /// 以便 UI 提示——不静默假装磁盘已清干净。
  Future<void> remove(ComicRef ref) async {
    final entry = await localService.find(ref);
    if (entry == null) return;
    final dir = Directory(entry.folderPath);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } finally {
      await localService.remove(ref);
    }
  }

  Future<List<LocalComicChapterInfo>> _chapters(
    ComicLocalEntry entry,
    LocalComicManifest? manifest,
    Directory root,
  ) async {
    if (manifest != null && manifest.chapters.isNotEmpty) {
      return manifest.chapters;
    }
    if (!await root.exists()) return const <LocalComicChapterInfo>[];
    final dirs = <Directory>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        final images = await _imagesIn(entity);
        if (images.isNotEmpty) dirs.add(entity);
      }
    }
    dirs.sort((a, b) => compareNatural(p.basename(a.path), p.basename(b.path)));
    if (dirs.isEmpty) {
      final images = await _imagesIn(root);
      if (images.isEmpty) return const <LocalComicChapterInfo>[];
      return <LocalComicChapterInfo>[
        LocalComicChapterInfo(
          id: '',
          title: entry.title,
          dir: '',
          pages: images.length,
        ),
      ];
    }
    return [
      for (final dir in dirs)
        LocalComicChapterInfo(
          id: p.basename(dir.path),
          title: p.basename(dir.path),
          dir: p.basename(dir.path),
          pages: (await _imagesIn(dir)).length,
        ),
    ];
  }

  Future<String> _coverPath(
    ComicLocalEntry entry,
    LocalComicManifest? manifest,
    Directory root,
    List<LocalComicChapterInfo> chapters,
  ) async {
    if (entry.coverPath != null && entry.coverPath!.isNotEmpty) {
      return entry.coverPath!;
    }
    if (manifest != null && manifest.cover.isNotEmpty) {
      final path = p.join(root.path, manifest.cover);
      if (await File(path).exists()) return path;
    }
    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is File && _isCoverName(p.basename(entity.path))) {
          return entity.path;
        }
      }
    }
    if (chapters.isNotEmpty) {
      final first = chapters.first;
      final dir = first.dir.isEmpty
          ? root
          : Directory(p.join(root.path, first.dir));
      final images = await _imagesIn(dir);
      if (images.isNotEmpty) return images.first.path;
    }
    return '';
  }

  Future<List<File>> _imagesIn(Directory dir) async {
    if (!await dir.exists()) return const <File>[];
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!_imageExtensions.contains(ext)) continue;
      if (_isCoverName(p.basename(entity.path))) continue;
      files.add(entity);
    }
    files.sort(
      (a, b) => compareNatural(p.basename(a.path), p.basename(b.path)),
    );
    return files;
  }

  static bool _isCoverName(String name) =>
      p.basenameWithoutExtension(name).toLowerCase() == 'cover';
}

/// 本地章节的阅读数据（不依赖 reader 目录，模块层再转成 reader 模型）。
class LocalChapterContent {
  /// 原详情里的章节序号（空章被跳过后仍与 `localChapterUrl` 对齐）。
  final int index;
  final String title;
  final List<String> imageUrls;

  const LocalChapterContent({
    required this.index,
    required this.title,
    required this.imageUrls,
  });
}

/// 本地详情里章节的稳定 URL（只承载序号，阅读时按序号取章）。
String localChapterUrl(int index) => 'mimao-local:///$index';

/// 从 [localChapterUrl] 解出章节序号；非法串返回 null。
int? tryDecodeLocalChapterUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'mimao-local') return null;
  final segments = uri.pathSegments;
  if (segments.length != 1) return null;
  return int.tryParse(segments.first);
}

/// 自然排序：连续数字按数值比较，其余按字符比较（大小写不敏感）。
///
/// 不引入第三方包：页文件名常见为 1.jpg / 2.jpg / 10.jpg，字典序会把 10
/// 排到 2 前面，阅读顺序直接错乱。
int compareNatural(String a, String b) {
  final reg = RegExp(r'\d+|\D+');
  final left = reg.allMatches(a).map((m) => m.group(0)!).toList();
  final right = reg.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final l = left[i];
    final r = right[i];
    final ln = int.tryParse(l);
    final rn = int.tryParse(r);
    final cmp = (ln != null && rn != null)
        ? ln.compareTo(rn)
        : l.toLowerCase().compareTo(r.toLowerCase());
    if (cmp != 0) return cmp;
  }
  return left.length.compareTo(right.length);
}
