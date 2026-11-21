// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 pages/ 文件头同款说明。
/// 漫画模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （closure-02 §3/§4/§5）。
///
/// 本类不 new 任何服务/DB：数据源、源仓库、收藏/历史/搜索历史服务、章节图片
/// 加载与图片缓存工厂都从构造参数进来，测试可逐个替换。
///
/// 接线职责：
/// - 收藏 → `ComicCollectService`（ref 由 [refOf] 构造，{id, sourceName}）；
/// - 打开详情 → `ComicHistoryService.open`（打开点校正）；
/// - 开始阅读 → 装配 `ComicReaderPage`（章节图片经注入的
///   [ComicModule.loadChapterImages] 从 A′ 引擎拉取；进度经收敛后的
///   `ComicLibraryProgressRecorder` 写 C′ 权威库）；
/// - 源管理写操作 → 执行池幂等对账（`ComicSourcePoolSync.syncPool`）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/data/engine_comic_data_source.dart';
import 'package:mimao/comic/download_api.dart';
import 'package:mimao/comic/engine/engine.dart' show ComicSourceCatalog;
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/comic/library_api_impl.dart';
import 'package:mimao/comic/local_comic_content.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:mimao/comic/pages/comic_module_page.dart';
import 'package:mimao/comic/pages/comic_module_settings.dart';
import 'package:mimao/comic/read_later_service.dart';
import 'package:mimao/comic/reader/reader_cache.dart' as reader;
import 'package:mimao/comic/reader/reader_models.dart' as reader;
import 'package:mimao/comic/reader/reader_page.dart' as reader;
import 'package:mimao/comic/reader/reader_progress.dart';
import 'package:mimao/comic/search_history_service.dart';
import 'package:mimao/core/contract.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 生产图片缓存：应用支持目录下 `comic_images/` 的磁盘 LRU
/// （app_registry 生产路径注入；测试注入 MemoryByteStore + 假 loader）。
Future<reader.ReaderImageCache> defaultComicImageCache() async {
  final support = await getApplicationSupportDirectory();
  return reader.ReaderImageCache(
    loader: reader.defaultImageByteLoader,
    disk: reader.DiskByteStore(Directory(p.join(support.path, 'comic_images'))),
  );
}

/// 漫画模块入口。
class ComicModule implements AppModule {
  ComicModule({
    required this.dataSource,
    required this.sourceRepository,
    required this.collect,
    required this.history,
    required this.searchHistory,
    required this.loadChapterImages,
    this.localService,
    this.localContent,
    this.readLater,
    this.downloads,
    this.browseSource,
    this.sourceCatalog,
    this.imageCacheFactory,
  });

  final ComicDataSource dataSource;
  final ComicSourceRepository sourceRepository;

  /// 发现/分类的浏览能力。null 时回退：若 [dataSource] 自身实现了
  /// [ComicBrowseSource]（生产路径就是 EngineComicDataSource），自动采用它。
  final ComicBrowseSource? browseSource;

  /// 本地漫画服务（主页「本地漫画」区块）；null 时该区块为空。
  final ComicLocalService? localService;

  /// 本地内容读取（本地详情/阅读器）；null 时本地漫画只能列不能读。
  final ComicLocalContent? localContent;

  /// 稍后阅读服务；null 时主页不显示该卡片。
  final ComicReadLaterService? readLater;

  /// 在线下载能力；null 时详情页不显示下载按钮。
  final ComicDownloadApi? downloads;

  /// 源仓库目录（浏览 `index.json` 按需导入）。null 时源管理页不显示仓库区块。
  final ComicSourceCatalog? sourceCatalog;

  final ComicCollectService collect;
  final ComicHistoryService history;
  final ComicSearchHistoryService searchHistory;

  /// 取一章的图片地址列表（由适配层提供，空列表 = 该章不可加载，跳过）。
  final Future<List<String>> Function(ComicSummary item, ComicChapter chapter)
  loadChapterImages;

  /// 阅读器图片缓存工厂；null 时回退内存缓存（不碰 path_provider，
  /// 便于模块级测试）。生产由 app_registry 注入 [defaultComicImageCache]。
  final Future<reader.ReaderImageCache> Function()? imageCacheFactory;

  /// 内存回退缓存（懒创建，整个模块生命周期复用）。
  reader.ReaderImageCache? _fallbackCache;

  @override
  MediaType get type => MediaType.comic;

  @override
  String get label => '漫画';

  @override
  IconData get icon => MediaType.comic.icon;

  @override
  Widget buildHome(BuildContext context) {
    // 浏览能力：显式注入优先；否则数据源自身实现时直接采用（生产路径）。
    final browse =
        browseSource ??
        (dataSource is ComicBrowseSource
            ? dataSource as ComicBrowseSource
            : null);
    final libraryApi = ComicLibraryApiImpl(
      collect: collect,
      history: history,
      localService: localService,
      localContent: localContent,
      readLaterService: readLater,
    );
    return ComicModulePage(
      dataSource: dataSource,
      sourceRepository: sourceRepository,
      browseSource: browse,
      library: libraryApi,
      readLater: readLater == null ? null : libraryApi,
      localApi: localContent == null ? null : libraryApi,
      downloads: downloads,
      sourceCatalog: sourceCatalog,
      embedded: true,
      // 各入口的设置放进各入口：模块设置面板收在主页右上角按钮里
      // （底部栏四个位置留给功能分区）。
      settingsTab: buildSettings(context),
      onOpenDetail: (item) => history.open(refOf(item)),
      isFavorite: (item) => collect.isCollected(refOf(item)),
      isReadLater: (item) async => readLater?.contains(refOf(item)) ?? false,
      onFavoriteChanged: (item, favorite) =>
          _setFavorite(item, favorite, context),
      onReadLaterChanged: (item, included) =>
          _setReadLater(item, included, context),
      onStartReading: (item, detail, chapter) =>
          _openReader(item, detail, chapter, context),
      onImportSource: (url) => _syncSources(),
      onDeleteSource: (source) => _syncSources(),
    );
  }

  @override
  Widget buildSettings(BuildContext context) {
    return ComicModuleSettings(
      sourceRepository: sourceRepository,
      sourceCatalog: sourceCatalog,
      searchHistory: searchHistory,
      // 与 buildHome 的模块页路径对齐：写操作后触发执行池对账（导入失败
      // 回滚池条目时，下次写操作能把仍存在的源补注册回来）。
      onImportSource: (url) => _syncSources(),
      onDeleteSource: (source) => _syncSources(),
    );
  }

  /// 列表项 → 模块内部权威主键。sourceName 承载 A′ 注册 key（决策④），
  /// 与 core 投影主键 {id, mediaType, sourceName} 逐维对齐。
  static ComicRef refOf(ComicSummary item) =>
      ComicRef(id: item.id, sourceName: item.sourceName ?? '未知源');

  Future<void> _setFavorite(
    ComicSummary item,
    bool favorite,
    BuildContext context,
  ) async {
    final ref = refOf(item);
    try {
      if (favorite) {
        await collect.collect(
          ref,
          title: item.title,
          coverUrl: item.coverUrl.isEmpty ? null : item.coverUrl,
        );
      } else {
        await collect.remove(ref);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(favorite ? '收藏失败：$e' : '取消收藏失败：$e')),
        );
      }
    }
  }

  /// 稍后阅读切换：写模块内部表（不投影书架）；失败回滚提示。
  Future<void> _setReadLater(
    ComicSummary item,
    bool included,
    BuildContext context,
  ) async {
    final service = readLater;
    if (service == null) {
      _showSnack(context, '稍后阅读能力未接线');
      return;
    }
    try {
      await service.set(
        refOf(item),
        included: included,
        title: item.title,
        coverUrl: item.coverUrl.isEmpty ? null : item.coverUrl,
        detailUrl: item.detailUrl,
      );
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, included ? '加入稍后阅读失败：$e' : '移出稍后阅读失败：$e');
      }
    }
  }

  /// 阅读装配方：打开点校正 → 全章预载图片（空章跳过）→ 历史反查初始位置
  /// → push 阅读器。任何一步失败收敛为 SnackBar，不崩导航栈。
  Future<void> _openReader(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter? chapter,
    BuildContext context,
  ) async {
    final ref = refOf(item);
    try {
      await history.open(ref);

      final readerChapters = <reader.ComicChapter>[];
      if (ref.sourceName == ComicRef.localSource) {
        final content = localContent;
        if (content == null) throw StateError('本地内容读取未接线');
        final localEntry = await content.find(ref);
        if (localEntry == null) throw StateError('本地漫画不存在：${item.title}');
        final chapters = await content.readerChapters(localEntry);
        for (var i = 0; i < chapters.length; i++) {
          final localChapter = chapters[i];
          readerChapters.add(
            reader.ComicChapter(
              title: localChapter.title,
              // 用原章节序号作 id：空章被跳过时也不会错位，且能写进历史。
              chapterId: localChapterUrl(i),
              imageUrls: localChapter.imageUrls,
            ),
          );
        }
      } else {
        for (final dc in detail.chapters) {
          final urls = await loadChapterImages(item, dc);
          if (urls.isEmpty) continue;
          final ep = tryDecodeComicEpisodeUrl(dc.url);
          readerChapters.add(
            reader.ComicChapter(
              title: dc.title,
              chapterId: ep?.episodeId ?? '',
              imageUrls: urls,
            ),
          );
        }
      }
      if (readerChapters.isEmpty) {
        if (context.mounted) {
          _showSnack(context, '本章暂无图片或章节列表为空');
        }
        return;
      }

      // 初始位置：显式点章节 → 该章第 1 页；否则历史进度（按 epId 匹配，
      // 空章跳过后下标会偏移，不能按位置推）；都拿不到 → 第一章。
      final entry = await history.latest(ref);
      var initialChapter = 0;
      var initialPage = 0;
      if (chapter != null) {
        // 在线章：epId；本地章：`mimao-local:///<index>`（与上面 chapterId 一致）。
        final tapped = ref.sourceName == ComicRef.localSource
            ? chapter.url
            : tryDecodeComicEpisodeUrl(chapter.url)?.episodeId;
        final index = readerChapters.indexWhere(
          (c) => tapped != null && c.chapterId == tapped,
        );
        if (index >= 0) initialChapter = index;
      } else if (entry != null && entry.chapterId.isNotEmpty) {
        final index = readerChapters.indexWhere(
          (c) => c.chapterId == entry.chapterId,
        );
        if (index >= 0) {
          initialChapter = index;
          initialPage = (entry.page - 1).clamp(
            0,
            readerChapters[index].pageCount - 1,
          );
        }
      }

      final cache = await _resolveCache();
      final recorder = ComicLibraryProgressRecorder(
        history: history,
        ref: ref,
        title: item.title,
        // 本地封面是本机路径，属模块私有：不写进 core 投影的公共 coverUrl。
        coverUrl: ref.sourceName == ComicRef.localSource
            ? null
            : (item.coverUrl.isEmpty ? null : item.coverUrl),
      );
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'comic/reader'),
          builder: (_) => reader.ComicReaderPage(
            title: item.title,
            chapters: readerChapters,
            imageCache: cache,
            recorder: recorder,
            initialChapter: initialChapter,
            initialPage: initialPage,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, '打开阅读器失败：$e');
      }
    }
  }

  /// 源管理写操作后的幂等对账：执行池按 store 现状补注册/释放
  /// （决策⑩——不重复发起 importSource 的网络请求）。
  Future<void> _syncSources() async {
    // 两个接口类型无子型关系，is 后须显式 cast 才能调到窄能力方法。
    final sync = sourceRepository is ComicSourcePoolSync
        ? sourceRepository as ComicSourcePoolSync
        : null;
    if (sync == null) return;
    try {
      await sync.syncPool();
    } on Object {
      // 对账失败留给下次写操作或重启兜底，不打断页面流程。
    }
  }

  Future<reader.ReaderImageCache> _resolveCache() async {
    final factory = imageCacheFactory;
    if (factory != null) return factory();
    return _fallbackCache ??= reader.ReaderImageCache(
      loader: reader.defaultImageByteLoader,
    );
  }

  void _showSnack(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
