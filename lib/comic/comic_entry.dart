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
import 'package:mimao/comic/reader/reader_chapter_source.dart' as reader;
import 'package:mimao/comic/reader/reader_image_loader.dart' as reader;
import 'package:mimao/comic/reader/reader_integration.dart' as reader;
import 'package:mimao/comic/reader/reader_models.dart' as reader;
import 'package:mimao/comic/reader/reader_page.dart' as reader;
import 'package:mimao/comic/reader/reader_progress.dart';
import 'package:mimao/comic/reader/reader_settings.dart' as reader;
import 'package:mimao/comic/search_history_service.dart';
import 'package:mimao/core/contract.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 沉浸式阅读页构造器（生产由 app_registry 注入，测试可不注入走历史页）。
typedef ImmersiveReaderBuilder =
    Widget Function({
      required String title,
      required reader.ReaderChapterSource source,
      required reader.ReaderImageCache imageCache,
      required reader.ReaderSettingsStore settingsStore,
      required ProgressRecorder recorder,
      required int initialChapter,
      required int initialPage,
      required List<String> chapterTitles,
    });

/// 生产图片缓存：应用支持目录下 `comic_images/` 的磁盘 LRU
/// （app_registry 生产路径注入；测试注入 MemoryByteStore + 假 loader）。
/// 同时注入按 [ImageRequest]（Referer/headers/UA + 失败重试）取字节的新加载器，
/// 让阅读器能带防盗链头取图；旧 [loader] 保留作无请求头时的降级。
Future<reader.ReaderImageCache> defaultComicImageCache() async {
  final support = await getApplicationSupportDirectory();
  return reader.ReaderImageCache(
    loader: reader.defaultImageByteLoader,
    requestLoader: reader.defaultImageRequestLoader(),
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
    this.loadChapterImageRequests,
    this.localService,
    this.localContent,
    this.readLater,
    this.downloads,
    this.browseSource,
    this.sourceCatalog,
    this.imageCacheFactory,
    this.immersiveReaderBuilder,
    this.readerSettingsStoreFactory,
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

  /// 取一章的图片请求（含源注入的防盗链头）；null 时阅读器退回纯地址。
  final Future<List<reader.ImageRequest>> Function(
    ComicSummary item,
    ComicChapter chapter,
  )?
  loadChapterImageRequests;

  /// 阅读器图片缓存工厂；null 时回退内存缓存（不碰 path_provider，
  /// 便于模块级测试）。生产由 app_registry 注入 [defaultComicImageCache]。
  final Future<reader.ReaderImageCache> Function()? imageCacheFactory;

  /// 沉浸式阅读器构造器（新体验）：注入后"开始阅读"改走懒加载 + 瀑布流阅读页。
  /// null 时保留历史 [ComicReaderPage] 路径——模块测试据此锁定旧行为。
  /// 生产由 app_registry 提供。
  final ImmersiveReaderBuilder? immersiveReaderBuilder;

  /// 阅读设置存储工厂；生产注入文件版，测试可注入内存版。
  final reader.ReaderSettingsStore Function()? readerSettingsStoreFactory;

  /// 内存回退缓存（懒创建，整个模块生命周期复用）。
  reader.ReaderImageCache? _fallbackCache;

  /// 已解析的图片缓存（同一 App 会话内复用，保留内存 LRU 与加载器连接池）。
  Future<reader.ReaderImageCache>? _resolvedCache;

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
          // 本地封面是本机路径，属模块私有：不写进收藏/投影的公共 coverUrl。
          coverUrl:
              ref.sourceName == ComicRef.localSource || item.coverUrl.isEmpty
              ? null
              : item.coverUrl,
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

  /// 阅读装配方：打开点校正 → 装配章节源 → 历史反查初始位置 → push 阅读器。
  ///
  /// 沉浸式阅读器（生产）走真·按章懒加载：开书不抓任何图片，读到哪章才抓哪章，
  /// 单章撞反爬/验证只影响该章；历史在打开时即落一条，不再等翻页。
  /// 历史页（测试注入缺失时）保持旧的全章预载行为，不动锁定测试。
  /// 任何一步失败收敛为 SnackBar，不崩导航栈。
  Future<void> _openReader(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter? chapter,
    BuildContext context,
  ) async {
    final ref = refOf(item);
    try {
      await history.open(ref);
      final isLocal = ref.sourceName == ComicRef.localSource;
      final coverUrl = isLocal
          ? null
          : (item.coverUrl.isEmpty ? null : item.coverUrl);

      // ── 沉浸式阅读器（生产注入）────────────────────────────
      final builder = immersiveReaderBuilder;
      if (builder != null) {
        if (!context.mounted) return;
        await _openImmersiveReader(
          item,
          detail,
          chapter,
          context,
          ref,
          isLocal,
          coverUrl,
          builder,
        );
        return;
      }

      // ── 历史页（测试注入缺失时保留旧行为）─────────────────
      final readerChapters = <reader.ComicChapter>[];
      if (isLocal) {
        final content = localContent;
        if (content == null) throw StateError('本地内容读取未接线');
        final localEntry = await content.find(ref);
        if (localEntry == null) throw StateError('本地漫画不存在：${item.title}');
        final chapters = await content.readerChapters(localEntry);
        for (final localChapter in chapters) {
          readerChapters.add(
            reader.ComicChapter(
              title: localChapter.title,
              chapterId: localChapterUrl(localChapter.index),
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
      final pos = await _resolveInitialPosition(
        ref,
        readerChapters,
        chapter,
        isLocal,
      );
      final cache = await _resolveCache();
      final recorder = ComicLibraryProgressRecorder(
        history: history,
        ref: ref,
        title: item.title,
        coverUrl: coverUrl,
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
            initialChapter: pos.$1,
            initialPage: pos.$2,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, '打开阅读器失败：$e');
      }
    }
  }

  /// 沉浸式阅读器装配：只装配章节元数据，图片地址推迟到读到该章时才抓。
  /// 打开时先写一条历史，让"正在读的漫画"立刻出现在历史里。
  Future<void> _openImmersiveReader(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter? chapter,
    BuildContext context,
    ComicRef ref,
    bool isLocal,
    String? coverUrl,
    ImmersiveReaderBuilder builder,
  ) async {
    // 章节元数据：标题 + 稳定 id。在线用 epId，本地用章节地址（作 id）。
    final titles = <String>[];
    final ids = <String>[];
    final dataChapters = <ComicChapter>[];
    if (isLocal) {
      final content = localContent;
      if (content == null) throw StateError('本地内容读取未接线');
      final localEntry = await content.find(ref);
      if (localEntry == null) throw StateError('本地漫画不存在：${item.title}');
      final localChapters = await content.readerChapters(localEntry);
      for (final c in localChapters) {
        titles.add(c.title);
        ids.add(localChapterUrl(c.index));
      }
      // 本地图片走磁盘，抓图闭包按章号从已读清单取（无网络）。
      final localImages = localChapters;
      sourceForLocal(int chapter) async =>
          chapter >= 1 && chapter <= localImages.length
          ? localImages[chapter - 1].imageUrls
          : const <String>[];
      Future<List<reader.ImageRequest>> requestsForLocal(int chapter) async {
        final urls = await sourceForLocal(chapter);
        return <reader.ImageRequest>[
          for (final url in urls) reader.ImageRequest(url: url),
        ];
      }

      if (!context.mounted) return;
      await _pushImmersive(
        item,
        ref,
        coverUrl,
        context,
        builder,
        titles,
        ids,
        sourceForLocal,
        requestsForLocal,
        chapter,
        isLocal,
      );
      return;
    }

    // 在线：详情里的章节列表即元数据，抓图闭包按章号现抓该章。
    for (final dc in detail.chapters) {
      titles.add(dc.title);
      ids.add(tryDecodeComicEpisodeUrl(dc.url)?.episodeId ?? dc.url);
      dataChapters.add(dc);
    }
    if (titles.isEmpty) {
      if (context.mounted) _showSnack(context, '章节列表为空');
      return;
    }
    Future<List<String>> sourceForOnline(int chapter) async {
      if (chapter < 1 || chapter > dataChapters.length) return const <String>[];
      return loadChapterImages(item, dataChapters[chapter - 1]);
    }

    Future<List<reader.ImageRequest>> requestsForOnline(int chapter) async {
      if (chapter < 1 || chapter > dataChapters.length) {
        return const <reader.ImageRequest>[];
      }
      final requestLoader = loadChapterImageRequests;
      if (requestLoader != null) {
        try {
          final requests = await requestLoader(item, dataChapters[chapter - 1]);
          if (requests.isNotEmpty) return requests;
        } on Object {
          // 源级请求头解析失败时退回纯地址：图片加载器仍会补 UA/同源 Referer。
        }
      }
      final urls = await sourceForOnline(chapter);
      return <reader.ImageRequest>[
        for (final url in urls) reader.ImageRequest(url: url),
      ];
    }

    await _pushImmersive(
      item,
      ref,
      coverUrl,
      context,
      builder,
      titles,
      ids,
      sourceForOnline,
      requestsForOnline,
      chapter,
      isLocal,
    );
  }

  /// 计算起始章/页（1 基），并写一条历史。返回 (chapter, page)。
  Future<(int, int)> _openingPosition(
    ComicRef ref,
    String title,
    List<String> ids,
    ComicChapter? chapter,
    bool isLocal,
    String? coverUrl,
  ) async {
    final entry = await history.latest(ref);
    var chapterNumber = 1; // 1 基
    var page = 1; // 1 基
    if (chapter != null) {
      final tapped = isLocal
          ? chapter.url
          : tryDecodeComicEpisodeUrl(chapter.url)?.episodeId ?? chapter.url;
      final index = ids.indexOf(tapped);
      if (index >= 0) chapterNumber = index + 1;
    } else if (entry != null && entry.chapterId.isNotEmpty) {
      final index = ids.indexOf(entry.chapterId);
      if (index >= 0) {
        chapterNumber = index + 1;
        if (entry.page >= 1) page = entry.page;
      }
    }
    // 打开即写历史（新书立刻进历史；老书刷新打开时间）。pageCount 未知传 0，
    // 读到该章后 reader 会用真实总数覆盖。
    await history.saveProgress(
      ref,
      title: title,
      coverUrl: coverUrl,
      chapterId: ids[chapterNumber - 1],
      page: page,
      pageCount: 0,
    );
    return (chapterNumber, page);
  }

  Future<void> _pushImmersive(
    ComicSummary item,
    ComicRef ref,
    String? coverUrl,
    BuildContext context,
    ImmersiveReaderBuilder builder,
    List<String> titles,
    List<String> ids,
    Future<List<String>> Function(int) loadImages,
    Future<List<reader.ImageRequest>> Function(int) loadRequests,
    ComicChapter? chapter,
    bool isLocal,
  ) async {
    final (chapterNumber, page) = await _openingPosition(
      ref,
      item.title,
      ids,
      chapter,
      isLocal,
      coverUrl,
    );

    // 关键：起始章在进入阅读器之前抓。抓图可能撞反爬 → 弹验证 WebView
    // （它加载站点章节页，看着像"站点自己的阅读器"）。此刻我们阅读器还没 push，
    // 验证页在详情页之上弹出、关掉后回到详情页，不会盖住阅读器、更不会让
    // 阅读器拿不到图变空白。其余章节仍交给阅读器按需懒加载。
    //
    // 用 loadRequests 而不是 loadImages：源支持 onImageLoad 时，起始章也能
    // 带着防盗链头进缓存，不会因为预取路径不同而第一次读图就失败。
    Map<int, List<reader.ImageRequest>> initialRequestCache =
        const <int, List<reader.ImageRequest>>{};
    try {
      final firstRequests = await loadRequests(chapterNumber);
      if (firstRequests.isNotEmpty) {
        initialRequestCache = <int, List<reader.ImageRequest>>{
          chapterNumber: firstRequests,
        };
      }
    } on Object {
      // 抓图失败（含用户取消验证）：仍进阅读器，让其在读该章时按 UI 重试，
      // 不把整本书卡在打不开的状态。
    }
    if (!context.mounted) return;

    final source = reader.LazyChapterSource(
      episodeIds: ids,
      titles: titles,
      loadImages: loadImages,
      loadRequests: loadRequests,
      initialRequestCache: initialRequestCache,
    );
    final cache = await _resolveCache();
    final recorder = ComicLibraryProgressRecorder(
      history: history,
      ref: ref,
      title: item.title,
      coverUrl: coverUrl,
    );
    final settingsStore = readerSettingsStoreFactory != null
        ? readerSettingsStoreFactory!()
        : reader.MemoryReaderSettingsStore();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/reader'),
        builder: (_) => builder(
          title: item.title,
          source: source,
          imageCache: cache,
          settingsStore: settingsStore,
          recorder: recorder,
          initialChapter: chapterNumber,
          initialPage: page,
          chapterTitles: titles,
        ),
      ),
    );
  }

  /// 历史页用的初始位置解析（0 基章/页），保持旧行为。
  Future<(int, int)> _resolveInitialPosition(
    ComicRef ref,
    List<reader.ComicChapter> chapters,
    ComicChapter? chapter,
    bool isLocal,
  ) async {
    var initialChapter = 0;
    var initialPage = 0;
    if (chapter != null) {
      final tapped = isLocal
          ? chapter.url
          : tryDecodeComicEpisodeUrl(chapter.url)?.episodeId;
      final index = chapters.indexWhere(
        (c) => tapped != null && c.chapterId == tapped,
      );
      if (index >= 0) initialChapter = index;
    } else {
      final entry = await history.latest(ref);
      if (entry != null && entry.chapterId.isNotEmpty) {
        final index = chapters.indexWhere(
          (c) => c.chapterId == entry.chapterId,
        );
        if (index >= 0) {
          initialChapter = index;
          initialPage = (entry.page - 1).clamp(
            0,
            chapters[index].pageCount - 1,
          );
        }
      }
    }
    return (initialChapter, initialPage);
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

  Future<reader.ReaderImageCache> _resolveCache() {
    // 同一会话内缓存实例只建一次：反复进出阅读器不再丢内存 LRU，也复用
    // defaultImageRequestLoader 内部的 HttpClient 连接池。
    return _resolvedCache ??= () async {
      final factory = imageCacheFactory;
      if (factory != null) return factory();
      return _fallbackCache ??= reader.ReaderImageCache(
        loader: reader.defaultImageByteLoader,
      );
    }();
  }

  void _showSnack(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
