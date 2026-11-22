// 阅读器集成胶水：把模块已有的"按章取图"能力适配成 [ReaderChapterSource]
// （懒加载），把设置落到文件（不新增依赖，沿用 path_provider）。
//
// 本文件只做适配，不碰源引擎/DB；生产由 ComicModule 装配，测试可不注入。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'reader_chapter_source.dart';
import 'reader_settings.dart';

/// 真·按章懒加载章节源：只持有章节的轻量描述（标题 / 稳定 epId），
/// 图片地址在真正读到某章时才通过 [loadImages] 抓那一章。
///
/// 与 [EagerChapterSource] 的区别：后者吃的是开书前已全本抓好的图片列表，
/// 任一章抓图失败（反爬 / 验证页）就会拖垮整本书；本源把抓图推迟到阅读时，
/// 单章失败只影响该章，且开书瞬间不需要任何网络请求。
///
/// [loadImages] 由集成层提供（按 1 基章号抓，闭包捕获章节列表与源），返回
/// 该章图片地址；空列表 = 该章不可读。[scope] 取消后调用方应尽快返回空。
class LazyChapterSource implements ReaderChapterSource {
  LazyChapterSource({
    required this.episodeIds,
    required this.titles,
    required this.loadImages,
  }) : assert(episodeIds.length == titles.length, '章节 id 与标题长度必须一致');

  /// 1 基章号 → 稳定 epId（本地章可为章节地址）。
  final List<String> episodeIds;

  /// 1 基章号 → 章节标题。
  final List<String> titles;

  /// 按 1 基章号抓该章图片地址；在真正读到该章时才调用。
  final Future<List<String>> Function(int chapter) loadImages;

  /// 已抓过的章缓存：翻回去不重复抓。
  final Map<int, List<String>> _cache = <int, List<String>>{};

  @override
  int get chapterCount => episodeIds.length;

  @override
  String chapterId(int chapter) => chapter >= 1 && chapter <= episodeIds.length
      ? episodeIds[chapter - 1]
      : '';

  @override
  Future<List<String>> load(int chapter, ReaderLoadScope scope) async {
    if (chapter < 1 || chapter > episodeIds.length) return const <String>[];
    final cached = _cache[chapter];
    if (cached != null) return cached;
    final urls = await loadImages(chapter);
    if (scope.isCancelled) return const <String>[];
    final result = List<String>.unmodifiable(urls);
    _cache[chapter] = result;
    return result;
  }
}

/// 按章懒加载章节源：集成层把 ComicModule.loadChapterImages + 章节列表
/// 适配成本端口。图片只在真正读到该章时才解析地址（不再开书就全本拉一遍）。
class EagerChapterSource implements ReaderChapterSource {
  EagerChapterSource({
    required this.episodeIds,
    required this.imageUrlsByChapter,
    required this.titles,
  }) : assert(
         episodeIds.length == imageUrlsByChapter.length,
         '章节 id 与图片列表长度必须一致',
       );

  /// 1 基章号 → 稳定 epId；空串表示本地/测试章。
  final List<String> episodeIds;

  /// 1 基章号 → 该章图片地址（可空列表，表示空章）。
  final List<List<String>> imageUrlsByChapter;

  /// 1 基章号 → 章节标题。
  final List<String> titles;

  @override
  int get chapterCount => episodeIds.length;

  @override
  String chapterId(int chapter) => chapter >= 1 && chapter <= episodeIds.length
      ? episodeIds[chapter - 1]
      : '';

  @override
  Future<List<String>> load(int chapter, ReaderLoadScope scope) async {
    if (scope.isCancelled) return const <String>[];
    if (chapter < 1 || chapter > imageUrlsByChapter.length) {
      return const <String>[];
    }
    final urls = imageUrlsByChapter[chapter - 1];
    if (scope.isCancelled) return const <String>[];
    return urls;
  }
}

/// 文件版阅读设置存储：落到应用支持目录 `comic_reader_settings.json`，
/// 失败时静默回退默认值（不让设置把阅读器卡死）。path_provider 已是现有依赖。
class FileReaderSettingsStore implements ReaderSettingsStore {
  FileReaderSettingsStore({this.fileName = 'comic_reader_settings.json'});

  final String fileName;

  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, fileName));
  }

  @override
  Future<ReaderSettings> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const ReaderSettings();
      final raw = await file.readAsString();
      return ReaderSettings.deserialize(raw);
    } on Object {
      return const ReaderSettings();
    }
  }

  @override
  Future<void> save(ReaderSettings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()));
    } on Object {
      // 写失败不影响本次阅读；下次进入仍是上一次成功保存的设置。
    }
  }
}
